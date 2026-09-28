import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/hrmate.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import '../billing/subscription_banner.dart';
import '../hrmate/hrmate_widgets.dart';

/// Server-driven role dashboard: the API decides which KPIs, charts,
/// tables, alerts and quick actions each profile sees.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

num? _todayTotal(dynamic raw, String listKey, String dateKey, String valueKey, {String? fallbackKey}) {
  if (raw is! Map || raw[listKey] is! List) return null;
  final today = todayYmd();
  num total = 0;
  for (final row in (raw[listKey] as List)) {
    if (row is! Map || !'${row[dateKey] ?? ''}'.startsWith(today)) continue;
    final value = row[valueKey] ?? (fallbackKey == null ? null : row[fallbackKey]);
    if (value is num) total += value;
    else total += num.tryParse('${value ?? 0}') ?? 0;
  }
  return total;
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final api = context.read<AuthController>().api;
    final dashboard = (await api.get('/dashboard') as Map).cast<String, dynamic>();

    // The dashboard endpoint is intentionally role/server driven. On older
    // servers it does not yet include today's production/dispatch roll-ups,
    // so enrich the same live response from the existing read-only endpoints.
    // A missing permission or legacy route is harmless — the UI keeps the
    // server KPI or an em dash instead of inventing a count.
    Future<dynamic> safeGet(String path) async {
      try {
        return await api.get(path);
      } catch (_) {
        return null;
      }
    }
    final extra = await Future.wait<dynamic>([
      safeGet('/production/batches'),
      safeGet('/dispatch'),
      safeGet('/inventory'),
    ]);
    final liveKpis = <Map<String, dynamic>>[];
    final production = _todayTotal(extra[0], 'batches', 'planned_date', 'produced_cb', fallbackKey: 'planned_cb');
    final dispatch = _todayTotal(extra[1], 'dispatches', 'dispatch_date', 'total_cartons');
    final inventory = extra[2] is Map ? (extra[2] as Map)['summary'] : null;
    if (production != null) liveKpis.add({'label': 'Production Today', 'value': production});
    if (dispatch != null) liveKpis.add({'label': 'Dispatch Today', 'value': dispatch});
    if (inventory is Map && inventory['low_count'] != null) {
      liveKpis.add({'label': 'Low Stock', 'value': inventory['low_count']});
    }
    return {...dashboard, '_liveKpis': liveKpis};
  }

  void _reload() {
    HrMate.instance.summary(force: true); // pull-to-refresh → fresh HRMate numbers too (no-op unless connected; never throws)
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final data = snap.data!;
        // Industry gating: drop server widgets that belong to hidden sections
        // (Loss % tile for a company that switched the sheet off, production
        // for trading-only profiles) and shortcuts/alerts pointing there.
        final widgets = [
          for (final w in (data['widgets'] as List).cast<Map<String, dynamic>>())
            if (CompanyProfile.sectionVisible((w['route'] as String?) ?? '/')) _gateWidget(w),
        ];
        final kpis = <Map<String, dynamic>>[
          for (final w in widgets.where((w) => w['type'] == 'kpi'))
            ...(w['items'] as List).cast<Map<String, dynamic>>(),
          ...((data['_liveKpis'] as List?) ?? const []).cast<Map<String, dynamic>>(),
        ];
        final alerts = _firstWidget(widgets, 'alerts');
        final actions = _firstWidget(widgets, 'actions');
        final coreKpis = _referenceKpis(kpis, alerts);
        final additionalKpis = _additionalKpis(kpis);
        final secondaryWidgets = widgets.where((w) {
          final type = w['type'];
          return type != 'kpi' && type != 'actions' && type != 'alerts';
        }).toList();
        // Keep the old dashboard's complete detail flow together in the new
        // shell: role table first, then production/dispatch charts, followed
        // by any other server-provided detail widgets.
        final detailWidgets = [
          ...secondaryWidgets.where((w) => w['type'] == 'table'),
          ...secondaryWidgets.where((w) => const {'line', 'bar', 'pie'}.contains(w['type'])),
          ...secondaryWidgets.where((w) => !const {'table', 'line', 'bar', 'pie'}.contains(w['type'])),
        ];
        final scheme = Theme.of(context).colorScheme;
        return Container(
          // Keep the new dashboard composition readable in both the light and
          // dark app themes. The previous fixed pale background made section
          // headings disappear when the user's selected theme was dark.
          color: scheme.surfaceContainerLow,
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
                14,
                MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
                28,
              ),
              children: [
                _DashboardHero(kpis: kpis),
                const SizedBox(height: 14),
                _DashboardKpiGrid(items: coreKpis),
                const SizedBox(height: 18),
                if (actions != null) _DashboardQuickActions(widget: actions),
                if (actions != null) const SizedBox(height: 18),
                _DashboardActivity(kpis: kpis),
                const SizedBox(height: 18),
                if (alerts != null) _buildWidget(alerts),
                if (alerts != null) const SizedBox(height: 18),
                if (additionalKpis.isNotEmpty) ...[
                  SectionCard(title: tr('Workspace snapshot'), child: _DashboardKpiGrid(items: additionalKpis)),
                  const SizedBox(height: 18),
                ],
                if (detailWidgets.isNotEmpty) ...[
                  Text('Dashboard details', style: TextStyle(color: scheme.onSurface, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  for (final w in detailWidgets) ...[
                    _buildWidget(w),
                    const SizedBox(height: 16),
                  ],
                ],
                const SubscriptionBanner(),
                // HRMate head-count (read-only bridge) — renders nothing when
                // HRMate is not connected on this device or is unreachable.
                const HrPresenceStrip(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Remove items that link into sections hidden for this industry.
  static Map<String, dynamic> _gateWidget(Map<String, dynamic> w) {
    final items = w['items'];
    if (items is! List) return w;
    return {
      ...w,
      'items': [
        for (final it in items)
          if (it is! Map ||
              (CompanyProfile.sectionVisible((it['route'] as String?) ?? '/') &&
                  (CompanyProfile.usesTrays || !U.isTrayLabel((it['label'] as String?) ?? '')))) it,
      ],
    };
  }

  Widget _buildWidget(Map<String, dynamic> w) {
    switch (w['type']) {
      case 'kpi': return _DashboardKpiGrid(items: (w['items'] as List).cast<Map<String, dynamic>>());
      case 'line': return SectionCard(title: U.ize(w['title'] as String), child: _Line(w));
      case 'bar': return SectionCard(title: U.ize(w['title'] as String), child: _Bar(w));
      case 'pie': return SectionCard(title: U.ize(w['title'] as String), child: _Pie(w));
      case 'alerts':
        final alertTitle = (w['title'] as String?)?.trim();
        return SectionCard(title: U.ize(alertTitle == null || alertTitle.isEmpty ? 'System Alerts' : alertTitle), child: _Alerts(w));
      case 'table':
        final route = w['route'] as String?;
        return SectionCard(
          title: U.ize(w['title'] as String),
          trailing: route == null
              ? null
              : TextButton.icon(
                  onPressed: () => context.go(route),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(tr('Open')),
                ),
          child: _ServerTable(w),
        );
      case 'actions': return SectionCard(title: U.ize(w['title'] as String), child: _Actions(w));
      default: return const SizedBox.shrink();
    }
  }
}

class _DashboardHero extends StatelessWidget {
  final List<Map<String, dynamic>> kpis;
  const _DashboardHero({required this.kpis});

  String _value(List<String> terms) {
    for (final term in terms) {
      for (final item in kpis) {
        final label = '${item['label'] ?? ''}'.toLowerCase();
        if (label.contains(term)) return item['money'] == true ? inr(item['value']) : qtyInt(item['value']);
      }
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final stock = _value(['stock on hand', 'stock']);
    final production = _value(['production today', 'production']);
    final dispatch = _value(['dispatch today', 'dispatch']);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        gradient: AppBrand.gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppBrand.blue.withValues(alpha: .18), blurRadius: 14, offset: const Offset(0, 7))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Dashboard Overview', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 9),
        Text('Stock on Hand ${U.cb} value', style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(stock, style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, height: .95)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _summary('Production Today', production)),
          const SizedBox(width: 10),
          Expanded(child: _summary('Dispatch Today', dispatch)),
        ]),
      ]),
    );
  }

  Widget _summary(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .86), fontSize: 10.8, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
      );
}

