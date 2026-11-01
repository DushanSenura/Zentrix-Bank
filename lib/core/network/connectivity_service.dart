import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

abstract interface class ConnectivityService {
  Future<bool> isOnline();

  /// Emits whenever the device gains or loses a network interface.
  Stream<bool> get onlineChanges;
}

/// Reports whether the device has a network interface up. That is not proof the bank is reachable
/// (a captive portal still counts as "online"); real failures surface as `NetworkException`.
class PlatformConnectivityService implements ConnectivityService {
  PlatformConnectivityService([Connectivity? connectivity]) : _c = connectivity ?? Connectivity();
  final Connectivity _c;

  static bool _up(List<ConnectivityResult> r) => r.any((e) => e != ConnectivityResult.none);

  /// If the platform can't tell us, assume online rather than block the customer.
  @override
  Future<bool> isOnline() async {
    try {
      return _up(await _c.checkConnectivity());
    } catch (_) {
      return true;
    }
  }

  @override
  Stream<bool> get onlineChanges => _c.onConnectivityChanged.map(_up).handleError((Object _) {});
}
