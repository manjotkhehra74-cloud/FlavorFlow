import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/i18n.dart';
import '../../core/secure.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import '../home/home_models.dart';
import 'punch_models.dart';

/// Punch — Phase 2, Phase 7 look. Flow: load today (status + geofence) →
/// take a GPS fix → show distance / inside-outside → fingerprint confirm →
/// POST punch → result sheet → refresh today's punches. Punches are never
/// queued offline. The screen is now the webapp's navy punch card: ambient
/// glows, facility pill, live clock, shift progress ring, emerald action
/// button and translucent alert rows (the location card's states).
class PunchPage extends StatefulWidget {
  const PunchPage({super.key});
  @override
  State<PunchPage> createState() => _PunchPageState();
}

class _PunchPageState extends State<PunchPage> with WidgetsBindingObserver {
  TodayAttendance? _today;
  Geofence? _fence;
  List<PunchRecord> _punches = const [];
  Object? _error;
  bool _loading = true;

  GeoFix? _fix;
  GeoFailure? _geoFail;
  bool _locating = false;
  bool _punching = false;
  DateTime _now = DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 1 s tick: the webapp's live clock + shift-elapsed timer.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _load();
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from Settings after enabling location → try again automatically.
    if (state == AppLifecycleState.resumed && _geoFail != null) _locate();
  }

  Future<void> _load() async {
    final api = context.read<AuthController>().api;
    try {
      final json = await api.get('/attendance/today');
      final map = (json as Map).cast<String, dynamic>();
      await ApiCache.put('attendance/today', json);
      final punches = await _loadPunches(api);
      if (!mounted) return;
      setState(() {
        _today = TodayAttendance.fromJson(map);
        _fence = Geofence.fromJson(map['geofence']);
        _punches = punches;
        _error = null;
        _loading = false;
      });
      if (_fix == null) _locate();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<List<PunchRecord>> _loadPunches(ApiClient api) async {
    try {
      final d = Fmt.iso(DateTime.now());
      final json = await api.get('/attendance/history', query: {'from': d, 'to': d});
      final days = AttendanceDay.listFromJson(json);
      if (days.isEmpty) return const [];
      return days.first.punches..sort((a, b) => a.at.compareTo(b.at));
    } catch (_) {
      return _punches; // history is secondary — keep what we had
    }
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _geoFail = null;
    });
    try {
      final fix = await Geo.locate(_fence);
      if (mounted) setState(() => _fix = fix);
    } on GeoException catch (e) {
      if (mounted) setState(() => _geoFail = e.reason);
    } catch (_) {
      if (mounted) setState(() => _geoFail = GeoFailure.timeout);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _punch() async {
    final today = _today;
    final fix = _fix;
    if (today == null || fix == null || _punching) return;
    final type = today.punchedIn ? 'out' : 'in';
    final api = context.read<AuthController>().api;
    // 1) fingerprint / face / device PIN — the server records the method.
    final ok = await SecureStore.verify(type == 'in' ? tr('Confirm punch in') : tr('Confirm punch out'));
    if (!ok || !mounted) return;
    setState(() => _punching = true);
    try {
      final json = await api.post('/attendance/punch', {
        'type': type,
        'lat': fix.lat,
        'lng': fix.lng,
        'accuracyM': fix.accuracyM,
        'mocked': fix.mocked,
        'method': 'biometric',
        'deviceId': await SecureStore.deviceId(),
        'clientTime': DateTime.now().toIso8601String(),
      });
      final map = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
      final rec = map['punch'] is Map ? PunchRecord.fromJson((map['punch'] as Map).cast<String, dynamic>()) : null;
      if (!mounted) return;
      await _showResult(success: true, type: type, at: rec?.at ?? DateTime.now(), message: map['message']?.toString());
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      final dist = e.data?['distanceM'];
      final msg = e.code == 'GEOFENCE'
          ? tr('You are %s m from the site — move inside the %s m geofence and try again')
              .arg(dist is num ? dist.round() : '?')
              .replaceFirst('%s', (_fence?.radiusM ?? 150).round().toString())
          : e.message;
      await _showResult(success: false, type: type, at: DateTime.now(), message: msg);
      if (e.code == 'GEOFENCE') _locate();
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _punching = false);
    }
  }

  Future<void> _showResult({required bool success, required String type, required DateTime at, String? message}) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: success ? HrBrand.greenContainer : HrBrand.redContainer, shape: BoxShape.circle),
            child: Icon(success ? Icons.check_rounded : Icons.close_rounded, size: 46, color: success ? const Color(0xFF07945D) : HrBrand.red),
          ),
          const SizedBox(height: 16),
          Text(
            success ? (type == 'in' ? tr('Punched in') : tr('Punched out')) : tr('Punch failed'),
            style: Theme.of(c).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(success ? Fmt.time(at) : (message ?? tr('Something went wrong')),
              style: Theme.of(c).textTheme.bodyMedium, textAlign: TextAlign.center),
          if (success && message != null && message.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(message, style: Theme.of(c).textTheme.bodySmall, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('Done'))),
        ]),
      ),
    );
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
    return Scaffold(body: body);
  }

  Widget _content(BuildContext context, TodayAttendance today) {
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _NavyPunchCard(
            today: today,
            fix: _fix,
            fence: _fence,
            fail: _geoFail,
            locating: _locating,
            punching: _punching,
            now: _now,
            onPunch: _punch,
            onRetryLocate: _locate,
          ),
          const SizedBox(height: 18),
          // ---- today's punches ----
          Text(tr("Today's punches"), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: HrBrand.heading)),
          const SizedBox(height: 10),
          if (_punches.isEmpty)
            HrCard(
              child: Row(children: [
                const Icon(Icons.history_rounded, color: HrBrand.subInk),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('No punches yet today'), style: t.bodyMedium)),
              ]),
            )
          else
            HrCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < _punches.length; i++) ...[
                  if (i > 0) const Divider(),
                  _PunchRow(record: _punches[i]),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

class _PunchRow extends StatelessWidget {
  final PunchRecord record;
  const _PunchRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final r = record;
    final d = r.distanceM;
    final parts = <String>[
      if (r.method.isNotEmpty) r.method,
      if (d != null) '${d.round()} m',
      if (!r.insideGeofence) tr('outside geofence'),
    ];
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: r.isIn ? HrBrand.greenContainer : HrBrand.blueContainer, borderRadius: BorderRadius.circular(10)),
        child: Icon(r.isIn ? Icons.login_rounded : Icons.logout_rounded, size: 18, color: r.isIn ? const Color(0xFF07945D) : HrBrand.blueDeep),
      ),
      title: Text(r.isIn ? tr('Punch in') : tr('Punch out')),
      subtitle: parts.isEmpty ? null : Text(parts.join(' · ')),
      trailing: Text(Fmt.time(r.at), style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// The webapp's navy PunchWidget, recreated natively: gradient + ambient
/// glows, facility pill + live clock, shift label, progress ring with the
/// status in the centre, emerald action button, translucent alert rows.
class _NavyPunchCard extends StatelessWidget {
  final TodayAttendance today;
  final GeoFix? fix;
  final Geofence? fence;
  final GeoFailure? fail;
  final bool locating;
  final bool punching;
  final DateTime now;
  final VoidCallback onPunch;
  final VoidCallback onRetryLocate;
  const _NavyPunchCard({
    required this.today,
    required this.fix,
    required this.fence,
    required this.fail,
    required this.locating,
    required this.punching,
    required this.now,
    required this.onPunch,
    required this.onRetryLocate,
  });

  @override
  Widget build(BuildContext context) {
    final t = today;
    final elapsed = t.firstIn != null ? now.difference(t.firstIn!) : Duration.zero;
    final target = _shiftDuration(t);
    final progress = t.holiday || t.onLeave
        ? 0.0
        : t.done
            ? 1.0
            : t.punchedIn
                ? (elapsed.inSeconds / target.inSeconds).clamp(0.0, 1.0).toDouble()
                : 0.95;
    final ringColor = t.punchedIn || t.done ? HrBrand.emerald : HrBrand.ringBlue;

    final blocked = t.holiday && !t.punchedIn; // holidays: allow punch-out if somehow punched in
    final canPunch = fix != null && !punching && !blocked && !fix!.mocked;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: HrBrand.punchGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(HrBrand.radiusPunch),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Stack(children: [
        const NavyGlow(color: HrBrand.emerald, top: -64, right: -64, size: 260),
        const NavyGlow(color: HrBrand.blue, bottom: -64, left: -64, size: 260),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ---- facility + live clock ----
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
            const SizedBox(height: 18),
            // ---- shift label ----
            Center(
              child: Text(
                _shiftLabel(t).toUpperCase(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: HrBrand.slateOnNavy),
              ),
            ),
            const SizedBox(height: 14),
            // ---- ring + centre status ----
            Center(
              child: SizedBox(
                width: 176,
                height: 176,
                child: Stack(children: [
                  Positioned.fill(child: CustomPaint(painter: _RingPainter(progress: progress, color: ringColor))),
                  Center(child: _Centre(today: t, elapsed: elapsed, target: target)),
                ]),
              ),
            ),
            // ---- action ----
            if (!t.done && !t.holiday && !t.onLeave) ...[
              const SizedBox(height: 16),
              _PunchButton(
                label: t.punchedIn ? tr('Punch out') : tr('Punch in'),
                canTap: canPunch,
                busy: punching,
                onTap: onPunch,
              ),
            ],
            // ---- location / error alerts (translucent rows) ----
            ..._alerts(),
          ]),
        ),
      ]),
    );
  }

  String _shiftLabel(TodayAttendance t) {
    if (t.holiday) return tr('Holiday');
    if (t.onLeave) return tr('On leave');
    if (t.done) return tr('Shift completed');
    final name = t.shiftName ?? tr('Shift');
    final hours = Fmt.compact(_shiftDuration(t).inMinutes / 60);
    if (t.punchedIn) return '$name ($hours ${tr('Hours')})';
    if (t.shiftStart != null) return '$name (${t.shiftStart} · $hours ${tr('Hours')})';
    return '$name ($hours ${tr('Hours')})';
  }

  static Duration _shiftDuration(TodayAttendance t) {
    final s = _hm(t.shiftStart);
    if (s == null) return const Duration(hours: 8);
    final e = _hm(t.shiftEnd);
    if (e == null) return const Duration(hours: 8);
    var d = e - s;
    if (d.inSeconds <= 0) d += const Duration(hours: 24);
    return d;
  }

  static Duration? _hm(String? v) {
    if (v == null) return null;
    final parts = v.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return Duration(hours: h, minutes: m);
  }

  List<Widget> _alerts() {
    final f = fix;
    if (locating && f == null) {
      return [_alertRow(
        bg: const Color(0xFF0EA5E9).withValues(alpha: 0.2),
        border: const Color(0xFF38BDF8).withValues(alpha: 0.3),
        fg: const Color(0xFFBAE6FD),
        spinner: true,
        title: tr('Getting your location…'),
        sub: tr('Stand in the open for a faster GPS fix'),
      )];
    }
    if (fail != null) {
      final fr = fail!;
      late String title;
      late String sub;
      late String action;
      late VoidCallback onAction;
      switch (fr) {
        case GeoFailure.serviceOff:
          title = tr('Location is switched off');
          sub = tr('Turn on Location (GPS) to punch');
          action = tr('Open settings');
          onAction = Geo.openSettings;
        case GeoFailure.denied:
          title = tr('Location permission needed');
          sub = tr('HRMate checks that you are at the site when you punch');
          action = tr('Allow location');
          onAction = onRetryLocate;
        case GeoFailure.deniedForever:
          title = tr('Location permission blocked');
          sub = tr('Allow Location for HRMate in app settings');
          action = tr('Open app settings');
          onAction = Geo.openAppSettings;
        case GeoFailure.timeout:
          title = tr('Could not get a GPS fix');
          sub = tr('Move near a window or outside and retry');
          action = tr('Retry');
          onAction = onRetryLocate;
      }
      return [_alertRow(
        bg: const Color(0xFFF43F5E).withValues(alpha: 0.2),
        border: const Color(0xFFF87171).withValues(alpha: 0.3),
        fg: const Color(0xFFFECDD3),
        icon: Icons.warning_rounded,
        title: title,
        sub: sub,
        action: action,
        onAction: onAction,
      )];
    }
    if (f != null) {
      if (f.mocked) {
        return [_alertRow(
          bg: const Color(0xFFF43F5E).withValues(alpha: 0.2),
          border: const Color(0xFFF87171).withValues(alpha: 0.3),
          fg: const Color(0xFFFECDD3),
          icon: Icons.gpp_bad_rounded,
          title: tr('Mock location detected'),
          sub: tr('Turn off fake-GPS apps to punch'),
        )];
      }
      if (fence != null && !f.inside) {
        return [_alertRow(
          bg: const Color(0xFFF43F5E).withValues(alpha: 0.2),
          border: const Color(0xFFF87171).withValues(alpha: 0.3),
          fg: const Color(0xFFFECDD3),
          icon: Icons.wrong_location_rounded,
          title: tr('Outside the site geofence'),
          sub: '${f.distanceM!.round()} m ${tr('from site')} · ${tr('allowed')} ${fence!.radiusM.round()} m',
          action: tr('Refresh location'),
          onAction: onRetryLocate,
        )];
      }
      return [_alertRow(
        bg: HrBrand.emerald.withValues(alpha: 0.2),
        border: HrBrand.emerald.withValues(alpha: 0.3),
        fg: const Color(0xFFA7F3D0),
        icon: fence == null ? Icons.location_on_rounded : Icons.where_to_vote_rounded,
        title: fence == null ? tr('Location captured') : tr('Inside the site geofence'),
        sub: fence == null ? '± ${f.accuracyM.round()} m' : '${f.distanceM!.round()} m ${tr('from site')} · ± ${f.accuracyM.round()} m',
      )];
    }
    return [_alertRow(
      bg: Colors.white.withValues(alpha: 0.08),
      border: Colors.white.withValues(alpha: 0.15),
      fg: const Color(0xFFCBD5E1),
      icon: Icons.location_searching_rounded,
      title: tr('Location not checked yet'),
      action: tr('Check location'),
      onAction: onRetryLocate,
    )];
  }

  Widget _alertRow({
    required Color bg,
    required Color border,
    required Color fg,
    IconData? icon,
    bool spinner = false,
    required String title,
    String? sub,
    String? action,
    VoidCallback? onAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
      child: Row(children: [
        if (spinner)
          const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7DD3FC)))
        else
          Icon(icon, size: 16, color: fg),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
            if (sub != null && sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.8))),
          ]),
        ),
        if (action != null)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(action, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Ring centre — the three webapp states (punched in / shift finished /
/// punch in) plus holiday & leave.
class _Centre extends StatelessWidget {
  final TodayAttendance today;
  final Duration elapsed;
  final Duration target;
  const _Centre({required this.today, required this.elapsed, required this.target});

  @override
  Widget build(BuildContext context) {
    final t = today;
    final Widget child;
    if (t.holiday) {
      child = Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.celebration_rounded, color: Color(0xFFFBBF24), size: 30),
        const SizedBox(height: 6),
        Text(tr('Holiday'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
        if ((t.holidayName ?? '').isNotEmpty) Text(t.holidayName!, style: const TextStyle(fontSize: 11.5, color: HrBrand.faint)),
      ]);
    } else if (t.onLeave) {
      child = Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.event_available_rounded, color: HrBrand.emeraldOnNavy, size: 30),
        const SizedBox(height: 6),
        Text(tr('On leave'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 2),
        Text(tr('Enjoy your day off'), style: const TextStyle(fontSize: 11.5, color: HrBrand.faint)),
      ]);
    } else if (t.punchedIn) {
      final hrs = elapsed.inHours.toString().padLeft(2, '0');
      final mins = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
      final secs = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
      child = Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${hrs}h ${mins}m / ${target.inHours.toString().padLeft(2, '0')}h ${(target.inMinutes % 60).toString().padLeft(2, '0')}m',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: HrBrand.emeraldOnNavy, fontFeatures: [FontFeature.tabularNumbers()])),
        const SizedBox(height: 2),
        Text('$hrs:$mins:$secs',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularNumbers()],
              shadows: [Shadow(color: Color(0x8010B981), blurRadius: 14)],
            )),
        const SizedBox(height: 2),
        Text(tr('Punched in at %s').arg(Fmt.time(t.firstIn)), style: const TextStyle(fontSize: 10.5, color: HrBrand.faint)),
      ]);
    } else if (t.done) {
      child = Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded, color: HrBrand.emeraldOnNavy, size: 32),
        const SizedBox(height: 6),
        Text(tr('Shift finished'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 2),
        Text(tr('Out at %s').arg(Fmt.time(t.lastOut)), style: const TextStyle(fontSize: 11, color: HrBrand.faint)),
      ]);
    } else {
      final name = t.shiftName ?? tr('Shift');
      final hours = Fmt.compact(target.inMinutes / 60);
      child = Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.fingerprint_rounded, color: HrBrand.emeraldOnNavy, size: 30),
        const SizedBox(height: 6),
        Text(tr('Punch in'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 2),
        Text('$name (${hours}h)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: HrBrand.emeraldOnNavy)),
      ]);
    }
    return child;
  }
}

/// Progress ring painter (track `#1E293B`, stroke 8, emerald/blue progress —
/// the webapp's r68/stroke8 geometry).
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = HrBrand.slate,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.color != color;
}

/// Full-width emerald gradient punch button (webapp action, radius 16).
class _PunchButton extends StatelessWidget {
  final String label;
  final bool canTap;
  final bool busy;
  final VoidCallback onTap;
  const _PunchButton({required this.label, required this.canTap, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: canTap ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: canTap ? 1 : 0.4,
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: HrBrand.punchButtonGradient, begin: Alignment.centerLeft, end: Alignment.centerRight),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: HrBrand.emeraldLight.withValues(alpha: 0.3), width: 2),
              boxShadow: const [BoxShadow(color: Color(0x6610B981), blurRadius: 20, offset: Offset(0, 4))],
            ),
            child: Center(
              child: busy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.fingerprint_rounded, size: 20, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}
