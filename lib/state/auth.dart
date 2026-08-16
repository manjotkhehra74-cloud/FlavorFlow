import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/biometric.dart';

class UserSession {
  final int id;
  final String name;
  final String email;
  final String role;
  final String roleLabel;
  final String roleColor;
  final Set<String> permissions;
  final List<Map<String, dynamic>> nav;
  final Map<String, dynamic> currency;

  UserSession.fromJson(Map<String, dynamic> json)
      : id = json['user']['id'] as int,
        name = json['user']['name'] as String,
        email = json['user']['email'] as String,
        role = json['user']['role'] as String,
        roleLabel = json['user']['roleLabel'] as String,
        roleColor = json['user']['roleColor'] as String,
        permissions = (json['permissions'] as List).cast<String>().toSet(),
        nav = (json['nav'] as List).cast<Map<String, dynamic>>(),
        currency = (json['currency'] as Map).cast<String, dynamic>();

  bool can(String perm) => permissions.contains(perm);
}

class AuthController extends ChangeNotifier {
  final ApiClient api = ApiClient();
  UserSession? session;
  bool ready = false; // restored-from-storage completed
  bool busy = false;

  bool get isLoggedIn => session != null;
  bool can(String perm) => session?.can(perm) ?? false;

  /// Resolved API base (may be null on native until the user sets it).
  String? get serverBase => api.baseUrl;

  /// Persist a custom server address (null → back to automatic).
  Future<void> setServerBase(String? url) async {
    await api.setBaseOverride(url);
    notifyListeners();
  }

  Future<void> restore() async {
    try {
      await api.loadSavedBase();
      if (!kIsWeb) {
        // SECURITY (mobile): the session never survives an app close —
        // back button, swipe from recents or force-stop all end it. Every
        // fresh open lands on the login screen (password or biometrics).
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('token');
        api.token = null;
        session = null;
      } else {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        if (token != null) {
          api.token = token;
          final json = await api.get('/auth/me');
          session = UserSession.fromJson((json as Map).cast<String, dynamic>());
        }
      }
    } catch (_) {
      api.token = null;
      session = null;
    }
    ready = true;
    notifyListeners();
  }

  /// Returns null on success, 'TOTP_REQUIRED' when the account has 2FA on
  /// and no/wrong code was given, or a user-facing error message.
  Future<String?> login(String email, String password, {String? totpCode}) async {
    busy = true;
    notifyListeners();
    try {
      final json = await api.post('/auth/login', {
        'email': email,
        'password': password,
        if (totpCode != null) 'totpCode': totpCode,
      });
      final map = (json as Map).cast<String, dynamic>();
      api.token = map['token'] as String;
      session = UserSession.fromJson(map);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', api.token!);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Refresh session (role/permission changes take effect immediately).
  Future<void> refreshSession() async {
    if (api.token == null) return;
    try {
      final json = await api.get('/auth/me');
      session = UserSession.fromJson((json as Map).cast<String, dynamic>());
      notifyListeners();
    } catch (_) {/* keep old session */}
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } catch (_) {/* ignore */}
    api.token = null;
    session = null;
    // In-memory credentials are dropped; the saved passkey (secure storage)
    // stays so "Login with passkey" keeps working on the login screen.
    BiometricAuth.forgetSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    notifyListeners();
  }
}
