import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  bool get forbidden => status == 403;
  bool get unauthenticated => status == 401;
  @override
  String toString() => message;
}

/// Thin REST client. The server is the authority — every call is re-authorized.
class ApiClient {
  /// API base URL resolution order:
  /// 1. `--dart-define=API_BASE=...` (dev / emulator).
  /// 2. The address SAVED by the user (native apps need it once — persisted).
  /// 3. Same origin as the page (web builds served by the ERP itself — works
  ///    for localhost PCs, 192.168.x.x LAN and https cloud domains).
  /// 4. localhost:4000 convenience when the page itself is on localhost.
  /// 5. null → the login screen asks the user to set the server address.
  String? get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (_savedBase != null && _savedBase!.isNotEmpty) return _savedBase;
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

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _send('POST', path, body);
  Future<dynamic> put(String path, [Map<String, dynamic>? body]) => _send('PUT', path, body);
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

  Future<dynamic> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final base = baseUrl;
    if (base == null) {
      throw ApiException(-2, 'Server address is not set. Tap the gear icon on the login screen and enter your ERP address.');
    }
    final uri = Uri.parse('$base$path');
    http.Response res;
    try {
      switch (method) {
        case 'POST':
          res = await http.post(uri, headers: _headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 20));
          break;
        case 'PUT':
          res = await http.put(uri, headers: _headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 20));
          break;
        case 'DELETE':
          res = await http.delete(uri, headers: _headers).timeout(const Duration(seconds: 20));
          break;
        default:
          res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      }
    } catch (e) {
      throw ApiException(-1, 'Cannot reach the server at $base. Is the ERP running? ($e)');
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
    throw ApiException(res.statusCode, msg);
  }
}
