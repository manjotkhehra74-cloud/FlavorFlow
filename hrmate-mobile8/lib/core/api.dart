import 'dart:convert';

import 'package:http/http.dart' as http;

/// Error surfaced to the UI. `status` -1 = network, -2 = base URL missing.
class ApiException implements Exception {
  final int status;
  final String message;
  final String? code; // server error code: UNAUTHENTICATED / FORBIDDEN / VALIDATION / GEOFENCE / CONFLICT
  final Map<String, dynamic>? data; // extra payload (e.g. distanceM on GEOFENCE)
  ApiException(this.status, this.message, {this.code, this.data});
  bool get unauthenticated => status == 401;
  bool get forbidden => status == 403;
  bool get network => status < 0;
  @override
  String toString() => message;
}

/// Thin JSON client for the HRMate Mobile API (`/api/v1/mobile/*`).
///
/// The server is the authority — every call carries the Bearer token and
/// the app renders exactly what comes back. Never uses the browser session
/// cookie (that is what broke the earlier native attempt).
class ApiClient {
  /// Base URL. Release builds bake it in with
  /// `--dart-define=HRMATE_API=https://gdfoods.duckdns.org/api/v1/mobile`;
  /// the default points at production so a plain `flutter run` also works.
  static const String base = String.fromEnvironment(
    'HRMATE_API',
    defaultValue: 'https://gdfoods.duckdns.org/api/v1/mobile',
  );

  static const requestTimeout = Duration(seconds: 20);

  String? token;

  /// Called on every 401 so AuthController can drop the session once.
  void Function()? onUnauthenticated;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'accept': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _send('POST', path, body: body);
  Future<dynamic> put(String path, [Map<String, dynamic>? body]) => _send('PUT', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Uri _uri(String path, Map<String, String>? query) {
    final p = path.startsWith('/') ? path : '/$path';
    final u = Uri.parse('$base$p');
    return (query == null || query.isEmpty) ? u : u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  Future<dynamic> _send(String method, String path, {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final uri = _uri(path, query);
    http.Response res;
    try {
      switch (method) {
        case 'POST':
          res = await http.post(uri, headers: _headers, body: jsonEncode(body ?? {})).timeout(requestTimeout);
        case 'PUT':
          res = await http.put(uri, headers: _headers, body: jsonEncode(body ?? {})).timeout(requestTimeout);
        case 'DELETE':
          res = await http.delete(uri, headers: _headers).timeout(requestTimeout);
        default:
          res = await http.get(uri, headers: _headers).timeout(requestTimeout);
      }
    } catch (e) {
      throw ApiException(-1, 'Cannot reach HRMate. Check your internet connection and try again.');
    }
    dynamic json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      json = null;
    }
    final map = json is Map ? json.cast<String, dynamic>() : null;
    final okFlag = map == null || map['ok'] != false;
    if (res.statusCode >= 200 && res.statusCode < 300 && okFlag) return json;
    final msg = (map != null && (map['error'] != null || map['message'] != null))
        ? (map['error'] ?? map['message']).toString()
        : 'Request failed (${res.statusCode})';
    if (res.statusCode == 401) {
      try { onUnauthenticated?.call(); } catch (_) {}
    }
    throw ApiException(res.statusCode, msg, code: map?['code']?.toString(), data: map);
  }
}
