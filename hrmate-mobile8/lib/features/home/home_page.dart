import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/cache.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/app_shell.dart';
import '../../ui/widgets.dart';
import 'home_models.dart';

/// Home — the webapp dashboard (Phase 8): greeting, ID Card / Apply Leave
/// actions, navy punch summary, quick tiles, KPI cards, announcements.
/// Every block is REAL data via cachedFetch (ARCHITECTURE.md §6); nothing
/// on this screen is decorative-only.
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Cached<TodayAttendance>? _today;
  Cached<List<Announcement>>? _news;
  Cached<LeaveBalance>? _leave;
  Cached<Holiday?>? _holiday;
  Cached<TeamToday>? _team;
  int? _monthPct;
  Object? _error; // only when today AND cache both fail
  bool _loading = true;
  DateTime _now = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // `auth.api` — the ONE client (tests inject an offline fake, §8).
    final auth = context.read<AuthController>();
    final api = auth.api;
    final isManager = auth.user?.isManager ?? false;
    Object? err;
    Cached<TodayAttendance>? today;
    try {
      today = await cachedFetch('attendance/today', () => api.get('/attendance/today'),
          (j) => TodayAttendance.fromJson((j as Map).cast<String, dynamic>()));
    } catch (e) {
      err = e;
    }
    Cached<List<Announcement>>? news;
    try {
      news = await cachedFetch('announcements', () => api.get('/announcements'), Announcement.listFromJson);
    } catch (_) {}
    Cached<LeaveBalance>? leave;
    try {
      leave = await cachedFetch('leaves/balance', () => api.get('/leaves/balance'), LeaveBalance.fromJson);
    } catch (_) {}
    Cached<Holiday?>? holiday;
    try {
      final now = DateTime.now();
      holiday = await cachedFetch('holidays/${now.year}', () => api.get('/holidays', query: {'year': now.year.toString()}),
          (j) => _nextHoliday(Holiday.listFromJson(j), now));
    } catch (_) {}
    Cached<TeamToday>? team;
    if (isManager) {
      try {
        team = await cachedFetch('team/today', () => api.get('/team/today'), TeamToday.fromJson);
      } catch (_) {}
    }
    int? pct;
    try {
      final now = DateTime.now();
      final json = await api.get('/attendance/history', query: {'from': Fmt.iso(DateTime(now.year, now.month, 1)), 'to': Fmt.iso(now)});
      final days = AttendanceDay.listFromJson(json);
      final present = days.where((d) => d.status == 'present').length;
      final half = days.where((d) => d.status == 'half').length;
      final absent = days.where((d) => d.status == 'absent').length;
      final denom = present + half + absent;
      if (denom > 0) pct = ((present + half * 0.5) / denom * 100).round();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _today = today ?? _today;
      _news = news ?? _news;
      _leave = leave ?? _leave;
      _holiday = holiday ?? _holiday;
      _team = team ?? _team;
      if (pct != null) _monthPct = pct;
      _error = today == null ? err : null;
      _loading = false;
    });
  }

  /// First holiday on/after today.
  Holiday? _nextHoliday(List<Holiday> all, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    for (final h in all) {
      if (!h.date.isBefore(today)) return h;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    context.watch<L10n>();
    final user = auth.user;
    final isManager = user?.isManager ?? false;
    final offlineSince = _today?.staleSince ?? _news?.staleSince;
    final name = (user?.name ?? '').trim();
    final firstName = name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text('${tr(Fmt.greeting(_now))}, $firstName! 👋',
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: HrBrand.heading)),
            const SizedBox(height: 3),
            Text('${tr('Welcome to HRMate')} · ${HrBrand.company}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: HrBrand.subInk)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text(Fmt.weekday(_now), style: Theme.of(context).textTheme.bodySmall)),
              if (offlineSince != null) OfflineChip(since: offlineSince),
            ]),
            const SizedBox(height: 14),
            // ---- actions (webapp: ID Card + Apply Leave) ----
            Row(children: [
              Expanded(
                child: HrCard(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen())),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.badge_outlined, size: 18, color: HrBrand.ink),
                    const SizedBox(width: 7),
                    Text(tr('ID Card'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: HrBrand.ink)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HrGradientButton(label: tr('Apply for leave'), icon: Icons.event_note_rounded, height: 46, onPressed: () => context.go('/leaves')),
              ),
            ]),
            const SizedBox(height: 14),
            // ---- navy punch summary ----
            if (_loading && _today == null)
              const _NavyLoading()
            else if (_error != null && _today == null)
              HrCard(child: SizedBox(height: 220, child: ErrorRetryView(error: _error!, onRetry: _load)))
            else if (_today != null)
              _NavyCard(today: _today!.data, now: _now, onTap: () => context.go('/punch')),
            const SizedBox(height: 14),
            // ---- quick tiles ----
            Row(children: [
              Expanded(
                child: QuickTile(
                  icon: Icons.fingerprint_rounded,
                  label: tr('Punch'),
                  value: _today == null ? '—' : (_today!.data.punchedIn ? tr('Punch out') : tr('Punch in')),
                  color: HrBrand.blue,
                  onTap: () => context.go('/punch'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: QuickTile(
                  icon: Icons.event_available_rounded,
                  label: tr('Leave balance'),
                  value: _leave == null ? '—' : Fmt.compact(_leave!.data.available),
                  sub: (_leave?.data.pending ?? 0) > 0 ? tr('%s pending').arg(_leave!.data.pending) : null,
                  color: HrBrand.green,
                  onTap: () => context.go('/leaves'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: QuickTile(
                  icon: Icons.schedule_rounded,
                  label: tr('Worked today'),
                  value: _today == null ? '—' : (_today!.data.workedMinutes > 0 ? Fmt.duration(_today!.data.workedMinutes) : '—'),
                  color: HrBrand.violet,
                  onTap: () => context.go('/punch'),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            // ---- KPI grid ----
            _KpiGrid(
              leave: _leave?.data,
              monthPct: _monthPct,
              holiday: _holiday?.data,
              team: isManager ? _team?.data : null,
              onTapLeave: () => context.go('/leaves'),
              onTapMonth: () => context.go('/punch'),
              onTapHoliday: () => context.go('/more'),
              onTapTeam: () => context.go('/team'),
            ),
            const SizedBox(height: 14),
            // ---- announcements ----
            Row(children: [
              const Icon(Icons.campaign_rounded, size: 16, color: HrBrand.subInk),
              const SizedBox(width: 6),
              Text(tr('Announcements'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: HrBrand.ink)),
            ]),
            const SizedBox(height: 8),
            if (_news == null && _loading)
              const _NewsSkeleton()
            else if ((_news?.data ?? const []).isEmpty)
              HrCard(child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(tr('No announcements right now'),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: HrBrand.faint)),
              ))
            else
              Column(children: [
                for (final a in (_news?.data ?? const <Announcement>[]).take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: HrCard(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      child: Row(children: [
                        if (a.pinned) ...[
                          const Icon(Icons.push_pin_rounded, size: 14, color: HrBrand.amberText),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: HrBrand.ink)),
                            if (a.body.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(a.body, maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5, color: HrBrand.subInk)),
                            ],
                          ]),
                        ),
                        if (a.at != null) ...[
                          const SizedBox(width: 8),
                          Text(Fmt.dateShort(a.at!), style: const TextStyle(fontSize: 10.5, color: HrBrand.faint)),
                        ],
                      ]),
                    ),
                  ),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Navy loading card (shimmer) — same footprint as the real card.
class _NavyLoading extends StatelessWidget {
  const _NavyLoading();

  @override
  Widget build(BuildContext context) => Container(
        height: 208,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: HrBrand.punchGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(HrBrand.radiusPunch),
          boxShadow: HrBrand.shadowPop,
        ),
        child: const Center(child: SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))),
      );
}

