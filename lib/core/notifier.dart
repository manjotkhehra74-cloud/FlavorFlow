import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app_settings.dart';
import 'company.dart';

/// Shared unread badge state. Server polling remains authoritative, while local
/// read actions update this immediately instead of waiting up to 20 seconds.
class NotificationBadge {
  static final ValueNotifier<int> count = ValueNotifier<int>(0);
  static int _mutation = 0;

  /// Capture this before an async server fetch. A local read that happens while
  /// the request is in flight invalidates the stale response.
  static int beginSync() => _mutation;

  static void syncFromServer(int value, int startedAtMutation) {
    if (startedAtMutation != _mutation) return;
    count.value = value < 0 ? 0 : value;
  }

  static void setFromLoadedList(int value) {
    _mutation++;
    count.value = value < 0 ? 0 : value;
  }

  static void markOneRead() {
    _mutation++;
    if (count.value > 0) count.value--;
  }

  static void markAllRead() {
    _mutation++;
    count.value = 0;
  }

  static void resetForAccount() {
    _mutation++;
    count.value = 0;
  }
}

/// Phone notifications (status-bar) for new ERP alerts.
///
/// The app polls /notifications while it is open or in the background (every
/// 45 s, and immediately when the app comes back to the front). A fully closed
/// app cannot poll: alerts that arrived meanwhile show on the next open. True
/// closed-app delivery needs a push service (FCM), which is not set up.
///
/// MAN-12: one business event = one phone notification. The server can store
/// the same event more than once (several writers), so every alert gets a
/// fingerprint (title + body + route); a fingerprint already shown in the last
/// 24 h is skipped, and the notification id is derived from the fingerprint so
/// a repeat can never stack up in the tray.
class PhoneNotifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _lastSeenId = 0;
  static bool _showing = false;

  static const _seenKey = 'notif_last_seen';
  static const _shownKey = 'notif_shown_fingerprints';
  static const _dedupeWindowMs = 24 * 60 * 60 * 1000;
  static Map<String, int> _shown = {}; // fingerprint → time shown (ms)
  static bool _shownLoaded = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'ff_alerts',
      'ERP Alerts',
      channelDescription: 'Low stock, approvals, production & dispatch alerts',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
      // Android 13+ runtime permission
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      // Remember where we left off across app restarts, so alerts that
      // arrived while the app was closed still pop on next open.
      try {
        _lastSeenId = (await SharedPreferences.getInstance()).getInt(_seenKey) ?? 0;
      } catch (_) {}
      _ready = true;
    } catch (_) {}
  }

  /// True when the phone currently allows FlavorFlow notifications.
  static Future<bool> notificationsAllowed() async {
    if (kIsWeb) return true;
    try {
      return await Permission.notification.isGranted;
    } catch (_) {
      return true;
    }
  }

  static Future<void> _persistSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_seenKey, _lastSeenId);
    } catch (_) {}
  }

  static Future<void> _loadShown() async {
    if (_shownLoaded) return;
    _shownLoaded = true;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_shownKey);
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map;
        _shown = {for (final e in m.entries) '${e.key}': (e.value as num).toInt()};
      }
    } catch (_) {}
  }

  static Future<void> _persistShown() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_shownKey, jsonEncode(_shown));
    } catch (_) {}
  }

  static String _fingerprint(Map<String, dynamic> n) =>
      '${n['title'] ?? ''}|${n['body'] ?? ''}|${n['route'] ?? ''}'.trim().toLowerCase();

  /// Stable notification id per event, kept clear of the reminder ids (900001/2).
  static int _idFor(String fingerprint) => 1000 + (fingerprint.hashCode & 0x7fffffff) % 800000;

  /// Show phone notifications for notifications newer than the last seen id.
  /// [items] = server list (each: id, title, body, is_read).
  static Future<void> showNew(List<Map<String, dynamic>> items) async {
    if (kIsWeb || !_ready) return;
    if (_showing) return; // overlapping poll — the running call handles it
    _showing = true;
    try {
      await _loadShown();
      final now = DateTime.now().millisecondsSinceEpoch;
      _shown.removeWhere((_, t) => now - t > _dedupeWindowMs);
      final unread = items.where((n) => n['is_read'] == 0).toList();
      // very first run on this device: don't blast history — remember newest
      if (_lastSeenId == 0) {
        for (final n in unread) {
          final id = (n['id'] as num?)?.toInt() ?? 0;
          if (id > _lastSeenId) _lastSeenId = id;
          _shown[_fingerprint(n)] = now; // history counts as already shown
        }
        await _persistSeen();
        await _persistShown();
        return;
      }
      final fresh = unread.where((n) => ((n['id'] as num?)?.toInt() ?? 0) > _lastSeenId).toList()
        ..sort((a, b) => ((a['id'] as num).toInt()).compareTo((b['id'] as num).toInt()));
      // don't blast a giant backlog either — show the latest few, mark rest seen
      if (fresh.length > 5) {
        for (final n in fresh.sublist(0, fresh.length - 5)) {
          final id = (n['id'] as num?)?.toInt() ?? 0;
          if (id > _lastSeenId) _lastSeenId = id;
          _shown[_fingerprint(n)] = now;
        }
      }
      final batchKeys = <String>{};
      for (final n in fresh) {
        final id = (n['id'] as num?)?.toInt() ?? 0;
        if (id <= _lastSeenId) continue;
        final fp = _fingerprint(n);
        final duplicate = _shown.containsKey(fp) || !batchKeys.add(fp);
        if (!duplicate) {
          _shown[fp] = now;
          await _plugin.show(_idFor(fp), '${n['title'] ?? 'FlavorFlow ERP'}', '${n['body'] ?? ''}', _details);
        }
        if (id > _lastSeenId) _lastSeenId = id;
      }
      await _persistSeen();
      await _persistShown();
    } catch (_) {} finally {
      _showing = false;
    }
  }
}

