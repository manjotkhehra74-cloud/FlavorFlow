import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/notifier.dart';
import '../core/company.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/format.dart';
import '../state/auth.dart';
import 'widgets.dart';

/// Authenticated shell: dark enterprise sidebar (desktop) / drawer (mobile),
/// slim top bar with live notification badge and the user's role identity.
class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _unread = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    PhoneNotifier.init(); // status-bar notifications (Android permission ask)
    _loadUnread();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _loadUnread());
    // Load the editable company identity used on every exported PDF.
    CompanyProfile.load(context.read<AuthController>().api);
    // Rebuild when the company profile / industry changes (units + gating).
    CompanyProfile.rev.addListener(_onCompanyChanged);
  }

  void _onCompanyChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadUnread() async {
    try {
      final auth = context.read<AuthController>();
      final json = await auth.api.get('/notifications');
      final items = ((json as Map)['notifications'] as List).cast<Map<String, dynamic>>();
      final unread = items.where((n) => n['is_read'] == 0).length;
      if (mounted) setState(() => _unread = unread);
      // New unread items → real phone notifications (sound + status bar).
      await PhoneNotifier.showNew(items);
    } catch (_) {/* transient */}
  }

  @override
  void dispose() {
    _timer?.cancel();
    CompanyProfile.rev.removeListener(_onCompanyChanged);
    super.dispose();
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _selectedIndex(BuildContext context, List nav) {
    final path = GoRouterState.of(context).uri.path;
    var best = 0, bestLen = -1;
    for (var i = 0; i < nav.length; i++) {
      final p = nav[i]['path'] as String;
      if (path == p || path.startsWith('$p/')) {
        if (p.length > bestLen) { best = i; bestLen = p.length; }
      }
    }
    return best;
  }

  Future<void> _logout() async {
    await context.read<AuthController>().logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final session = auth.session;
    if (session == null) return const Scaffold();
    final nav = [...session.nav.map((e) => Map<String, dynamic>.from(e as Map))];
    // Raw Material gets its own menu entry right below Packing Material.
    // Once the server knows raw.view/loss.view (ff-permfix) it sends these
    // entries itself and gates them per user; until then we inject them
    // client-side for anyone with packing access.
    final pi = nav.indexWhere((e) => e['path'] == '/packing');
    if (!nav.any((e) => e['path'] == '/raw') && auth.canOr('raw.view', 'packing.view')) {
      final at = pi != -1 ? pi + 1 : nav.length;
      nav.insert(at, {'path': '/raw', 'label': 'Raw Material', 'icon': 'science', 'group': pi != -1 ? nav[pi]['group'] : 'Operations'});
    }
    final ri = nav.indexWhere((e) => e['path'] == '/raw');
    if (!nav.any((e) => e['path'] == '/loss') && auth.canOr('loss.view', 'packing.view') && CompanyProfile.usesLossPct) {
      final at = ri != -1 ? ri + 1 : nav.length;
      nav.insert(at, {'path': '/loss', 'label': 'Packing Loss %', 'icon': 'percent', 'group': ri != -1 ? nav[ri]['group'] : 'Operations'});
    }
    // Industry gating: server nav may carry /loss for everyone — drop it
    // where the industry doesn't track a packing Loss % sheet.
    if (!CompanyProfile.usesLossPct) nav.removeWhere((e) => e['path'] == '/loss');
    // Settings entry at the end of the menu for every user.
    if (!nav.any((e) => e['path'] == '/settings')) {
      nav.add({'path': '/settings', 'label': 'Settings', 'icon': 'settings', 'group': nav.isNotEmpty ? (nav.last['group'] ?? 'System') : 'System'});
    }
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1060;
    final phone = width < 700;
    final selected = _selectedIndex(context, nav);
    final title = tr(nav[selected]['label'] as String);

    void goTo(int i) {
      context.go(nav[i]['path'] as String);
      if (!wide) {
        Future.delayed(const Duration(milliseconds: 160), () {
          _scaffoldKey.currentState?.closeDrawer();
        });
      }
    }

    final sidebar = _Sidebar(
      nav: nav,
      selected: selected,
      session: session,
      onTap: goTo,
      onLogout: _logout,
    );

    final topBar = _TopBar(title: title, unread: _unread, session: session, onLogout: _logout);

    if (wide) {
      return Scaffold(
        body: Row(children: [
          sidebar,
          Expanded(
            child: Column(children: [
              topBar,
              const Divider(height: 1),
              Expanded(child: widget.child),
            ]),
          ),
        ]),
      );
    }

    final path = GoRouterState.of(context).uri.path;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(title)),
        titleSpacing: 0,
        actions: [topBar.actionsPadding(child: topBar.bellAction(context)), topBar.userAction(context, compact: true)],
      ),
      drawer: phone
          ? _MobileModulesDrawer(nav: nav, selected: selected, session: session, onTap: goTo, onLogout: _logout)
          : Drawer(backgroundColor: Shell.bg, child: SafeArea(child: sidebar)),
      body: widget.child,
      bottomNavigationBar: phone
          ? _MobileBottomBar(
              currentPath: path,
              hasReports: nav.any((e) => e['path'] == '/reports'),
              onModules: () => _scaffoldKey.currentState?.openDrawer(),
            )
          : null,
    );
  }
}