/// The webapp's navy punch card: ambient glows, shift pill, live clock,
/// status + times, emerald action button.
class _NavyCard extends StatelessWidget {
  final TodayAttendance today;
  final DateTime now;
  final VoidCallback onTap;
  const _NavyCard({required this.today, required this.now, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = today;
    final (label, color, icon) = _statusOf(t);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: HrBrand.punchGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(HrBrand.radiusPunch),
        boxShadow: HrBrand.shadowPop,
      ),
      child: Stack(children: [
        const Positioned(top: -60, right: -40, child: NavyGlow(size: 190, color: HrBrand.blue, alignment: Alignment.center)),
        const Positioned(bottom: -50, left: -30, child: NavyGlow(size: 160, color: HrBrand.emerald, alignment: Alignment.center)),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const LiveDot(),
                const SizedBox(width: 6),
                Text(t.shiftName ?? tr('Shift'),
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: HrBrand.slateOnNavy)),
              ]),
            ),
            const Spacer(),
            Text(Fmt.time(now),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, fontFeatures: kTnum)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 1),
                Text(_subline(t), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: HrBrand.slateOnNavy)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            _TimeCell(label: tr('In'), value: t.firstIn == null ? '—' : Fmt.time(t.firstIn!)),
            const SizedBox(width: 8),
            _TimeCell(label: tr('Out'), value: t.lastOut == null ? '—' : Fmt.time(t.lastOut!)),
            const SizedBox(width: 8),
            _TimeCell(label: tr('Hours'), value: t.workedMinutes > 0 ? Fmt.duration(t.workedMinutes) : '—'),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 44,
            child: HrGradientButton(
              label: t.punchedIn ? tr('Punch out') : tr('Punch in'),
              icon: t.punchedIn ? Icons.logout_rounded : Icons.fingerprint_rounded,
              height: 44,
              onPressed: t.done || t.onLeave || t.holiday ? null : onTap,
            ),
          ),
        ]),
      ]),
    );
  }

  (String, Color, IconData) _statusOf(TodayAttendance t) {
    if (t.holiday) return (tr('Holiday'), HrBrand.amber, Icons.beach_access_rounded);
    if (t.onLeave) return (tr('On leave'), HrBrand.violet, Icons.beach_access_rounded);
    if (t.done) return (tr('Day complete'), HrBrand.emerald, Icons.check_circle_rounded);
    if (t.punchedIn) return (tr('Punched in'), HrBrand.emerald, Icons.access_time_rounded);
    return (tr('Not punched in'), HrBrand.ringBlue, Icons.schedule_rounded);
  }

  String _subline(TodayAttendance t) {
    if (t.holiday) return t.holidayName ?? tr('Holiday');
    if (t.onLeave) return tr('Enjoy your day off');
    if (t.done) return '${tr('Shift completed')} · ${t.shiftName ?? ''}';
    if (t.punchedIn) return '${tr('Since')} ${t.firstIn == null ? '' : Fmt.time(t.firstIn!)}';
    return tr('Tap Punch to start your day');
  }
}

