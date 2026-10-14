import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-time upfront permission request — like big apps do on first open.
/// Asks all the permissions the app uses in one flow:
/// notifications · camera (QR scan) · photos · location (dispatch stamp).
/// Runs once (flag saved); later the OS remembers each answer anyway.
class AppPermissions {
  static Future<void> requestAllOnce() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('perms_asked') ?? false) return;
      await [
        Permission.notification,
        Permission.camera,
        Permission.photos, // Android 13+: READ_MEDIA_IMAGES
        Permission.locationWhenInUse,
      ].request();
      // Xiaomi/Oppo aggressive battery killers: ask to exempt the app so
      // notification polling keeps working (system dialog, one time).
      try {
        final st = await Permission.ignoreBatteryOptimizations.status;
        if (!st.isGranted) await Permission.ignoreBatteryOptimizations.request();
      } catch (_) {}
      await prefs.setBool('perms_asked', true);
    } catch (_) {}
  }

  /// Camera check right before the scanner opens (in case it was denied).
  static Future<bool> ensureCamera() async {
    if (kIsWeb) return true;
    try {
      var st = await Permission.camera.status;
      if (!st.isGranted) st = await Permission.camera.request();
      if (st.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      return st.isGranted;
    } catch (_) {
      return true; // let the scanner surface its own error
    }
  }
}
