import '../../core/format.dart';

/// `GET attendance/today` (ARCHITECTURE.md §5).
class TodayAttendance {
  final String status; // in | out | none
  final DateTime? firstIn;
  final DateTime? lastOut;
  final int workedMinutes;
  final String? shiftName;
  final String? shiftStart; // "09:00"
  final String? shiftEnd; // "18:00"
  final bool onLeave;
  final bool holiday;
  final String? holidayName;

  const TodayAttendance({
    required this.status,
    required this.firstIn,
    required this.lastOut,
    required this.workedMinutes,
    required this.shiftName,
    required this.shiftStart,
    required this.shiftEnd,
    required this.onLeave,
    required this.holiday,
    required this.holidayName,
  });

  factory TodayAttendance.fromJson(Map<String, dynamic> j) {
    final shift = j['shift'] is Map ? (j['shift'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    return TodayAttendance(
      status: (j['status'] ?? 'none').toString().toLowerCase(),
      firstIn: Fmt.parse(j['firstIn']),
      lastOut: Fmt.parse(j['lastOut']),
      workedMinutes: (j['workedMinutes'] is num) ? (j['workedMinutes'] as num).round() : 0,
      shiftName: shift['name']?.toString(),
      shiftStart: shift['start']?.toString(),
      shiftEnd: shift['end']?.toString(),
      onLeave: j['onLeave'] == true,
      holiday: j['holiday'] == true,
      holidayName: j['holidayName']?.toString(),
    );
  }

  bool get punchedIn => status == 'in';
  bool get done => status == 'out';
}

/// `GET announcements` item.
class Announcement {
  final String id;
  final String title;
  final String body;
  final DateTime? at;
  final bool pinned;

  const Announcement({required this.id, required this.title, required this.body, required this.at, required this.pinned});

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? j['message'] ?? '').toString(),
        at: Fmt.parse(j['at'] ?? j['createdAt'] ?? j['date']),
        pinned: j['pinned'] == true,
      );

  static List<Announcement> listFromJson(dynamic json) {
    final list = json is Map ? (json['items'] ?? json['announcements'] ?? const []) : json;
    if (list is! List) return const [];
    return list.whereType<Map>().map((m) => Announcement.fromJson(m.cast<String, dynamic>())).toList();
  }
}

/// `GET leaves/balance` — compact numbers for the Home tile + KPI bar.
class LeaveBalance {
  final double available;
  final double total;
  final int pending;
  const LeaveBalance({required this.available, required this.total, required this.pending});

  factory LeaveBalance.fromJson(dynamic json) {
    if (json is! Map) return const LeaveBalance(available: 0, total: 0, pending: 0);
    final m = json.cast<String, dynamic>();
    double avail = 0;
    double total = 0;
    if (m['available'] is num) {
      avail = (m['available'] as num).toDouble();
      total = m['total'] is num ? (m['total'] as num).toDouble() : 0;
    } else if (m['balances'] is List) {
      for (final b in (m['balances'] as List).whereType<Map>()) {
        final v = b['available'] ?? b['balance'];
        if (v is num) avail += v.toDouble();
        if (b['total'] is num) total += (b['total'] as num).toDouble();
      }
    }
    final pending = (m['pending'] is num) ? (m['pending'] as num).round() : 0;
    // No per-type totals (older server) → bar shows full, numbers still right.
    return LeaveBalance(available: avail, total: total > 0 ? total : avail, pending: pending);
  }
}

/// `GET holidays?year=` → `items[{date, name, type, optional}]`.
/// (Local copy so Home is self-contained in Phase 8; the More phase owns
/// the full holidays list.)
class Holiday {
  final DateTime date;
  final String name;
  final bool optional;
  const Holiday({required this.date, required this.name, required this.optional});

  factory Holiday.fromJson(Map<String, dynamic> j) => Holiday(
        date: Fmt.parse(j['date']) ?? DateTime.now(),
        name: (j['name'] ?? j['title'] ?? '').toString(),
        optional: j['optional'] == true || (j['type'] ?? '').toString().toLowerCase() == 'optional',
      );

  static List<Holiday> listFromJson(dynamic json) {
    final list = json is Map ? (json['items'] ?? json['holidays'] ?? const []) : json;
    if (list is! List) return const [];
    final out = list.whereType<Map>().map((m) => Holiday.fromJson(m.cast<String, dynamic>())).toList();
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }
}

/// `GET team/today` → counts (Home tile; the Team phase owns the full model).
class TeamToday {
  final int total;
  final int present;
  const TeamToday({required this.total, required this.present});

  factory TeamToday.fromJson(dynamic json) {
    final m = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    final c = m['counts'] is Map ? (m['counts'] as Map).cast<String, dynamic>() : m;
    int n(String k) => c[k] is num ? (c[k] as num).round() : 0;
    final members = (m['members'] is List ? (m['members'] as List).length : 0);
    return TeamToday(total: n('total') > 0 ? n('total') : members, present: n('present'));
  }
}

/// A day row from `GET attendance/history?from&to` (Home month % only).
class AttendanceDay {
  final DateTime date;
  final String status; // present | absent | leave | holiday | weekoff | half
  const AttendanceDay({required this.date, required this.status});

  factory AttendanceDay.fromJson(Map<String, dynamic> j) => AttendanceDay(
        date: DateTime.tryParse((j['date'] ?? '').toString()) ?? DateTime.now(),
        status: (j['status'] ?? '').toString().toLowerCase(),
      );

  static List<AttendanceDay> listFromJson(dynamic json) {
    final list = json is Map ? (json['days'] ?? json['items'] ?? const []) : json;
    if (list is! List) return const [];
    return list.whereType<Map>().map((m) => AttendanceDay.fromJson(m.cast<String, dynamic>())).toList();
  }
}