class _TimeCell extends StatelessWidget {
  final String label;
  final String value;
  const _TimeCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: HrBrand.slateOnNavy)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white, fontFeatures: kTnum)),
          ]),
        ),
      );
}

/// KPI grid — leave balance, month attendance, next holiday, team (managers).
class _KpiGrid extends StatelessWidget {
  final LeaveBalance? leave;
  final int? monthPct;
  final Holiday? holiday;
  final TeamToday? team;
  final VoidCallback onTapLeave;
  final VoidCallback onTapMonth;
  final VoidCallback onTapHoliday;
  final VoidCallback onTapTeam;
  const _KpiGrid({required this.leave, required this.monthPct, required this.holiday, required this.team, required this.onTapLeave, required this.onTapMonth, required this.onTapHoliday, required this.onTapTeam});

  @override
  Widget build(BuildContext context) {
    final items = <_KpiItem>[
      _KpiItem(
        label: tr('Leave balance'),
        value: leave == null ? '—' : Fmt.compact(leave!.available),
        sub: leave == null ? null : (leave!.pending > 0 ? tr('%s pending').arg(leave!.pending) : tr('%s day(s)').arg(Fmt.compact(leave!.total))),
        bar: leave == null || leave!.total <= 0 ? null : leave!.available / leave!.total,
        color: HrBrand.green,
        icon: Icons.event_available_rounded,
        onTap: onTapLeave,
      ),
      _KpiItem(
        label: tr('This month'),
        value: monthPct == null ? '—' : '$monthPct%',
        sub: tr('Attendance'),
        bar: monthPct == null ? null : monthPct / 100,
        color: HrBrand.blue,
        icon: Icons.insights_rounded,
        onTap: onTapMonth,
      ),
      _KpiItem(
        label: tr('Upcoming holiday'),
        value: holiday == null ? '—' : Fmt.dateShort(holiday!.date),
        sub: holiday?.name,
        color: HrBrand.amber,
        icon: Icons.beach_access_rounded,
        onTap: onTapHoliday,
      ),
      if (team != null)
        _KpiItem(
          label: tr('Team working'),
          value: '${team!.present}/${team!.total}',
          sub: tr('Present today'),
          color: HrBrand.violet,
          icon: Icons.groups_rounded,
          onTap: onTapTeam,
        ),
    ];
    return Column(children: [
      Row(children: [
        for (var i = 0; i < (items.length > 2 ? 2 : items.length); i++)
          Expanded(child: Padding(padding: const EdgeInsets.only(right: i == 0 ? 10 : 0), child: _KpiCard(item: items[i]))),
      ]),
      if (items.length > 2) ...[
        const SizedBox(height: 10),
        Row(children: [
          for (var i = 2; i < items.length; i++)
            Expanded(child: Padding(padding: const EdgeInsets.only(right: i == 2 ? 10 : 0), child: _KpiCard(item: items[i]))),
        ]),
      ],
    ]);
  }
}

class _KpiItem {
  final String label;
  final String value;
  final String? sub;
  final double? bar;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _KpiItem({required this.label, required this.value, this.sub, this.bar, required this.color, required this.icon, required this.onTap});
}

class _KpiCard extends StatelessWidget {
  final _KpiItem item;
  const _KpiCard({required this.item});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(HrBrand.radiusCard),
          onTap: item.onTap,
          child: KpiTile(label: item.label, value: item.value, sub: item.sub, bar: item.bar, color: item.color),
        ),
      );
}

/// Skeleton shimmer for announcements while the first load is in flight.
class _NewsSkeleton extends StatelessWidget {
  const _NewsSkeleton();

  @override
  Widget build(BuildContext context) => const Column(children: [
        Shimmer(width: double.infinity, height: 52, radius: 16),
        SizedBox(height: 8),
        Shimmer(width: double.infinity, height: 52, radius: 16),
      ]);
}
