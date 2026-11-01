import 'package:flutter/foundation.dart';

enum NotifCategory { transactions, security, payments, offers, bankNotices }

enum Severity { info, warning, critical }

@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.date,
    this.read = false,
    this.severity = Severity.info,
  });
  final String id, title, body;
  final NotifCategory category;
  final DateTime date;
  final bool read;

  /// Only meaningful for security alerts.
  final Severity severity;

  AppNotification copyWith({bool? read}) =>
      AppNotification(id: id, category: category, title: title, body: body, date: date, read: read ?? this.read, severity: severity);
}

@immutable
class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastActive,
    required this.approxLocation,
    this.current = false,
  });
  final String id, name, platform, approxLocation;
  final DateTime lastActive;
  final bool current;
}

@immutable
class LoginEvent {
  const LoginEvent({required this.date, required this.device, required this.success, required this.approxLocation});
  final DateTime date;
  final String device, approxLocation;
  final bool success;
}

@immutable
class TransferLimits {
  const TransferLimits({required this.bankMaximum, required this.daily});

  /// Ceiling set by the bank; the customer can only lower their own limit.
  final double bankMaximum, daily;
}

@immutable
class SupportBranch {
  const SupportBranch({
    required this.name,
    required this.address,
    required this.distanceKm,
    required this.isAtm,
    this.latitude,
    this.longitude,
  });
  final String name, address;

  /// From a fixed reference point until the customer shares their location, then from where they are.
  final double distanceKm;
  final bool isAtm;
  final double? latitude, longitude;

  bool get hasLocation => latitude != null && longitude != null;

  SupportBranch withDistance(double km) =>
      SupportBranch(name: name, address: address, distanceKm: km, isAtm: isAtm, latitude: latitude, longitude: longitude);
}