/// Replace default-industry unit words in server-sent labels with the active
/// industry's unit names (e.g. "Stock on Hand (CB)" → "... (Bag)").
String _unitize(String label) => U.ize(label);

Map<String, dynamic>? _firstWidget(List<Map<String, dynamic>> widgets, String type) {
  for (final widget in widgets) {
    if (widget['type'] == type) return widget;
  }
  return null;
}

Map<String, dynamic>? _findKpi(List<Map<String, dynamic>> items, List<String> terms) {
  for (final term in terms) {
    for (final item in items) {
      final label = '${item['label'] ?? ''}'.toLowerCase();
      if (label == term || label.contains(term)) return item;
    }
  }
  return null;
}

String _liveKpiValue(List<Map<String, dynamic>> items, List<String> terms) {
  final item = _findKpi(items, terms);
  if (item == null) return '—';
  return item['money'] == true ? inr(item['value']) : qtyInt(item['value']);
}

List<Map<String, dynamic>> _additionalKpis(List<Map<String, dynamic>> items) {
  const coreTerms = ['stock on hand', 'stock', 'production today', 'production', 'dispatch today', 'dispatch', 'low stock', 'low'];
  return [
    for (final item in items)
      if (!coreTerms.any((term) => '${item['label'] ?? ''}'.toLowerCase().contains(term))) item,
  ];
}

