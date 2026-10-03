import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../platform/browser.dart';

const _kAccess = 'tf.access';
const _kId = 'tf.id';
const _kRefresh = 'tf.refresh';
const _kExpires = 'tf.expires';
const _kVerifier = 'tf.verifier';
const _kState = 'tf.state';

String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

String randomString(int bytes, [Random? rng]) {
  final r = rng ?? Random.secure();
  return _b64url(List<int>.generate(bytes, (_) => r.nextInt(256)));
}

/// code_challenge = BASE64URL(SHA256(verifier)) (RFC 7636, método S256).
String pkceChallenge(String verifier) => _b64url(sha256.convert(ascii.encode(verifier)).bytes);

Map<String, dynamic> decodeJwtPayload(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) return {};
  try {
    final norm = base64Url.normalize(parts[1]);
    return jsonDecode(utf8.decode(base64Url.decode(norm))) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

class AuthState {
  const AuthState({this.authenticated = false, this.email, this.busy = true, this.error});

  final bool authenticated;
  final String? email;
  final bool busy;
  final String? error;
}

final browserProvider = Provider<Browser>((ref) => createBrowser());
final httpClientProvider = Provider<http.Client>((ref) => http.Client());

/// Autenticación con Cognito managed login: Authorization Code + PKCE (sin secreto).
class AuthController extends Notifier<AuthState> {
  late final AppConfig _cfg = ref.read(configProvider);
  late final Browser _browser = ref.read(browserProvider);
  late final http.Client _http = ref.read(httpClientProvider);

  @override
  AuthState build() => const AuthState();

  /// Se llama una vez al arrancar: procesa `?code=` o restaura la sesión.
  Future<void> init() async {
    final uri = _browser.currentUri;
    final code = uri.queryParameters['code'];
    final st = uri.queryParameters['state'];
    final oauthError = uri.queryParameters['error'];
    if (oauthError != null) {
      _browser.replaceUrl(uri.path);
      state = AuthState(busy: false, error: uri.queryParameters['error_description'] ?? oauthError);
      return;
    }
    if (code != null) {
      final expected = _browser.getSession(_kState);
      final verifier = _browser.getSession(_kVerifier);
      _browser.replaceUrl(uri.path);
      if (st == null || st != expected || verifier == null) {
        state = const AuthState(busy: false, error: 'Respuesta de inicio de sesión no válida');
        return;
      }
      try {
        await _tokenRequest({
          'grant_type': 'authorization_code',
          'client_id': _cfg.clientId,
          'code': code,
          'redirect_uri': _cfg.redirectUri,
          'code_verifier': verifier,
        });
        _browser.removeSession(_kVerifier);
        _browser.removeSession(_kState);
      } catch (e) {
        state = AuthState(busy: false, error: '$e');
      }
      return;
    }
    if (_browser.getSession(_kAccess) != null) {
      if (_expired()) {
        await refresh();
      } else {
        _publish();
      }
      return;
    }
    state = const AuthState(busy: false);
  }

  bool _expired() {
    final exp = int.tryParse(_browser.getSession(_kExpires) ?? '') ?? 0;
    return DateTime.now().millisecondsSinceEpoch > exp - 30000;
  }

  void _publish() {
    final id = _browser.getSession(_kId);
    final email = id == null ? null : decodeJwtPayload(id)['email'] as String?;
    state = AuthState(authenticated: true, email: email, busy: false);
  }

  Future<void> _tokenRequest(Map<String, String> body) async {
    final res = await _http.post(
      Uri.parse('${_cfg.cognitoDomain}/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );
    if (res.statusCode != 200) {
      throw StateError('Cognito rechazó la solicitud de token (${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    _browser.setSession(_kAccess, j['access_token'] as String);
    if (j['id_token'] != null) _browser.setSession(_kId, j['id_token'] as String);
    if (j['refresh_token'] != null) _browser.setSession(_kRefresh, j['refresh_token'] as String);
    final ttl = (j['expires_in'] as num?)?.toInt() ?? 3600;
    _browser.setSession(
      _kExpires,
      '${DateTime.now().millisecondsSinceEpoch + ttl * 1000}',
    );
    _publish();
  }

  Future<bool> refresh() async {
    final rt = _browser.getSession(_kRefresh);
    if (rt == null) {
      _clear();
      return false;
    }
    try {
      await _tokenRequest({
        'grant_type': 'refresh_token',
        'client_id': _cfg.clientId,
        'refresh_token': rt,
      });
      return true;
    } catch (_) {
      _clear();
      return false;
    }
  }

  /// Token de acceso vigente (renueva si hace falta) o `null` si no hay sesión.
  Future<String?> accessToken() async {
    if (_browser.getSession(_kAccess) == null) return null;
    if (_expired() && !await refresh()) return null;
    return _browser.getSession(_kAccess);
  }

  void login() {
    final verifier = randomString(48);
    final st = randomString(16);
    _browser.setSession(_kVerifier, verifier);
    _browser.setSession(_kState, st);
    final url = Uri.parse('${_cfg.cognitoDomain}/oauth2/authorize').replace(queryParameters: {
      'response_type': 'code',
      'client_id': _cfg.clientId,
      'redirect_uri': _cfg.redirectUri,
      'scope': 'openid email profile',
      'code_challenge': pkceChallenge(verifier),
      'code_challenge_method': 'S256',
      'state': st,
    });
    _browser.redirect(url.toString());
  }

  void logout() {
    _clear();
    final url = Uri.parse('${_cfg.cognitoDomain}/logout').replace(queryParameters: {
      'client_id': _cfg.clientId,
      'logout_uri': _cfg.redirectUri,
    });
    _browser.redirect(url.toString());
  }

  void _clear() {
    for (final k in [_kAccess, _kId, _kRefresh, _kExpires]) {
      _browser.removeSession(k);
    }
    state = const AuthState(busy: false);
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
