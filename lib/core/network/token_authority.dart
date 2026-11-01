import 'package:dio/dio.dart';
import '../security/session_store.dart';

/// Owns the short-lived access token and knows how to renew it.
abstract interface class TokenAuthority {
  String? get accessToken;

  /// Exchanges the stored refresh token for a new access token. False when that is impossible
  /// (no token, expired, revoked) — the caller must then end the session.
  Future<bool> refresh();

  /// Forgets the in-memory access token (sign-out).
  void clear();
}

/// Access token lives in memory only; the rotating refresh token lives in secure storage.
/// Concurrent refreshes share one request so a burst of 401s cannot burn the refresh token twice.
class SessionTokenAuthority implements TokenAuthority {
  SessionTokenAuthority(this._sessions, this._bare);
  final SessionStore _sessions;

  /// A Dio without the auth interceptor, so refreshing can never recurse.
  final Dio _bare;

  String? _access;
  Future<bool>? _inFlight;

  @override
  String? get accessToken => _access;

  void setAccessToken(String token) => _access = token;

  @override
  void clear() => _access = null;

  @override
  Future<bool> refresh() => _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<bool> _refresh() async {
    final token = await _sessions.refreshToken();
    if (token == null) return false;
    try {
      final res = await _bare.post<Map<String, dynamic>>('/v1/auth/refresh', data: {'refreshToken': token});
      final data = res.data;
      final access = data?['accessToken'];
      final rotated = data?['refreshToken'];
      if (access is! String || rotated is! String) return false;
      _access = access;
      await _sessions.saveRefreshToken(rotated);
      return true;
    } on DioException {
      return false;
    }
  }
}