List<Map<String, dynamic>> _referenceKpis(List<Map<String, dynamic>> items, Map<String, dynamic>? alerts) {
  Map<String, dynamic> metric(String label, List<String> terms, IconData icon, Color tint, {String? display}) {
    final source = _findKpi(items, terms);
    return {
      'label': label,
      'display': display ?? (source == null ? '—' : (source['money'] == true ? inr(source['value']) : qtyInt(source['value']))),
      'iconData': icon,
      'tintColor': tint,
    };
  }

  String? lowDisplay;
  if (alerts != null) {
    final alertItems = (alerts['items'] as List?) ?? const [];
    final low = alertItems.where((item) {
      if (item is! Map) return false;
      final severity = '${item['severity'] ?? ''}'.toLowerCase();
      return severity == 'high' || severity == 'medium';
    }).length;
    lowDisplay = qtyInt(low);
  }
  return [
    metric(_unitize('Stock on Hand'), ['stock on hand', 'stock'], Icons.inventory_2_outlined, AppBrand.blue),
    metric(_unitize('Production Today'), ['production today', 'production'], Icons.factory_outlined, AppColors.cyan),
    metric(_unitize('Dispatch Today'), ['dispatch today', 'dispatch'], Icons.local_shipping_outlined, AppBrand.green),
    metric(_unitize('Low Stock'), ['low stock', 'low'], Icons.trending_down_rounded, AppColors.red, display: lowDisplay),
  ];
}

class _DashboardQuickActions extends StatelessWidget {
  final Map<String, dynamic> widget;
  const _DashboardQuickActions({required this.widget});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final items = <Map<String, dynamic>>[];
    void add(String label, String route, IconData icon, Color color, bool allowed) {
      if (allowed && !items.any((item) => item['route'] == route)) {
        items.add({'label': label, 'route': route, 'icon': icon, 'color': color});
      }
    }

    // These are the four operational shortcuts from the mobile reference. The
    // permission checks keep the shortcuts role-safe; values remain server/API
    // driven and the modules drawer remains the complete navigation surface.
    add('Receive Stock', '/inventory', Icons.inventory_2_outlined, AppBrand.blue, auth.can('inventory.manage'));
    add('New Batch', '/production', Icons.factory_outlined, AppColors.cyan, auth.can('production.manage'));
    add('Dispatch', '/dispatch', Icons.local_shipping_outlined, AppBrand.green, auth.can('dispatch.manage'));
    add('Reports', '/reports', Icons.bar_chart_rounded, AppColors.slate, auth.can('reports.view'));

