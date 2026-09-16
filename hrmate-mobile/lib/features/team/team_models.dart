import '../../core/format.dart';
import '../punch/punch_models.dart';

/// One row of `GET team/today` → `members[]` (and `GET team/members` — same
/// shape, attendance fields simply null when not asked for a day).
class TeamMember {
  final String id;
  final String code;
  final String name;
  final String department;
  final String? designation;
  final String? avatarUrl;
  final String status; // present | absent | leave | holiday | weekoff | half | notyet
  final DateTime? firstIn;
  final DateTime? lastOut;
  final int workedMinutes;
  final bool late;
  final String? leaveType;

  const TeamMember({
    required this.id,
    required this.code,
    required this.name,
    required this.department,
    required this.designation,
    required this.avatarUrl,
    required this.status,
    required this.firstIn,
    required this.lastOut,
    required this.workedMinutes,
    required this.late,
    required this.leaveType,
  });

  factory TeamMember.fromJson(Map<String, dynamic> j) {
    final att = j['today'] is Map ? (j['today'] as Map).cast<String, dynamic>() : j;
    return TeamMember(
      id: (j['id'] ?? j['userId'] ?? '').toString(),
      code: (j['code'] ?? j['employeeCode'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      department: (j['department'] ?? '').toString(),
      designation: j['designation']?.toString(),
      avatarUrl: j['avatarUrl']?.toString(),
      status: (att['status'] ?? j['status'] ?? 'absent').toString().toLowerCase(),
      firstIn: Fmt.parse(att['firstIn']),
      lastOut: Fmt.parse(att['lastOut']),
      workedMinutes: att['workedMinutes'] is num ? (att['workedMinutes'] as num).round() : 0,
      late: att['late'] == true,
      leaveType: att['leaveType']?.toString(),
    );
  }

  static List<TeamMember> listFromJson(dynamic json) {
    final list = json is Map ? (json['members'] ?? json['items'] ?? const []) : json;
    if (list is! List) return const [];
    return list.whereType<Map>().map((m) => TeamMember.fromJson(m.cast<String, dynamic>())).toList();
  }

  bool get present => status == 'present' || status == 'half' || status == 'in' || status == 'out';
  bool get onLeave => status == 'leave';
  bool get off => status == 'holiday' || status == 'weekoff';
  bool get stillIn => present && firstIn != null && lastOut == null;
}

/// `GET team/today` → counts + members. Counts come from the server; when
/// absent we derive them so old servers still render.
class TeamToday {
  final DateTime date;
  final int total;
  final int present;
  final int absent;
  final int onLeave;
  final int late;
  final List<TeamMember> members;
  const TeamToday({
    required this.date,
    required this.total,
    required this.present,
    required this.absent,
    required this.onLeave,
    required this.late,
    required this.members,
  });

  factory TeamToday.fromJson(dynamic json) {
    final m = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    final members = TeamMember.listFromJson(m);
    final c = m['counts'] is Map ? (m['counts'] as Map).cast<String, dynamic>() : m;
    int n(String k, int fallback) => c[k] is num ? (c[k] as num).round() : fallback;
    return TeamToday(
      date: DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now(),
      total: n('total', members.length),
      present: n('present', members.where((x) => x.present).length),
      absent: n('absent', members.where((x) => !x.present && !x.onLeave && !x.off).length),
      onLeave: n('onLeave', members.where((x) => x.onLeave).length),
      late: n('late', members.where((x) => x.late).length),
      members: members,
    );
  }
}

/// `GET team/members/:id/day?date=` → the member + that day's attendance.
class MemberDay {
  final TeamMember member;
  final AttendanceDay day;
  final String? shiftName;
  final String? shiftStart;
  final String? shiftEnd;
  const MemberDay({required this.member, required this.day, required this.shiftName, required this.shiftStart, required this.shiftEnd});

  factory MemberDay.fromJson(dynamic json, TeamMember fallback) {
    final m = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    final member = m['member'] is Map ? TeamMember.fromJson((m['member'] as Map).cast<String, dynamic>()) : fallback;
    final dayJson = m['day'] is Map ? (m['day'] as Map).cast<String, dynamic>() : m;
    final shift = m['shift'] is Map ? (m['shift'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    return MemberDay(
      member: member,
      day: AttendanceDay.fromJson(dayJson),
      shiftName: shift['name']?.toString(),
      shiftStart: shift['start']?.toString(),
      shiftEnd: shift['end']?.toString(),
    );
  }
}
