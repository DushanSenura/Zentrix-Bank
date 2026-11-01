import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/mappers.dart';
import '../../../core/network/token_authority.dart';
import '../../../shared/models/models.dart';
import '../domain/auth_repository.dart';

/// [AuthRepository] backed by the REST API (`docs/api_contract.md`, "Authentication").
///
/// Passwords are sent once over TLS and never stored. The access token stays in memory
/// ([SessionTokenAuthority]); only the rotating refresh token is persisted, by the caller.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api, this._tokens);
  final ApiClient _api;
  final SessionTokenAuthority _tokens;

  /// Refresh token from the most recent sign-in, handed out by [issueRefreshToken] for "remember me".
  String? _lastRefreshToken;

  AppUser _accept(Json response) {
    final access = response['accessToken'];
    final refresh = response['refreshToken'];
    final user = response['user'];
    if (access is! String || user is! Json) throw const ServerException();
    _tokens.setAccessToken(access);
    _lastRefreshToken = refresh is String ? refresh : null;
    return userFromJson(user);
  }

  /// Auth endpoints return 401/403/409 for business reasons; surface them as [AuthException]
  /// with wording that does not reveal whether an account exists.
  Future<T> _auth<T>(Future<T> Function() call, {String rejected = 'Incorrect username or password.'}) async {
    try {
      return await call();
    } on UnauthorizedException {
      throw AuthException(rejected);
    } on RejectedException catch (e) {
      throw AuthException(e.message);
    } on NetworkException {
      throw const AuthException('Can’t reach the bank. Check your connection and try again.');
    } on MaintenanceException catch (e) {
      throw AuthException(e.message);
    } on ServerException {
      throw const AuthException('Something went wrong on our side. Please try again.');
    }
  }

  @override
  Future<AppUser> signIn(String identifier, String password) => _auth(
    () async => _accept(await _api.post('/v1/auth/login', body: {'identifier': identifier.trim(), 'password': password}, authenticated: false)),
  );

  @override
  Future<AppUser> register({
    required String fullName,
    required String username,
    required String password,
    required double initialDeposit,
    Map<String, String> profile = const {},
  }) => _auth(
    () async => _accept(
      await _api.post(
        '/v1/auth/register',
        authenticated: false,
        body: {
          'fullName': fullName,
          'username': username.trim(),
          'password': password,
          'initialDepositMinor': toMinor(initialDeposit),
          'profile': profile,
        },
      ),
    ),
  );

  @override
  Future<String> issueRefreshToken(AppUser user) async {
    final cached = _lastRefreshToken;
    if (cached != null) return cached;
    final res = await _api.post('/v1/auth/device-token');
    final token = res['refreshToken'];
    if (token is! String) throw const ServerException();
    return token;
  }

  @override
  Future<AppUser?> restoreSession(String refreshToken) async {
    // The stored token is exchanged (and rotated) by the authority, which also saves the new one.
    if (!await _tokens.refresh()) return null;
    try {
      final user = (await _api.get('/v1/me'))['user'];
      return user is Json ? userFromJson(user) : null;
    } on UnauthorizedException {
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _api.post('/v1/auth/logout');
    } on ApiException {
      // Signing out must always succeed locally; the server also expires the token on its own.
    } finally {
      _tokens.clear();
      _lastRefreshToken = null;
    }
  }

  @override
  Future<void> changePassword({required String userId, required String current, required String next}) => _auth(
    () => _api.post('/v1/auth/password', body: {'current': current, 'next': next}),
    rejected: 'Your current password is incorrect.',
  );

  @override
  Future<AppUser> updateContact({required String userId, required String email, required String phone}) => _auth(() async {
    final res = await _api.put('/v1/me/contact', body: {'email': email, 'phone': phone});
    final user = res['user'];
    if (user is! Json) throw const ServerException();
    return userFromJson(user);
  });

  @override
  Future<void> requestPasswordReset(String identifier) async {
    try {
      await _api.post('/v1/auth/password-reset/request', body: {'identifier': identifier.trim()}, authenticated: false);
    } on ApiException {
      // Contract: always looks successful so callers cannot learn whether an account exists.
    }
  }

  @override
  Future<void> confirmPasswordReset({required String identifier, required String code, required String newPassword}) => _auth(
    () => _api.post(
      '/v1/auth/password-reset/confirm',
      authenticated: false,
      body: {'identifier': identifier.trim(), 'code': code, 'newPassword': newPassword},
    ),
    rejected: 'That code is invalid or has expired.',
  );
}
