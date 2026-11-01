import 'pin_hasher.dart';
import 'secure_store.dart';

/// Everything persisted for "remember me" and app unlock. Holds a refresh token,
/// a salted PIN hash and the biometric preference — never a password or a raw PIN.
class SessionStore {
  SessionStore(this._store);
  final SecureStore _store;

  static const _token = 'refresh_token';
  static const _salt = 'pin_salt';
  static const _hash = 'pin_hash';
  static const _bio = 'biometric_enabled';
  static const _len = 'pin_length';

  Future<String?> refreshToken() => _store.read(_token);
  Future<void> saveRefreshToken(String token) => _store.write(_token, token);

  Future<bool> hasPin() async => await _store.read(_hash) != null;

  /// How many digits the stored PIN has (4 or 6), so screens know how many dots to show.
  Future<int> pinLength() async {
    final n = int.tryParse(await _store.read(_len) ?? '');
    return n == 4 ? 4 : 6;
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^(\d{4}|\d{6})$').hasMatch(pin)) throw ArgumentError.value('PIN', 'pin', 'must be exactly 4 or 6 digits');
    await _store.write(_len, pin.length.toString());
    final salt = PinHasher.newSalt();
    await _store.write(_salt, salt);
    await _store.write(_hash, PinHasher.hash(pin, salt));
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _store.read(_salt);
    final hash = await _store.read(_hash);
    if (salt == null || hash == null) return false;
    return PinHasher.verify(pin, salt, hash);
  }

  Future<bool> biometricEnabled() async => await _store.read(_bio) == 'true';
  Future<void> setBiometricEnabled(bool on) => _store.write(_bio, on.toString());

  /// A returning user can unlock only if both a token and a PIN exist.
  Future<bool> canUnlock() async => await refreshToken() != null && await hasPin();

  Future<void> clear() async {
    for (final key in [_token, _salt, _hash, _bio, _len]) {
      await _store.delete(key);
    }
  }
}