    // Keep the server-defined shortcuts too: the old dashboard exposed
    // Manage Users and Audit Log here for permitted roles. They remain live,
    // role-gated actions; the complete module drawer is still unchanged.
    for (final action in (widget['items'] as List).cast<Map<String, dynamic>>()) {
      final route = action['route'] as String?;
      if (route == null || items.any((item) => item['route'] == route)) continue;
      items.add({
        'label': U.ize(action['label'] as String),
        'route': route,
        'icon': iconFor(action['icon'] as String?),
        'color': AppColors.slate,
      });
    }

    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Quick Actions', style: TextStyle(color: scheme.onSurface, fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Wrap(spacing: 9, runSpacing: 9, children: [
        for (final item in items)
          _DashboardActionChip(
            label: item['label'] as String,
            icon: item['icon'] as IconData,
            route: item['route'] as String,
            color: item['color'] as Color,
            filled: items.first == item,
          ),
      ]),
    ]);
  }
}

class _DashboardActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final String route;
  final Color color;
  final bool filled;
  const _DashboardActionChip({required this.label, required this.icon, required this.route, required this.color, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: () => context.go(route),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withValues(alpha: filled ? 0 : .70), width: 1.4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: filled ? Colors.white : color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: filled ? Colors.white : color, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

class _DashboardActivity extends StatelessWidget {
  final List<Map<String, dynamic>> kpis;
  const _DashboardActivity({required this.kpis});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = [
      ('Production batches', _liveKpiValue(kpis, ['production today', 'production'])),
      ('Dispatches', _liveKpiValue(kpis, ['dispatch today', 'dispatch'])),
      ('Stock updates', _liveKpiValue(kpis, ['stock updates', 'updates'])),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: .06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Today's Activity", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 11),
        Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 6, decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(8))),
          const SizedBox(width: 11),
          Expanded(child: Column(children: [
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : 9),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: Text(rows[i].$1, style: TextStyle(color: scheme.onSurface, fontSize: 13.5, fontWeight: FontWeight.w500))),
                    Text(rows[i].$2, style: TextStyle(color: scheme.onSurface, fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ]),
                  if (i != rows.length - 1) ...[
                    const SizedBox(height: 8),
                    Divider(height: 1, color: scheme.outlineVariant),
                  ],
                ]),
              ),
          ])),
        ]),
      ]),
    );
  }
}

class _DashboardKpiGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _DashboardKpiGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 340 ? 1 : 2;
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: cols == 1 ? 3.1 : 2.1,
        children: [
          for (final item in items)
            _DashboardKpiTile(
              label: item['label'] as String,
              value: item['display'] as String? ?? (item['money'] == true ? inr(item['value']) : qtyInt(item['value'])),
              icon: item['iconData'] as IconData? ?? iconFor(item['icon'] as String?),
              tint: item['tintColor'] as Color? ?? hexColor(item['tint'] as String?),
            ),
        ],
      );
    });
  }
}

class _DashboardKpiTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  const _DashboardKpiTile({required this.label, required this.value, required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 11),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: .06), blurRadius: 7, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: tint.withValues(alpha: .12), shape: BoxShape.circle), child: Icon(icon, size: 17, color: tint)),
          const SizedBox(width: 9),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 13.5, fontWeight: FontWeight.w600))),
        ]),
        const Spacer(),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 23, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _KpiGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // The Play Store mobile layout uses compact 2-column metric tiles,
      // matching the module-card rhythm while retaining 3/4 columns on web.
      final cols = c.maxWidth > 1300 ? 4 : c.maxWidth > 900 ? 3 : c.maxWidth < 340 ? 1 : 2;
      final ratio = ((c.maxWidth - (cols - 1) * 12) / cols / 100).clamp(1.38, 4.5);
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12, crossAxisSpacing: 12,
        childAspectRatio: ratio,
        children: [
          for (final it in items)
            KpiCard(
              // Server labels are written for the default industry (CB/Trays/
              // Bottles) — swap in the active industry's unit names.
              label: _unitize(it['label'] as String),
              value: (it['money'] == true) ? inr(it['value']) : qtyInt(it['value']),
              icon: iconFor(it['icon'] as String?),
              tint: hexColor(it['tint'] as String?),
            ),
        ],
      );
    });
  }
}

