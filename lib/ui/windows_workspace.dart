import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../core/offline_queue.dart';
import '../core/theme.dart';
import '../state/auth.dart';
import 'widgets.dart';

/// Classic, keyboard-friendly desktop frame inspired by traditional ERP
/// workspaces. It deliberately uses FlavorFlow branding and permissions/routes
/// rather than copying another product's artwork or business data.
class WindowsWorkspace extends StatefulWidget {
  final Widget page;
  final Widget syncBanner;
  final List<Map<String, dynamic>> nav;
  final int selectedIndex;
  final String title;
  final int unread;
  final UserSession session;
  final ValueChanged<int> onNavigate;
  final VoidCallback onMainMenu;
  final Future<void> Function() onLogout;
  final Future<void> Function() onRefreshPage;
  final Future<void> Function() onRefreshPermissions;

  const WindowsWorkspace({
    super.key,
    required this.page,
    required this.syncBanner,
    required this.nav,
    required this.selectedIndex,
    required this.title,
    required this.unread,
    required this.session,
    required this.onNavigate,
    required this.onMainMenu,
    required this.onLogout,
    required this.onRefreshPage,
    required this.onRefreshPermissions,
  });

  @override
  State<WindowsWorkspace> createState() => _WindowsWorkspaceState();
}

class _WindowsWorkspaceState extends State<WindowsWorkspace> {
  bool _modulesVisible = true;
  final TextEditingController _moduleSearch = TextEditingController();
  final FocusNode _moduleSearchFocus = FocusNode();
  String _moduleQuery = '';

  @override
  void dispose() {
    _moduleSearch.dispose();
    _moduleSearchFocus.dispose();
    super.dispose();
  }

