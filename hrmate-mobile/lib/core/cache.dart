import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Last successful GET per endpoint (ARCHITECTURE.md §6 offline rule).
/// Screens show cached data with an "offline · last updated hh:mm" chip
/// when the network call fails. Punches are never queued here.
class ApiCache {
  static const _prefix = 'cache:';

  static Future<void> put(String key, dynamic json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$key', jsonEncode({'at': DateTime.now().toIso8601String(), 'data': json}));
    } catch (_) {}
  }

  /// Returns `(data, savedAt)` or null when nothing is cached.
  static Future<({dynamic data, DateTime at})?> get(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final at = DateTime.tryParse(m['at']?.toString() ?? '');
      if (at == null) return null;
      return (data: m['data'], at: at);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}

/// Result of a cached fetch: fresh from the network, or stale from cache
/// (with the error that made us fall back).
class Cached<T> {
  final T data;
  final DateTime? staleSince; // null → fresh
  final Object? error;
  const Cached(this.data, {this.staleSince, this.error});
  bool get offline => staleSince != null;
}

/// Fetch through the network; on failure fall back to the cache. Throws only
/// when both fail (the screen then shows ErrorRetryView).
Future<Cached<T>> cachedFetch<T>(String key, Future<dynamic> Function() fetch, T Function(dynamic json) parse) async {
  try {
    final json = await fetch();
    await ApiCache.put(key, json);
    return Cached(parse(json));
  } catch (e) {
    final hit = await ApiCache.get(key);
    if (hit == null) rethrow;
    return Cached(parse(hit.data), staleSince: hit.at, error: e);
  }
}
