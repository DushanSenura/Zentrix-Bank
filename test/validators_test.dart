import 'package:bank_app/core/utils/formatters.dart';
import 'package:bank_app/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  phoneValidatorTests();
  group('Validators', () {
    test('email', () {
      expect(Validators.email('a@b.co'), isNull);
      expect(Validators.email('nope'), isNotNull);
      expect(Validators.email(''), isNotNull);
    });

    test('password rules', () {
      expect(Validators.password('Abcdef1!'), isNull);
      expect(Validators.password('abcdef1!'), isNotNull); // no uppercase
      expect(Validators.password('Abcdefg!'), isNotNull); // no number
      expect(Validators.password('Ab1!'), isNotNull); // too short
    });

    test('amount', () {
      expect(Validators.amount('25,000.00'), isNull);
      expect(Validators.amount('0'), isNotNull);
      expect(Validators.amount('abc'), isNotNull);
      expect(Validators.amount('500', max: 100), isNotNull);
    });

    test('pin and account number', () {
      expect(Validators.pin('123456'), isNull);
      expect(Validators.pin('1234'), isNotNull);
      expect(Validators.accountNumber('1000200030'), isNull);
      expect(Validators.accountNumber('12ab'), isNotNull);
    });
  });

  group('Formatters', () {
    test('money', () {
      expect(formatMoney(428750), 'LKR 428,750.00');
      expect(formatMoney(-1500, signed: true), '-LKR 1,500.00');
      expect(formatMoney(185000, signed: true), '+LKR 185,000.00');
    });
  });
}

void phoneValidatorTests() {
  group('Validators.phone', () {
    test('accepts local and international formats, with spaces or dashes', () {
      for (final ok in ['0771234567', '077 123 4567', '077-123-4567', '+94 77 123 4567', '+94771234567']) {
        expect(Validators.phone(ok), isNull, reason: ok);
      }
    });

    test('rejects empty, too short, letters and a misplaced +', () {
      for (final bad in ['', '12345', 'abcdefghij', '077+1234567', '++94771234567', '0771234567890123456']) {
        expect(Validators.phone(bad), isNotNull, reason: bad);
      }
    });
  });
}
