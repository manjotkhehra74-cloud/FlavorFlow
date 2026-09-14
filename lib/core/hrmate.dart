import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'format.dart';

/// One-way, READ-ONLY bridge to HRMate — FlavorFlow's sister product for
/// attendance, leaves and daily punch-in (hr.flavorflow.co.in).
///
/// Phase 2 of the integration: FlavorFlow only *reads* the day's head-count
/// (`GET <base>/api/v1/attendance/summary?date=YYYY-MM-DD`) and shows it on
/// the dashboard and on a production batch. Nothing is ever written back.
///
/// Fail-safe by design:
///   • never routed through [ApiClient] — HRMate is a different server with
///     its own address + key, configured per device in Settings;
///   • every failure (not configured, DNS, CORS, 401, 404, timeout, unknown
///     JSON shape) resolves to `null` → the caller simply hides its tile;
///   • the JSON shape is parsed tolerantly (snake/camel keys, `data`/`summary`
///     envelopes, lists of employee rows) because HRMate's contract may still
///     evolve — a changed field name must never break the ERP.
class HrSummary {
  /// YYYY-MM-DD the numbers are for.
  final String date;
  final int? present, absent, onLeave, lateIn, halfDay, total;
  /// Server's own "as of" stamp, when it sends one (raw string).
  final String? updatedAt;
  final DateTime fetchedAt;

  const HrSummary({
    required this.date,
    this.present,
    this.absent,
    this.onLeave,
    this.lateIn,
    this.halfDay,
    this.total,
    this.updatedAt,
    required this.fetchedAt,
  });

  bool get hasAny => present != null || absent != null || onLeave != null || lateIn != null;
}

typedef HrFetchResult = ({HrSummary? summary, String? error, String? detail});

class HrMate extends ChangeNotifier {
  HrMate._();
  static final HrMate instance = HrMate._();

  static const defaultBase = 'https://hr.flavorflow.co.in';
  static const summaryPath = '/api/v1/attendance/summary';
  static const requestTimeout = Duration(seconds: 8);
  static const cacheTtl = Duration(minutes: 3);
  static const _retryAfterFail = Duration(seconds: 45);

  String base = '';
  String token = '';
  /// Average daily wage per worker (₹) — optional, only for the approximate
  /// "labour cost per carton" figure. 0 = not set.
  double wage = 0;

  bool get configured => base.isNotEmpty;
  String get host => Uri.tryParse(base)?.host ?? base;

  final Map<String, HrSummary> _cache = {};
  final Map<String, DateTime> _failedAt = {};
  final Map<String, Future<HrSummary?>> _inflight = {};

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      base = normalizeBase(p.getString('set_hrmate_base') ?? '');
      token = (p.getString('set_hrmate_token') ?? '').trim();
      wage = p.getDouble('set_hrmate_wage') ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  /// `hr.flavorflow.co.in/` → `https://hr.flavorflow.co.in`; a pasted API
  /// url (`…/api/v1/attendance/summary`) is trimmed back to the site root.
  static String normalizeBase(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    if (!s.contains('://')) s = 'https://$s';
    s = s.replaceAll(RegExp(r'/+$'), '');
    for (final suffix in const [summaryPath, '/api/v1', '/api']) {
      if (s.endsWith(suffix)) s = s.substring(0, s.length - suffix.length);
    }
    s = s.replaceAll(RegExp(r'/+$'), '');
    return Uri.tryParse(s)?.host.isNotEmpty == true ? s : '';
  }

