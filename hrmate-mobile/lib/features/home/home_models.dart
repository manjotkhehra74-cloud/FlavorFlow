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

/// `GET leaves/balance` — compact numbers for the Home tile.
class LeaveBalance {
  final double available;
  final int pending;
  const LeaveBalance({required this.available, required this.pending});

  factory LeaveBalance.fromJson(dynamic json) {
    if (json is! Map) return const LeaveBalance(available: 0, pending: 0);
    final m = json.cast<String, dynamic>();
    double avail = 0;
    if (m['available'] is num) {
      avail = (m['available'] as num).toDouble();
    } else if (m['balances'] is List) {
      for (final b in (m['balances'] as List).whereType<Map>()) {
        final v = b['available'] ?? b['balance'];
        if (v is num) avail += v.toDouble();
      }
    }
    final pending = (m['pending'] is num) ? (m['pending'] as num).round() : 0;
    return LeaveBalance(available: avail, pending: pending);
  }
}
