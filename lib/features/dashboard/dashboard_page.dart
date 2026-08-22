import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

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

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthController>().session!;
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final data = snap.data!;
        final widgets = (data['widgets'] as List).cast<Map<String, dynamic>>();
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              _Header(greeting: data['greeting'] as String, name: data['name'] as String, session: session),
              const SizedBox(height: 16),
              _WorkspaceGrid(session: session),
              const SizedBox(height: 16),
              for (final w in widgets) ...[
                _buildWidget(w),
                const SizedBox(height: 16),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildWidget(Map<String, dynamic> w) {
    switch (w['type']) {
      case 'kpi': return _KpiGrid(items: (w['items'] as List).cast<Map<String, dynamic>>());
      case 'line': return SectionCard(title: w['title'] as String, child: _Line(w));
      case 'bar': return SectionCard(title: w['title'] as String, child: _Bar(w));
      case 'pie': return SectionCard(title: w['title'] as String, child: _Pie(w));
      case 'alerts': return SectionCard(title: w['title'] as String, child: _Alerts(w));
      case 'table':
        final route = w['route'] as String?;
        return SectionCard(
          title: w['title'] as String,
          trailing: route == null
              ? null
              : TextButton.icon(
                  onPressed: () => context.go(route),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(tr('Open')),
                ),
          child: _ServerTable(w),
        );
      case 'actions': return SectionCard(title: w['title'] as String, child: _Actions(w));
      default: return const SizedBox.shrink();
    }
  }
}

class _Header extends StatelessWidget {
  final String greeting, name;
  final UserSession session;
  const _Header({required this.greeting, required this.name, required this.session});

  @override
  Widget build(BuildContext context) {
    // Gradient hero card — logo blue → green, like the brand mockups.
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E6FE0), Color(0xFF16A085), Color(0xFF22C55E)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x331E6FE0), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(13)),
          child: const Icon(Icons.insights_rounded, color: Colors.white, size: 23),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$greeting, ${name.split(' ').first}',
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Colors.white)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 2, children: [
              Text('${session.roleLabel} workspace', style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12.5)),
              Text('·  ${fmtDateWithDay(todayYmd())}', softWrap: false, style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12.5)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Replace default-industry unit words in server-sent labels with the active
/// industry's unit names (e.g. "Stock on Hand (CB)" → "... (Bale)").
String _unitize(String label) {
  var out = label;
  if (U.cb != 'CB') out = out.replaceAll('(CB)', '(${U.cb})').replaceAll(' CB', ' ${U.cb}');
  if (U.carton != 'Cartons') out = out.replaceAll('Cartons', U.carton);
  if (U.tray != 'Trays') out = out.replaceAll('Trays', U.tray).replaceAll('trays', U.trayLc);
  if (U.piece != 'Bottles') out = out.replaceAll('Bottles', U.piece).replaceAll('bottles', U.piece.toLowerCase());
  return out;
}

class _KpiGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _KpiGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 1300 ? 4 : c.maxWidth > 900 ? 3 : c.maxWidth > 560 ? 2 : 1;
      final ratio = ((c.maxWidth - (cols - 1) * 12) / cols / 84).clamp(1.6, 5.0);
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
    final columns = (w['columns'] as List).cast<String>();
    final rows = (w['rows'] as List).map((r) => (r as List).cast<dynamic>()).toList();
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


/// "Your workspace" — rounded-square tiles (3 per row) for every module the
/// user can open, like the brand mockups. Built from the same nav the
/// sidebar uses, so permissions/industry gating apply automatically.
class _WorkspaceGrid extends StatelessWidget {
  final UserSession session;
  const _WorkspaceGrid({required this.session});

  static const _tints = [
    Color(0xFF1E6FE0), Color(0xFF16A34A), Color(0xFF7C3AED), Color(0xFFEA580C),
    Color(0xFF0D9488), Color(0xFFDB2777), Color(0xFFD97706), Color(0xFF0891B2),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      for (final e in session.nav)
        if (e['path'] != '/dashboard') e,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 10),
        child: Text(tr('Your workspace'),
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: scheme.onSurface)),
      ),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 900 ? 6 : c.maxWidth > 560 ? 4 : 3;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, crossAxisSpacing: 10,
          childAspectRatio: 0.98,
          children: [
            for (var i = 0; i < items.length; i++)
              _WorkTile(
                label: tr(items[i]['label'] as String),
                icon: iconFor(items[i]['icon'] as String?),
                tint: _tints[i % _tints.length],
                onTap: () => context.go(items[i]['path'] as String),
              ),
          ],
        );
      }),
    ]);
  }
}

class _WorkTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
  const _WorkTile({required this.label, required this.icon, required this.tint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, size: 21, color: tint),
            ),
            const SizedBox(height: 8),
            Text(label,
                maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.8, fontWeight: FontWeight.w700, height: 1.15, color: scheme.onSurface)),
          ]),
        ),
      ),
    );
  }
}
