import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Biometric / passkey-style quick sign-in.
///
/// Flow: after the FIRST successful password login the app offers to enable
/// quick login. If accepted, the credentials are stored in the device's
/// hardware-encrypted keystore (flutter_secure_storage). From then on the
/// login screen shows a fingerprint button — the OS biometric prompt
/// (fingerprint / face / device PIN) unlocks the stored credentials and the
/// app signs in automatically. Turning it off wipes the stored credentials.
class BiometricAuth {
  static final _auth = LocalAuthentication();
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kEnabled = 'bio_enabled';
  static const _kEmail = 'bio_email';
  static const _kPassword = 'bio_password';

  /// Credentials of the CURRENT session (memory only — cleared on logout).
  /// Lets the user save a passkey later from the user menu without retyping.
  static String? _sessEmail;
  static String? _sessPassword;
  static void rememberSession(String email, String password) {
    _sessEmail = email;
    _sessPassword = password;
  }
  static void forgetSession() { _sessEmail = null; _sessPassword = null; }
  static bool get hasSession => _sessEmail != null && _sessPassword != null;

  /// Device has fingerprint/face/PIN available (web: never).
  static Future<bool> available() async {
    if (kIsWeb) return false;
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Quick login is set up on this device.
  static Future<bool> enabled() async {
    if (kIsWeb) return false;
    try {
      return (await _storage.read(key: _kEnabled)) == '1' &&
          (await _storage.read(key: _kEmail)) != null;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> savedEmail() async {
    try { return await _storage.read(key: _kEmail); } catch (_) { return null; }
  }

  /// Store credentials as a device passkey. Saving itself REQUIRES the OS
  /// biometric prompt (fingerprint/face/PIN) — like registering a passkey.
  /// Returns false if the user cancelled the biometric check.
  static Future<bool> enable(String email, String password) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Verify to save your passkey on this device',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
      if (!ok) return false;
    } catch (_) {
      return false;
    }
    await _storage.write(key: _kEnabled, value: '1');
    await _storage.write(key: _kEmail, value: email);
    await _storage.write(key: _kPassword, value: password);
    return true;
  }

  /// Save a passkey for the CURRENT logged-in session (from the user menu).
  static Future<bool> enableFromSession() async {
    if (!hasSession) return false;
    return enable(_sessEmail!, _sessPassword!);
  }

  static Future<void> disable() async {
    try {
      await _storage.delete(key: _kEnabled);
      await _storage.delete(key: _kEmail);
      await _storage.delete(key: _kPassword);
    } catch (_) {}
  }

  /// Show the OS biometric prompt; on success return the stored credentials.
  /// Returns null when cancelled/failed/not set up.
  static Future<({String email, String password})?> authenticate() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Sign in to FlavorFlow ERP',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // allow device PIN/pattern as fallback
        ),
      );
      if (!ok) return null;
      final email = await _storage.read(key: _kEmail);
      final password = await _storage.read(key: _kPassword);
      if (email == null || password == null) return null;
      return (email: email, password: password);
    } catch (_) {
      return null;
    }
  }
}
