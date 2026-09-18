import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../features/more/profile_page.dart';
import '../state/auth.dart';
import '../ui/widgets.dart';

/// Authenticated shell — the webapp's chrome (Phase 7):
/// white top bar (logo + "HR" + "Mate" + company subline + user pill) and a
/// bottom nav Home · Leaves · Punch (centre, raised emerald circle) · Team ·
/// More. Team is hidden for roles without a team (server still enforces).
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

    // Tab switches collapse the pushed pages first (Profile, member day,
    // sheets closed) so the shell never stacks on itself.
    void go(String path) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      context.go(path);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _Header(onProfile: () {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfilePage()));
          }),
          Expanded(child: child),
        ]),
      ),
      bottomNavigationBar: _BottomNav(tabs: tabs, index: index, onGo: go),
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

/// White 64-ish top bar, exactly like the webapp header.
class _Header extends StatelessWidget {
  final VoidCallback onProfile;
  const _Header({required this.onProfile});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    return Container(
      color: HrBrand.card,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: HrBrand.lineSoft))),
      padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(11)),
          child: Image.asset(
            'assets/icon/app_icon.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.badge_rounded, color: HrBrand.blue, size: 22),
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: 'HR', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: HrBrand.heading, height: 1)),
                TextSpan(text: 'Mate', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: HrBrand.blue, height: 1)),
              ]),
            ),
            SizedBox(height: 1.5),
            Text(HrBrand.company,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: HrBrand.subInk, letterSpacing: 0.2)),
          ]),
        ),
        const SizedBox(width: 8),
        _UserPill(user: user, onTap: onProfile),
      ]),
    );
  }
}

/// Avatar + green dot + name, tap → profile (webapp user pill).
class _UserPill extends StatelessWidget {
  final HrUser? user;
  final VoidCallback onTap;
  const _UserPill({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.only(left: 4, right: 12, top: 4, bottom: 4),
            decoration: BoxDecoration(color: HrBrand.tile, borderRadius: BorderRadius.circular(999), border: Border.all(color: HrBrand.lineSoft)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Avatar(name: user?.name ?? '', url: user?.avatarUrl, size: 30, online: true),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  user?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: HrBrand.ink),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// Bottom nav — white, top border, raised emerald Punch circle in the
/// centre (webapp MobileNav), active icon in a blue/10 rounded box.
class _BottomNav extends StatelessWidget {
  final List<_Tab> tabs;
  final int index;
  final ValueChanged<String> onGo;
  const _BottomNav({required this.tabs, required this.index, required this.onGo});

  @override
  Widget build(BuildContext context) => Container(
        color: HrBrand.card,
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: HrBrand.lineSoft))),
        clipBehavior: Clip.none,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: tabs[i].path == '/punch'
                        ? _NavPunch(active: index == i, onTap: () => onGo(tabs[i].path))
                        : _NavItem(tab: tabs[i], active: index == i, onTap: () => onGo(tabs[i].path)),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _NavItem extends StatelessWidget {
  final _Tab tab;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({required this.tab, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 34,
              height: 28,
              decoration: BoxDecoration(
                color: active ? HrBrand.blueContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(active ? tab.activeIcon : tab.icon, size: 22, color: active ? HrBrand.blue : HrBrand.subInk),
            ),
            const SizedBox(height: 3),
            Text(
              tr(tab.label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? HrBrand.blue : HrBrand.subInk,
              ),
            ),
          ]),
        ),
      );
}

/// The raised emerald Punch circle (56 px, white ring, emerald glow).
class _NavPunch extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _NavPunch({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Padding(
              padding: const EdgeInsets.only(top: -18),
              child: Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x5910B981), blurRadius: 16, offset: Offset(0, 6)),
                    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [HrBrand.emeraldDeep, HrBrand.emerald, HrBrand.emeraldLight],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 26),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tr('Punch'),
              maxLines: 1,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? HrBrand.emeraldDeep : HrBrand.subInk),
            ),
          ]),
        ),
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
