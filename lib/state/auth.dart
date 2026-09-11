import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/subscription.dart';
import '../core/biometric.dart';
import '../core/company.dart';

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
  /// FlavorFlow cloud subscription (plan, due invoice, cheque details).
  final SubscriptionController subscription = SubscriptionController();
  UserSession? session;

  AuthController() {
    api.onPaymentRequired = (msg, billing, code) {
      // Plan-limit 402s (feature / users) are per-request errors, not a block.
      if (code != null && code.startsWith('PLAN_')) return;
      subscription.onPaymentRequired(msg, billing);
    };
  }
  bool ready = false; // restored-from-storage completed
  bool busy = false;

  bool get isLoggedIn => session != null;
  bool can(String perm) => session?.can(perm) ?? false;

  /// True once the server knows the split raw./loss. permissions
  /// (ff-permfix applied) — the session then carries at least one of them.
  bool get hasSplitPerms =>
      session?.permissions.any((p) => p.startsWith('raw.') || p.startsWith('loss.')) ?? false;

  /// Permission check with a legacy fallback: before ff-permfix runs on the
  /// server, the old umbrella permission (packing.*) keeps everything working.
  bool canOr(String perm, String legacy) => can(perm) || (!hasSplitPerms && can(legacy));

  /// True once the server carries the billing.* permissions (ff-billing applied).
  bool get hasBillingPerms => session?.permissions.any((p) => p.startsWith('billing.')) ?? false;

  /// Sales billing access — falls back to dispatch permissions on servers that
  /// are not yet updated (the server still enforces its own guard).
  bool get canViewBilling => can('billing.view') || (!hasBillingPerms && can('dispatch.view'));
  bool get canManageBilling => can('billing.manage') || (!hasBillingPerms && can('dispatch.manage'));

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
          subscription.refresh(api);
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
      // Company/industry of THIS tenant (units, categories, destinations)
      // — refreshed on every login so a device that last opened a food
      // company shows mill units the moment a rice mill signs in.
      try { await CompanyProfile.load(api); } catch (_) {/* server route optional */}
      subscription.refresh(api); // fire-and-forget (cloud tenants only)
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
      subscription.refresh(api);
    } catch (_) {/* keep old session */}
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } catch (_) {/* ignore */}
    api.token = null;
    session = null;
    subscription.clear();
    // In-memory credentials are dropped; the saved passkey (secure storage)
    // stays so "Login with passkey" keeps working on the login screen.
    BiometricAuth.forgetSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    notifyListeners();
  }
}
