import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Runtime configuration (`config.json`, generated from the stack outputs).
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.cognitoDomain,
    required this.clientId,
    required this.redirectUri,
  });

  final String apiBaseUrl;
  final String cognitoDomain;
  final String clientId;
  final String redirectUri;

  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
        apiBaseUrl: (j['apiBaseUrl'] as String).replaceAll(RegExp(r'/+$'), ''),
        cognitoDomain: (j['cognitoDomain'] as String).replaceAll(RegExp(r'/+$'), ''),
        clientId: j['clientId'] as String,
        redirectUri: j['redirectUri'] as String,
      );

  static Future<AppConfig> load({http.Client? client}) async {
    final c = client ?? http.Client();
    final res = await c.get(Uri.parse('config.json'));
    if (res.statusCode != 200) {
      throw StateError('Could not load config.json (${res.statusCode})');
    }
    return AppConfig.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}

final configProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('configProvider must be overridden in main()'),
);
