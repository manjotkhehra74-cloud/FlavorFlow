import '../../core/format.dart';

/// One leave type row from `GET leaves/balance` → `balances[]`.
class LeaveTypeBalance {
  final String type; // EL | CL | SL | …
  final String name; // "Earned Leave (EL)"
  final double total;
  final double used;
  final double available;
  const LeaveTypeBalance({required this.type, required this.name, required this.total, required this.used, required this.available});

  factory LeaveTypeBalance.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
    final type = (j['type'] ?? j['code'] ?? '').toString().toUpperCase();
    return LeaveTypeBalance(
      type: type,
      name: (j['name'] ?? type).toString(),
      total: d(j['total']),
      used: d(j['used']),
      available: d(j['available'] ?? j['balance']),
    );
  }

  static List<LeaveTypeBalance> listFromJson(dynamic json) {
    final list = json is Map ? json['balances'] : json;
    if (list is! List) return const [];
    return list.whereType<Map>().map((m) => LeaveTypeBalance.fromJson(m.cast<String, dynamic>())).toList();
  }
}

/// A leave request — same shape from `GET leaves`, `POST leaves`,
/// `POST leaves/:id/approve` and `POST leaves/:id/reject`.
class LeaveRequest {
  final String id;
  final String type;
  final String typeName;
  final DateTime from;
  final DateTime to;
  final double days;
  final bool halfDay;
  final String reason;
  final String status; // pending | approved | rejected | cancelled
  final DateTime? appliedAt;
  final DateTime? decidedAt;
  final String? decidedBy;
  final String? decisionNote;
  final String? employeeId;
  final String? employeeName;
  final String? employeeCode;

  const LeaveRequest({
    required this.id,
    required this.type,
    required this.typeName,
    required this.from,
    required this.to,
    required this.days,
    required this.halfDay,
    required this.reason,
    required this.status,
    required this.appliedAt,
    required this.decidedAt,
    required this.decidedBy,
    required this.decisionNote,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
  });

  factory LeaveRequest.fromJson(Map<String, dynamic> j) {
    final emp = j['employee'] is Map ? (j['employee'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final from = Fmt.parse(j['from'] ?? j['fromDate'] ?? j['startDate']) ?? DateTime.now();
    final to = Fmt.parse(j['to'] ?? j['toDate'] ?? j['endDate']) ?? from;
    final halfDay = j['halfDay'] == true;
    final type = (j['type'] ?? j['leaveType'] ?? '').toString().toUpperCase();
    final by = j['decidedBy'];
    return LeaveRequest(
      id: (j['id'] ?? j['_id'] ?? '').toString(),
      type: type,
      typeName: (j['typeName'] ?? j['leaveTypeName'] ?? type).toString(),
      from: from,
      to: to,
      days: j['days'] is num ? (j['days'] as num).toDouble() : (halfDay ? 0.5 : to.difference(from).inDays + 1.0),
      halfDay: halfDay,
      reason: (j['reason'] ?? '').toString(),
      status: (j['status'] ?? 'pending').toString().toLowerCase(),
      appliedAt: Fmt.parse(j['appliedAt'] ?? j['createdAt']),
      decidedAt: Fmt.parse(j['decidedAt']),
      decidedBy: by is Map ? by['name']?.toString() : by?.toString(),
      decisionNote: j['decisionNote']?.toString(),
      employeeId: emp['id']?.toString(),
      employeeName: emp['name']?.toString(),
      employeeCode: emp['code']?.toString(),
    );
  }

  static List<LeaveRequest> listFromJson(dynamic json) {
    final list = json is Map ? (json['items'] ?? json['leaves'] ?? const []) : json;
    if (list is! List) return const [];
    return list.whereType<Map>().map((m) => LeaveRequest.fromJson(m.cast<String, dynamic>())).toList();
  }

  bool get pending => status == 'pending';
  bool get approved => status == 'approved';
  bool get rejected => status == 'rejected';
  bool get sameDay => Fmt.iso(from) == Fmt.iso(to);

  /// "25 Sep 2026" or "25 Sep – 27 Sep 2026".
  String get dateLabel => sameDay ? Fmt.date(from) : '${Fmt.dateShort(from)} – ${Fmt.date(to)}';
}
