import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Hardware-encrypted token store + biometric unlock.
///
/// The Bearer token from the Mobile API is kept in the device keystore
/// (flutter_secure_storage). If the user enabled "Unlock with fingerprint",
/// the token is only released after the OS biometric prompt (fingerprint /
/// face / device PIN fallback). Nothing here talks to the network.
class SecureStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static final _auth = LocalAuthentication();

  static const _kToken = 'hr_token';
  static const _kUser = 'hr_user_json';
  static const _kBio = 'hr_bio_unlock';
  static const _kDevice = 'hr_device_id';

  static Future<void> saveSession(String token, String userJson) async {
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kUser, value: userJson);
  }

  static Future<String?> token() => _storage.read(key: _kToken);
  static Future<String?> userJson() => _storage.read(key: _kUser);

  static Future<void> clearSession() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUser);
  }

  /// Stable per-install device id (sent with login so the server can list /
  /// revoke devices).
  static Future<String> deviceId() async {
    var id = await _storage.read(key: _kDevice);
    if (id == null || id.isEmpty) {
      id = 'and-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
      await _storage.write(key: _kDevice, value: id);
    }
    return id;
  }

  // ---- biometric unlock ----
  static Future<bool> biometricAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> biometricEnabled() async => (await _storage.read(key: _kBio)) == '1';

  static Future<void> setBiometricEnabled(bool on) =>
      on ? _storage.write(key: _kBio, value: '1') : _storage.delete(key: _kBio);

  /// OS prompt only — true when the user passed it.
  static Future<bool> verify(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
    } catch (_) {
      return false;
    }
  }
}
