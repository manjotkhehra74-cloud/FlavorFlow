import 'package:flutter/material.dart';

import '../core/i18n.dart';

/// A module view in the Windows work area. Mobile continues to use the
/// familiar horizontal tabs; Windows gets a compact vertical view selector
/// and an independent document workspace.
class WindowsModuleTab {
  final String label;
  final IconData icon;
  const WindowsModuleTab(this.label, this.icon);
}

class WindowsModuleWorkspace extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<WindowsModuleTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget content;
  final Widget? commandBar;
  final Widget? actions;

  const WindowsModuleWorkspace({
    super.key,
    required this.title,
    required this.subtitle,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
    required this.content,
    this.commandBar,
    this.actions,
  });

  static const Color _canvas = Color(0xFFE9EEF3);
  static const Color _nav = Color(0xFFF2F5F8);
  static const Color _line = Color(0xFFC7D1DB);
  static const Color _ink = Color(0xFF26394A);
  static const Color _muted = Color(0xFF627588);
  static const Color _selected = Color(0xFFDCEAF7);
  static const Color _accent = Color(0xFF214E6B);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 820;
      final navWidth = compact ? 58.0 : 190.0;
      final safeIndex = tabs.isEmpty ? 0 : selectedIndex.clamp(0, tabs.length - 1).toInt();
      return ColoredBox(
        color: _canvas,
        child: Row(children: [
          SizedBox(
            width: navWidth,
            child: ColoredBox(
              color: _nav,
              child: Column(children: [
                SizedBox(
                  height: 58,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 11, vertical: 8),
                    child: compact
                        ? const Center(child: Icon(Icons.view_list_outlined, size: 20, color: _accent))
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(tr('VIEWS'), style: const TextStyle(color: _muted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.3)),
                            const SizedBox(height: 2),
                            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 11, fontWeight: FontWeight.w700)),
                          ]),
                  ),
                ),
                const Divider(height: 1, color: _line),
                Expanded(
                  child: ListView(padding: const EdgeInsets.symmetric(vertical: 7), children: [
                    for (var i = 0; i < tabs.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        child: Tooltip(
                          message: tr(tabs[i].label),
                          waitDuration: const Duration(milliseconds: 450),
                          child: Material(
                            color: i == safeIndex ? _selected : Colors.transparent,
                            child: InkWell(
                              onTap: () => onSelect(i),
                              child: Container(
                                height: 36,
                                padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(color: i == safeIndex ? const Color(0xFF0A6ED1) : Colors.transparent, width: 3),
                                    bottom: BorderSide(color: i == safeIndex ? const Color(0xFFB9CDE0) : Colors.transparent),
                                  ),
                                ),
                                child: compact
                                    ? Center(child: Icon(tabs[i].icon, size: 18, color: i == safeIndex ? _accent : _muted))
                                    : Row(children: [
                                        Icon(tabs[i].icon, size: 16, color: i == safeIndex ? _accent : _muted),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(tr(tabs[i].label), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: i == safeIndex ? _ink : _muted, fontSize: 11, fontWeight: i == safeIndex ? FontWeight.w700 : FontWeight.w500))),
                                        if (i == safeIndex) const Icon(Icons.chevron_right_rounded, size: 15, color: _accent),
                                      ]),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1, color: _line),
          Expanded(
            child: Column(children: [
              Container(
                height: 42,
                color: const Color(0xFFE2E9EF),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  if (tabs.isNotEmpty) Icon(tabs[safeIndex].icon, size: 17, color: _accent),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(tr(title), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w700)),
                    Text(tr(subtitle), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 9.5)),
                  ])),
                  if (actions != null) actions!,
                ]),
              ),
              if (commandBar != null) commandBar!,
              Expanded(child: ColoredBox(color: _canvas, child: content)),
            ]),
          ),
        ]),
      );
    });
  }
}

/// A document-style Windows page for single-screen registers and worklists.
/// The title/command area stays fixed while the table or form content scrolls.
class WindowsDocumentWorkspace extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget content;
  final Widget? commandBar;
  final Widget? actions;

  const WindowsDocumentWorkspace({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.content,
    this.commandBar,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE9EEF3),
      child: Column(children: [
        Container(
          height: 44,
          color: const Color(0xFFE2E9EF),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Icon(icon, size: 17, color: const Color(0xFF214E6B)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(tr(title), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF26394A), fontSize: 12, fontWeight: FontWeight.w700)),
              Text(tr(subtitle), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF627588), fontSize: 9.5)),
            ])),
            if (actions != null) actions!,
          ]),
        ),
        if (commandBar != null) commandBar!,
        Expanded(child: ColoredBox(color: const Color(0xFFE9EEF3), child: content)),
      ]),
    );
  }
}

/// Dense command strip used by native Windows work screens. Each page supplies
/// its own permitted actions; the mobile UI keeps its existing controls.
class WindowsCommandStrip extends StatelessWidget {
  final List<Widget> children;
  const WindowsCommandStrip({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFEDF2F6), border: Border(bottom: BorderSide(color: Color(0xFFC7D1DB)))),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Wrap(spacing: 6, runSpacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: children),
    );
  }
}