/// Play Store phone navigation: persistent shortcuts around a prominent
/// module-grid button. Routes and permission checks remain unchanged.
class _MobileBottomBar extends StatelessWidget {
  final String currentPath;
  final bool hasReports;
  final VoidCallback onModules;
  const _MobileBottomBar({required this.currentPath, required this.hasReports, required this.onModules});

  bool _at(String path) => currentPath == path || currentPath.startsWith('$path/');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
        boxShadow: [BoxShadow(color: Theme.of(context).shadowColor.withValues(alpha: 0.38), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(children: [
            _MobileNavItem(
              icon: Icons.home_rounded,
              label: tr('Dashboard'),
              active: _at('/dashboard'),
              onTap: () => context.go('/dashboard'),
            ),
            _MobileNavItem(
              icon: Icons.notifications_outlined,
              label: tr('Notifications'),
              active: _at('/notifications'),
              onTap: () => context.go('/notifications'),
            ),
            SizedBox(
              width: 66,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onModules,
                    customBorder: const CircleBorder(),
                    child: Ink(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: AppBrand.gradient,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppBrand.blue.withValues(alpha: 0.30), blurRadius: 12, offset: const Offset(0, 5))],
                      ),
                      child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ),
            ),
            if (hasReports)
              _MobileNavItem(
                icon: Icons.insert_chart_outlined_rounded,
                label: tr('Reports'),
                active: _at('/reports'),
                onTap: () => context.go('/reports'),
              )
            else
              const Spacer(),
            _MobileNavItem(
              icon: Icons.person_outline_rounded,
              label: tr('Settings'),
              active: _at('/settings'),
              onTap: () => context.go('/settings'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MobileNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _MobileNavItem({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9.5, height: 1.1, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: color)),
        ]),
      ),
    );
  }
}

/// Phone drawer presented as the colourful module grid in the design reference.
/// It renders the same server-provided navigation list and invokes the same routes.
class _MobileModulesDrawer extends StatelessWidget {
  final List nav;
  final int selected;
  final UserSession session;
  final void Function(int) onTap;
  final Future<void> Function() onLogout;
  const _MobileModulesDrawer({required this.nav, required this.selected, required this.session, required this.onTap, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final available = MediaQuery.sizeOf(context).width * 0.90;
    final drawerWidth = available > 390 ? 390.0 : available;
    return Drawer(
      width: drawerWidth,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: scheme.outlineVariant)),
                clipBehavior: Clip.antiAlias,
                child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('FlavorFlow ERP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface, letterSpacing: -0.2)),
                Text(session.roleLabel, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Divider(color: scheme.outlineVariant),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.92,
              ),
              itemCount: nav.length,
              itemBuilder: (context, i) {
                final color = AppColors.chart[i % AppColors.chart.length];
                final active = i == selected;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onTap(i),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 11),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: active ? 0.16 : 0.075),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: color.withValues(alpha: active ? 0.48 : 0.12), width: active ? 1.4 : 1),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                          child: Icon(iconFor(nav[i]['icon'] as String?), color: color, size: 21),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr(nav[i]['label'] as String),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, height: 1.15, fontWeight: active ? FontWeight.w700 : FontWeight.w600, color: scheme.onSurface),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            decoration: BoxDecoration(color: scheme.surfaceContainerLow, border: Border(top: BorderSide(color: scheme.outlineVariant))),
            child: Row(children: [
              _Avatar(session: session, radius: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(session.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                Text(session.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
              ])),
              IconButton(tooltip: tr('Sign out'), onPressed: onLogout, icon: Icon(Icons.logout_rounded, color: scheme.error, size: 20)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Slim white top bar: page title • date • notifications • user menu.
class _TopBar extends StatelessWidget {
  final String title;
  final int unread;
  final UserSession session;
  final Future<void> Function() onLogout;
  const _TopBar({required this.title, required this.unread, required this.session, required this.onLogout});

  Widget actionsPadding({required Widget child}) => Padding(padding: const EdgeInsets.only(right: 6), child: child);

  Widget bellAction(BuildContext context) => IconButton(
        tooltip: 'Notifications',
        onPressed: () => context.go('/notifications'),
        icon: Badge(
          isLabelVisible: unread > 0 && AppSettings.instance.showNotifBadge,
          label: Text(tr('$unread')),
          child: const Icon(Icons.notifications_outlined),
        ),
      );

  /// User menu. [compact] (mobile app bar) shows only the avatar so the page
  /// title gets the full width — name & role still appear inside the menu.
  Widget userAction(BuildContext context, {bool compact = false}) => Padding(
        padding: const EdgeInsets.only(right: 12, left: 2),
        child: PopupMenuButton<String>(
          tooltip: session.name,
          position: PopupMenuPosition.under,
          onSelected: (v) async {
            if (v == 'logout') await onLogout();
            if (v == 'refresh') {
              await context.read<AuthController>().refreshSession();
              if (context.mounted) showOk(context, 'Permissions refreshed.');
            }
          },
          itemBuilder: (c) => [
            PopupMenuItem(enabled: false, child: _UserHeader(session: session)),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'refresh', child: ListTile(leading: const Icon(Icons.sync_rounded, size: 20), title: Text(tr('Refresh permissions')), dense: true, contentPadding: EdgeInsets.zero)),
            PopupMenuItem(value: 'logout', child: ListTile(leading: const Icon(Icons.logout_rounded, size: 20), title: Text(tr('Sign out')), dense: true, contentPadding: EdgeInsets.zero)),
          ],
          child: compact
              ? _Avatar(session: session, radius: 16)
              : Row(children: [
                  _Avatar(session: session, radius: 15),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(session.name, style: TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface, height: 1.15)),
                    Text(session.roleLabel, style: const TextStyle(fontSize: 10.5, color: Color(0xFF5C6B7A), height: 1.2)),
                  ]),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: Color(0xFF5C6B7A)),
                ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(color: theme.shadowColor.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.only(left: 24),
      child: Row(children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(gradient: AppBrand.gradient, borderRadius: BorderRadius.circular(8)),
        ),
        const SizedBox(width: 11),
        Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: theme.colorScheme.onSurface)),
        const Spacer(),
        Icon(Icons.calendar_today_outlined, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(fmtDateWithDay(todayYmd()),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(width: 14),
        Container(width: 1, height: 22, color: Theme.of(context).colorScheme.outlineVariant),
        const SizedBox(width: 6),
        bellAction(context),
        userAction(context),
      ]),
    );
  }
}

