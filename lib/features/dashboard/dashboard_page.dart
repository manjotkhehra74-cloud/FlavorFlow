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

class _DashboardPageState extends State<DashboardPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final json = await context.read<AuthController>().api.get('/dashboard');
    return (json as Map).cast<String, dynamic>();
  }

  void _reload() {
    HrMate.instance.summary(force: true); // pull-to-refresh → fresh HRMate numbers too (no-op unless connected; never throws)
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthController>().session!;
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
        // Keep the live server widgets and permissions, but place the KPI and
        // quick-action blocks first so the mobile dashboard matches the new
        // overview hierarchy.
        final orderedWidgets = [
          ...widgets.where((w) => w['type'] == 'kpi'),
          ...widgets.where((w) => w['type'] == 'actions'),
          ...widgets.where((w) => w['type'] != 'kpi' && w['type'] != 'actions'),
        ];
        final kpis = [
          for (final w in widgets.where((w) => w['type'] == 'kpi'))
            ...(w['items'] as List).cast<Map<String, dynamic>>(),
        ];
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 24),
            children: [
              _DashboardHero(greeting: data['greeting'] as String, name: data['name'] as String, session: session, kpis: kpis),
              const SizedBox(height: 18),
              const SubscriptionBanner(),
              // HRMate head-count (read-only bridge) — renders nothing when
              // HRMate is not connected on this device or is unreachable.
              const HrPresenceStrip(),
              for (final w in orderedWidgets) ...[
                _buildWidget(w),
                const SizedBox(height: 16),
              ],
            ],
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
      case 'kpi': return _KpiGrid(items: (w['items'] as List).cast<Map<String, dynamic>>());
      case 'line': return SectionCard(title: U.ize(w['title'] as String), child: _Line(w));
      case 'bar': return SectionCard(title: U.ize(w['title'] as String), child: _Bar(w));
      case 'pie': return SectionCard(title: U.ize(w['title'] as String), child: _Pie(w));
      case 'alerts': return SectionCard(title: U.ize(w['title'] as String), child: _Alerts(w));
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
  final String greeting;
  final String name;
  final UserSession session;
  final List<Map<String, dynamic>> kpis;
  const _DashboardHero({required this.greeting, required this.name, required this.session, required this.kpis});

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
    final firstName = name.split(' ').first;
    final stock = _value(['stock on hand', 'stock']);
    final production = _value(['production today', 'production']);
    final dispatch = _value(['dispatch today', 'dispatch']);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
      decoration: BoxDecoration(
        gradient: AppBrand.gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppBrand.blue.withValues(alpha: .18), blurRadius: 14, offset: const Offset(0, 7))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dashboard Overview', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('$greeting, $firstName', style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 12.5, fontWeight: FontWeight.w500)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
            child: Text(fmtDateWithDay(todayYmd()), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(stock, style: const TextStyle(color: Colors.white, fontSize: 37, fontWeight: FontWeight.w800, height: .95)),
          const SizedBox(width: 8),
          const Padding(padding: EdgeInsets.only(bottom: 3), child: Text('Stock on hand', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _summary('Production today', production)),
          const SizedBox(width: 10),
          Expanded(child: _summary('Dispatch today', dispatch)),
        ]),
        const SizedBox(height: 12),
        Text('${session.roleLabel} workspace', style: TextStyle(color: Colors.white.withValues(alpha: .78), fontSize: 11.5)),
      ]),
    );
  }

  Widget _summary(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(11)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 10.5, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Replace default-industry unit words in server-sent labels with the active
/// industry's unit names (e.g. "Stock on Hand (CB)" → "... (Bag)").
String _unitize(String label) => U.ize(label);

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
