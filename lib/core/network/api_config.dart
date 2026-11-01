import 'package:flutter/foundation.dart';

/// Where the real backend lives. Supplied at build time so no environment is baked into source:
///
///     flutter run --dart-define=API_BASE_URL=https://api.example-bank.test
///     flutter build apk --dart-define=API_BASE_URL=https://api.zentrix.example \
///       --dart-define=API_PINS=<sha256-of-cert-hex>,<backup-pin-hex>
@immutable
class ApiConfig {
  ApiConfig({
    required this.baseUrl,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 20),
    this.certificatePins = const [],
    bool? allowInsecureLoopback,
  }) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'must be an absolute URL');
    }
    final loopback = uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '10.0.2.2';
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback && (allowInsecureLoopback ?? kDebugMode))) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'must use https (plain http is allowed only for local debug servers)');
    }
  }

  final String baseUrl;
  final Duration connectTimeout, receiveTimeout;

  /// Lower-case hex SHA-256 digests of server certificates (DER). Empty = rely on the system trust store.
  final List<String> certificatePins;

  /// Null when the build has no backend, which keeps the app on its in-memory mocks.
  static ApiConfig? fromEnvironment() {
    const url = String.fromEnvironment('API_BASE_URL');
    if (url.isEmpty) return null;
    const pins = String.fromEnvironment('API_PINS');
    return ApiConfig(
      baseUrl: url,
      certificatePins: pins.isEmpty ? const [] : pins.split(',').map((p) => p.trim().toLowerCase()).where((p) => p.isNotEmpty).toList(),
    );
  }
}
