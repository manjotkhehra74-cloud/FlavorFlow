import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Phone notifications (status-bar) for new ERP alerts.
///
/// The app already polls /notifications/unread-count every 20s while open;
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
      _ready = true;
    } catch (_) {}
  }

  /// Show phone notifications for notifications newer than the last seen id.
  /// [items] = server list (each: id, title, body, is_read).
  static Future<void> showNew(List<Map<String, dynamic>> items) async {
    if (kIsWeb || !_ready) return;
    try {
      final unread = items.where((n) => n['is_read'] == 0).toList();
      // first sync: don't blast old items — just remember the newest id
      if (_lastSeenId == 0) {
        for (final n in unread) {
          final id = (n['id'] as num?)?.toInt() ?? 0;
          if (id > _lastSeenId) _lastSeenId = id;
        }
        return;
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
    } catch (_) {}
  }
}
