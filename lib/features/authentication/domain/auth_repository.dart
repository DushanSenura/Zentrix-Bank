import '../../../shared/models/models.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class AuthRepository {
  /// Throws [AuthException] when the credentials are not accepted.
  Future<AppUser> signIn(String identifier, String password);

  /// [profile] carries every collected registration field (name, address, KYC answers…).
  Future<AppUser> register({
    required String fullName,
    required String username,
    required String password,
    required double initialDeposit,
    Map<String, String> profile = const {},
  });

  /// Issues a long-lived token that can later re-open the session via [restoreSession].
  Future<String> issueRefreshToken(AppUser user);

  /// Returns null when the token is unknown, expired or revoked.
  Future<AppUser?> restoreSession(String refreshToken);

  Future<void> signOut();

  /// Throws [AuthException] when [current] is wrong.
  Future<void> changePassword({required String userId, required String current, required String next});

  /// Changes the email and mobile number on file and returns the updated customer.
  /// Throws [AuthException] if the bank refuses (for example the number belongs to another customer).
  Future<AppUser> updateContact({required String userId, required String email, required String phone});

  /// Always completes normally so callers cannot learn whether an account exists.
  Future<void> requestPasswordReset(String identifier);

  /// Throws [AuthException] for any invalid identifier/code combination.
  Future<void> confirmPasswordReset({
    required String identifier,
    required String code,
    required String newPassword,
  });
}
