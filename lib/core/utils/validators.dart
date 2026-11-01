/// Centralised, UI-agnostic validators. Each returns an error message or null.
class Validators {
  const Validators._();

  static String? required(String? v, [String field = 'This field']) =>
      (v ?? '').trim().isEmpty ? '$field is required.' : null;

  static String? email(String? v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return 'Email is required.';
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text) ? null : 'Enter a valid email address.';
  }

  static String? phone(String? v) {
    final text = (v ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (text.isEmpty) return 'Mobile number is required.';
    return RegExp(r'^\+?\d{7,15}$').hasMatch(text) ? null : 'Enter a valid mobile number.';
  }

  static String? accountNumber(String? v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return 'Account number is required.';
    return RegExp(r'^\d{8,16}$').hasMatch(text) ? null : 'Account numbers have 8–16 digits.';
  }

  static String? amount(String? v, {double? max}) {
    final n = double.tryParse((v ?? '').replaceAll(',', '').trim());
    if (n == null || !n.isFinite || n <= 0) return 'Enter a valid amount.';
    if (max != null && n > max) return 'Amount exceeds your available balance.';
    return null;
  }

  static String? fullName(String? v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return 'Full name is required.';
    return text.contains(' ') && text.length >= 5 ? null : 'Enter your first and last name.';
  }

  /// Sri Lankan NIC (old 9 digits + V/X, new 12 digits) or a passport (6–9 letters/digits).
  static String? idDocument(String? v) {
    final text = (v ?? '').trim().toUpperCase();
    if (text.isEmpty) return 'NIC or passport number is required.';
    final ok = RegExp(r'^(\d{9}[VX]|\d{12}|[A-Z0-9]{6,9})$').hasMatch(text);
    return ok ? null : 'Enter a valid NIC or passport number.';
  }

  static String? postalCode(String? v) =>
      RegExp(r'^\d{5}$').hasMatch((v ?? '').trim()) ? null : 'Postal codes have 5 digits.';

  /// Expects `dd/MM/yyyy`; the customer must be at least 18.
  static String? adultDateOfBirth(String? v, DateTime now) {
    final parts = (v ?? '').split('/');
    if (parts.length != 3) return 'Select your date of birth.';
    final d = int.tryParse(parts[0]), m = int.tryParse(parts[1]), y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return 'Select your date of birth.';
    final dob = DateTime(y, m, d);
    final adult = DateTime(dob.year + 18, dob.month, dob.day);
    return adult.isAfter(now) ? 'You must be at least 18 to open an account.' : null;
  }

  static String? initialDeposit(String? v, {double minimum = 1000}) {
    final n = double.tryParse((v ?? '').replaceAll(',', '').trim());
    if (n == null || !n.isFinite) return 'Enter a valid amount.';
    return n < minimum ? 'The minimum opening deposit is LKR ${minimum.toStringAsFixed(0)}.' : null;
  }

  static String? username(String? v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return 'Username is required.';
    return RegExp(r'^[A-Za-z][A-Za-z0-9._]{3,19}$').hasMatch(text)
        ? null
        : 'Use 4–20 letters, numbers, dots or underscores, starting with a letter.';
  }

  static String? matches(String? v, String other, [String message = 'Passwords do not match.']) =>
      v == other ? null : message;

  static String? pin(String? v) =>
      RegExp(r'^\d{6}$').hasMatch(v ?? '') ? null : 'Your PIN has 6 digits.';

  static String? password(String? v) {
    final text = v ?? '';
    if (text.isEmpty) return 'Password is required.';
    return PasswordRule.all.every((r) => r.test(text)) ? null : 'Password does not meet all requirements.';
  }
}

class PasswordRule {
  const PasswordRule(this.label, this.test);
  final String label;
  final bool Function(String) test;

  static final all = [
    PasswordRule('At least 8 characters', (s) => s.length >= 8),
    PasswordRule('An uppercase letter', (s) => s.contains(RegExp('[A-Z]'))),
    PasswordRule('A lowercase letter', (s) => s.contains(RegExp('[a-z]'))),
    PasswordRule('A number', (s) => s.contains(RegExp('[0-9]'))),
    PasswordRule('A special character', (s) => s.contains(RegExp(r'[^A-Za-z0-9]'))),
  ];
}
