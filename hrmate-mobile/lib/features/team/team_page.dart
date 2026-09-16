import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cache.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import 'team_models.dart';

/// Team — Phase 4 (managers only; the tab is hidden otherwise and the
/// server enforces FORBIDDEN). Today's counts → filter chips → member list
/// with search. Tapping a member opens their day (punch list) for any date.
class TeamPage extends StatefulWidget {
  const TeamPage({super.key});
  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  Cached<TeamToday>? _today;
  Object? _error;
  bool _loading = true;
  String _filter = 'all'; // all | present | absent | leave | late
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AuthController>().api;
    try {
      final today = await cachedFetch('team/today', () => api.get('/team/today'), TeamToday.fromJson);
      if (!mounted) return;
      setState(() {
        _today = today;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<TeamMember> _visible(TeamToday t) {
    final q = _search.text.trim().toLowerCase();
    return t.members.where((m) {
      final okFilter = switch (_filter) {
        'present' => m.present,
        'absent' => !m.present && !m.onLeave && !m.off,
        'leave' => m.onLeave,
        'late' => m.late,
        _ => true,
      };
      if (!okFilter) return false;
      if (q.isEmpty) return true;
      return m.name.toLowerCase().contains(q) || m.code.toLowerCase().contains(q) || m.department.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<L10n>();
    final today = _today;
    final Widget body;
    if (_loading) {
      body = const LoadingView();
    } else if (today == null) {
      body = ErrorRetryView(error: _error ?? tr('Something went wrong'), onRetry: _load);
    } else {
      body = _content(context, today);
    }
    return Scaffold(appBar: AppBar(title: Text(tr('Team'))), body: body);
  }

  Widget _content(BuildContext context, Cached<TeamToday> cached) {
    final t = Theme.of(context).textTheme;
    final today = cached.data;
    final members = _visible(today);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (cached.staleSince != null) ...[
            Align(alignment: Alignment.centerLeft, child: OfflineChip(since: cached.staleSince!)),
            const SizedBox(height: 10),
          ],
          Text(Fmt.weekday(today.date), style: t.bodySmall),
          const SizedBox(height: 10),
          // ---- counts ----
          Row(children: [
            Expanded(child: _CountTile(label: tr('Present'), value: today.present, color: HrBrand.green, background: HrBrand.greenContainer, selected: _filter == 'present', onTap: () => _toggle('present'))),
            const SizedBox(width: 8),
            Expanded(child: _CountTile(label: tr('Absent'), value: today.absent, color: HrBrand.red, background: HrBrand.redContainer, selected: _filter == 'absent', onTap: () => _toggle('absent'))),
            const SizedBox(width: 8),
            Expanded(child: _CountTile(label: tr('On leave'), value: today.onLeave, color: const Color(0xFFB26A00), background: HrBrand.amberContainer, selected: _filter == 'leave', onTap: () => _toggle('leave'))),
            const SizedBox(width: 8),
            Expanded(child: _CountTile(label: tr('Late'), value: today.late, color: HrBrand.blueDeep, background: HrBrand.blueContainer, selected: _filter == 'late', onTap: () => _toggle('late'))),
          ]),
          const SizedBox(height: 16),
          // ---- search ----
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: tr('Search name, code or department'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: _search.clear),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text(tr('Showing %s').arg('${members.length} / ${today.total}'), style: t.bodySmall)),
            if (_filter != 'all')
              TextButton(onPressed: () => setState(() => _filter = 'all'), child: Text(tr('Show all'))),
          ]),
          const SizedBox(height: 4),
          // ---- members ----
          if (members.isEmpty)
            HrCard(
              child: Row(children: [
                const Icon(Icons.person_search_rounded, color: HrBrand.subInk),
                const SizedBox(width: 12),
                Expanded(child: Text(today.members.isEmpty ? tr('No team members assigned to you') : tr('Nothing here'), style: t.bodyMedium)),
              ]),
            )
          else
            HrCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < members.length; i++) ...[
                  if (i > 0) const Divider(),
                  _MemberRow(member: members[i], onTap: () => _openMember(members[i])),
                ],
              ]),
            ),
        ],
      ),
    );
  }

  void _toggle(String f) => setState(() => _filter = _filter == f ? 'all' : f);

  void _openMember(TeamMember m) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MemberDayPage(member: m)));
  }
}

class _CountTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final Color background;
  final bool selected;
  final VoidCallback onTap;
  const _CountTile({required this.label, required this.value, required this.color, required this.background, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? background : HrBrand.card,
        borderRadius: BorderRadius.circular(HrBrand.radiusCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(HrBrand.radiusCard),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HrBrand.radiusCard),
              border: Border.all(color: selected ? color : HrBrand.border),
            ),
            child: Column(children: [
              Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: HrBrand.subInk), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      );
}

StatusPill _memberPill(TeamMember m) {
  if (m.onLeave) return StatusPill.warning(m.leaveType == null || m.leaveType!.isEmpty ? tr('On leave') : m.leaveType!);
  if (m.off) return StatusPill.info(m.status == 'holiday' ? tr('Holiday') : tr('Week off'));
  if (m.stillIn) return StatusPill.success(tr('In'));
  if (m.present) return StatusPill.info(tr('Out'));
  return StatusPill.danger(tr('Absent'));
}

