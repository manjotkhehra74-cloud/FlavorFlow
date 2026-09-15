import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/cache.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import 'home_models.dart';

/// Home — Phase 0 header + identity card, Phase 1 adds (below them):
/// today card · quick tiles · announcements, with pull-to-refresh and the
/// offline chip (last successful response from cache).
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Cached<TodayAttendance>? _today;
  Cached<List<Announcement>>? _news;
  Cached<LeaveBalance>? _leave;
  Object? _error; // only when today AND cache both fail
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthController>().api;
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
    Cached<LeaveBalance>? leave;
    try {
      news = await cachedFetch('announcements', () => api.get('/announcements'), Announcement.listFromJson);
    } catch (_) {}
    try {
      leave = await cachedFetch('leaves/balance', () => api.get('/leaves/balance'), LeaveBalance.fromJson);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _today = today ?? _today;
      _news = news ?? _news;
      _leave = leave ?? _leave;
      _error = today == null ? err : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    context.watch<L10n>();
    final user = auth.user;
    final now = DateTime.now();
    final offlineSince = _today?.staleSince ?? _news?.staleSince;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              title: Row(children: [
                Avatar(name: user?.name ?? '', url: user?.avatarUrl, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tr(Fmt.greeting(now)), style: Theme.of(context).textTheme.bodySmall),
                    Text(Fmt.shortName(user?.name ?? ''), style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              sliver: SliverList.list(children: [
                Row(children: [
                  Expanded(child: Text(Fmt.weekday(now), style: Theme.of(context).textTheme.bodySmall)),
                  if (offlineSince != null) OfflineChip(since: offlineSince),
                ]),
                const SizedBox(height: 12),
                // ---- identity card (Phase 0) ----
                HrCard(
                  child: Row(children: [
                    Avatar(name: user?.name ?? '', url: user?.avatarUrl, size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(user?.name ?? '', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          [if ((user?.code ?? '').isNotEmpty) user!.code, if ((user?.department ?? '').isNotEmpty) user!.department].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        StatusPill.info(user?.roleLabel ?? 'Employee'),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                // ---- today card (Phase 1) ----
                if (_loading && _today == null)
                  const HrCard(child: SizedBox(height: 120, child: LoadingView()))
                else if (_error != null && _today == null)
                  HrCard(child: SizedBox(height: 200, child: ErrorRetryView(error: _error!, onRetry: _load)))
                else if (_today != null)
                  TodayCard(today: _today!.data, onPunch: () => context.go('/punch')),
                const SizedBox(height: 12),
                // ---- quick tiles (Phase 1) ----
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
                      value: _leave == null ? '—' : Fmt.num(_leave!.data.available),
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
                const SizedBox(height: 20),
                // ---- announcements (Phase 1) ----
                Text(tr('Announcements'), style: Theme.of(context).textTheme.titleMedium),
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
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Big status card: punched in / out / not yet, first in, last out, shift.
class TodayCard extends StatelessWidget {
  final TodayAttendance today;
  final VoidCallback onPunch;
  const TodayCard({super.key, required this.today, required this.onPunch});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final StatusPill pill;
    final String headline;
    if (today.holiday) {
      pill = StatusPill.info(tr('Holiday'));
      headline = today.holidayName ?? tr('Holiday');
    } else if (today.onLeave) {
      pill = StatusPill.warning(tr('On leave'));
      headline = tr('Enjoy your day off');
    } else if (today.punchedIn) {
      pill = StatusPill.success(tr('Punched in'));
      headline = '${tr('Since')} ${Fmt.time(today.firstIn)}';
    } else if (today.done) {
      pill = StatusPill.info(tr('Day complete'));
      headline = '${Fmt.time(today.firstIn)} → ${Fmt.time(today.lastOut)}';
    } else {
      pill = StatusPill.danger(tr('Not punched in'));
      headline = tr('Tap Punch to start your day');
    }
    return HrCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(tr('Today'), style: t.titleMedium)),
          pill,
        ]),
        const SizedBox(height: 8),
        Text(headline, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        Row(children: [
          _Stat(label: tr('First in'), value: Fmt.time(today.firstIn)),
          _Stat(label: tr('Last out'), value: Fmt.time(today.lastOut)),
          _Stat(label: tr('Worked'), value: Fmt.duration(today.workedMinutes)),
        ]),
        if (today.shiftName != null || today.shiftStart != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.access_time_rounded, size: 16, color: HrBrand.subInk),
            const SizedBox(width: 6),
            Text(
              [if (today.shiftName != null) today.shiftName!, if (today.shiftStart != null) '${today.shiftStart} – ${today.shiftEnd ?? ''}'].join(' · '),
              style: t.bodySmall,
            ),
          ]),
        ],
        if (!today.holiday && !today.onLeave && !today.done) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onPunch,
            icon: const Icon(Icons.fingerprint_rounded),
            label: Text(today.punchedIn ? tr('Punch out') : tr('Punch in')),
          ),
        ],
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ]),
      );
}

class QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final Color color;
  final VoidCallback onTap;
  const QuickTile({super.key, required this.icon, required this.label, required this.value, this.sub, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return HrCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(height: 10),
        Text(value, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(sub ?? label, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
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
          Expanded(child: Text(item.title, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
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
