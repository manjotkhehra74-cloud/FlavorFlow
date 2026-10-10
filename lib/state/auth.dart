import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/subscription.dart';
import '../core/biometric.dart';
import '../core/company.dart';
import '../core/offline_queue.dart';
import '../core/offline_session.dart';

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

  bool can(String perm) {
    // Super Admin wildcard
    if (permissions.contains('*')) return true;
    if (permissions.contains(perm)) return true;
    // Granular fallback: create/edit/delete/view -> manage
    // Ensures old roles with manage still work before granular migration
    final parts = perm.split('.');
    if (parts.length >= 2) {
      final base = parts[0];
      final manageKey = '$base.manage';
      if (permissions.contains(manageKey)) return true;
      // Special cases: bom.view -> packing.manage, etc.
      if (perm == 'packing.bom.view' && (permissions.contains('packing.view') || permissions.contains('packing.manage'))) return true;
      if (perm == 'packing.bom.manage' && permissions.contains('packing.manage')) return true;
      if (perm.startsWith('packing.') && permissions.contains('packing.manage')) return true;
      if (perm.startsWith('raw.') && permissions.contains('raw.manage')) return true;
      if (perm.startsWith('inventory.') && permissions.contains('inventory.manage')) return true;
      if (perm.startsWith('production.') && permissions.contains('production.manage')) return true;
      if (perm.startsWith('dispatch.') && permissions.contains('dispatch.manage')) return true;
      if (perm.startsWith('billing.') && permissions.contains('billing.manage')) return true;
      if (perm.startsWith('users.') && permissions.contains('users.manage')) return true;
    }
    return false;
  }

  /// Check if user has ANY permission for a module (for auto-registration)
  bool canAny(String module) {
    if (permissions.contains('*')) return true;
    return permissions.any((p) => p.startsWith('$module.'));
  }
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

  /// True when this phone holds a saved session (encrypted keystore) that the
  /// login screen can unlock after the OS fingerprint/PIN prompt — MAN-13
  /// offline open. Never restored silently.
  bool hasSavedSession = false;

  /// Set by [login]: the last attempt failed because the server could not be
  /// reached (no network / timeout / 5xx) — NOT because the credentials were
  /// rejected. Lets the biometric button fall back to the offline unlock
  /// instead of resetting the stored credentials.
  bool lastLoginNetworkError = false;

  bool get isLoggedIn => session != null;
  bool can(String perm) => session?.can(perm) ?? false;

  /// True once the server knows the split raw./loss. permissions
  /// (ff-permfix applied) — the session then carries at least one of them.
  bool get hasSplitPerms =>
      session?.permissions.any((p) => p.startsWith('raw.') || p.startsWith('loss.')) ?? false;

  /// True once server has granular permissions (ff-permfix-granular applied)
  bool get hasGranularPerms =>
      session?.permissions.any((p) => p.contains('.create') || p.contains('.edit') || p.contains('.delete')) ?? false;

  /// Permission check with a legacy fallback: before ff-permfix runs on the
  /// server, the old umbrella permission (packing.*) keeps everything working.
  bool canOr(String perm, String legacy) => can(perm) || (!hasSplitPerms && can(legacy));

  /// Granular permission check with manage fallback
  /// e.g., canGranular('products.create') checks create, then manage, then legacy view
  bool canGranular(String perm, {String? legacyManage, String? legacyView}) {
    if (can(perm)) return true;
    final parts = perm.split('.');
    if (parts.length >= 2) {
      final manageKey = '${parts[0]}.manage';
      if (can(manageKey)) return true;
    }
    if (legacyManage != null && can(legacyManage)) return true;
    if (legacyView != null && can(legacyView)) return true;
    return false;
  }

  /// True once the server carries the billing.* permissions (ff-billing applied).
  bool get hasBillingPerms => session?.permissions.any((p) => p.startsWith('billing.')) ?? false;

  /// Sales billing access — falls back to dispatch permissions on servers that
  /// are not yet updated (the server still enforces its own guard).
  bool get canViewBilling => can('billing.view') || (!hasBillingPerms && can('dispatch.view'));
  bool get canManageBilling => can('billing.manage') || (!hasBillingPerms && can('dispatch.manage'));

  /// Super Admin check — has wildcard or super_admin role
  bool get isSuperAdmin => session?.role == 'super_admin' || (session?.permissions.contains('*') ?? false);

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
        // MAN-13: a session saved in the encrypted keystore may still be
        // unlocked from the login screen (after the OS prompt) so the app can
        // be OPENED with no internet. It is never restored silently here.
        hasSavedSession = await OfflineSession.load() != null;
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
    lastLoginNetworkError = false;
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
      // MAN-13: remember this session in the encrypted keystore so the app can
      // be opened offline (login screen → OS prompt → unlock). Web keeps its
      // own token persistence in SharedPreferences.
      if (!kIsWeb) await OfflineSession.save(api.token!, map);
      // Never mix one account's cached reads into another account's session.
      await api.clearReadCache();
      // Company/industry of THIS tenant (units, categories, destinations)
      // — refreshed on every login so a device that last opened a food
      // company shows mill units the moment a rice mill signs in.
      try { await CompanyProfile.load(api); } catch (_) {/* server route optional */}
      subscription.refresh(api); // fire-and-forget (cloud tenants only)
      return null;
    } on ApiException catch (e) {
      lastLoginNetworkError = e.isNetworkError || e.status == 502 || e.status == 503 || e.status == 504;
      return e.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Open the session saved on this phone (MAN-13 offline unlock). Called from
  /// the login screen only AFTER the OS fingerprint/face/device-PIN prompt
  /// passed — the same gate as biometric login. Online, the saved token is
  /// validated against `/auth/me` and refreshed; with no connection the saved
  /// session is trusted until the next online check. Returns null on success
  /// or a user-facing error message.
  Future<String?> unlockSavedSession() async {
    final bundle = await OfflineSession.load();
    if (bundle == null) return 'No saved session on this phone — sign in once with internet.';
    busy = true;
    notifyListeners();
    try {
      api.token = bundle['token'] as String;
      // Online check with a short timeout: when the server answers, the saved
      // token is validated and the bundle refreshed. Any network failure (or
      // a hanging connection) falls through to the offline path below.
      try {
        final json = await api.get('/auth/me').timeout(const Duration(seconds: 8));
        session = UserSession.fromJson((json as Map).cast<String, dynamic>());
        await OfflineSession.save(api.token!, (json as Map).cast<String, dynamic>());
        try { await CompanyProfile.load(api); } catch (_) {/* server route optional */}
        subscription.refresh(api); // fire-and-forget (cloud tenants only)
        return null;
      } on ApiException catch (e) {
        if (e.status == 401 || e.status == 403) {
          // The server rejected the saved token — it is stale. Drop it.
          await OfflineSession.clear();
          hasSavedSession = false;
          api.token = null;
          session = null;
          return e.message;
        }
        // Unreachable / server error → offline path below.
      } catch (_) {
        // Timeout etc → offline path below.
      }
      // OFFLINE: trust the session saved on this phone so the app is usable
      // without internet — screens show the last synced data and new entries
      // are queued (OfflineQueue). The next online open re-validates the
      // token against the server and drops it if it was revoked.
      try {
        session = UserSession.fromJson(bundle['session'] as Map<String, dynamic>);
      } catch (_) {
        await OfflineSession.clear();
        hasSavedSession = false;
        api.token = null;
        return 'The saved session is unreadable — sign in again with internet.';
      }
      OfflineQueue.instance.setOnline(false);
      try { await CompanyProfile.load(api); } catch (_) {/* cached/default profile */}
      return null;
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
    // MAN-13: the offline unlock and this account's cached reads go away with
    // the session — another account on this phone must not see either.
    hasSavedSession = false;
    await OfflineSession.clear();
    await api.clearReadCache();
    subscription.clear();
    // In-memory credentials are dropped; the saved passkey (secure storage)
    // stays so "Login with passkey" keeps working on the login screen.
    BiometricAuth.forgetSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    notifyListeners();
  }
}
