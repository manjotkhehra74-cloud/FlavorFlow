import '../../core/format.dart';

/// `GET me` → `user` plus the optional profile block Phase 5 adds
/// (`profile{ designation, joinedOn, phone, manager{name}, shift{name,start,end}, site }`).
class Profile {
  final String name;
  final String code;
  final String email;
  final String department;
  final String roleLabel;
  final String? avatarUrl;
  final String? designation;
  final DateTime? joinedOn;
  final String? phone;
  final String? managerName;
  final String? shiftName;
  final String? shiftStart;
  final String? shiftEnd;
  final String? site;

  const Profile({
    required this.name,
    required this.code,
    required this.email,
    required this.department,
    required this.roleLabel,
    required this.avatarUrl,
    required this.designation,
    required this.joinedOn,
    required this.phone,
    required this.managerName,
    required this.shiftName,
    required this.shiftStart,
    required this.shiftEnd,
    required this.site,
  });

  factory Profile.fromJson(dynamic json) {
    final m = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    final u = m['user'] is Map ? (m['user'] as Map).cast<String, dynamic>() : m;
    final p = m['profile'] is Map ? (m['profile'] as Map).cast<String, dynamic>() : (u['profile'] is Map ? (u['profile'] as Map).cast<String, dynamic>() : const <String, dynamic>{});
    final mgr = p['manager'];
    final shift = p['shift'] is Map ? (p['shift'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final role = (u['role'] ?? '').toString().replaceAll(RegExp(r'[_-]+'), ' ').trim();
    return Profile(
      name: (u['name'] ?? '').toString(),
      code: (u['code'] ?? '').toString(),
      email: (u['email'] ?? '').toString(),
      department: (u['department'] ?? '').toString(),
      roleLabel: role.isEmpty ? '' : role.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' '),
      avatarUrl: u['avatarUrl']?.toString(),
      designation: (p['designation'] ?? u['designation'])?.toString(),
      joinedOn: Fmt.parse(p['joinedOn'] ?? p['joiningDate'] ?? u['joinedOn']),
      phone: (p['phone'] ?? u['phone'])?.toString(),
      managerName: mgr is Map ? mgr['name']?.toString() : mgr?.toString(),
      shiftName: shift['name']?.toString(),
      shiftStart: shift['start']?.toString(),
      shiftEnd: shift['end']?.toString(),
      site: p['site']?.toString(),
    );
  }
}

/// `GET holidays?year=` → `items[{date, name, type, optional}]`.
class Holiday {
  final DateTime date;
  final String name;
  final String? type;
  final bool optional;
  const Holiday({required this.date, required this.name, required this.type, required this.optional});

  factory Holiday.fromJson(Map<String, dynamic> j) => Holiday(
        date: Fmt.parse(j['date']) ?? DateTime.now(),
        name: (j['name'] ?? j['title'] ?? '').toString(),
        type: j['type']?.toString(),
        optional: j['optional'] == true || (j['type'] ?? '').toString().toLowerCase() == 'optional',
      );

  static List<Holiday> listFromJson(dynamic json) {
    final list = json is Map ? (json['items'] ?? json['holidays'] ?? const []) : json;
    if (list is! List) return const [];
    final out = list.whereType<Map>().map((m) => Holiday.fromJson(m.cast<String, dynamic>())).toList();
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  bool get past => date.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));
}

/// `GET payslips` → `items[{id, month:"2026-08", label, netPay, currency, url}]`.
class Payslip {
  final String id;
  final String month; // YYYY-MM
  final String label; // "August 2026"
  final double? netPay;
  final String currency;
  final String? url; // PDF / page to open in the browser (server-signed, short-lived)
  const Payslip({required this.id, required this.month, required this.label, required this.netPay, required this.currency, required this.url});

  factory Payslip.fromJson(Map<String, dynamic> j) {
    final month = (j['month'] ?? j['period'] ?? '').toString();
    return Payslip(
      id: (j['id'] ?? month).toString(),
      month: month,
      label: (j['label'] ?? month).toString(),
      netPay: j['netPay'] is num ? (j['netPay'] as num).toDouble() : null,
      currency: (j['currency'] ?? 'INR').toString(),
      url: j['url']?.toString(),
    );
  }

  static List<Payslip> listFromJson(dynamic json) {
    final list = json is Map ? (json['items'] ?? json['payslips'] ?? const []) : json;
    if (list is! List) return const [];
    return list.whereType<Map>().map((m) => Payslip.fromJson(m.cast<String, dynamic>())).toList();
  }
}
