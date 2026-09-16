import 'dart:async';

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

/// Punch — Phase 2. Flow: load today (status + geofence) → take a GPS fix →
/// show distance / inside-outside → fingerprint confirm → POST punch →
/// result sheet → refresh today's punches. Punches are never queued offline.
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
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
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
    return Scaffold(appBar: AppBar(title: Text(tr('Punch'))), body: body);
  }

  Widget _content(BuildContext context, TodayAttendance today) {
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // ---- clock + status ----
          HrCard(
            child: Column(children: [
              Text(Fmt.time(DateTime.now()), style: t.headlineSmall?.copyWith(fontSize: 40, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(Fmt.weekday(DateTime.now()), style: t.bodySmall),
              const SizedBox(height: 12),
              _statusPill(today),
              if (today.shiftStart != null) ...[
                const SizedBox(height: 8),
                Text('${today.shiftName ?? tr('Shift')} · ${today.shiftStart} – ${today.shiftEnd ?? ''}', style: t.bodySmall),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          // ---- location ----
          _LocationCard(fix: _fix, fail: _geoFail, fence: _fence, locating: _locating, onRetry: _locate),
          const SizedBox(height: 16),
          // ---- big punch button ----
          _PunchButton(today: today, fix: _fix, busy: _punching || _locating, onTap: _punch),
          const SizedBox(height: 20),
          // ---- today's punches ----
          Text(tr("Today's punches"), style: t.titleMedium),
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

  Widget _statusPill(TodayAttendance today) {
    if (today.holiday) return StatusPill.info(today.holidayName ?? tr('Holiday'));
    if (today.onLeave) return StatusPill.warning(tr('On leave'));
    if (today.punchedIn) return StatusPill.success('${tr('Punched in')} · ${Fmt.time(today.firstIn)}');
    if (today.done) return StatusPill.info('${tr('Day complete')} · ${Fmt.duration(today.workedMinutes)}');
    return StatusPill.danger(tr('Not punched in'));
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
        decoration: BoxDecoration(color: r.isIn ? HrBrand.greenContainer : HrBrand.blueContainer, shape: BoxShape.circle),
        child: Icon(r.isIn ? Icons.login_rounded : Icons.logout_rounded, size: 18, color: r.isIn ? const Color(0xFF07945D) : HrBrand.blueDeep),
      ),
      title: Text(r.isIn ? tr('Punch in') : tr('Punch out')),
      subtitle: parts.isEmpty ? null : Text(parts.join(' · ')),
      trailing: Text(Fmt.time(r.at), style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final GeoFix? fix;
  final GeoFailure? fail;
  final Geofence? fence;
  final bool locating;
  final VoidCallback onRetry;
  const _LocationCard({required this.fix, required this.fail, required this.fence, required this.locating, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    IconData icon = Icons.location_searching_rounded;
    Color color = HrBrand.subInk;
    String title = '';
    String sub = '';
    Widget? action;
    if (locating && fix == null) {
      icon = Icons.my_location_rounded;
      color = HrBrand.blue;
      title = tr('Getting your location…');
      sub = tr('Stand in the open for a faster GPS fix');
    } else if (fail != null) {
      icon = Icons.location_off_rounded;
      color = HrBrand.red;
      switch (fail!) {
        case GeoFailure.serviceOff:
          title = tr('Location is switched off');
          sub = tr('Turn on Location (GPS) to punch');
          action = OutlinedButton(onPressed: Geo.openSettings, child: Text(tr('Open settings')));
        case GeoFailure.denied:
          title = tr('Location permission needed');
          sub = tr('HRMate checks that you are at the site when you punch');
          action = OutlinedButton(onPressed: onRetry, child: Text(tr('Allow location')));
        case GeoFailure.deniedForever:
          title = tr('Location permission blocked');
          sub = tr('Allow Location for HRMate in app settings');
          action = OutlinedButton(onPressed: Geo.openAppSettings, child: Text(tr('Open app settings')));
        case GeoFailure.timeout:
          title = tr('Could not get a GPS fix');
          sub = tr('Move near a window or outside and retry');
          action = OutlinedButton(onPressed: onRetry, child: Text(tr('Retry')));
      }
    } else if (fix != null) {
      final f = fix!;
      if (fence == null) {
        icon = Icons.location_on_rounded;
        color = HrBrand.blue;
        title = tr('Location captured');
        sub = '± ${f.accuracyM.round()} m';
      } else if (f.inside) {
        icon = Icons.where_to_vote_rounded;
        color = const Color(0xFF07945D);
        title = tr('Inside the site geofence');
        sub = '${f.distanceM!.round()} m ${tr('from site')} · ± ${f.accuracyM.round()} m';
      } else {
        icon = Icons.wrong_location_rounded;
        color = HrBrand.red;
        title = tr('Outside the site geofence');
        sub = '${f.distanceM!.round()} m ${tr('from site')} · ${tr('allowed')} ${fence!.radiusM.round()} m';
        action = OutlinedButton(onPressed: onRetry, child: Text(tr('Refresh location')));
      }
      if (f.mocked) {
        icon = Icons.gpp_bad_rounded;
        color = HrBrand.red;
        title = tr('Mock location detected');
        sub = tr('Turn off fake-GPS apps to punch');
      }
    } else {
      icon = Icons.location_searching_rounded;
      color = HrBrand.subInk;
      title = tr('Location not checked yet');
      sub = '';
      action = OutlinedButton(onPressed: onRetry, child: Text(tr('Check location')));
    }
    return HrCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: locating && fix == null
                ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2.2))
                : Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.titleMedium),
              if (sub.isNotEmpty) Text(sub, style: t.bodySmall),
            ]),
          ),
          if (fix != null && !locating) IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), tooltip: tr('Refresh location')),
        ]),
        if (action != null) ...[const SizedBox(height: 12), action],
      ]),
    );
  }
}

class _PunchButton extends StatelessWidget {
  final TodayAttendance today;
  final GeoFix? fix;
  final bool busy;
  final VoidCallback onTap;
  const _PunchButton({required this.today, required this.fix, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isIn = today.punchedIn;
    final blocked = today.holiday && !isIn; // holidays: allow punch-out if somehow punched in
    final canPunch = fix != null && !busy && !blocked && !fix!.mocked;
    final color = isIn ? HrBrand.red : HrBrand.blue;
    return Column(children: [
      GestureDetector(
        onTap: canPunch ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 168,
          height: 168,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: canPunch ? color : HrBrand.border,
            boxShadow: canPunch ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 10))] : null,
          ),
          child: Center(
            child: busy
                ? const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.fingerprint_rounded, size: 56, color: Colors.white),
                    const SizedBox(height: 6),
                    Text(isIn ? tr('Punch out') : tr('Punch in'),
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                  ]),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        blocked
            ? tr('Holiday — no punch needed')
            : fix == null
                ? tr('Waiting for location')
                : (fix!.inside ? tr('Confirm with your fingerprint') : tr('You can try, but the server may reject punches outside the geofence')),
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    ]);
  }
}
