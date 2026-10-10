import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  bool get forbidden => status == 403;
  bool get unauthenticated => status == 401;
  /// SaaS subscription ended / suspended / plan limit (gateway 402).
  bool get paymentRequired => status == 402;
  /// No connection / timeout — the request may not have reached the server.
  bool get isNetworkError => status == -1;
  @override
  String toString() => message;
}

/// Thin REST client. The server is the authority — every call is re-authorized.
class ApiClient {
  /// Called whenever the server answers 402 (SaaS subscription ended /
  /// suspended / plan limit). Wired by AuthController to the subscription
  /// controller so the app can show the "pay by cheque" screen.
  void Function(String message, Map<String, dynamic>? billing, String? code)? onPaymentRequired;

  /// API base URL resolution order:
  /// 1. The address SAVED by the user (login-screen ✏️) — must WIN so a user
  ///    can point the app at any server (SaaS tenants), even in release
  ///    builds that bake in a default via --dart-define.
  /// 2. `--dart-define=API_BASE=...` (release default / dev emulator).
  /// 3. Same origin as the page (web builds served by the ERP itself).
  /// 4. localhost:4000 convenience when the page itself is on localhost.
  /// 5. null → the login screen asks the user to set the server address.
  String? get baseUrl {
    if (_savedBase != null && _savedBase!.isNotEmpty) return _savedBase;
    const fromEnv = String.fromEnvironment('API_BASE');
    if (fromEnv.isNotEmpty) return fromEnv;
    try {
      final b = Uri.base;
      if ((b.scheme == 'http' || b.scheme == 'https') && b.host.isNotEmpty) {
        final port = b.hasPort ? ':${b.port}' : '';
        final origin = '${b.scheme}://${b.host}$port';
        // flutter dev server on a random localhost port → use the ERP's default
        if ((b.host == 'localhost' || b.host == '127.0.0.1') && b.port != 4000) {
          return 'http://localhost:4000/api';
        }
        return '$origin/api';
      }
    } catch (_) {/* non-web platform */}
    return null; // native apps: must be set once from the login screen
  }

  String? _savedBase;

  static const _prefsKey = 'api_base_override';

