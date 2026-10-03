import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:terraformation_web/core/auth/auth.dart';
import 'package:terraformation_web/core/config.dart';
import 'package:terraformation_web/core/platform/browser.dart';

const cfg = AppConfig(
  apiBaseUrl: 'https://api.example.test',
  cognitoDomain: 'https://login.example.test',
  clientId: 'client123',
  redirectUri: 'https://app.example.test/',
);

String jwt(Map<String, dynamic> payload) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.s';

ProviderContainer make(MemoryBrowser b, http.Client c) => ProviderContainer(overrides: [
      configProvider.overrideWithValue(cfg),
      browserProvider.overrideWithValue(b),
      httpClientProvider.overrideWithValue(c),
    ]);

void main() {
  test('PKCE S256 matches the RFC 7636 test vector', () {
    expect(pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
  });

  test('login redirects to /oauth2/authorize with PKCE and state', () {
    final b = MemoryBrowser();
    final c = make(b, MockClient((_) async => http.Response('{}', 200)));
    c.read(authProvider.notifier).login();
    final u = Uri.parse(b.lastRedirect!);
    expect(u.host, 'login.example.test');
    expect(u.path, '/oauth2/authorize');
    expect(u.queryParameters['response_type'], 'code');
    expect(u.queryParameters['code_challenge_method'], 'S256');
    expect(u.queryParameters['client_id'], 'client123');
    expect(u.queryParameters['code_challenge'], pkceChallenge(b.getSession('tf.verifier')!));
    expect(u.queryParameters['state'], b.getSession('tf.state'));
  });

  test('init exchanges the code for tokens and cleans the URL', () async {
    final b = MemoryBrowser(uri: Uri.parse('https://app.example.test/?code=abc&state=xyz'));
    b.setSession('tf.state', 'xyz');
    b.setSession('tf.verifier', 'ver');
    late http.Request seen;
    final c = make(b, MockClient((req) async {
      seen = req;
      return http.Response(
        jsonEncode({
          'access_token': 'at',
          'id_token': jwt({'email': 'ana@example.com'}),
          'refresh_token': 'rt',
          'expires_in': 3600,
        }),
        200,
      );
    }));
    await c.read(authProvider.notifier).init();
    final s = c.read(authProvider);
    expect(s.authenticated, isTrue);
    expect(s.email, 'ana@example.com');
    expect(seen.url.path, '/oauth2/token');
    expect(seen.bodyFields['code_verifier'], 'ver');
    expect(seen.bodyFields['grant_type'], 'authorization_code');
    expect(b.currentUri.query, isEmpty);
    expect(await c.read(authProvider.notifier).accessToken(), 'at');
  });

  test('a different state invalidates the sign-in', () async {
    final b = MemoryBrowser(uri: Uri.parse('https://app.example.test/?code=abc&state=bad'));
    b.setSession('tf.state', 'ok');
    b.setSession('tf.verifier', 'ver');
    final c = make(b, MockClient((_) async => http.Response('{}', 200)));
    await c.read(authProvider.notifier).init();
    expect(c.read(authProvider).authenticated, isFalse);
    expect(c.read(authProvider).error, isNotNull);
  });

  test('no session: unauthenticated and no error', () async {
    final b = MemoryBrowser();
    final c = make(b, MockClient((_) async => http.Response('{}', 200)));
    await c.read(authProvider.notifier).init();
    expect(c.read(authProvider).busy, isFalse);
    expect(c.read(authProvider).authenticated, isFalse);
  });

  test('refresh with an expired token renews it', () async {
    final b = MemoryBrowser();
    b.setSession('tf.access', 'old');
    b.setSession('tf.refresh', 'rt');
    b.setSession('tf.expires', '1');
    final c = make(b, MockClient((req) async {
      expect(req.bodyFields['grant_type'], 'refresh_token');
      return http.Response(jsonEncode({'access_token': 'new', 'expires_in': 3600}), 200);
    }));
    expect(await c.read(authProvider.notifier).accessToken(), 'new');
  });
}
