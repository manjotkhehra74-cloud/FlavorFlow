import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cache.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import '../punch/punch_models.dart';

/// My attendance calendar — one month of `GET attendance/history?from&to`
/// (the Phase 2 route). Tap a day → that day's punches.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Cached<List<AttendanceDay>>? _days;
  Object? _error;
  bool _loading = true;
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthController>().api;
    final from = Fmt.iso(_month);
    final last = DateTime(_month.year, _month.month + 1, 0);
    final to = Fmt.iso(last.isAfter(DateTime.now()) ? DateTime.now() : last);
    try {
      final days = await cachedFetch('history:$from', () => api.get('/attendance/history', query: {'from': from, 'to': to}), AttendanceDay.listFromJson);
      if (!mounted) return;
      setState(() {
        _days = days;
        _loading = false;
        if (_selected == null && _isCurrentMonth) _selected = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  bool get _isCurrentMonth => _month.year == DateTime.now().year && _month.month == DateTime.now().month;

  void _shiftMonth(int delta) {
    final m = DateTime(_month.year, _month.month + delta);
    if (m.isAfter(DateTime(DateTime.now().year, DateTime.now().month))) return;
    setState(() {
      _month = m;
      _selected = null;
      _days = null;
      _loading = true;
      _error = null;
    });
    _load();
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<L10n>();
    final t = Theme.of(context).textTheme;
    final cached = _days;
    final Widget body;
    if (_loading) {
      body = const LoadingView();
    } else if (cached == null) {
      body = ErrorRetryView(error: _error ?? tr('Something went wrong'), onRetry: _retry);
    } else {
      final byDate = {for (final d in cached.data) Fmt.iso(d.date): d};
      final sel = _selected == null ? null : byDate[Fmt.iso(_selected!)];
      final present = cached.data.where((d) => d.status == 'present' || d.status == 'half').length;
      final absent = cached.data.where((d) => d.status == 'absent').length;
      final leave = cached.data.where((d) => d.status == 'leave').length;
      final worked = cached.data.fold<int>(0, (s, d) => s + d.workedMinutes);
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (cached.staleSince != null) ...[
              Align(alignment: Alignment.centerLeft, child: OfflineChip(since: cached.staleSince!)),
              const SizedBox(height: 10),
            ],
            HrCard(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Column(children: [
                Row(children: [
                  IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
                  Expanded(child: Text(_monthLabel(_month), style: t.titleMedium, textAlign: TextAlign.center)),
                  IconButton(onPressed: _isCurrentMonth ? null : () => _shiftMonth(1), icon: const Icon(Icons.chevron_right_rounded)),
                ]),
                _MonthGrid(month: _month, byDate: byDate, selected: _selected, onTap: (d) => setState(() => _selected = d)),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Stat(label: tr('Present'), value: '$present', color: HrBrand.green)),
              Expanded(child: _Stat(label: tr('Absent'), value: '$absent', color: HrBrand.red)),
              Expanded(child: _Stat(label: tr('Leave'), value: '$leave', color: const Color(0xFFB26A00))),
              Expanded(child: _Stat(label: tr('Worked'), value: Fmt.duration(worked), color: HrBrand.blueDeep)),
            ]),
            const SizedBox(height: 16),
            if (_selected != null) ...[
              Text(Fmt.weekday(_selected!), style: t.titleMedium),
              const SizedBox(height: 10),
              if (sel == null)
                HrCard(child: Text(tr('No record for this day'), style: t.bodyMedium))
              else ...[
                HrCard(
                  child: Row(children: [
                    Expanded(child: _Stat(label: tr('First in'), value: Fmt.time(sel.firstIn), color: HrBrand.ink)),
                    Expanded(child: _Stat(label: tr('Last out'), value: Fmt.time(sel.lastOut), color: HrBrand.ink)),
                    Expanded(child: _Stat(label: tr('Worked'), value: Fmt.duration(sel.workedMinutes), color: HrBrand.ink)),
                    _statusPill(sel.status),
                  ]),
                ),
                if (sel.punches.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  HrCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0; i < sel.punches.length; i++) ...[
                        if (i > 0) const Divider(),
                        ListTile(
                          dense: true,
                          leading: Icon(sel.punches[i].isIn ? Icons.login_rounded : Icons.logout_rounded, color: sel.punches[i].isIn ? HrBrand.green : HrBrand.blueDeep),
                          title: Text(sel.punches[i].isIn ? tr('Punch in') : tr('Punch out')),
                          subtitle: sel.punches[i].method.isEmpty ? null : Text(sel.punches[i].method),
                          trailing: Text(Fmt.time(sel.punches[i].at), style: t.titleMedium),
                        ),
                      ],
                    ]),
                  ),
                ],
              ],
            ],
          ],
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: Text(tr('My attendance'))), body: body);
  }

  static String _monthLabel(DateTime m) {
    final d = Fmt.date(DateTime(m.year, m.month, 1)); // "1 Sep 2026"
    return d.substring(d.indexOf(' ') + 1);
  }
}

StatusPill _statusPill(String status) {
  switch (status) {
    case 'present':
      return StatusPill.success(tr('Present'));
    case 'half':
      return StatusPill.info(tr('Half day'));
    case 'leave':
      return StatusPill.warning(tr('On leave'));
    case 'holiday':
      return StatusPill.info(tr('Holiday'));
    case 'weekoff':
      return StatusPill.info(tr('Week off'));
    default:
      return StatusPill.danger(tr('Absent'));
  }
}

Color _dayColor(String? status) {
  switch (status) {
    case 'present':
      return HrBrand.green;
    case 'half':
      return HrBrand.blue;
    case 'leave':
      return HrBrand.amber;
    case 'holiday':
    case 'weekoff':
      return HrBrand.subInk;
    case 'absent':
      return HrBrand.red;
    default:
      return Colors.transparent;
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final Map<String, AttendanceDay> byDate;
  final DateTime? selected;
  final ValueChanged<DateTime> onTap;
  const _MonthGrid({required this.month, required this.byDate, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday % 7; // Sunday-first grid
    final today = DateTime.now();
    final cells = <Widget>[];
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final future = date.isAfter(today);
      final rec = byDate[Fmt.iso(date)];
      final isSel = selected != null && Fmt.iso(selected!) == Fmt.iso(date);
      final isToday = Fmt.iso(today) == Fmt.iso(date);
      final dot = _dayColor(rec?.status);
      cells.add(InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: future ? null : () => onTap(date),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSel ? HrBrand.blue : (isToday ? HrBrand.blueContainer : null),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$d', style: TextStyle(fontSize: 13, fontWeight: isToday || isSel ? FontWeight.w800 : FontWeight.w500, color: isSel ? Colors.white : (future ? HrBrand.border : HrBrand.ink))),
            const SizedBox(height: 3),
            Container(width: 6, height: 6, decoration: BoxDecoration(color: isSel ? Colors.white : dot, shape: BoxShape.circle)),
          ]),
        ),
      ));
    }
    return Column(children: [
      Row(children: [
        for (final w in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
          Expanded(child: Center(child: Text(w, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: HrBrand.subInk)))),
      ]),
      const SizedBox(height: 4),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1,
        children: cells,
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
      ]);
}
