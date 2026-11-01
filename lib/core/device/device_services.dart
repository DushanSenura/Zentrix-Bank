import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// A rough position, used only to sort branches and ATMs by distance. Never stored or sent anywhere.
@immutable
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude, longitude;
}

abstract interface class LocationService {
  /// The device's current approximate position, or null when location is off or the customer declined.
  /// Asks for permission the first time; call it only in response to the customer asking for "near me".
  Future<GeoPoint?> current();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<GeoPoint?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 10)),
      );
      return GeoPoint(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }
}