class _Line extends StatelessWidget {
  final Map<String, dynamic> w;
  const _Line(this.w);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final values = (w['values'] as List).map((e) => (e as num).toDouble()).toList();
    final axis = _niceAxis(values);
    return SizedBox(
      height: 220,
      child: LineChart(LineChartData(
        minY: 0, maxY: axis.maxY,
        gridData: FlGridData(
          show: true, drawVerticalLine: false, horizontalInterval: axis.interval,
          getDrawingHorizontalLine: (v) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 0.7, dashArray: [4, 5]),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 42, interval: axis.interval,
              getTitlesWidget: (v, m) => SideTitleWidget(axisSide: m.axisSide, child: Text(_tick(v), style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, interval: 3, reservedSize: 26,
              getTitlesWidget: (v, m) {
                final labels = (w['labels'] as List).cast<String>();
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return SideTitleWidget(axisSide: m.axisSide, child: Text(labels[i], style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)));
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final s in spots) LineTooltipItem(qty(s.y), TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
            isCurved: true, barWidth: 2.4, color: scheme.primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: scheme.primary.withValues(alpha: 0.07)),
          ),
        ],
      )),
    );
  }
}

String _tick(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k' : qty(v);

/// Pick a clean axis step (1/2/5 × power of 10) for ~4 gridlines, then
/// round maxY UP to a multiple of it — so every label lands exactly on a
/// gridline and the top value never overlaps the tick below it.
({double maxY, double interval}) _niceAxis(List<double> values) {
  final rawMax = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
  if (rawMax <= 0) return (maxY: 4, interval: 1);
  final target = rawMax * 1.15 / 4; // aim for ~4 intervals incl. headroom
  double magnitude = 1;
  while (magnitude * 10 <= target) { magnitude *= 10; }
  while (magnitude > target && magnitude > 0.001) { magnitude /= 10; }
  double interval;
  if (target <= magnitude * 1) {
    interval = magnitude * 1;
  } else if (target <= magnitude * 2) {
    interval = magnitude * 2;
  } else if (target <= magnitude * 5) {
    interval = magnitude * 5;
  } else {
    interval = magnitude * 10;
  }
  if (interval < 1) interval = 1; // counts (CB, trips) are whole numbers
  final maxY = ((rawMax * 1.15) / interval).ceil() * interval;
  return (maxY: maxY <= rawMax ? maxY + interval : maxY.toDouble(), interval: interval);
}

class _Bar extends StatelessWidget {
  final Map<String, dynamic> w;
  const _Bar(this.w);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final values = (w['values'] as List).map((e) => (e as num).toDouble()).toList();
    final axis = _niceAxis(values);
    return SizedBox(
      height: 220,
      child: BarChart(BarChartData(
        maxY: axis.maxY,
        gridData: FlGridData(
          show: true, drawVerticalLine: false, horizontalInterval: axis.interval,
          getDrawingHorizontalLine: (v) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 0.7, dashArray: [4, 5]),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 42, interval: axis.interval,
              getTitlesWidget: (v, m) => SideTitleWidget(axisSide: m.axisSide, child: Text(_tick(v), style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, interval: 3, reservedSize: 26,
              getTitlesWidget: (v, m) {
                final labels = (w['labels'] as List).cast<String>();
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return SideTitleWidget(axisSide: m.axisSide, child: Text(labels[i], style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)));
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(qty(rod.toY), TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w700)),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: values[i],
                width: values.length > 10 ? 9 : 16,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(3), topRight: Radius.circular(3)),
                color: values[i] > 0 ? scheme.primary : scheme.surfaceContainerHighest,
              ),
            ]),
        ],
      )),
    );
  }
}

