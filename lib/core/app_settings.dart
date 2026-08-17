import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device app preferences: text size, dark theme, notification badge.
/// Persisted in SharedPreferences; applied instantly across the app.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  /// 1.0 = normal · 1.15 = large · 1.3 = extra large (factory floor).
  double textScale = 1.0;
  bool darkMode = false;
  bool showNotifBadge = true;
  bool dailyReminder = false;
  int dailyReminderHour = 17; // 5 PM

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      textScale = p.getDouble('set_text_scale') ?? 1.0;
      darkMode = p.getBool('set_dark_mode') ?? false;
      showNotifBadge = p.getBool('set_notif_badge') ?? true;
      dailyReminder = p.getBool('set_daily_reminder') ?? false;
      dailyReminderHour = p.getInt('set_daily_reminder_hour') ?? 17;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setTextScale(double v) async {
    textScale = v;
    notifyListeners();
    try { (await SharedPreferences.getInstance()).setDouble('set_text_scale', v); } catch (_) {}
  }

  Future<void> setDarkMode(bool v) async {
    darkMode = v;
    notifyListeners();
    try { (await SharedPreferences.getInstance()).setBool('set_dark_mode', v); } catch (_) {}
  }

  Future<void> setShowNotifBadge(bool v) async {
    showNotifBadge = v;
    notifyListeners();
    try { (await SharedPreferences.getInstance()).setBool('set_notif_badge', v); } catch (_) {}
  }

  Future<void> setDailyReminder(bool v, int hour) async {
    dailyReminder = v;
    dailyReminderHour = hour;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('set_daily_reminder', v);
      await p.setInt('set_daily_reminder_hour', hour);
    } catch (_) {}
  }
}