/// 238px dark navigation sidebar with grouped modules.
class _Sidebar extends StatelessWidget {
  final List nav;
  final int selected;
  final UserSession session;
  final void Function(int) onTap;
  final Future<void> Function() onLogout;
  const _Sidebar({required this.nav, required this.selected, required this.session, required this.onTap, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    // group module entries, preserving server order
    final groups = <String, List<int>>{};
    for (var i = 0; i < nav.length; i++) {
      groups.putIfAbsent(nav[i]['group'] as String? ?? 'Menu', () => []).add(i);
    }

    return Container(
      width: 252,
      decoration: const BoxDecoration(gradient: Shell.gradient),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // brand
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Shell.border))),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))],
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
            ),
            const SizedBox(width: 11),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('FlavorFlow ERP', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.white, height: 1.15, letterSpacing: -0.1)),
              Text('MANUFACTURING SUITE', style: TextStyle(fontSize: 8.5, color: Shell.groupLabel, letterSpacing: 1.6, fontWeight: FontWeight.w600, height: 1.4)),
            ]),
          ]),
        ),
        // modules
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: [
            for (final g in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 5),
                child: Text(tr(g.key).toUpperCase(),
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Shell.groupLabel, letterSpacing: 1.5)),
              ),
              for (final i in g.value)
                _NavTile(
                  icon: iconFor(nav[i]['icon'] as String?),
                  label: tr(nav[i]['label'] as String),
                  selected: i == selected,
                  onTap: () => onTap(i),
                ),
            ],
          ]),
        ),
        // user footer
        Container(
          decoration: const BoxDecoration(
            color: Shell.bgDeep,
            border: Border(top: BorderSide(color: Shell.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            _Avatar(session: session, radius: 15),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(session.name, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.3, fontWeight: FontWeight.w600, color: Colors.white, height: 1.2)),
                Text(session.roleLabel, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Shell.groupLabel, height: 1.3)),
              ]),
            ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: onLogout,
              icon: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFF9FB3C4)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _NavTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavTile({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1.5),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 40,
            decoration: BoxDecoration(
              color: active ? null : (_hover ? Shell.itemHover : Colors.transparent),
              gradient: active
                  ? const LinearGradient(colors: [Color(0xFF1B5DA0), Color(0xFF137A70)])
                  : null,
              borderRadius: BorderRadius.circular(10),
              boxShadow: active
                  ? const [BoxShadow(color: Color(0x2816B878), blurRadius: 12, offset: Offset(0, 3))]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Icon(widget.icon, size: 19, color: active ? Colors.white : Shell.item),
              const SizedBox(width: 12),
              Expanded(
                child: Text(widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.8,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active ? Colors.white : Shell.item,
                    )),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final UserSession session;
  final double radius;
  const _Avatar({required this.session, this.radius = 15});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: hexColor(session.roleColor),
      child: Text(
        session.name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join(),
        style: TextStyle(color: Colors.white, fontSize: radius * 0.78, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _UserHeader extends StatelessWidget {
  final UserSession session;
  const _UserHeader({required this.session});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _Avatar(session: session, radius: 19),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(session.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(session.email, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: hexColor(session.roleColor).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: hexColor(session.roleColor).withValues(alpha: 0.35)),
            ),
            child: Text(session.roleLabel.toUpperCase(),
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: hexColor(session.roleColor))),
          ),
        ]),
      ),
    ]);
  }
}

