import 'package:intl/intl.dart';

/// Dates and times as HRMate shows them (IST, factory-friendly formats).
/// One place for formats so every screen matches the webapp.
class Fmt {
  static final _time = DateFormat('h:mm a');
  static final _date = DateFormat('d MMM yyyy');
  static final _dateShort = DateFormat('d MMM');
  static final _weekday = DateFormat('EEEE, d MMMM');
  static final _iso = DateFormat('yyyy-MM-dd');

  static String time(DateTime? d) => d == null ? '—' : _time.format(d.toLocal());
  static String date(DateTime? d) => d == null ? '—' : _date.format(d.toLocal());
  static String dateShort(DateTime? d) => d == null ? '—' : _dateShort.format(d.toLocal());
  static String weekday(DateTime d) => _weekday.format(d.toLocal());
  static String iso(DateTime d) => _iso.format(d);

  /// 12 → "12", 1.5 → "1.5" (leave balances, counts).
  static String num(num v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  /// "7h 45m" from minutes.
  static String duration(int? minutes) {
    if (minutes == null || minutes <= 0) return '0m';
    final h = minutes ~/ 60, m = minutes % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// Parses server timestamps (ISO string or epoch ms); null when absent.
  static DateTime? parse(dynamic v) {
    if (v == null) return null;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  static String greeting(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// "Manjot K." style short name.
  static String shortName(String full) {
    final parts = full.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts.last[0].toUpperCase()}.';
  }

  static String initials(String full) {
    final parts = full.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
