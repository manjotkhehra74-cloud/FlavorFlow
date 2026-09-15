import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../state/auth.dart';

/// Authenticated shell — bottom navigation exactly like the webapp:
/// Home · Leaves · Punch (centre, elevated) · Team · More.
/// Team is hidden for roles without a team (server still enforces).
class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = [
    _Tab('/home', 'Home', Icons.home_outlined, Icons.home_rounded),
    _Tab('/leaves', 'Leaves', Icons.event_note_outlined, Icons.event_note_rounded),
    _Tab('/punch', 'Punch', Icons.fingerprint_rounded, Icons.fingerprint_rounded),
    _Tab('/team', 'Team', Icons.groups_outlined, Icons.groups_rounded),
    _Tab('/more', 'More', Icons.grid_view_outlined, Icons.grid_view_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    context.watch<L10n>();
    final tabs = _tabs.where((t) => t.path != '/team' || (auth.user?.isManager ?? false)).toList();
    final location = GoRouterState.of(context).matchedLocation;
    var index = tabs.indexWhere((t) => location == t.path || location.startsWith('${t.path}/'));
    if (index < 0) index = 0;

    return Scaffold(
      body: SafeArea(top: false, child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(tabs[i].path),
        destinations: [
          for (final t in tabs)
            if (t.path == '/punch')
              NavigationDestination(
                icon: const _PunchIcon(active: false),
                selectedIcon: const _PunchIcon(active: true),
                label: tr(t.label),
              )
            else
              NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.activeIcon), label: tr(t.label)),
        ],
      ),
    );
  }
}

class _Tab {
  final String path;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _Tab(this.path, this.label, this.icon, this.activeIcon);
}

/// The blue elevated punch button in the middle of the bar.
class _PunchIcon extends StatelessWidget {
  final bool active;
  const _PunchIcon({required this.active});
  @override
  Widget build(BuildContext context) => Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: active ? HrBrand.blueDeep : HrBrand.blue,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: HrBrand.blue.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 28),
      );
}

/// Placeholder body used by tabs whose phase has not been built yet.
/// Replaced (not rewritten) when that phase lands.
class PhasePlaceholder extends StatelessWidget {
  final String title;
  final IconData icon;
  final int phase;
  const PhasePlaceholder({super.key, required this.title, required this.icon, required this.phase});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr(title))),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: HrBrand.blueContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 34, color: HrBrand.blue),
            ),
            const SizedBox(height: 16),
            Text(tr(title), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(tr('Coming in Phase %s').arg(phase), style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}
