import 'package:intl/intl.dart';

/// Indian Rupee formatting with lakh/crore digit grouping everywhere.
/// Example: inr(125000) → "₹1,25,000.00"
final NumberFormat _inr2 = NumberFormat('#,##,##0.00', 'en_IN');
final NumberFormat _inr0 = NumberFormat('#,##,##0', 'en_IN');
final NumberFormat _qty = NumberFormat('#,##,##0.##', 'en_IN');
final NumberFormat _int0 = NumberFormat('#,##,##0', 'en_IN');

num _n(Object? v) {
  if (v is num) return v;
  return num.tryParse('${v ?? 0}') ?? 0;
}

String inr(Object? value, {bool decimals = true}) {
  final v = _n(value);
  return decimals ? '₹${_inr2.format(v)}' : '₹${_inr0.format(v)}';
}

/// Compact ₹ for charts: ₹1.25 Cr / ₹2.40 L / ₹8.5k
String compactInr(Object? value) {
  final v = _n(value).abs();
  if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)} L';
  if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}k';
  return '₹${v.toStringAsFixed(0)}';
}

String qty(Object? v) => _qty.format(_n(v));
String qtyInt(Object? v) => _int0.format(_n(v).round());

DateTime? _parse(Object? raw) {
  if (raw == null) return null;
  var s = '$raw'.trim();
  if (s.isEmpty || s == '—') return null;
  // stored as 'YYYY-MM-DD HH:MM:SS' (already IST display time) or ISO
  s = s.replaceFirst('T', ' ');
  try {
    final datePart = s.split(' ').first;
    final timePart = s.contains(' ') ? s.split(' ')[1] : '';
    final dp = datePart.split('-').map(int.parse).toList();
    DateTime dt;
    if (timePart.isNotEmpty) {
      final tp = timePart.split(':');
      dt = DateTime(dp[0], dp[1], dp[2], int.parse(tp[0]), int.parse(tp.length > 1 ? tp[1] : '0'));
    } else {
      dt = DateTime(dp[0], dp[1], dp[2]);
    }
    return dt;
  } catch (_) {
    return null;
  }
}

/// '2026-08-03 14:15:00' → '03 Aug 2026'
String fmtDate(Object? raw) {
  final dt = _parse(raw);
  return dt == null ? '—' : DateFormat('dd MMM yyyy').format(dt);
}

/// '2026-08-03 14:15:00' → '03 Aug, 2:15 PM'
String fmtDateTime(Object? raw) {
  final dt = _parse(raw);
  return dt == null ? '—' : DateFormat('dd MMM, h:mm a').format(dt);
}

String fmtAgo(Object? raw) {
  final dt = _parse(raw);
  if (dt == null) return '—';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return fmtDate(raw);
}

String todayYmd() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// '2026-08-03' → 'Monday'
String weekdayOf(Object? raw) {
  final dt = _parse(raw);
  return dt == null ? '' : DateFormat('EEEE').format(dt);
}

/// '2026-08-03' → 'Monday, 03 Aug 2026'
String fmtDateWithDay(Object? raw) {
  final dt = _parse(raw);
  return dt == null ? '—' : DateFormat('EEEE, dd MMM yyyy').format(dt);
}

/// DateTime → 'YYYY-MM-DD'
String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
