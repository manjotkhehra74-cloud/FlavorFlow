import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/secure.dart';
import 'auth.dart';

/// Push notifications (Phase 6) — FCM token registration + display + tap routing.
///
/// How it fits the architecture:
/// * The SERVER decides what to send (punch reminders, leave decisions,
///   announcements) through its existing `notify()` pipeline; the app only
///   registers its device token (`POST devices/push-token`) and shows what
///   arrives. No notification logic lives on the phone.
/// * Background / app-closed messages are shown by the OS (FCM `notification`
///   payload on channel [channelId]). Foreground messages are shown through
///   `flutter_local_notifications` on the same channel, so the user sees them
///   in both cases. A tap opens the matching screen ([screenFor]).
/// * Degrades gracefully: without `google-services.json` in the build, or
///   without Play services, `Firebase.initializeApp()` fails → [available]
///   stays false and the rest of the app is unaffected. An un-patched server
///   (404 on `devices/push-token`) is simply retried on the next sign-in.
class PushController extends ChangeNotifier {
  PushController._();
  static final PushController instance = PushController._();

  /// Must match `default_notification_channel_id` in AndroidManifest.xml and
  /// `android.notification.channel_id` sent by the server (`_lib/fcm.ts`).
  static const channelId = 'hrmate_default';
  static const _channelName = 'HRMate';
  static const _channelDescription = 'Punch reminders, leave decisions and announcements';
  static const _icon = 'ic_notification'; // android/app/src/main/res/drawable/ic_notification.xml

  /// Firebase initialised in this build (google-services.json present).
  bool available = false;

  /// OS notification permission granted (Android 13+ asks; older = always true).
  bool permitted = false;

  AuthController? _auth;
  String? _token;
  String? _registeredKey; // "<userId>|<token>" that the server currently has
  bool _syncing = false;
  bool _askedPermission = false;
  void Function(String screen)? _onOpen;
  String? _pendingScreen;

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  /// Called once from main(). Never throws.
  Future<void> start(AuthController auth) async {
    _auth = auth;
    try {
      await Firebase.initializeApp();
      available = true;
    } catch (_) {
      available = false; // push not configured in this build — app runs as before
      notifyListeners();
      return;
    }
    try {
      await _local.initialize(
        const InitializationSettings(android: AndroidInitializationSettings(_icon)),
        onDidReceiveNotificationResponse: (r) => _open(r.payload),
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ));
    } catch (_) {}
    try {
      final fm = FirebaseMessaging.instance;
      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data['link']?.toString()));
      final initial = await fm.getInitialMessage(); // app was closed, opened by a tap
      if (initial != null) _open(initial.data['link']?.toString());
      fm.onTokenRefresh.listen((t) {
        _token = t;
        _registeredKey = null;
        _sync();
      });
    } catch (_) {}
    auth.addListener(_sync);
    auth.beforeLogout = unregister;
    notifyListeners();
    await _sync();
  }

  /// Where a tap should land. Set by the app once the router exists; a tap
  /// that arrived earlier (cold start) is delivered as soon as it is set.
  void attachOpenHandler(void Function(String screen)? handler) {
    _onOpen = handler;
    final p = _pendingScreen;
    if (handler != null && p != null) {
      _pendingScreen = null;
      handler(p);
    }
  }

  /// Webapp notification links → app screens (server links are webapp paths).
  static String screenFor(String? link) {
    final l = (link ?? '').trim().toLowerCase();
    if (l.startsWith('/leaves') || l.startsWith('/approvals')) return '/leaves';
    if (l.startsWith('/attendance')) return '/punch';
    if (l.startsWith('/team') || l.startsWith('/roster')) return '/team';
    return '/home';
  }

  /// Re-register the token (after the user turns notifications back on).
  Future<void> ensureRegistered() {
    _registeredKey = null;
    _askedPermission = false;
    return _sync();
  }

  /// Remove this phone's token on the server — called by AuthController
  /// BEFORE the session is dropped (needs the Bearer token). Best effort;
  /// the server's logout route deletes the device's tokens as well.
  Future<void> unregister() async {
    final auth = _auth;
    final t = _token;
    _registeredKey = null;
    if (!available || auth == null || t == null || auth.api.token == null) return;
    try {
      await auth.api.delete('/devices/push-token?token=${Uri.encodeQueryComponent(t)}');
    } catch (_) {}
  }

  Future<void> _sync() async {
    final auth = _auth;
    if (!available || auth == null) return;
    if (!auth.isLoggedIn) {
      _registeredKey = null;
      return;
    }
    if (_syncing) return;
    _syncing = true;
    try {
      if (!_askedPermission) {
        _askedPermission = true;
        final s = await FirebaseMessaging.instance.requestPermission();
        permitted = s.authorizationStatus == AuthorizationStatus.authorized ||
            s.authorizationStatus == AuthorizationStatus.provisional;
        notifyListeners();
      }
      _token ??= await FirebaseMessaging.instance.getToken();
      final t = _token;
      final user = auth.user;
      if (t == null || t.isEmpty || user == null) return;
      final key = '${user.id}|$t';
      if (_registeredKey == key) return;
      await auth.api.post('/devices/push-token', {
        'token': t,
        'platform': 'android',
        'deviceId': await SecureStore.deviceId(),
      });
      _registeredKey = key;
    } catch (_) {
      // offline / un-patched server: retried on the next auth change or token refresh
    } finally {
      _syncing = false;
    }
  }

  Future<void> _showForeground(RemoteMessage m) async {
    final n = m.notification;
    final title = n?.title ?? m.data['title']?.toString();
    final body = n?.body ?? m.data['body']?.toString();
    if (title == null && body == null) return;
    try {
      await _local.show(
        (m.messageId ?? DateTime.now().toIso8601String()).hashCode & 0x7fffffff,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: _icon,
          ),
        ),
        payload: m.data['link']?.toString(),
      );
    } catch (_) {}
  }

  void _open(String? link) {
    final screen = screenFor(link);
    final h = _onOpen;
    if (h == null) {
      _pendingScreen = screen;
      return;
    }
    h(screen);
  }
}
