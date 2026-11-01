/// Removes secrets and personal data before anything is written to a log.
/// Allow-listing would be safer still; this deny-list errs on the side of hiding too much.
class LogSanitizer {
  const LogSanitizer._();

  static const redacted = '‹redacted›';

  static const _secretKeys = [
    'password',
    'passwd',
    'pin',
    'token',
    'secret',
    'authorization',
    'cookie',
    'otp',
    'code',
    'cvv',
    'cvc',
    'pan',
    'cardnumber',
    'accountnumber',
    'nic',
    'passport',
    'dob',
    'birth',
    'address',
    'email',
    'phone',
    'idempotency',
  ];

  static bool _isSecret(String key) {
    final k = key.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return _secretKeys.any(k.contains);
  }

  /// Long digit runs look like card or account numbers: keep only the last four.
  static String maskDigits(String s) => s.replaceAllMapped(RegExp(r'\d{9,19}'), (m) => '••••${m[0]!.substring(m[0]!.length - 4)}');

  static Object? body(Object? value) {
    if (value is Map) {
      return {for (final e in value.entries) e.key: _isSecret('${e.key}') ? redacted : body(e.value)};
    }
    if (value is List) return [for (final v in value) body(v)];
    if (value is String) return maskDigits(value);
    return value;
  }

  static Map<String, Object?> headers(Map<String, dynamic> h) => {
    for (final e in h.entries) e.key: _isSecret(e.key) ? redacted : e.value,
  };

  /// Query strings can carry identifiers, so only their keys are logged.
  static String uri(Uri uri) => '${uri.origin}${uri.path}${uri.hasQuery ? '?${uri.queryParameters.keys.join('&')}' : ''}';
}
