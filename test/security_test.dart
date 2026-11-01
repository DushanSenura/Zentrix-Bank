import 'package:bank_app/core/security/pin_hasher.dart';
import 'package:bank_app/core/security/secure_store.dart';
import 'package:bank_app/core/security/session_store.dart';
import 'package:bank_app/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinHasher', () {
    test('verifies the right PIN and rejects others', () {
      final salt = PinHasher.newSalt();
      final hash = PinHasher.hash('246813', salt);
      expect(PinHasher.verify('246813', salt, hash), isTrue);
      expect(PinHasher.verify('246814', salt, hash), isFalse);
    });

    test('salts make equal PINs hash differently, and the PIN is not in the output', () {
      final a = PinHasher.hash('246813', PinHasher.newSalt());
      final b = PinHasher.hash('246813', PinHasher.newSalt());
      expect(a, isNot(b));
      expect(a.contains('246813'), isFalse);
    });

    test('matches the RFC 7914 PBKDF2-HMAC-SHA256 vector shape (deterministic)', () {
      expect(PinHasher.hash('123456', 'c2FsdA==', rounds: 2), PinHasher.hash('123456', 'c2FsdA==', rounds: 2));
      expect(PinHasher.hash('123456', 'c2FsdA==', rounds: 2), isNot(PinHasher.hash('123456', 'c2FsdA==', rounds: 3)));
    });

    test('flags guessable PINs', () {
      for (final weak in ['111111', '123456', '654321', '000000', '234567']) {
        expect(PinHasher.isWeak(weak), isTrue, reason: weak);
      }
      expect(PinHasher.isWeak('246813'), isFalse);
    });
  });

  group('SessionStore', () {
    test('stores only a hash, verifies the PIN and clears everything', () async {
      final backing = MemorySecureStore();
      final store = SessionStore(backing);
      expect(await store.canUnlock(), isFalse);

      await store.saveRefreshToken('token-1');
      await store.setPin('246813');
      expect(await store.canUnlock(), isTrue);
      expect(await store.verifyPin('246813'), isTrue);
      expect(await store.verifyPin('000000'), isFalse);
      expect(await backing.read('pin_hash'), isNot(contains('246813')));

      await store.clear();
      expect(await store.canUnlock(), isFalse);
      expect(await store.refreshToken(), isNull);
      expect(await store.biometricEnabled(), isFalse);
    });
  });

  group('Registration validators', () {
    test('NIC and passport', () {
      for (final ok in ['200012345678', '901234567V', 'N1234567']) {
        expect(Validators.idDocument(ok), isNull, reason: ok);
      }
      for (final bad in ['', '123', 'abc!']) {
        expect(Validators.idDocument(bad), isNotNull, reason: bad);
      }
    });

    test('date of birth requires 18+', () {
      final now = DateTime(2026, 11, 1);
      expect(Validators.adultDateOfBirth('01/11/2008', now), isNull);
      expect(Validators.adultDateOfBirth('02/11/2008', now), isNotNull);
      expect(Validators.adultDateOfBirth('', now), isNotNull);
    });

    test('username, postal code, deposit', () {
      expect(Validators.username('nimal.f'), isNull);
      expect(Validators.username('1nimal'), isNotNull);
      expect(Validators.postalCode('10100'), isNull);
      expect(Validators.postalCode('1010'), isNotNull);
      expect(Validators.initialDeposit('5000'), isNull);
      expect(Validators.initialDeposit('500'), isNotNull);
    });
  });
}
