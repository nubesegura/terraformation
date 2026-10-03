import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../auth/auth.dart';
import '../config.dart';
import '../state_ref.dart';
import 'models.dart';

class ApiException implements Exception {
  ApiException(this.status, this.detail);
  final int status;
  final String detail;
  @override
  String toString() => detail;
}

/// Typed HTTP client for the API (contract: docs/openapi.yaml).
class ApiClient {
  ApiClient({required this.baseUrl, required this.client, required this.token, this.onUnauthorized});

  final String baseUrl;
  final http.Client client;
  final Future<String?> Function() token;
  final void Function()? onUnauthorized;

  Future<Json> _send(String method, String path, {Map<String, String?>? query, Json? body}) async {
    final params = <String, String>{
      for (final e in (query ?? const <String, String?>{}).entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: params.isEmpty ? null : params);
    final t = await token();
    final headers = {
      if (t != null) 'Authorization': 'Bearer $t',
      if (body != null) 'Content-Type': 'application/json',
    };
    final res = method == 'GET'
        ? await client.get(uri, headers: headers)
        : await client.post(uri, headers: headers, body: jsonEncode(body));
    if (res.statusCode == 401) onUnauthorized?.call();
    if (res.statusCode >= 400) {
      var detail = 'Error ${res.statusCode}';
      try {
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        if (j is Map && j['detail'] != null) detail = '${j['detail']}';
        if (j is Map && j['message'] != null) detail = '${j['message']}';
      } catch (_) {}
      throw ApiException(res.statusCode, detail);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Json;
  }

  static String _p(String project) => Uri.encodeComponent(project);

  Future<DashboardData> dashboard({int days = 30}) async =>
      DashboardData.fromJson(await _send('GET', '/api/dashboard', query: {'days': '$days'}));

  Future<ProjectList> projects({String? q}) async =>
      ProjectList.fromJson(await _send('GET', '/api/projects', query: {'q': q}));

  Map<String, String> _q(StateRef r, [Map<String, String> extra = const {}]) =>
      {'workspace': r.workspace, 'path': r.path, ...extra};

  Future<Project> project(StateRef r) async => Project.fromJson(
      await _send('GET', '/api/projects/${_p(r.project)}', query: _q(r)));

  Future<VersionList> versions(StateRef r) async => VersionList.fromJson(
      await _send('GET', '/api/projects/${_p(r.project)}/versions', query: _q(r)));

  Future<Timeline> timeline(StateRef r) async => Timeline.fromJson(
      await _send('GET', '/api/projects/${_p(r.project)}/timeline', query: _q(r)));

  Future<StateDetail> state(StateRef r, String version) async =>
      StateDetail.fromJson(await _send(
        'GET',
        '/api/projects/${_p(r.project)}/versions/${Uri.encodeComponent(version)}',
        query: _q(r),
      ));

  Future<StateDiff> diff(StateRef r, String from, String to) async =>
      StateDiff.fromJson(await _send(
        'GET',
        '/api/projects/${_p(r.project)}/diff',
        query: _q(r, {'from_version': from, 'to_version': to}),
      ));

  Future<DiffSummary> diffSummary(StateRef r, String from, String to, {String language = 'en'}) async =>
      DiffSummary.fromJson(await _send(
        'POST',
        '/api/projects/${_p(r.project)}/diff/summary',
        body: {
          'workspace': r.workspace,
          'path': r.path,
          'from_version': from,
          'to_version': to,
          'language': language,
        },
      ));

  Future<DependencyGraph> graph(StateRef r, String version) async =>
      DependencyGraph.fromJson(await _send(
        'GET',
        '/api/projects/${_p(r.project)}/graph',
        query: _q(r, {'version': version}),
      ));

  Future<LockHistory> projectLocks(StateRef r) async => LockHistory.fromJson(
      await _send('GET', '/api/projects/${_p(r.project)}/locks', query: _q(r)));

  Future<AwsResources> awsResources(StateRef r) async => AwsResources.fromJson(
      await _send('GET', '/api/projects/${_p(r.project)}/aws-resources', query: _q(r)));

  Future<ActiveLocks> activeLocks() async =>
      ActiveLocks.fromJson(await _send('GET', '/api/locks'));

  Future<Facets> facets() async => Facets.fromJson(await _send('GET', '/api/facets'));

  Future<SearchResult> search({
    String? type,
    String? name,
    String? module,
    String? project,
    String? attributeKey,
    String? attributeValue,
    int limit = 200,
  }) async =>
      SearchResult.fromJson(await _send('GET', '/api/search', query: {
        'type': type,
        'name': name,
        'module': module,
        'project': project,
        'attribute_key': attributeKey,
        'attribute_value': attributeValue,
        'limit': '$limit',
      }));
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.read(authProvider.notifier);
  return ApiClient(
    baseUrl: ref.read(configProvider).apiBaseUrl,
    client: ref.read(httpClientProvider),
    token: auth.accessToken,
    onUnauthorized: () => auth.refresh(),
  );
});