class _Pie extends StatelessWidget {
  final Map<String, dynamic> w;
  const _Pie(this.w);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labels = (w['labels'] as List).cast<String>();
    final values = (w['values'] as List).map((e) => (e as num).toDouble()).toList();
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return const EmptyState('No data yet');
    return LayoutBuilder(builder: (context, c) {
      final chart = SizedBox(
        height: 210, width: 210,
        child: PieChart(PieChartData(
          sectionsSpace: 2, centerSpaceRadius: 48,
          sections: [
            for (var i = 0; i < values.length; i++)
              PieChartSectionData(
                value: values[i],
                color: AppColors.chart[i % AppColors.chart.length],
                radius: 56,
                title: values[i] / total >= 0.06 ? '${(values[i] / total * 100).toStringAsFixed(0)}%' : '',
                titleStyle: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
              ),
          ],
        )),
      );
      final legend = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.chart[i % AppColors.chart.length], borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Flexible(child: Text(labels[i], style: TextStyle(fontSize: 12.5, color: scheme.onSurface, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 10),
              Text('${qty(values[i])} ${U.cb}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ]),
          ),
      ]);
      if (c.maxWidth < 520) {
        return Column(children: [chart, const SizedBox(height: 12), legend]);
      }
      return Row(children: [chart, const SizedBox(width: 24), Expanded(child: legend)]);
    });
  }
}

class _Alerts extends StatelessWidget {
  final Map<String, dynamic> w;
  const _Alerts(this.w);
  @override
  Widget build(BuildContext context) {
    final items = (w['items'] as List).cast<Map<String, dynamic>>();
    if (items.isEmpty) {
      return Row(children: [
        const Icon(Icons.check_circle_outlined, color: AppColors.green, size: 17),
        const SizedBox(width: 8),
        Text('All clear — nothing needs attention.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.8)),
      ]);
    }
    return Column(children: [
      for (var i = 0; i < items.length; i++)
        Builder(builder: (context) {
          final a = items[i];
          final sev = a['severity'] as String? ?? 'info';
          final color = sev == 'high' ? AppColors.red : sev == 'medium' ? AppColors.amber : AppColors.blue;
          final icon = sev == 'high' ? Icons.error_outline_rounded : sev == 'medium' ? Icons.warning_amber_rounded : Icons.info_outline_rounded;
          return InkWell(
            onTap: a['route'] == null ? null : () => context.go(a['route'] as String),
            child: Container(
              decoration: BoxDecoration(
                border: i > 0 ? Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)) : null,
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 11),
                Expanded(child: Text(_unitize(a['text'] as String), style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w500))),
                Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.outline, size: 18),
              ]),
            ),
          );
        }),
    ]);
  }
}

class _ServerTable extends StatelessWidget {
  final Map<String, dynamic> w;
  const _ServerTable(this.w);
  @override
  Widget build(BuildContext context) {
    // Server tables use the default industry's units — filter/relabel them.
    final (columns, rows) = U.table(
      (w['columns'] as List).cast<String>(),
      (w['rows'] as List).map((r) => (r as List).cast<dynamic>()).toList(),
    );
    final moneyCols = <int>{for (var i = 0; i < columns.length; i++) if (columns[i].contains('₹')) i};
    if (rows.isEmpty) return const EmptyState('No records yet');
    return AppDataTable(columns: columns, rows: rows, moneyColumns: moneyCols);
  }
}

class _Actions extends StatelessWidget {
  final Map<String, dynamic> w;
  const _Actions(this.w);
  @override
  Widget build(BuildContext context) {
    final items = (w['items'] as List).cast<Map<String, dynamic>>();
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final a in items)
        OutlinedButton.icon(
          onPressed: () => context.go(a['route'] as String),
          icon: Icon(iconFor(a['icon'] as String?), size: 17),
          label: Text(a['label'] as String),
        ),
    ]);
  }
}