class _MemberRow extends StatelessWidget {
  final TeamMember member;
  final VoidCallback onTap;
  const _MemberRow({required this.member, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = member;
    final t = Theme.of(context).textTheme;
    final sub = <String>[
      if (m.code.isNotEmpty) m.code,
      if (m.department.isNotEmpty) m.department,
      if (m.firstIn != null) '${tr('In')} ${Fmt.time(m.firstIn)}',
      if (m.lastOut != null) '${tr('Out')} ${Fmt.time(m.lastOut)}',
      if (m.late) tr('Late'),
    ];
    return ListTile(
      onTap: onTap,
      leading: Avatar(name: m.name, url: m.avatarUrl, size: 40),
      title: Text(m.name, style: t.titleMedium),
      subtitle: Text(sub.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: _memberPill(m),
    );
  }
}

/// Member day detail — pushed on top of the shell (Team tab stays selected).
class MemberDayPage extends StatefulWidget {
  final TeamMember member;
  const MemberDayPage({super.key, required this.member});
  @override
  State<MemberDayPage> createState() => _MemberDayPageState();
}

class _MemberDayPageState extends State<MemberDayPage> {
  DateTime _date = DateTime.now();
  MemberDay? _day;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<AuthController>().api;
    try {
      final json = await api.get('/team/members/${widget.member.id}/day', query: {'date': Fmt.iso(_date)});
      if (!mounted) return;
      setState(() {
        _day = MemberDay.fromJson(json, widget.member);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(now.year - 1, 1, 1), lastDate: now);
    if (d == null || !mounted) return;
    setState(() => _date = DateTime(d.year, d.month, d.day));
    _load();
  }

  void _shift(int days) {
    final d = _date.add(Duration(days: days));
    if (d.isAfter(DateTime.now())) return;
    setState(() => _date = d);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<L10n>();
    final t = Theme.of(context).textTheme;
    final m = _day?.member ?? widget.member;
    final isToday = Fmt.iso(_date) == Fmt.iso(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text(m.name)),
      body: Column(children: [
        // ---- header: who + date switcher ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: HrCard(
            child: Column(children: [
              Row(children: [
                Avatar(name: m.name, url: m.avatarUrl, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.name, style: t.titleMedium),
                    Text([m.code, m.department, if (m.designation != null && m.designation!.isNotEmpty) m.designation!].where((s) => s.isNotEmpty).join(' · '), style: t.bodySmall),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [
                        Text(isToday ? tr('Today') : Fmt.weekday(_date), style: t.titleMedium, textAlign: TextAlign.center),
                        Text(Fmt.date(_date), style: t.bodySmall),
                      ]),
                    ),
                  ),
                ),
                IconButton(onPressed: isToday ? null : () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
              ]),
            ]),
          ),
        ),
        Expanded(child: _body(context)),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_loading) return const LoadingView();
    final day = _day;
    if (day == null) return ErrorRetryView(error: _error ?? tr('Something went wrong'), onRetry: _load);
    final d = day.day;
    final punches = [...d.punches]..sort((a, b) => a.at.compareTo(b.at));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        HrCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(tr('Attendance'), style: t.titleMedium)),
              _dayPill(d.status),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Stat(label: tr('First in'), value: Fmt.time(d.firstIn))),
              Expanded(child: _Stat(label: tr('Last out'), value: Fmt.time(d.lastOut))),
              Expanded(child: _Stat(label: tr('Worked'), value: Fmt.duration(d.workedMinutes))),
            ]),
            if (day.shiftStart != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.schedule_rounded, size: 16, color: HrBrand.subInk),
                const SizedBox(width: 6),
                Text('${day.shiftName ?? tr('Shift')} · ${day.shiftStart} – ${day.shiftEnd ?? ''}', style: t.bodySmall),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        Text(tr('Punches'), style: t.titleMedium),
        const SizedBox(height: 10),
        if (punches.isEmpty)
          HrCard(
            child: Row(children: [
              const Icon(Icons.history_rounded, color: HrBrand.subInk),
              const SizedBox(width: 12),
              Expanded(child: Text(tr('No punches on this day'), style: t.bodyMedium)),
            ]),
          )
        else
          HrCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < punches.length; i++) ...[
                if (i > 0) const Divider(),
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: punches[i].isIn ? HrBrand.greenContainer : HrBrand.blueContainer, shape: BoxShape.circle),
                    child: Icon(punches[i].isIn ? Icons.login_rounded : Icons.logout_rounded, size: 18, color: punches[i].isIn ? const Color(0xFF07945D) : HrBrand.blueDeep),
                  ),
                  title: Text(punches[i].isIn ? tr('Punch in') : tr('Punch out')),
                  subtitle: Text([
                    if (punches[i].method.isNotEmpty) punches[i].method,
                    if (punches[i].distanceM != null) '${punches[i].distanceM!.round()} m',
                    if (!punches[i].insideGeofence) tr('outside geofence'),
                  ].join(' · ')),
                  trailing: Text(Fmt.time(punches[i].at), style: t.titleMedium),
                ),
              ],
            ]),
          ),
      ],
    );
  }

  StatusPill _dayPill(String status) {
    switch (status) {
      case 'present':
      case 'in':
      case 'out':
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
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ]);
}