  Future<void> loadSavedBase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_prefsKey);
      _savedBase = (v != null && v.isNotEmpty) ? v : null;
    } catch (_) {/* storage unavailable */}
  }

  /// Persist (or clear, when null) a custom server address.
  Future<void> setBaseOverride(String? url) async {
    _savedBase = (url != null && url.isNotEmpty) ? normalizeBase(url) : null;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_savedBase == null) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, _savedBase!);
      }
    } catch (_) {/* storage unavailable */}
  }

  /// Normalize user-typed server text into a canonical API base URL.
  static String normalizeBase(String input) {
    var u = input.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) { u = 'http://$u'; }
    while (u.endsWith('/')) { u = u.substring(0, u.length - 1); }
    if (!u.endsWith('/api')) { u = '$u/api'; }
    return u;
  }

  /// Ping the server (used by the "Test connection" button).
  static Future<String?> testConnection(String url) async {
    try {
      final base = normalizeBase(url);
      final health = base.endsWith('/api') ? '${base.substring(0, base.length - 4)}/api/health' : '$base/health';
      final res = await http.get(Uri.parse(health)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return null; // OK
      return 'Server answered with ${res.statusCode} — check the address.';
    } catch (e) {
      return 'Cannot reach the server. Check the address and that the ERP is running. ($e)';
    }
  }

  String? token;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  /// GET with an offline read cache (MAN-13): the last good reply of every GET
  /// is kept on the phone; when the server cannot be reached the cached reply
  /// is served, so screens and entry-form dropdowns stay usable offline.
  /// Auth-critical calls (the `/health` probe, `/auth/me` validation) are never
  /// cached — a cached copy must not fake a successful online check.
  Future<dynamic> get(String path) async {
    try {
      final json = await _send('GET', path);
      if (json != null && !_readCacheSkip(path)) unawaited(_cacheRead(path, json));
      return json;
    } on ApiException catch (e) {
      final unreachable = e.isNetworkError || e.status == 502 || e.status == 503 || e.status == 504;
      if (unreachable) {
        final cached = await _readCacheGet(path);
        if (cached != null) return cached; // offline: last known good data
      }
      rethrow;
    }
  }

  static bool _readCacheSkip(String path) => path.startsWith('/health') || path.startsWith('/auth/me');

  // ---- Offline read cache (MAN-13) --------------------------------------
  static const _rcPrefix = 'ff_read_cache_v1:';
  static const _rcIndexKey = 'ff_read_cache_v1:index';
  static const _rcMaxEntries = 120;
  static const _rcMaxEntryBytes = 512 * 1024; // skip huge report payloads

  Future<void> _cacheRead(String path, dynamic json) async {
    try {
      final encoded = jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'body': json});
      if (encoded.length > _rcMaxEntryBytes) return;
      final prefs = await SharedPreferences.getInstance();
      final key = '$_rcPrefix$path';
      await prefs.setString(key, encoded);
      final index = _rcIndex(prefs.getString(_rcIndexKey));
      index.remove(key);
      index.add(key);
      while (index.length > _rcMaxEntries) {
        await prefs.remove(index.removeAt(0)); // oldest first
      }
      await prefs.setString(_rcIndexKey, jsonEncode(index));
    } catch (_) {/* the cache is best-effort */}
  }

  Future<dynamic> _readCacheGet(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_rcPrefix$path');
      if (raw == null) return null;
      final j = jsonDecode(raw);
      if (j is Map && j['body'] != null) return j['body'];
    } catch (_) {}
    return null;
  }

  static List<String> _rcIndex(String? raw) {
    if (raw == null) return <String>[];
    try {
      final l = jsonDecode(raw);
      if (l is List) return l.whereType<String>().toList();
    } catch (_) {}
    return <String>[];
  }

  /// Drop every cached GET reply — called on login/logout so one account's
  /// cached reads are never shown to another account on the same phone.
  Future<void> clearReadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_rcPrefix) || k == _rcIndexKey).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  /// [idempotencyKey] (MAN-13): sent as `Idempotency-Key` so a server with the
  /// ff-idempotency patch answers a repeated request with the first reply.
  Future<dynamic> post(String path, [Map<String, dynamic>? body, String? idempotencyKey]) =>
      _send('POST', path, body, idempotencyKey);
  Future<dynamic> put(String path, [Map<String, dynamic>? body, String? idempotencyKey]) =>
      _send('PUT', path, body, idempotencyKey);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Raw bytes (e.g. the Excel stock report).
  Future<Uint8List> getBytes(String path) async {
    final uri = Uri.parse('${baseUrl ?? ''}$path');
    try {
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
      throw ApiException(res.statusCode, 'Download failed (${res.statusCode})');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(-1, 'Cannot reach the server at $baseUrl. Is the ERP running? ($e)');
    }
  }

  Map<String, String> _headersWith(String? idempotencyKey) => {
        ..._headers,
        // Native apps only: a custom header on web could need a CORS preflight change.
        if (!kIsWeb && idempotencyKey != null && idempotencyKey.isNotEmpty) 'Idempotency-Key': idempotencyKey,
      };

  Future<dynamic> _send(String method, String path, [Map<String, dynamic>? body, String? idempotencyKey]) async {
    final base = baseUrl;
    if (base == null) {
      throw ApiException(-2, 'Server address is not set. Tap the gear icon on the login screen and enter your ERP address.');
    }
    final uri = Uri.parse('$base$path');
    http.Response res;
    final requestTimeout = method == 'POST' ? const Duration(seconds: 30) : const Duration(seconds: 45);

    Future<http.Response> requestOnce() {
      switch (method) {
        case 'POST':
          return http.post(uri, headers: _headersWith(idempotencyKey), body: jsonEncode(body ?? {}));
        case 'PUT':
          return http.put(uri, headers: _headersWith(idempotencyKey), body: jsonEncode(body ?? {}));
        case 'DELETE':
          return http.delete(uri, headers: _headers);
        default:
          return http.get(uri, headers: _headers);
      }
    }

    try {
      res = await requestOnce().timeout(requestTimeout);
    } catch (e) {
      // GETs are safe to retry, and PUT is idempotent for an existing
      // material/batch/user record. This covers a slow or briefly waking
      // DuckDNS/ERP instance without repeating stock-receive POSTs.
      if (method != 'GET' && method != 'PUT') {
        throw ApiException(-1, 'Cannot reach the server at $base. Is the ERP running? ($e)');
      }
      try {
        res = await requestOnce().timeout(requestTimeout);
      } catch (retryError) {
        throw ApiException(-1, 'Cannot reach the server at $base. Is the ERP running? ($retryError)');
      }
    }
    dynamic json;
    try {
      json = jsonDecode(res.body);
    } catch (_) {
      json = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    final msg = (json is Map && (json['error'] != null || json['message'] != null))
        ? (json['error'] ?? json['message']).toString()
        : 'Request failed (${res.statusCode})';
    if (res.statusCode == 402 && onPaymentRequired != null) {
      final billing = json is Map && json['billing'] is Map ? (json['billing'] as Map).cast<String, dynamic>() : null;
      final code = json is Map ? json['code']?.toString() : null;
      try { onPaymentRequired!(msg, billing, code); } catch (_) {}
    }
    throw ApiException(res.statusCode, msg);
  }
}
