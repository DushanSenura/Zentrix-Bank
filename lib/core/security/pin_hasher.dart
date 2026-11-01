import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Salted PBKDF2-HMAC-SHA256 for the on-device unlock PIN.
///
/// This only guards the local app lock. Real transaction authorisation must be
/// verified server-side; the client never decides that a PIN is "correct" for money movement.
class PinHasher {
  const PinHasher._();

  static const iterations = 20000;

  static String newSalt() {
    final rng = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => rng.nextInt(256)));
  }

  static String hash(String pin, String salt, {int rounds = iterations}) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    // PBKDF2 with a single 32-byte output block.
    var u = hmac.convert([...base64Url.decode(salt), 0, 0, 0, 1]).bytes;
    final out = List<int>.from(u);
    for (var i = 1; i < rounds; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return base64Url.encode(out);
  }

  /// Constant-time comparison.
  static bool verify(String pin, String salt, String expected, {int rounds = iterations}) {
    final actual = hash(pin, salt, rounds: rounds);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Rejects PINs that are trivially guessable.
  static bool isWeak(String pin) {
    if (RegExp(r'^(\d)\1+$').hasMatch(pin)) return true;
    const runs = '0123456789012345678909876543210';
    return runs.contains(pin);
  }
}
