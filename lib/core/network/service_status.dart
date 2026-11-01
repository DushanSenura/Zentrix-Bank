import 'package:flutter/foundation.dart';

/// Whether the bank has taken its service offline on purpose.
@immutable
class ServiceStatus {
  const ServiceStatus({this.maintenance = false, this.message, this.retryAfter});
  final bool maintenance;
  final String? message;
  final Duration? retryAfter;

  static const normal = ServiceStatus();
}

/// Asks the bank whether it is serving requests again.
abstract interface class HealthCheck {
  Future<bool> isUp();
}

class AlwaysUpHealthCheck implements HealthCheck {
  const AlwaysUpHealthCheck();
  @override
  Future<bool> isUp() async => true;
}
