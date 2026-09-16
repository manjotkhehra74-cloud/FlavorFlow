import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cache.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import 'more_models.dart';

/// Profile — read-only view of `GET me` (+ optional profile block).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Cached<Profile>? _profile;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthController>().api;
    try {
      final p = await cachedFetch('me', () => api.get('/me'), Profile.fromJson);
      if (!mounted) return;
      setState(() {
        _profile = p;
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
    final cached = _profile;
    final Widget body;
    if (_loading) {
      body = const LoadingView();
    } else if (cached == null) {
      body = ErrorRetryView(error: _error ?? tr('Something went wrong'), onRetry: _retry);
    } else {
      final p = cached.data;
      Widget row(IconData icon, String label, String? value) => value == null || value.isEmpty
          ? const SizedBox.shrink()
          : ListTile(
              leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
              title: Text(label, style: t.bodySmall),
              subtitle: Text(value, style: t.bodyLarge),
            );
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
              child: Column(children: [
                Avatar(name: p.name, url: p.avatarUrl, size: 84),
                const SizedBox(height: 12),
                Text(p.name, style: t.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text([p.code, if (p.designation != null && p.designation!.isNotEmpty) p.designation!].where((s) => s.isNotEmpty).join(' · '), style: t.bodyMedium, textAlign: TextAlign.center),
                if (p.roleLabel.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  StatusPill.info(p.roleLabel),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            HrCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                row(Icons.badge_outlined, tr('Employee code'), p.code),
                row(Icons.apartment_rounded, tr('Department'), p.department),
                row(Icons.work_outline_rounded, tr('Designation'), p.designation),
                row(Icons.supervisor_account_outlined, tr('Reports to'), p.managerName),
                row(Icons.schedule_rounded, tr('Shift'), _shiftLabel(p)),
                row(Icons.place_outlined, tr('Site'), p.site),
                row(Icons.event_available_outlined, tr('Joined on'), p.joinedOn == null ? null : Fmt.date(p.joinedOn)),
                row(Icons.mail_outline_rounded, tr('Email'), p.email),
                row(Icons.phone_outlined, tr('Phone'), p.phone),
              ]),
            ),
            const SizedBox(height: 12),
            Text(tr('To change these details, contact HR.'), style: t.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: Text(tr('Profile'))), body: body);
  }

  static String? _shiftLabel(Profile p) {
    final parts = <String>[
      if (p.shiftName != null && p.shiftName!.isNotEmpty) p.shiftName!,
      if (p.shiftStart != null && p.shiftStart!.isNotEmpty) '${p.shiftStart} – ${p.shiftEnd ?? ''}'.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
