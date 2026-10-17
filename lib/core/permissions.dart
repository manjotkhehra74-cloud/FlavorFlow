import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_support.dart';

/// Ask for notification permission once. Other access is requested only when
/// the user invokes the feature: Android's system picker handles photos, and
/// the dispatch form asks for location when the operator submits a dispatch.
class AppPermissions {
  static Future<void> requestNotificationOnce() async {
    if (!isPhonePlatform) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('perms_asked') ?? false) return;
      await Permission.notification.request();
      await prefs.setBool('perms_asked', true);
    } catch (_) {}
  }
}
