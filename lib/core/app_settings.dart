import 'dart:async';
import 'dart:ui' show PlatformDispatcher, Brightness;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dark theme behaviour:
///   off    — always light
///   on     — always dark
///   system — follow the phone's dark-mode setting
///   auto   — by TIME: dark from [autoDarkStart] to [autoDarkEnd] (evening →
///            morning) even when the phone has no dark-mode schedule.
enum DarkPref { off, on, system, auto }

/// Per-device app preferences: text size, dark theme, notification badge.
/// Persisted in SharedPreferences; applied instantly across the app.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  /// 1.0 = normal · 1.15 = large · 1.3 = extra large (factory floor).
  double textScale = 1.0;
  DarkPref darkPref = DarkPref.off;
  int autoDarkStart = 19; // 7 PM → dark
  int autoDarkEnd = 6; // 6 AM → light again
  bool showNotifBadge = true;
  bool dailyReminder = false;
  int dailyReminderHour = 17; // 5 PM

  Timer? _autoTimer;

  /// Legacy accessor — true when the RESOLVED theme is dark right now.
  bool get darkMode => resolveDark();

  /// Resolve the effective dark flag for this moment.
  bool resolveDark() {
    switch (darkPref) {
      case DarkPref.off:
        return false;
      case DarkPref.on:
        return true;
      case DarkPref.system:
        return PlatformDispatcher.instance.platformBrightness == Brightness.dark;
      case DarkPref.auto:
        final h = DateTime.now().hour;
        // window crosses midnight (e.g. 19 → 6)
        return autoDarkStart > autoDarkEnd
            ? (h >= autoDarkStart || h < autoDarkEnd)
            : (h >= autoDarkStart && h < autoDarkEnd);
    }
  }

  /// In auto mode re-check every minute so the switch happens by itself;
  /// in system mode listen to the OS brightness change.
  void _watch() {
    _autoTimer?.cancel();
    PlatformDispatcher.instance.onPlatformBrightnessChanged = null;
    if (darkPref == DarkPref.auto) {
      _autoTimer = Timer.periodic(const Duration(minutes: 1), (_) => notifyListeners());
    } else if (darkPref == DarkPref.system) {
      PlatformDispatcher.instance.onPlatformBrightnessChanged = notifyListeners;
    }
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      textScale = p.getDouble('set_text_scale') ?? 1.0;
      final dp = p.getString('set_dark_pref');
      if (dp != null) {
        darkPref = DarkPref.values.firstWhere((e) => e.name == dp, orElse: () => DarkPref.off);
      } else {
        // migrate the old on/off switch
        darkPref = (p.getBool('set_dark_mode') ?? false) ? DarkPref.on : DarkPref.off;
      }
      autoDarkStart = p.getInt('set_auto_dark_start') ?? 19;
      autoDarkEnd = p.getInt('set_auto_dark_end') ?? 6;
      showNotifBadge = p.getBool('set_notif_badge') ?? true;
      dailyReminder = p.getBool('set_daily_reminder') ?? false;
      dailyReminderHour = p.getInt('set_daily_reminder_hour') ?? 17;
      _watch();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setDarkPref(DarkPref v, {int? start, int? end}) async {
    darkPref = v;
    if (start != null) autoDarkStart = start;
    if (end != null) autoDarkEnd = end;
    _watch();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('set_dark_pref', v.name);
      await p.setInt('set_auto_dark_start', autoDarkStart);
      await p.setInt('set_auto_dark_end', autoDarkEnd);
    } catch (_) {}
  }

  Future<void> setTextScale(double v) async {
    textScale = v;
    notifyListeners();
    try { (await SharedPreferences.getInstance()).setDouble('set_text_scale', v); } catch (_) {}
  }

  /// Legacy switch — maps to DarkPref.on / DarkPref.off.
  Future<void> setDarkMode(bool v) async => setDarkPref(v ? DarkPref.on : DarkPref.off);

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
