import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/cache.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import '../more/more_models.dart';
import '../more/profile_page.dart';
import '../punch/punch_models.dart';
import '../team/team_models.dart';
import 'home_models.dart';

/// Home — the webapp dashboard (Phase 7): greeting + welcome subline,
/// ID Card / Apply Leave actions, navy punch summary, 3-col quick tiles,
/// KPI cards (leave balance · upcoming holiday · team/attendance),
/// announcements. Pull-to-refresh + offline chip stay as before.
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
    // Secondary blocks never block the screen — they just stay empty.
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
          (j) => _nextHoliday(j, now));
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
      final json = await api.get(
          '/attendance/history',
          query: {'from': Fmt.iso(DateTime(now.year, now.month, 1)), 'to': Fmt.iso(now)});
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

  /// First holiday on/after today (sorted list from `GET holidays?year=`).
  static Holiday? _nextHoliday(dynamic json, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    for (final h in Holiday.listFromJson(json)) {
      if (!h.date.isBefore(today)) return h;
    }
    return null;
  }

  void _openProfile(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfilePage()));
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
                  onTap: () => _openProfile(context),
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
                  value: _today == null ? '—' : Fmt.duration(_today!.data.workedMinutes),
                  color: HrBrand.amber,
                  onTap: () => context.go('/punch'),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            // ---- KPI cards ----
            _KpiGrid(
              leave: _leave?.data,
              holiday: _holiday?.data,
              team: isManager ? _team?.data : null,
              worked: isManager ? null : (_today?.data.workedMinutes ?? 0),
              monthPct: _monthPct,
            ),
            const SizedBox(height: 18),
            // ---- announcements ----
            Text(tr('Announcements'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: HrBrand.heading)),
            const SizedBox(height: 10),
            if (_news == null && _loading)
              const SizedBox(height: 80, child: LoadingView())
            else if (_news == null || _news!.data.isEmpty)
              HrCard(
                child: Row(children: [
                  const Icon(Icons.campaign_outlined, color: HrBrand.subInk),
                  const SizedBox(width: 12),
                  Expanded(child: Text(tr('No announcements right now'), style: Theme.of(context).textTheme.bodyMedium)),
                ]),
              )
            else
              for (final a in _news!.data.take(5)) ...[
                AnnouncementCard(item: a),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

/// Loading state for the navy card (same silhouette as the card).
class _NavyLoading extends StatelessWidget {
  const _NavyLoading();
  @override
  Widget build(BuildContext context) => Container(
        height: 170,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: HrBrand.punchGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(HrBrand.radiusPunch),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: const Center(
          child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
        ),
      );
}

/// Compact navy punch card (webapp PunchWidget, without camera) — status +
/// live clock, tap to open the full punch screen.
class _NavyCard extends StatelessWidget {
  final TodayAttendance today;
  final DateTime now;
  final VoidCallback onTap;
  const _NavyCard({required this.today, required this.now, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = today;
    final elapsed = t.firstIn != null ? now.difference(t.firstIn!) : Duration.zero;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: HrBrand.punchGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(HrBrand.radiusPunch),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Stack(children: [
        const NavyGlow(color: HrBrand.emerald, top: -50, right: -50, size: 190),
        const NavyGlow(color: HrBrand.blue, bottom: -50, left: -50, size: 190),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              NavyPill(
                icon: Icons.rss_feed_rounded,
                iconSize: 11,
                text: '${tr('Site')} · ${tr('Geofence verified')}',
                color: HrBrand.emeraldOnNavy,
                background: HrBrand.emerald.withValues(alpha: 0.15),
                border: HrBrand.emerald.withValues(alpha: 0.3),
              ),
              const Spacer(),
              NavyPill(
                icon: Icons.schedule_rounded,
                iconSize: 13,
                iconColor: HrBrand.emeraldOnNavy,
                text: Fmt.clock(now),
                color: Colors.white,
                background: Colors.white.withValues(alpha: 0.1),
                border: Colors.white.withValues(alpha: 0.15),
              ),
            ]),
            const SizedBox(height: 14),
            // ---- status ----
            if (t.holiday) ...[
              const Icon(Icons.celebration_rounded, color: Color(0xFFFBBF24), size: 30),
              const SizedBox(height: 6),
              Text(tr('Holiday'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
              if ((t.holidayName ?? '').isNotEmpty) Text(t.holidayName!, style: const TextStyle(fontSize: 11.5, color: HrBrand.faint)),
            ] else if (t.onLeave) ...[
              const Icon(Icons.event_available_rounded, color: HrBrand.emeraldOnNavy, size: 30),
              const SizedBox(height: 6),
              Text(tr('On leave'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 2),
              Text(tr('Enjoy your day off'), style: const TextStyle(fontSize: 11.5, color: HrBrand.faint)),
            ] else if (t.punchedIn) ...[
              Center(
                child: Text(
                  '${_hm(elapsed)} / ${_target(t)}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: HrBrand.emeraldOnNavy, fontFeatures: [FontFeature('tnum')]),
                ),
              ),
              const SizedBox(height: 2),
              Center(
                child: Text(
                  _hms(elapsed),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontFeatures: [FontFeature('tnum')],
                    shadows: [Shadow(color: Color(0x8010B981), blurRadius: 14)],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Center(child: Text(tr('Punched in at %s').arg(Fmt.time(t.firstIn)), style: const TextStyle(fontSize: 10.5, color: HrBrand.faint))),
            ] else if (t.done) ...[
              const Icon(Icons.check_circle_rounded, color: HrBrand.emeraldOnNavy, size: 30),
              const SizedBox(height: 6),
              Text(tr('Shift finished'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 2),
              Text(tr('Out at %s').arg(Fmt.time(t.lastOut)), style: const TextStyle(fontSize: 11, color: HrBrand.faint)),
            ] else ...[
              const Icon(Icons.fingerprint_rounded, color: HrBrand.emeraldOnNavy, size: 30),
              const SizedBox(height: 6),
              Text(tr('Punch in'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 2),
              Text(_shiftLabel(t), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: HrBrand.emeraldOnNavy)),
            ],
            const SizedBox(height: 14),
            if (!t.done && !t.holiday && !t.onLeave)
              HrGradientButton(
                label: t.punchedIn ? tr('Punch out') : tr('Punch in'),
                icon: Icons.fingerprint_rounded,
                height: 48,
                onPressed: onTap,
              ),
          ]),
        ),
      ]),
    );
  }

  static String _hm(Duration d) => '${d.inHours.toString().padLeft(2, '0')}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';

  static String _hms(Duration d) =>
      '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  static Duration _shiftDuration(TodayAttendance t) {
    final s = _hmDur(t.shiftStart);
    if (s == null) return const Duration(hours: 8);
    final e = _hmDur(t.shiftEnd);
    if (e == null) return const Duration(hours: 8);
    var d = e - s;
    if (d.inSeconds <= 0) d += const Duration(hours: 24);
    return d;
  }

  static Duration? _hmDur(String? v) {
    if (v == null) return null;
    final parts = v.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return Duration(hours: h, minutes: m);
  }

  static String _target(TodayAttendance t) {
    final d = _shiftDuration(t);
    return '${d.inHours.toString().padLeft(2, '0')}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  }

  static String _shiftLabel(TodayAttendance t) {
    final name = t.shiftName ?? tr('Shift');
    final hours = Fmt.compact(_shiftDuration(t).inMinutes / 60);
    if (t.shiftStart != null) return '$name (${t.shiftStart} · $hours ${tr('Hours')})';
    return '$name ($hours ${tr('Hours')})';
  }
}

/// 2×2 KPI cards (rounded-24, webapp style).
class _KpiGrid extends StatelessWidget {
  final LeaveBalance? leave;
  final Holiday? holiday;
  final TeamToday? team;
  final int? worked;
  final int? monthPct;
  const _KpiGrid({required this.leave, required this.holiday, required this.team, required this.worked, required this.monthPct});

  @override
  Widget build(BuildContext context) {
    final pending = leave?.pending ?? 0;
    final leaveKpi = _Kpi(
      icon: Icons.event_available_rounded,
      color: HrBrand.green,
      background: HrBrand.greenContainer,
      title: tr('Leave balance'),
      value: leave == null ? '—' : Fmt.compact(leave!.available),
      sub: [tr('days left'), if (pending > 0) tr('%s pending').arg(pending)].join(' · '),
      bar: leave == null || leave!.total <= 0 ? null : (leave!.available / leave!.total).clamp(0.0, 1.0).toDouble(),
    );
    final holidayKpi = _Kpi(
      icon: Icons.celebration_rounded,
      color: HrBrand.amber,
      background: HrBrand.amberContainer,
      title: tr('Upcoming holiday'),
      value: holiday == null ? '—' : holiday!.name,
      sub: holiday == null ? tr('No holidays yet') : Fmt.date(holiday!.date),
      smallValue: holiday != null && holiday!.name.length > 9,
    );
    final third = team != null
        ? _Kpi(
            icon: Icons.groups_rounded,
            color: HrBrand.green,
            background: HrBrand.greenContainer,
            title: tr('Team working'),
            value: '${team!.present}/${team!.total}',
            sub: tr('Present today'),
          )
        : _Kpi(
            icon: Icons.schedule_rounded,
            color: HrBrand.blue,
            background: HrBrand.blueContainer,
            title: tr('Worked today'),
            value: worked == null || worked! <= 0 ? '—' : Fmt.duration(worked),
            sub: tr('Worked'),
          );
    final monthKpi = _Kpi(
      icon: Icons.assessment_rounded,
      color: HrBrand.violet,
      background: HrBrand.violetContainer,
      title: tr('This month'),
      value: monthPct == null ? '—' : '$monthPct%',
      sub: tr('Attendance'),
    );
    return Column(children: [
      Row(children: [
        Expanded(child: leaveKpi),
        const SizedBox(width: 12),
        Expanded(child: holidayKpi),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: third),
        const SizedBox(width: 12),
        Expanded(child: monthKpi),
      ]),
    ]);
  }
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String value;
  final String? sub;
  final double? bar;
  final bool smallValue;
  const _Kpi({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.value,
    this.sub,
    this.bar,
    this.smallValue = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HrBrand.card,
          borderRadius: BorderRadius.circular(HrBrand.radiusKpi),
          border: Border.all(color: HrBrand.lineSoft),
          boxShadow: HrBrand.shadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: HrBrand.subInk)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: smallValue ? 15 : 21, fontWeight: FontWeight.w800, color: HrBrand.heading, height: 1.15)),
          if (sub != null && sub!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: HrBrand.subInk)),
          ],
          if (bar != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: bar, minHeight: 6, backgroundColor: HrBrand.greenContainer, color: HrBrand.green),
            ),
          ],
        ]),
      );
}

/// 3-col quick tile (webapp style: tinted icon square, bold value).
class QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final Color color;
  final VoidCallback onTap;
  const QuickTile({super.key, required this.icon, required this.label, required this.value, this.sub, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => HrCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: HrBrand.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(sub ?? label,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: HrBrand.subInk),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      );
}

class AnnouncementCard extends StatelessWidget {
  final Announcement item;
  const AnnouncementCard({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return HrCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (item.pinned) ...[const Icon(Icons.push_pin_rounded, size: 16, color: HrBrand.amber), const SizedBox(width: 6)],
          Expanded(child: Text(item.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: HrBrand.ink), maxLines: 2, overflow: TextOverflow.ellipsis)),
          if (item.at != null) Text(Fmt.dateShort(item.at), style: t.bodySmall),
        ]),
        if (item.body.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(item.body, style: t.bodyMedium, maxLines: 4, overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }
}
