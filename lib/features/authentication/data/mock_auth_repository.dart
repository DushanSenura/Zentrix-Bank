import 'dart:math';
import '../../../shared/models/models.dart';
import '../domain/auth_repository.dart';

/// Prototype auth. Nothing here talks to a bank; credentials are held in memory
/// only and the sample password exists purely so the app can be explored.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository({this.latency = const Duration(milliseconds: 900)});
  final Duration latency;

  static const demoUsername = 'dushan';
  static const demoUserId = 'u-001';
  static const demoPassword = 'Dushan@123';

  /// Accepted by [confirmPasswordReset] in this prototype; a real service emails/SMSes a code.
  static const demoResetCode = '123456';

  static const demoUser = AppUser(
    id: demoUserId,
    fullName: 'Dushan Perera',
    firstName: 'Dushan',
    customerNumber: 'NC 1029 3847',
    email: 'dushan@example.com',
    phone: '+94 77 123 4567',
  );

  final _users = <String, ({String password, AppUser user})>{
    demoUsername: (password: demoPassword, user: demoUser),
  };
  final _tokens = <String, AppUser>{};
  final _rng = Random.secure();

  String _key(String identifier) {
    final id = identifier.trim().toLowerCase();
    return (id == demoUser.email || id == 'nc10293847') ? demoUsername : id;
  }

  @override
  Future<AppUser> signIn(String identifier, String password) async {
    await Future<void>.delayed(latency);
    final entry = _users[_key(identifier)];
    if (entry != null && entry.password == password) return entry.user;
    throw const AuthException('Incorrect username or password.');
  }

  @override
  Future<AppUser> register({
    required String fullName,
    required String username,
    required String password,
    required double initialDeposit,
    Map<String, String> profile = const {},
  }) async {
    await Future<void>.delayed(latency);
    final key = username.trim().toLowerCase();
    if (_users.containsKey(key)) throw const AuthException('That username is already taken.');
    final n = _users.length;
    final user = AppUser(
      id: 'u-${n + 1}',
      fullName: fullName,
      firstName: fullName.trim().split(' ').first,
      customerNumber: 'NC ${(1000 + n).toString().padLeft(4, '0')} ${(2000 + n * 7).toString().padLeft(4, '0')}',
      email: profile['email'] ?? '',
      phone: profile['mobile'] ?? '',
    );
    _users[key] = (password: password, user: user);
    return user;
  }

  @override
  Future<String> issueRefreshToken(AppUser user) async {
    final token = List.generate(24, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    _tokens[token] = user;
    return token;
  }

  @override
  Future<AppUser?> restoreSession(String refreshToken) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return _tokens[refreshToken];
  }

  @override
  Future<void> signOut() async => _tokens.clear();

  @override
  Future<void> changePassword({required String userId, required String current, required String next}) async {
    await Future<void>.delayed(latency);
    final key = _users.entries.where((e) => e.value.user.id == userId).map((e) => e.key).firstOrNull;
    if (key == null || _users[key]!.password != current) throw const AuthException('Your current password is incorrect.');
    _users[key] = (password: next, user: _users[key]!.user);
  }

  @override
  Future<AppUser> updateContact({required String userId, required String email, required String phone}) async {
    await Future<void>.delayed(latency);
    final key = _users.entries.where((e) => e.value.user.id == userId).map((e) => e.key).firstOrNull;
    if (key == null) throw const AuthException('We couldn’t find your profile.');
    final taken = _users.entries.any((e) => e.key != key && e.value.user.email.toLowerCase() == email.toLowerCase() && email.isNotEmpty);
    if (taken) throw const AuthException('That email address is already used by another customer.');
    final old = _users[key]!.user;
    final updated = AppUser(id: old.id, fullName: old.fullName, firstName: old.firstName, customerNumber: old.customerNumber, email: email, phone: phone);
    _users[key] = (password: _users[key]!.password, user: updated);
    return updated;
  }

  @override
  Future<void> requestPasswordReset(String identifier) async {
    await Future<void>.delayed(latency);
  }

  @override
  Future<void> confirmPasswordReset({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    await Future<void>.delayed(latency);
    final key = _key(identifier);
    final entry = _users[key];
    if (entry == null || code != demoResetCode) {
      throw const AuthException('That code is invalid or has expired.');
    }
    _users[key] = (password: newPassword, user: entry.user);
  }
}