/// Super Admin: edit the company identity printed on all exported PDFs
/// (packing slips, stock reports, registers). Makes the app universal —
/// any manufacturing company can put its own name, address and GST/tax line.
class CompanyProfileDialog extends StatefulWidget {
  const CompanyProfileDialog({super.key});
  @override
  State<CompanyProfileDialog> createState() => _CompanyProfileDialogState();
}

class _CompanyProfileDialogState extends State<CompanyProfileDialog> {
  late final TextEditingController name;
  late final TextEditingController address;
  late final TextEditingController tax;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final p = CompanyProfile.current;
    name = TextEditingController(text: p.name);
    address = TextEditingController(text: p.address);
    tax = TextEditingController(text: p.taxLine);
  }

  @override
  void dispose() { name.dispose(); address.dispose(); tax.dispose(); super.dispose(); }

  String _industryLabel() {
    final id = CompanyProfile.current.industry;
    final row = CompanyProfile.industries.firstWhere((r) => r[0] == id, orElse: () => CompanyProfile.industries.last);
    return row[1];
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      showErr(context, 'Company name is required.');
      return;
    }
    setState(() => saving = true);
    final p = CompanyProfile.current; // industry & unit labels stay as set at first-run
    await CompanyProfile.save(
      CompanyProfile(
        name: name.text.trim(),
        address: address.text.trim(),
        taxLine: tax.text.trim(),
        industry: p.industry,
        cartonLabel: p.cartonLabel,
        cartonShort: p.cartonShort,
        trayLabel: p.trayLabel,
        pieceLabel: p.pieceLabel,
      ),
      context.read<AuthController>().api,
    );
    if (!mounted) return;
    Navigator.pop(context);
    showOk(context, 'Company details saved — all exported PDFs will use them.');
  }

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    return AlertDialog(
      title: Text(tr('Company details')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Printed at the top of every exported PDF (packing slips, stock reports, registers).',
                style: TextStyle(fontSize: 12.5, color: sub)),
            const SizedBox(height: 14),
            TextField(controller: name, decoration: InputDecoration(labelText: tr('Company name *'), hintText: 'e.g. G.D. Foods Mfg (I) Pvt. Ltd.')),
            const SizedBox(height: 12),
            TextField(controller: address, decoration: InputDecoration(labelText: tr('Address'), hintText: 'e.g. Khadoor Sahib, Punjab')),
            const SizedBox(height: 12),
            TextField(controller: tax, decoration: InputDecoration(labelText: tr('GSTIN / tax & contact line'), hintText: 'e.g. GSTIN 03XXXXX · info@company.in')),
            const SizedBox(height: 18),
            Text('INDUSTRY & UNIT NAMES', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: sub)),
            const SizedBox(height: 4),
            Text('Set once during first-run setup — shown here for reference.',
                style: TextStyle(fontSize: 11.5, color: sub)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.factory_outlined, size: 17, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(_industryLabel(), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                Text(
                  '${CompanyProfile.current.cartonLabel} (${CompanyProfile.current.cartonShort}) · ${CompanyProfile.current.trayLabel} · ${CompanyProfile.current.pieceLabel}',
                  style: TextStyle(fontSize: 12, color: sub),
                ),
              ]),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: saving ? null : _save, child: Text(saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}

/// Language picker — English · ਪੰਜਾਬੀ · हिन्दी. Per-device choice, applies
/// instantly across the whole app (no restart needed).
class LanguageDialog extends StatelessWidget {
  const LanguageDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<L10n>();
    return AlertDialog(
      title: Text('${tr('Language')} · ਭਾਸ਼ਾ · भाषा'),
      content: DropdownButtonFormField<String>(
        initialValue: l10n.code,
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Language / ਭਾਸ਼ਾ / भाषा')),
        items: [
          for (final lang in L10n.languages)
            DropdownMenuItem(value: lang[0], child: Text(lang[1])),
        ],
        onChanged: (v) async {
          await L10n.instance.set(v ?? 'en');
          if (context.mounted) Navigator.pop(context);
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
      ],
    );
  }
}