  Future<void> save(String rawBase, String rawToken, {double wage = 0}) async {
    base = normalizeBase(rawBase);
    token = rawToken.trim();
    this.wage = wage.isFinite && wage > 0 ? wage : 0;
    _cache.clear();
    _failedAt.clear();
    _inflight.clear(); // in-flight answers for the old address are dropped
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('set_hrmate_base', base);
      await p.setString('set_hrmate_token', token);
      await p.setDouble('set_hrmate_wage', this.wage);
    } catch (_) {}
  }

  Future<void> disconnect() async {
    base = '';
    token = '';
    wage = 0;
    _cache.clear();
    _failedAt.clear();
    _inflight.clear();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('set_hrmate_base');
      await p.remove('set_hrmate_token');
      await p.remove('set_hrmate_wage');
    } catch (_) {}
  }

  /// Last good numbers for [date] (no network).
  HrSummary? cached([String? date]) => _cache[date ?? todayYmd()];

  /// Head-count for [date] (default today). `null` = not configured, HRMate
  /// unreachable, or answer not understood — callers hide their tile.
  /// Cached for [cacheTtl]; after a failure the next try waits 45 s so a
  /// dead HRMate never hammers the phone's network or slows the dashboard.
  Future<HrSummary?> summary({String? date, bool force = false}) {
    if (!configured) return Future.value(null);
    final d = date ?? todayYmd();
    final hit = _cache[d];
    final now = DateTime.now();
    if (!force && hit != null && now.difference(hit.fetchedAt) < cacheTtl) return Future.value(hit);
    final failed = _failedAt[d];
    if (!force && failed != null && now.difference(failed) < _retryAfterFail) return Future.value(hit);
    final running = _inflight[d];
    if (running != null) return running;
    final f = _fetchInto(d);
    _inflight[d] = f;
    return f;
  }

  Future<HrSummary?> _fetchInto(String d) async {
    final b = base, t = token;
    try {
      final r = await fetch(b, t, d);
      // Settings changed while the request was in flight → stale answer.
      if (b != base || t != token) return null;
      if (r.summary != null) {
        _cache[d] = r.summary!;
        _failedAt.remove(d);
        notifyListeners();
        return r.summary;
      }
      _failedAt[d] = DateTime.now();
      return _cache[d];
    } finally {
      if (b == base && t == token) _inflight.remove(d);
    }
  }

  /// Raw call — also used by Settings → "Test connection" with unsaved values.
  /// [error] is an i18n key (wrap with `tr()`), [detail] a raw hint (HTTP code).
  static Future<HrFetchResult> fetch(String rawBase, String rawToken, String date) async {
    final b = normalizeBase(rawBase);
    if (b.isEmpty) return (summary: null, error: 'HRMate address missing', detail: null);
    final uri = Uri.tryParse('$b$summaryPath?date=$date');
    if (uri == null) return (summary: null, error: 'HRMate address missing', detail: rawBase);
    final t = rawToken.trim();
    try {
      // Only `Authorization: Bearer` — one non-safelisted header keeps the
      // browser CORS preflight simple (web build). Empty key → plain GET.
      final res = await http.get(uri, headers: {
        'Accept': 'application/json',
        if (t.isNotEmpty) 'Authorization': 'Bearer $t',
      }).timeout(requestTimeout);
      final code = res.statusCode;
      if (code == 401 || code == 403) return (summary: null, error: 'HRMate rejected the API key', detail: 'HTTP $code');
      if (code == 404) return (summary: null, error: 'HRMate summary API not found — update HRMate', detail: 'HTTP 404');
      if (code >= 400) return (summary: null, error: 'Could not reach HRMate', detail: 'HTTP $code');
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final s = parse(body, date);
      if (s == null) return (summary: null, error: 'Unexpected reply from HRMate', detail: null);
      return (summary: s, error: null, detail: null);
    } on TimeoutException {
      return (summary: null, error: 'HRMate did not answer', detail: '${requestTimeout.inSeconds}s');
    } on FormatException {
      return (summary: null, error: 'Unexpected reply from HRMate', detail: 'not JSON');
    } catch (e) {
      return (summary: null, error: 'Could not reach HRMate', detail: '$e');
    }
  }

  // ── tolerant JSON → HrSummary ────────────────────────────────────────────

  /// Understands, among others:
  ///   {present: 42, absent: 5, on_leave: 3, late: 2, total: 50, date: '…'}
  ///   {data: {presentCount: 42, …}}   {summary: {counts: {present: …}}}
  ///   {present: [ {…}, {…} ], absent: [ … ]}        (lists → counts)
  ///   [ {name, status: 'present'}, {name, status: 'absent'}, … ]  (rows)
  /// Returns null when nothing usable is found or the reply is clearly for
  /// another day (HRMate ignored `?date=`).
  static HrSummary? parse(dynamic body, String date) {
    if (body == null) return null;
    final now = DateTime.now();
    final Object? root = body;
    if (root is Map && root['ok'] == false) return null;

    if (root is List) {
      // Either a list of DAILY summaries (pick the requested day) or a bare
      // list of employee rows (count their statuses).
      final maps = root.whereType<Map>().toList();
      if (maps.isEmpty) return null;
      for (final m in maps) {
        final d = _find(m, _dateKeys);
        if (d is String && d.trim().startsWith(date)) return parse(m, date);
      }
      final first = maps.first;
      final looksLikeSummary = _int(_find(first, const ['present', 'present_count', 'presentCount', 'absent'])) != null;
      if (looksLikeSummary) return maps.length == 1 ? parse(first, date) : null;
      return _fromRows(maps, date, now);
    }
    if (root is! Map) return null;

    // Reject a reply that is plainly for another day (HRMate ignored
    // `?date=`). Only a bare YYYY-MM-DD is judged — a UTC timestamp for an
    // IST midnight legitimately reads as the previous day.
    final replyDate = _find(root, _dateKeys);
    if (replyDate is String) {
      final rd = replyDate.trim();
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rd) && rd != date) return null;
    }

    final present = _int(_find(root, const [
      'present', 'present_count', 'presentCount', 'present_today', 'presentToday', 'total_present', 'totalPresent',
      'punched_in', 'punchedIn', 'checked_in', 'checkedIn', 'attended',
    ]));
    final absent = _int(_find(root, const ['absent', 'absent_count', 'absentCount', 'total_absent', 'totalAbsent', 'not_marked', 'missing']));
    final onLeave = _int(_find(root, const ['on_leave', 'onLeave', 'leave', 'leaves', 'leave_count', 'leaveCount', 'on_leave_count']));
    final lateIn = _int(_find(root, const ['late', 'late_count', 'lateCount', 'late_comers', 'latecomers', 'late_arrivals']));
    final halfDay = _int(_find(root, const ['half_day', 'halfDay', 'half_days', 'halfDays', 'half_day_count']));
    var total = _int(_find(root, const [
      'total', 'total_employees', 'totalEmployees', 'total_staff', 'totalStaff', 'headcount', 'head_count', 'strength',
      'employees', 'staff', 'active_employees', 'activeEmployees', 'workforce', 'expected',
    ]));
    final upd = _find(root, const ['updated_at', 'updatedAt', 'generated_at', 'generatedAt', 'as_of', 'asOf', 'timestamp', 'computed_at']);

    if (present == null && absent == null && onLeave == null && lateIn == null) {
      // Maybe the rows live under a key: {employees: [ … ]} / {rows: [ … ]}.
      final rows = _find(root, const ['rows', 'employees', 'records', 'items', 'attendance', 'list']);
      if (rows is List && rows.isNotEmpty && rows.first is Map) return _fromRows(rows, date, now);
      return null;
    }
    if (total == null && present != null && absent != null) total = present + absent + (onLeave ?? 0);
    return HrSummary(
      date: date,
      present: present,
      absent: absent,
      onLeave: onLeave,
      lateIn: lateIn,
      halfDay: halfDay,
      total: total,
      updatedAt: upd == null ? null : '$upd',
      fetchedAt: now,
    );
  }

  static const _dateKeys = ['date', 'for_date', 'forDate', 'attendance_date', 'attendanceDate', 'day', 'on', 'as_of_date'];

  static HrSummary? _fromRows(List rows, String date, DateTime now) {
    int present = 0, absent = 0, leave = 0, lateIn = 0, half = 0, seen = 0, known = 0;
    for (final r in rows) {
      if (r is! Map) continue;
      seen++;
      var st = _norm('${r['status'] ?? r['attendance'] ?? r['state'] ?? r['mark'] ?? ''}');
      if (st.isEmpty && r['present'] is bool) st = (r['present'] as bool) ? 'present' : 'absent';
      if (st.isEmpty) continue;
      known++;
      if (st.startsWith('late')) { lateIn++; present++; }
      else if (st.startsWith('half')) { half++; present++; }
      else if (st.startsWith('present') || st == 'p' || st == 'in' || st.startsWith('punched') || st == 'wfh' || st == 'od' || st.startsWith('onduty')) { present++; }
      else if (st.startsWith('absent') || st == 'a') { absent++; }
      else if (st.contains('leave') || st == 'l' || st == 'cl' || st == 'sl' || st == 'el' || st == 'pl') { leave++; }
      else { known--; }
    }
    if (seen == 0 || known == 0) return null;
    return HrSummary(date: date, present: present, absent: absent, onLeave: leave, lateIn: lateIn, halfDay: half, total: seen, fetchedAt: now);
  }

  static String _norm(String k) => k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Breadth-first lookup (depth ≤ 4) of the first key matching any of
  /// [names] after normalisation (`present_count` == `presentCount`).
  /// Scalars, maps ({count: n}) and lists (→ length) are all accepted; the
  /// shallowest match wins so `total` beats `present.total`.
  static Object? _find(Map root, List<String> names) {
    final want = names.map(_norm).toSet();
    var level = <Map>[root];
    for (var depth = 0; depth < 4 && level.isNotEmpty; depth++) {
      final next = <Map>[];
      for (final node in level) {
        for (final e in node.entries) {
          final v = e.value;
          if (v == null) continue;
          if (want.contains(_norm('${e.key}'))) return v;
        }
        for (final v in node.values) {
          if (v is Map) next.add(v);
        }
      }
      level = next;
    }
    return null;
  }

  static int? _int(Object? v) {
    if (v == null) return null;
    if (v is bool) return null;
    if (v is num) return v.round();
    if (v is String) {
      final s = v.trim();
      return int.tryParse(s) ?? double.tryParse(s)?.round();
    }
    if (v is List) return v.length;
    if (v is Map) return _int(v['count'] ?? v['total'] ?? v['value'] ?? v['n'] ?? v['qty']);
    return null;
  }
}