  static const _titleBlue = Color(0xFF214E6B);
  static const _menuSurface = Color(0xFFF7F9FB);
  static const _toolbarSurface = Color(0xFFEDF2F6);
  static const _moduleSurface = Color(0xFFF7F9FC);
  static const _workspaceSurface = Color(0xFFE7ECF1);
  static const _line = Color(0xFFC7D1DB);
  static const _ink = Color(0xFF26394A);
  static const _muted = Color(0xFF627588);

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): const _MainMenuIntent(),
        const SingleActivator(LogicalKeyboardKey.keyM, control: true): const _ToggleModulesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): const _FindModuleIntent(),
        const SingleActivator(LogicalKeyboardKey.f5): const _RefreshPageIntent(),
        const SingleActivator(LogicalKeyboardKey.f1): const _AboutIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _MainMenuIntent: CallbackAction<_MainMenuIntent>(onInvoke: (_) {
            widget.onMainMenu();
            return null;
          }),
          _ToggleModulesIntent: CallbackAction<_ToggleModulesIntent>(onInvoke: (_) {
            setState(() => _modulesVisible = !_modulesVisible);
            return null;
          }),
          _FindModuleIntent: CallbackAction<_FindModuleIntent>(onInvoke: (_) {
            if (!_modulesVisible) setState(() => _modulesVisible = true);
            _moduleSearchFocus.requestFocus();
            return null;
          }),
          _RefreshPageIntent: CallbackAction<_RefreshPageIntent>(onInvoke: (_) {
            widget.onRefreshPage();
            return null;
          }),
          _AboutIntent: CallbackAction<_AboutIntent>(onInvoke: (_) {
            _showAbout(context);
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: _workspaceSurface,
            body: Column(
              children: [
                _titleBar(context),
                _menuBar(context),
                _toolBar(context),
                Expanded(child: _workArea(context)),
                _statusBar(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleBar(BuildContext context) {
    return Container(
      height: 34,
      color: _titleBlue,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Row(
        children: [
          Container(
            width: 23,
            height: 23,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
            clipBehavior: Clip.antiAlias,
            child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
          ),
          const SizedBox(width: 8),
          const Text(
            'FlavorFlow ERP',
            style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.15),
          ),
          const SizedBox(width: 9),
          const Text('Manufacturing workspace', style: TextStyle(color: Color(0xFFD3E2EE), fontSize: 11.5)),
          const Spacer(),
          Text(widget.session.roleLabel, style: const TextStyle(color: Color(0xFFE2ECF4), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _menuBar(BuildContext context) {
    final modules = <Widget>[
      for (var i = 0; i < widget.nav.length; i++)
        MenuItemButton(
          onPressed: () => widget.onNavigate(i),
          leadingIcon: Icon(iconFor(widget.nav[i]['icon'] as String?), size: 17),
          child: Text(tr(widget.nav[i]['label'] as String? ?? 'Module')),
        ),
    ];
    final tools = <Widget>[
      if (widget.nav.any((item) => item['path'] == '/stock')) _routeItem('Stock Ledger', Icons.history_rounded, '/stock'),
      if (widget.nav.any((item) => item['path'] == '/loss')) _routeItem('Packing Loss %', Icons.percent_rounded, '/loss'),
      if (widget.nav.any((item) => item['path'] == '/reports')) _routeItem('Reports', Icons.bar_chart_rounded, '/reports'),
      if (widget.nav.any((item) => item['path'] == '/productivity')) _routeItem('Productivity & Labour', Icons.analytics_outlined, '/productivity'),
    ];
    if (tools.isEmpty) {
      tools.add(MenuItemButton(onPressed: null, child: Text(tr('No tools available for this role'))));
    }

    return Container(
      height: 31,
      decoration: const BoxDecoration(
        color: _menuSurface,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          _ClassicMenuButton(
            label: 'File',
            children: [
              _menuItem('Main Menu', Icons.home_outlined, widget.onMainMenu, shortcut: 'Ctrl+0'),
              const MenuDivider(),
              _menuItem('Sign out', Icons.logout_rounded, () => widget.onLogout()),
            ],
          ),
          _ClassicMenuButton(
            label: 'Edit',
            children: [
              _routeItem('Settings', Icons.settings_outlined, '/settings'),
              _menuItem('Refresh access', Icons.manage_accounts_outlined, () => widget.onRefreshPermissions()),
            ],
          ),
          _ClassicMenuButton(
            label: 'View',
            children: [
              _menuItem(_modulesVisible ? 'Hide Modules panel' : 'Show Modules panel', Icons.view_sidebar_outlined, () {
                setState(() => _modulesVisible = !_modulesVisible);
              }, shortcut: 'Ctrl+M'),
            ],
          ),
          _ClassicMenuButton(
            label: 'Data',
            children: [
              _menuItem('Refresh current screen', Icons.refresh_rounded, () => widget.onRefreshPage(), shortcut: 'F5'),
            ],
          ),
          _ClassicMenuButton(
            label: 'Go To',
            children: [
              _menuItem('Main Menu', Icons.home_outlined, widget.onMainMenu, shortcut: 'Ctrl+0'),
              _routeItem('Notifications', Icons.notifications_outlined, '/notifications'),
              _routeItem('Offline entries', Icons.sync_problem_outlined, '/sync'),
            ],
          ),
          _ClassicMenuButton(label: 'Modules', children: modules),
          _ClassicMenuButton(label: 'Tools', children: tools),
          _ClassicMenuButton(
            label: 'Window',
            children: [
              MenuItemButton(
                onPressed: null,
                leadingIcon: const Icon(Icons.dashboard_outlined, size: 17),
                child: Text('Current screen: ${tr(widget.title)}'),
              ),
              _menuItem('Return to Main Menu', Icons.home_outlined, widget.onMainMenu),
            ],
          ),
          _ClassicMenuButton(
            label: 'Help',
            children: [
              _menuItem('Keyboard shortcuts', Icons.keyboard_outlined, () => _showShortcuts(context)),
              _menuItem('About FlavorFlow ERP', Icons.info_outline_rounded, () => _showAbout(context)),
            ],
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text('ERP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: _muted.withValues(alpha: 0.8))),
          ),
        ],
      ),
    );
  }

  MenuItemButton _menuItem(String label, IconData icon, VoidCallback onPressed, {String? shortcut}) {
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: Icon(icon, size: 17),
      shortcut: shortcut == null ? null : Text(shortcut, style: const TextStyle(fontSize: 11, color: _muted)),
      child: Text(tr(label)),
    );
  }

  MenuItemButton _routeItem(String label, IconData icon, String path) {
    final index = widget.nav.indexWhere((item) => item['path'] == path);
    return _menuItem(label, icon, () {
      if (index != -1) {
        widget.onNavigate(index);
      } else {
        context.go(path);
      }
    });
  }

  Widget _toolBar(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1240;
    return Container(
      height: 45,
      decoration: const BoxDecoration(
        color: _toolbarSurface,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _ToolButton(icon: Icons.home_outlined, label: 'Main Menu', showLabel: !compact, onPressed: widget.onMainMenu),
          _ToolButton(icon: Icons.refresh_rounded, label: 'Refresh', showLabel: !compact, onPressed: () => widget.onRefreshPage()),
          _ToolButton(
            icon: _modulesVisible ? Icons.view_sidebar_outlined : Icons.view_sidebar,
            label: _modulesVisible ? 'Hide Modules' : 'Show Modules',
            showLabel: !compact,
            onPressed: () => setState(() => _modulesVisible = !_modulesVisible),
          ),
          const VerticalDivider(width: 15, indent: 8, endIndent: 8, color: _line),
          SizedBox(
            height: 31,
            width: compact ? 175 : 245,
            child: TextField(
              controller: _moduleSearch,
              focusNode: _moduleSearchFocus,
              onChanged: (value) => setState(() => _moduleQuery = value),
              onTap: () { if (!_modulesVisible) setState(() => _modulesVisible = true); },
              style: const TextStyle(fontSize: 11.5),
              decoration: InputDecoration(
                hintText: tr('Find a module…'),
                prefixIcon: const Icon(Icons.search_rounded, size: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 31),
                suffixIconConstraints: const BoxConstraints(minWidth: 26),
                suffixIcon: _moduleQuery.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.only(right: 7),
                        child: Center(child: Text('Ctrl+F', style: TextStyle(fontSize: 9, color: Color(0xFF8B98A5)))),
                      )
                    : IconButton(
                        tooltip: tr('Clear search'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () { _moduleSearch.clear(); setState(() => _moduleQuery = ''); },
                        icon: const Icon(Icons.close_rounded, size: 14),
                      ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: const BorderSide(color: _line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: const BorderSide(color: _line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: const BorderSide(color: AppBrand.blue)),
              ),
            ),
          ),
          const Spacer(),
          if (!compact) ...[
            Icon(Icons.calendar_today_outlined, size: 13, color: _muted),
            const SizedBox(width: 6),
            Text(fmtDateWithDay(todayYmd()), style: const TextStyle(fontSize: 11, color: _ink)),
            const SizedBox(width: 9),
            const VerticalDivider(width: 12, indent: 9, endIndent: 9, color: _line),
          ],
          IconButton(
            tooltip: tr('Notifications'),
            visualDensity: VisualDensity.compact,
            onPressed: () => context.go('/notifications'),
            icon: Badge(
              isLabelVisible: widget.unread > 0,
              label: Text(tr('${widget.unread}')),
              child: const Icon(Icons.notifications_none_rounded, size: 19, color: _ink),
            ),
          ),
          _userMenu(context, compact: compact),
        ],
      ),
    );
  }

  Widget _userMenu(BuildContext context, {required bool compact}) {
    final initials = widget.session.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: null,
          leadingIcon: CircleAvatar(
            radius: 14,
            backgroundColor: AppBrand.blue,
            child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(widget.session.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            Text(widget.session.roleLabel, style: const TextStyle(fontSize: 10, color: _muted)),
          ]),
        ),
        const MenuDivider(),
        _menuItem('Refresh permissions', Icons.sync_rounded, () => widget.onRefreshPermissions()),
        _menuItem('Settings', Icons.settings_outlined, () {
          final index = widget.nav.indexWhere((item) => item['path'] == '/settings');
          if (index != -1) widget.onNavigate(index); else context.go('/settings');
        }),
        _menuItem('Sign out', Icons.logout_rounded, () => widget.onLogout()),
      ],
      builder: (context, controller, child) => TextButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: CircleAvatar(
          radius: 12,
          backgroundColor: AppBrand.blue,
          child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
        ),
        label: compact
            ? const SizedBox.shrink()
            : Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 125),
                  child: Text(widget.session.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: _ink)),
                ),
                const Icon(Icons.arrow_drop_down, size: 17, color: _muted),
              ]),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 32)),
      ),
    );
  }

  Widget _workArea(BuildContext context) {
    return Row(
      children: [
        if (_modulesVisible) ...[
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 1240 ? 220 : 248,
            child: _WindowsModulePane(
              nav: widget.nav,
              selectedIndex: widget.selectedIndex,
              query: _moduleQuery,
              onClearSearch: () { _moduleSearch.clear(); setState(() => _moduleQuery = ''); },
              onNavigate: widget.onNavigate,
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1, color: _line),
        ],
        Expanded(
          child: Column(
            children: [
              _windowHeader(context),
              widget.syncBanner,
              Expanded(
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: RepaintBoundary(child: widget.page),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _windowHeader(BuildContext context) {
    final item = widget.nav.isEmpty ? null : widget.nav[widget.selectedIndex.clamp(0, widget.nav.length - 1).toInt()];
    final icon = iconFor(item?['icon'] as String?);
    final currentLabel = item?['label'] as String?;
    final group = currentLabel != null && tr(currentLabel) == tr(widget.title) ? item?['group'] as String? : null;
    return Container(
      height: 34,
      decoration: const BoxDecoration(color: Color(0xFFE2E9EF), border: Border(bottom: BorderSide(color: _line))),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Icon(icon, size: 17, color: _titleBlue),
        const SizedBox(width: 8),
        Text('Main Menu', style: const TextStyle(fontSize: 11, color: _muted)),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 7), child: Icon(Icons.chevron_right, size: 14, color: _muted)),
        if (group != null) ...[
          Text(tr(group), style: const TextStyle(fontSize: 11, color: _muted)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 7), child: Icon(Icons.chevron_right, size: 14, color: _muted)),
        ],
        Expanded(child: Text(tr(widget.title), style: const TextStyle(fontSize: 12, color: _ink, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
        IconButton(
          tooltip: tr('Return to Main Menu'),
          visualDensity: VisualDensity.compact,
          onPressed: widget.onMainMenu,
          icon: const Icon(Icons.close_rounded, size: 16, color: _muted),
        ),
      ]),
    );
  }

  Widget _statusBar(BuildContext context) {
    return ListenableBuilder(
      listenable: OfflineQueue.instance,
      builder: (context, _) {
        final queue = OfflineQueue.instance;
        final online = queue.online;
        final statusColor = online ? const Color(0xFF218050) : const Color(0xFFB46A08);
        return Container(
          height: 25,
          decoration: const BoxDecoration(color: Color(0xFFF3F6F8), border: Border(top: BorderSide(color: _line))),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            Icon(online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, size: 14, color: statusColor),
            const SizedBox(width: 5),
            Text(online ? tr('Online') : tr('Offline'), style: TextStyle(fontSize: 10.5, color: statusColor, fontWeight: FontWeight.w600)),
            if (queue.pendingCount > 0) ...[
              const SizedBox(width: 9),
              Text('${queue.pendingCount} ${tr('pending')}', style: const TextStyle(fontSize: 10.5, color: _muted)),
            ],
            const Spacer(),
            Flexible(
              child: Text('${widget.session.name}  ·  ${widget.session.roleLabel}', style: const TextStyle(fontSize: 10.5, color: _muted), overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
            const SizedBox(width: 12),
            Text(fmtDateWithDay(todayYmd()), style: const TextStyle(fontSize: 10.5, color: _muted)),
          ]),
        );
      },
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'FlavorFlow ERP',
      applicationIcon: Image.asset('assets/icon/app_icon.png', width: 42, height: 42),
      applicationLegalese: 'Manufacturing operations workspace',
    );
  }

  void _showShortcuts(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Keyboard shortcuts')),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShortcutRow(keys: 'Ctrl+0', action: 'Main Menu / Dashboard'),
            _ShortcutRow(keys: 'Ctrl+M', action: 'Show or hide Modules'),
            _ShortcutRow(keys: 'Ctrl+F', action: 'Find a module'),
            _ShortcutRow(keys: 'F5', action: 'Refresh current screen'),
            _ShortcutRow(keys: 'F1', action: 'About FlavorFlow ERP'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close')))],
      ),
    );
  }
}

class _ClassicMenuButton extends StatefulWidget {
  final String label;
  final List<Widget> children;
  const _ClassicMenuButton({required this.label, required this.children});

  @override
  State<_ClassicMenuButton> createState() => _ClassicMenuButtonState();
}

class _ClassicMenuButtonState extends State<_ClassicMenuButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: widget.children,
      builder: (context, controller, child) => MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Material(
          color: controller.isOpen || _hovering ? const Color(0xFFE1EAF2) : Colors.transparent,
          child: InkWell(
            onTap: () => controller.isOpen ? controller.close() : controller.open(),
            child: SizedBox(
              height: 30,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: Center(child: Text(tr(widget.label), style: const TextStyle(fontSize: 11.5, color: _WindowsWorkspaceState._ink))),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool showLabel;
  final VoidCallback onPressed;
  const _ToolButton({required this.icon, required this.label, required this.showLabel, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr(label),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: _WindowsWorkspaceState._ink),
        label: showLabel ? Text(tr(label), style: const TextStyle(fontSize: 10.5, color: _WindowsWorkspaceState._ink)) : const SizedBox.shrink(),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          foregroundColor: _WindowsWorkspaceState._ink,
        ),
      ),
    );
  }
}

class _WindowsModulePane extends StatefulWidget {
  final List<Map<String, dynamic>> nav;
  final int selectedIndex;
  final String query;
  final VoidCallback onClearSearch;
  final ValueChanged<int> onNavigate;
  const _WindowsModulePane({required this.nav, required this.selectedIndex, required this.query, required this.onClearSearch, required this.onNavigate});

  @override
  State<_WindowsModulePane> createState() => _WindowsModulePaneState();
}

class _WindowsModulePaneState extends State<_WindowsModulePane> {
  final Map<String, bool> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<int>>{};
    for (var i = 0; i < widget.nav.length; i++) {
      final group = widget.nav[i]['group'] as String? ?? 'Modules';
      groups.putIfAbsent(group, () => []).add(i);
    }
    final needle = widget.query.trim().toLowerCase();

    return Container(
      color: _WindowsWorkspaceState._moduleSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _WindowsWorkspaceState._line))),
            child: Row(children: [
              const Icon(Icons.account_tree_outlined, size: 16, color: _WindowsWorkspaceState._titleBlue),
              const SizedBox(width: 7),
              Text(tr('Modules'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _WindowsWorkspaceState._ink)),
              const Spacer(),
              if (widget.query.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Clear search'),
                  onPressed: widget.onClearSearch,
                  icon: const Icon(Icons.close_rounded, size: 14),
                )
              else
                Text('${widget.nav.length}', style: const TextStyle(fontSize: 10, color: _WindowsWorkspaceState._muted)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(5, 1, 5, 8),
              children: [
                for (final entry in groups.entries) ...[
                  if (entry.value.any((i) => needle.isEmpty || tr(widget.nav[i]['label'] as String).toLowerCase().contains(needle)))
                    _groupHeader(entry.key, entry.value, needle),
                ],
                if (needle.isNotEmpty && !widget.nav.any((item) => tr(item['label'] as String).toLowerCase().contains(needle)))
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(tr('No modules found'), style: const TextStyle(fontSize: 11, color: _WindowsWorkspaceState._muted)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupHeader(String group, List<int> indices, String needle) {
    final filtered = indices.where((i) => needle.isEmpty || tr(widget.nav[i]['label'] as String).toLowerCase().contains(needle)).toList();
    if (filtered.isEmpty) return const SizedBox.shrink();
    final expanded = needle.isNotEmpty || (_expanded[group] ?? true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: needle.isEmpty ? () => setState(() => _expanded[group] = !expanded) : null,
          child: SizedBox(
            height: 27,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                Icon(expanded ? Icons.keyboard_arrow_down_rounded : Icons.chevron_right_rounded, size: 15, color: _WindowsWorkspaceState._muted),
                const SizedBox(width: 2),
                Expanded(child: Text(tr(group).toUpperCase(), style: const TextStyle(fontSize: 9.5, color: _WindowsWorkspaceState._muted, fontWeight: FontWeight.w700, letterSpacing: 0.65))),
                Text('${filtered.length}', style: const TextStyle(fontSize: 9, color: _WindowsWorkspaceState._muted)),
              ]),
            ),
          ),
        ),
        if (expanded)
          for (final i in filtered) _moduleRow(i),
      ],
    );
  }

  Widget _moduleRow(int index) {
    final item = widget.nav[index];
    final active = index == widget.selectedIndex;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Material(
        color: active ? const Color(0xFFDCEAF7) : Colors.transparent,
        child: InkWell(
          onTap: () => widget.onNavigate(index),
          child: SizedBox(
            height: 31,
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 3,
                height: 31,
                color: active ? AppBrand.blue : Colors.transparent,
              ),
              const SizedBox(width: 8),
              Icon(iconFor(item['icon'] as String?), size: 16, color: active ? AppBrand.blueDeep : _WindowsWorkspaceState._muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(item['label'] as String),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: active ? _WindowsWorkspaceState._ink : const Color(0xFF40566A), fontWeight: active ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              if (active) const Padding(padding: EdgeInsets.only(right: 7), child: Icon(Icons.chevron_right_rounded, size: 15, color: AppBrand.blue)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final String keys;
  final String action;
  const _ShortcutRow({required this.keys, required this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 78, child: Text(keys, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700))),
        const SizedBox(width: 10),
        Text(tr(action)),
      ]),
    );
  }
}

class _MainMenuIntent extends Intent { const _MainMenuIntent(); }
class _ToggleModulesIntent extends Intent { const _ToggleModulesIntent(); }
class _FindModuleIntent extends Intent { const _FindModuleIntent(); }
class _RefreshPageIntent extends Intent { const _RefreshPageIntent(); }
class _AboutIntent extends Intent { const _AboutIntent(); }
