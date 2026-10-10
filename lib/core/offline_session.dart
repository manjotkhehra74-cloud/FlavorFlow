import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The last signed-in session, kept in the phone's encrypted keystore so the
/// app can be OPENED without internet (MAN-13 offline mode).
///
/// The bundle holds the bearer token plus the `/auth/me` payload (user, role,
/// permissions, nav, currency). It is written on every successful login and
/// cleared on logout. It is NEVER restored silently: the login screen opens
/// it only after the OS fingerprint/face/device-PIN prompt passes — the same
/// gate as biometric login (`lib/core/biometric.dart` already stores the
/// password in this same keystore for quick login).
///
/// Storage is the Android Keystore-backed encrypted SharedPreferences — the
/// same protection the biometric credentials already use.
class OfflineSession {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kBundle = 'ff_session_bundle_v1';

  /// Persist the session of a successful login (mobile only — web keeps its
  /// token in SharedPreferences already).
  static Future<void> save(String token, Map<String, dynamic> sessionJson) async {
    try {
      await _storage.write(
        key: _kBundle,
        value: jsonEncode({
          'token': token,
          'session': sessionJson,
          'savedAt': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {/* keystore unavailable — offline unlock just won't be offered */}
  }

  /// The saved bundle as `{'token': …, 'session': …}`, or null when this phone
  /// has no saved session (or the stored copy is unreadable).
  static Future<Map<String, dynamic>?> load() async {
    try {
      final raw = await _storage.read(key: _kBundle);
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final token = j['token'];
      final session = j['session'];
      if (token is! String || token.isEmpty || session is! Map) return null;
      return {'token': token, 'session': session.cast<String, dynamic>()};
    } catch (_) {
      return null;
    }
  }

  /// Drop the saved session (logout, or the server rejected the token).
  static Future<void> clear() async {
    try {
      await _storage.delete(key: _kBundle);
    } catch (_) {}
  }
}
