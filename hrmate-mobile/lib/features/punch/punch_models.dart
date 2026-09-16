import '../../core/format.dart';

/// One punch record from `attendance/history` / `attendance/punch`.
class PunchRecord {
  final String id;
  final String type; // in | out
  final DateTime at;
  final String method; // biometric | password | web | device
  final double? distanceM;
  final bool insideGeofence;
  final String? note;

  const PunchRecord({
    required this.id,
    required this.type,
    required this.at,
    required this.method,
    required this.distanceM,
    required this.insideGeofence,
    required this.note,
  });

  factory PunchRecord.fromJson(Map<String, dynamic> j) => PunchRecord(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString().toLowerCase(),
        at: Fmt.parse(j['at'] ?? j['time'] ?? j['timestamp']) ?? DateTime.now(),
        method: (j['method'] ?? '').toString(),
        distanceM: j['distanceM'] is num ? (j['distanceM'] as num).toDouble() : null,
        insideGeofence: j['insideGeofence'] != false,
        note: j['note']?.toString(),
      );

  bool get isIn => type == 'in';
}

/// A day row from `GET attendance/history?from&to`.
class AttendanceDay {
  final DateTime date;
  final String status; // present | absent | leave | holiday | weekoff | half
  final DateTime? firstIn;
  final DateTime? lastOut;
  final int workedMinutes;
  final List<PunchRecord> punches;

  const AttendanceDay({
    required this.date,
    required this.status,
    required this.firstIn,
    required this.lastOut,
    required this.workedMinutes,
    required this.punches,
  });

  factory AttendanceDay.fromJson(Map<String, dynamic> j) => AttendanceDay(
        date: DateTime.tryParse((j['date'] ?? '').toString()) ?? DateTime.now(),
        status: (j['status'] ?? '').toString().toLowerCase(),
        firstIn: Fmt.parse(j['firstIn']),
        lastOut: Fmt.parse(j['lastOut']),
        workedMinutes: j['workedMinutes'] is num ? (j['workedMinutes'] as num).round() : 0,
        punches: ((j['punches'] as List?) ?? const []).whereType<Map>().map((m) => PunchRecord.fromJson(m.cast<String, dynamic>())).toList(),
      );

  static List<AttendanceDay> listFromJson(dynamic json) {
    final list = json is Map ? (json['days'] ?? json['items'] ?? const []) : json;
    if (list is! List) return const [];
    return list.whereType<Map>().map((m) => AttendanceDay.fromJson(m.cast<String, dynamic>())).toList();
  }
}