/// ---------------- Daily reminders (exact alarms) ----------------
/// 1) Daily production-entry reminder at a chosen hour:minute (default 5:00 PM)
/// 2) Month-end reminder (last day, 6 PM): closing-stock check + export
///    (+ close the Packing Loss % sheet where the company runs it).
class Reminders {
  static const _idDaily = 900001;
  static const _idMonthEnd = 900002;

  static Future<void> _init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  }

  /// Daily reminder at [hour]:[minute] (local time). Scheduling uses the same
  /// id every time, so changing the time replaces the alarm — no duplicates.
  static Future<void> enableDaily(int hour, [int minute = 0]) async {
    if (kIsWeb) return;
    try {
      await PhoneNotifier.init();
      await _init();
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.cancel(_idDaily);
      final now = tz.TZDateTime.now(tz.local);
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      if (at.isBefore(now)) at = at.add(const Duration(days: 1));
      await plugin.zonedSchedule(
        _idDaily,
        'FlavorFlow ERP — daily entry',
        'Aj di production, dispatch te consumption entries kar lao.',
        at,
        const NotificationDetails(
          android: AndroidNotificationDetails('ff_reminders', 'Reminders',
              channelDescription: 'Daily entry & month-end reminders',
              importance: Importance.high, priority: Priority.high),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // repeat daily
      );
    } catch (_) {}
  }

  static Future<void> enableMonthEnd() async {
    if (kIsWeb) return;
    try {
      await PhoneNotifier.init();
      await _init();
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.cancel(_idMonthEnd);
      final now = tz.TZDateTime.now(tz.local);
      // last day of current month, 18:00
      var lastDay = tz.TZDateTime(tz.local, now.year, now.month + 1, 1, 18).subtract(const Duration(days: 1));
      if (lastDay.isBefore(now)) {
        lastDay = tz.TZDateTime(tz.local, now.year, now.month + 2, 1, 18).subtract(const Duration(days: 1));
      }
      await plugin.zonedSchedule(
        _idMonthEnd,
        'FlavorFlow ERP — month end',
        CompanyProfile.usesLossPct
            ? 'Month end — Loss% sheet export karke month close kar lao (closing → next opening) + Stock Ledger / reports export.'
            : 'Month end — closing stock check karke Stock Ledger / reports export kar lao.',
        lastDay,
        const NotificationDetails(
          android: AndroidNotificationDetails('ff_reminders', 'Reminders',
              channelDescription: 'Daily entry & month-end reminders',
              importance: Importance.high, priority: Priority.high),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }

  /// App start: re-create the reminders the user switched on (alarms can be
  /// lost after a reboot, an app update or a force-stop).
  static Future<void> rescheduleIfEnabled() async {
    if (kIsWeb) return;
    final s = AppSettings.instance;
    if (!s.dailyReminder) return;
    await enableDaily(s.dailyReminderHour, s.dailyReminderMinute);
    await enableMonthEnd();
  }

  static Future<void> disableAll() async {
    if (kIsWeb) return;
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.cancel(_idDaily);
      await plugin.cancel(_idMonthEnd);
    } catch (_) {}
  }
}
