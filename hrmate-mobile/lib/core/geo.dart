import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// Site geofence as sent by `GET attendance/today` → `geofence{lat,lng,radiusM}`.
class Geofence {
  final double lat;
  final double lng;
  final double radiusM;
  const Geofence({required this.lat, required this.lng, required this.radiusM});

  static Geofence? fromJson(dynamic j) {
    if (j is! Map) return null;
    final lat = _d(j['lat']), lng = _d(j['lng']), r = _d(j['radiusM'] ?? j['radius']);
    if (lat == null || lng == null) return null;
    return Geofence(lat: lat, lng: lng, radiusM: r ?? 150);
  }

  static double? _d(dynamic v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  /// Haversine distance in metres from a point to the site centre.
  double distanceTo(double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat), dLng = _rad(lng2 - lng);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  bool contains(double lat2, double lng2) => distanceTo(lat2, lng2) <= radiusM;

  static double _rad(double deg) => deg * math.pi / 180;
}

/// A fix from the phone, plus what it means for the geofence.
class GeoFix {
  final double lat;
  final double lng;
  final double accuracyM;
  final double? distanceM; // null when no geofence known
  final bool inside;
  final bool mocked;
  const GeoFix({required this.lat, required this.lng, required this.accuracyM, required this.distanceM, required this.inside, required this.mocked});
}

/// Reason a fix could not be taken — the UI maps each to a message + action.
enum GeoFailure { serviceOff, denied, deniedForever, timeout }

class GeoException implements Exception {
  final GeoFailure reason;
  const GeoException(this.reason);
}

/// One-shot high-accuracy location for punching. No background tracking.
class Geo {
  static Future<GeoFix> locate(Geofence? fence, {Duration timeout = const Duration(seconds: 20)}) async {
    if (!await Geolocator.isLocationServiceEnabled()) throw const GeoException(GeoFailure.serviceOff);
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) throw const GeoException(GeoFailure.deniedForever);
    if (perm == LocationPermission.denied) throw const GeoException(GeoFailure.denied);
    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.best, timeLimit: timeout),
      );
    } catch (_) {
      // Fall back to the last known fix if it is fresh (< 2 min) — better than nothing on slow GPS.
      final last = await Geolocator.getLastKnownPosition();
      if (last == null || DateTime.now().difference(last.timestamp) > const Duration(minutes: 2)) {
        throw const GeoException(GeoFailure.timeout);
      }
      pos = last;
    }
    final d = fence?.distanceTo(pos.latitude, pos.longitude);
    return GeoFix(
      lat: pos.latitude,
      lng: pos.longitude,
      accuracyM: pos.accuracy,
      distanceM: d,
      inside: d == null || d <= (fence!.radiusM + math.min(pos.accuracy, 30)), // small accuracy allowance; server decides finally
      mocked: pos.isMocked,
    );
  }

  static Future<void> openSettings() async {
    await Geolocator.openLocationSettings();
  }

  static Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }
}
