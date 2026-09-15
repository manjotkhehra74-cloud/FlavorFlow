import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/secure.dart';

/// The signed-in employee as returned by `POST auth/login` / `GET me`.
class HrUser {
  final String id;
  final String code;
  final String name;
  final String email;
  final String role; // e.g. employee / manager / admin / superadmin
  final String department;
  final String? avatarUrl;
  final Set<String> permissions;

  HrUser({
    required this.id,
    required this.code,
    required this.name,
    required this.email,
    required this.role,
    required this.department,
    required this.avatarUrl,
    required this.permissions,
  });

  factory HrUser.fromJson(Map<String, dynamic> j) => HrUser(
        id: (j['id'] ?? '').toString(),
        code: (j['code'] ?? j['employeeCode'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        role: (j['role'] ?? 'employee').toString().toLowerCase(),
        department: (j['department'] ?? '').toString(),
        avatarUrl: j['avatarUrl']?.toString(),
        permissions: ((j['permissions'] as List?) ?? const []).map((e) => e.toString()).toSet(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'email': email,
        'role': role,
        'department': department,
        'avatarUrl': avatarUrl,
        'permissions': permissions.toList(),
      };

  bool can(String perm) => permissions.contains(perm);

  /// Team tab is shown for roles that manage people (server still decides).
  bool get isManager => const {'manager', 'admin', 'superadmin', 'super admin', 'hr'}.contains(role) || can('team.view');
}

/// Session controller — restore from secure storage, login, logout.
/// Screens read it with `context.watch<AuthController>()`; the router
/// listens to it for redirects. The server is the authority: a 401 from any
/// call drops the session and the router returns to the login screen.
class AuthController extends ChangeNotifier {
  final ApiClient api = ApiClient();

  HrUser? user;
  bool ready = false; // restore() finished — splash can go
  bool busy = false;
  bool locked = false; // token present but biometric unlock still required

  AuthController() {
    api.onUnauthenticated = () {
      if (user != null || locked) {
        user = null;
        locked = false;
        api.token = null;
        SecureStore.clearSession();
        notifyListeners();
      }
    };
  }

  bool get isLoggedIn => user != null;

  /// Restore the saved session. With fingerprint unlock enabled the token is
  /// kept but the UI stays on the login screen until the user verifies.
  Future<void> restore() async {
    try {
      final token = await SecureStore.token();
      final userJson = await SecureStore.userJson();
      if (token != null && userJson != null) {
        final bio = await SecureStore.biometricEnabled();
        if (bio) {
          locked = true; // login screen shows "Unlock with fingerprint"
        } else {
          api.token = token;
          user = HrUser.fromJson((jsonDecode(userJson) as Map).cast<String, dynamic>());
          _refreshMe(); // fire-and-forget: role/permission changes apply on next open
        }
      }
    } catch (_) {
      user = null;
      locked = false;
    } finally {
      ready = true;
      notifyListeners();
    }
  }

  Future<void> _refreshMe() async {
    try {
      final json = await api.get('/me');
      final map = (json as Map).cast<String, dynamic>();
      final u = (map['user'] is Map) ? (map['user'] as Map).cast<String, dynamic>() : map;
      user = HrUser.fromJson(u);
      await SecureStore.saveSession(api.token!, jsonEncode(user!.toJson()));
      notifyListeners();
    } on ApiException catch (e) {
      if (e.unauthenticated) return; // onUnauthenticated already handled it
      // offline / server hiccup: keep the cached user
    } catch (_) {}
  }

  /// Returns null on success or a user-facing error message.
  Future<String?> login(String login, String password) async {
    busy = true;
    notifyListeners();
    try {
      final json = await api.post('/auth/login', {
        'login': login.trim(),
        'password': password,
        'deviceId': await SecureStore.deviceId(),
        'deviceName': 'Android',
        'platform': 'android',
      });
      final map = (json as Map).cast<String, dynamic>();
      final token = (map['token'] ?? '').toString();
      if (token.isEmpty) return 'Server did not return a token.';
      api.token = token;
      user = HrUser.fromJson(((map['user'] ?? {}) as Map).cast<String, dynamic>());
      locked = false;
      await SecureStore.saveSession(token, jsonEncode(user!.toJson()));
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Biometric unlock of a stored session. Returns false when cancelled.
  Future<bool> unlockWithBiometrics(String reason) async {
    if (!locked) return isLoggedIn;
    final ok = await SecureStore.verify(reason);
    if (!ok) return false;
    try {
      final token = await SecureStore.token();
      final userJson = await SecureStore.userJson();
      if (token == null || userJson == null) {
        locked = false;
        notifyListeners();
        return false;
      }
      api.token = token;
      user = HrUser.fromJson((jsonDecode(userJson) as Map).cast<String, dynamic>());
      locked = false;
      notifyListeners();
      _refreshMe();
      return true;
    } catch (_) {
      locked = false;
      notifyListeners();
      return false;
    }
  }

  /// Forget the locked session (user wants to sign in as someone else).
  Future<void> discardLocked() async {
    await SecureStore.clearSession();
    locked = false;
    api.token = null;
    notifyListeners();
  }

  Future<void> logout() async {
    try { await api.post('/auth/logout'); } catch (_) {/* best effort */}
    await SecureStore.clearSession();
    api.token = null;
    user = null;
    locked = false;
    notifyListeners();
  }
}
