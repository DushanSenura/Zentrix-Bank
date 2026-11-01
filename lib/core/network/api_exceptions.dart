/// Everything the network layer can throw. Repositories and the UI only ever see these,
/// never a raw `DioException`, so no URL, header or server stack trace can leak into a screen.
sealed class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.requestId});

  /// Safe to show to the customer.
  final String message;
  final int? statusCode;

  /// Echoes the `X-Request-Id` we sent, so support can find the call in server logs.
  final String? requestId;

  @override
  String toString() => message;
}

/// No connection, DNS failure, TLS failure or timeout.
class NetworkException extends ApiException {
  const NetworkException([super.message = 'Can’t reach the bank. Check your connection and try again.', String? requestId])
    : super(requestId: requestId);
}

/// The access token was rejected and could not be refreshed.
class UnauthorizedException extends ApiException {
  const UnauthorizedException([super.message = 'Your session has expired. Please sign in again.', String? requestId])
    : super(statusCode: 401, requestId: requestId);
}

/// The bank has switched the service off for maintenance (HTTP 503 with code `maintenance`).
class MaintenanceException extends ApiException {
  const MaintenanceException([super.message = 'Zentrix Bank is briefly unavailable while we make improvements.', this.retryAfter, String? requestId])
    : super(statusCode: 503, requestId: requestId);
  final Duration? retryAfter;
}

/// The request was understood but refused (4xx other than 401). [code] is a stable machine-readable reason.
class RejectedException extends ApiException {
  const RejectedException(super.message, {required this.code, super.statusCode, super.requestId, this.fieldErrors = const {}});
  final String code;
  final Map<String, String> fieldErrors;
}

/// 5xx, or a response we could not understand.
class ServerException extends ApiException {
  const ServerException([super.message = 'Something went wrong on our side. Please try again.', int? statusCode, String? requestId])
    : super(statusCode: statusCode, requestId: requestId);
}
