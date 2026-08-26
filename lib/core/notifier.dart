import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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
/// The app polls /notifications every 20s while open;
/// this class turns NEW unread items into real Android notifications with
/// sound — like any other app. No Firebase needed: notifications appear
/// while the app is open or minimised (polling keeps running in background
/// for a while); a fully-closed app shows them on next open.
class PhoneNotifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _lastSeenId = 0;

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
        _lastSeenId = (await SharedPreferences.getInstance()).getInt('notif_last_seen') ?? 0;
      } catch (_) {}
      _ready = true;
    } catch (_) {}
  }

  static Future<void> _persistSeen() async {
    try { (await SharedPreferences.getInstance()).setInt('notif_last_seen', _lastSeenId); } catch (_) {}
  }

  /// Show phone notifications for notifications newer than the last seen id.
  /// [items] = server list (each: id, title, body, is_read).
  static Future<void> showNew(List<Map<String, dynamic>> items) async {
    if (kIsWeb || !_ready) return;
    try {
      final unread = items.where((n) => n['is_read'] == 0).toList();
      // very first run on this device: don't blast history — remember newest
      if (_lastSeenId == 0) {
        for (final n in unread) {
          final id = (n['id'] as num?)?.toInt() ?? 0;
          if (id > _lastSeenId) _lastSeenId = id;
        }
        await _persistSeen();
        return;
      }
      // don't blast a giant backlog either — show the latest few, mark rest seen
      final fresh = unread.where((n) => ((n['id'] as num?)?.toInt() ?? 0) > _lastSeenId).toList()
        ..sort((a, b) => ((a['id'] as num).toInt()).compareTo((b['id'] as num).toInt()));
      if (fresh.length > 5) {
        for (final n in fresh.sublist(0, fresh.length - 5)) {
          final id = (n['id'] as num?)?.toInt() ?? 0;
          if (id > _lastSeenId) _lastSeenId = id;
        }
      }
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'ff_alerts', 'ERP Alerts',
          channelDescription: 'Low stock, approvals, production & dispatch alerts',
          importance: Importance.high, priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );
      for (final n in unread) {
        final id = (n['id'] as num?)?.toInt() ?? 0;
        if (id <= _lastSeenId) continue;
        await _plugin.show(
          id,
          '${n['title'] ?? 'FlavorFlow ERP'}',
          '${n['body'] ?? ''}',
          details,
        );
        if (id > _lastSeenId) _lastSeenId = id;
      }
      await _persistSeen();
    } catch (_) {}
  }
}

/// ---------------- Daily reminders (exact alarms) ----------------
/// 1) Daily production-entry reminder at a chosen hour (default 5 PM)
/// 2) Month-end reminder (last day, 6 PM): export + close the Loss% sheet.
class Reminders {
  static const _idDaily = 900001;
  static const _idMonthEnd = 900002;

  static Future<void> _init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  }

  static Future<void> enableDaily(int hour) async {
    if (kIsWeb) return;
    try {
      await PhoneNotifier.init();
      await _init();
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.cancel(_idDaily);
      final now = tz.TZDateTime.now(tz.local);
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
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
        'Loss% sheet export karke month close kar lao (closing → next opening).',
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

  static Future<void> disableAll() async {
    if (kIsWeb) return;
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.cancel(_idDaily);
      await plugin.cancel(_idMonthEnd);
    } catch (_) {}
  }
}
