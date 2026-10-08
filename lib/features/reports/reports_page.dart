import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/download.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import 'report_pdf.dart';

/// Role-scoped reports with export to PDF & Excel — the server decides
/// which reports each role can open (and export) and enforces it.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsOverview extends StatelessWidget {
  final List<Map<String, dynamic>> reports;
  const _ReportsOverview({required this.reports});

  int _count(String terms) {
    final wanted = terms.split('|');
    return reports.where((r) {
      final key = '${r['id'] ?? ''} ${r['title'] ?? ''}'.toLowerCase();
      return wanted.any((term) => key.contains(term));
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final stock = _count('stock|inventory|batch|low');
    final production = _count('production|packing|bom');
    final dispatch = _count('dispatch|truck|shipment');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        decoration: BoxDecoration(
          gradient: AppBrand.gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: AppBrand.blue.withValues(alpha: .18), blurRadius: 14, offset: const Offset(0, 7))],
        ),
        child: Column(children: [
          const Text('Reports Overview', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text('${reports.length}', style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w800, height: .95)),
          const SizedBox(height: 9),
          const Text('PDF and Excel exports available', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500)),
        ]),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, constraints) {
        return GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: constraints.maxWidth >= 700 ? 1.5 : 1.25,
          children: [
            _ReportMetric(label: 'Stock', value: '$stock', sub: 'reports', icon: Icons.inventory_2_outlined, tint: AppColors.blue),
            _ReportMetric(label: 'Production', value: '$production', sub: 'reports', icon: Icons.factory_outlined, tint: AppColors.teal),
            _ReportMetric(label: 'Dispatch', value: '$dispatch', sub: 'reports', icon: Icons.local_shipping_outlined, tint: AppColors.orange),
          ],
        );
      }),
    ]);
  }
}

class _ReportMetric extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color tint;
  const _ReportMetric({required this.label, required this.value, required this.sub, required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: .06), blurRadius: 7, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 20, color: tint), const Spacer(), Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: tint))]),
        const Spacer(),
        Text(value, style: TextStyle(color: scheme.onSurface, fontSize: 22, fontWeight: FontWeight.w800)),
        Text('$label · $sub', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _ReportsPageState extends State<ReportsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  Map<String, dynamic>? _selected;
  Future<Map<String, dynamic>>? _reportFuture;
  Map<String, dynamic>? _data;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final json = await context.read<AuthController>().api.get('/reports');
    // The server's report library is the same for every company — keep only
    // what this industry runs (no recipe reports for discrete industries, no
    // tray registers where trays don't exist) and drop the retired Loss % sheet.
    final list = [
      for (final r in ((json as Map)['reports'] as List).cast<Map<String, dynamic>>())
        if (_reportVisible(r)) r,
    ];
    if (list.isNotEmpty) _select(list.first);
    return list;
  }

  static bool _reportVisible(Map<String, dynamic> r) {
    final key = '${r['id'] ?? ''} ${r['title'] ?? ''}'.toLowerCase();
    if (!CompanyProfile.usesLossPct && key.contains('loss')) return false; // Loss % sheet switched off for this company
    if (!CompanyProfile.usesRecipes && key.contains('recipe')) return false;
    if (!CompanyProfile.usesTrays && RegExp(r'\btrays?\b').hasMatch(key)) return false;
    if (!CompanyProfile.usesProduction && (key.contains('production') || key.contains('batch'))) return false;
    return true;
  }

  void _select(Map<String, dynamic> r) {
    _selected = r;
    _data = null;
    _reportFuture = context.read<AuthController>().api.get('/reports/${r['id']}').then((j) {
      _data = (j as Map).cast<String, dynamic>();
      // Rebuild the whole page (not just the FutureBuilder subtree) so the
      // Export PDF button — which is disabled while _data is null — enables
      // as soon as the report data arrives.
      if (mounted) setState(() {});
      return _data!;
    });
  }

  List<String> get _columns => U.table((_data?['columns'] as List? ?? const []).cast<String>(), const []).$1;

  /// Friendly mobile labels keep the report library readable while the
  /// server-provided report id and data remain unchanged.
  String _displayTitle(Map<String, dynamic> report) {
    final key = '${report['id'] ?? ''} ${report['title'] ?? ''}'.toLowerCase();
    if (key.contains('inventory') && key.contains('stock')) return 'Stock on Hand';
    if (key.contains('batch')) return 'Batch Register';
    if (key.contains('production')) return 'Production';
    if (key.contains('dispatch')) return 'Dispatch History';
    return '${report['title'] ?? ''}';
  }

  String _chipTitle(Map<String, dynamic> report) {
    final key = '${report['id'] ?? ''} ${report['title'] ?? ''}'.toLowerCase();
    if (key.contains('inventory') && key.contains('stock')) return 'Stock on Hand';
    if (key.contains('batch')) return 'Batch Register';
    if (key.contains('production')) return 'Production History';
    if (key.contains('summary')) return 'Inventory Summary';
    if (key.contains('low')) return 'Low Stock';
    // Keep the two material ledgers distinct. They used to both fall through
    // to the generic "Warehouse Logs" label, which made the mobile chips look
    // duplicated even though their report bodies were different.
    if (key.contains('packing') && key.contains('ledger')) return 'Packing Material Logs';
    if (key.contains('raw') && key.contains('ledger')) return 'Raw Material Logs';
    if (key.contains('audit')) return 'Approval Audit Trail';
    if (key.contains('warehouse')) return 'Warehouse Logs';
    return _displayTitle(report);
  }

  /// Empty-state text that tells a NEW company what feeds each report.
  String _emptyHint(String id) {
    if (id.contains('raw')) return 'No data yet — add raw materials (Raw Material → New Material) and receive stock; consumption appears here.';
    if (id.contains('packing')) return 'No data yet — add packing materials (Packing Material → New Material) and receive stock.';
    if (id.contains('dispatch')) return 'No data yet — dispatches you confirm appear here.';
    if (id.contains('production') || id.contains('batch')) return 'No data yet — production batches you complete appear here.';
    if (id.contains('adjust') || id.contains('approval') || id.contains('audit')) return 'No data yet — stock adjustments and approvals appear here.';
    if (id.contains('low')) return 'Nothing below minimum stock 🎉';
    return 'No data yet — add products in Products and receive opening stock; it appears here as you start working.';
  }
  List<List<dynamic>> get _rows => U.table(
        (_data?['columns'] as List? ?? const []).cast<String>(),
        ((_data?['rows'] as List? ?? const [])).map((r) => (r as List).cast<dynamic>()).toList(),
      ).$2;

  Future<void> _exportExcel() async {
    if (_selected == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final id = _selected!['id'] as String;
      final bytes = await context.read<AuthController>().api.getBytes('/reports/$id.xlsx');
      final date = DateTime.now().toIso8601String().substring(0, 10);
      downloadBytes('flavorflow-$id-$date.xlsx', bytes, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      if (mounted) showOk(context, 'Excel file downloaded.');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_data == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await ReportPdf.build(
        title: U.ize(_displayTitle(_selected!)),
        desc: U.ize(_selected!['desc'] as String? ?? ''),
        columns: _columns,
        rows: _rows,
      );
      final date = DateTime.now().toIso8601String().substring(0, 10);
      downloadBytes('flavorflow-${_data!['id']}-$date.pdf', bytes, 'application/pdf');
      if (mounted) showOk(context, 'PDF downloaded.');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: () => setState(() => _future = _load()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final reports = snap.data!;
        if (reports.isEmpty) return const EmptyState('No reports available for your role', icon: Icons.bar_chart_rounded);
        return LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 900;
          return ListView(padding: const EdgeInsets.all(18), children: [
            _ReportsOverview(reports: reports),
            const SizedBox(height: 16),
            if (!wide) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final r in reports) _reportChip(r)],
              ),
              const SizedBox(height: 14),
              _reportBody(),
            ] else
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 268,
                  child: SectionCard(
                    title: 'Report Library',
                    padding: const EdgeInsets.all(8),
                    child: Column(children: [for (final r in reports) _reportTile(r)]),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: _reportBody()),
              ]),
          ]);
        });
      },
    );
  }

  Widget _reportChip(Map<String, dynamic> r) {
    final sel = _selected?['id'] == r['id'];
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: () => setState(() => _select(r)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: sel ? AppColors.blue : const Color(0xFFC3CEDA)),
        ),
        child: Text(U.ize(tr(_chipTitle(r))),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurface)),
      ),
    );
  }

  Widget _reportTile(Map<String, dynamic> r) {
    final sel = _selected?['id'] == r['id'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _select(r)),
        child: Container(
          decoration: BoxDecoration(
            color: sel ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: sel ? const Border(left: BorderSide(color: AppColors.blue, width: 3)) : null,
          ),
          padding: EdgeInsets.fromLTRB(sel ? 9 : 12, 9, 10, 9),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(U.ize(tr(_displayTitle(r))),
                style: TextStyle(fontSize: 12.6, fontWeight: FontWeight.w600, color: sel ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 2),
            Text(U.ize(tr(r['desc'] as String)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35)),
          ]),
        ),
      ),
    );
  }

  Widget _reportBody() {
    if (_selected == null) return const SizedBox.shrink();
    return SectionCard(
      title: U.ize(_displayTitle(_selected!)),
      stackTrailingOnNarrow: true,
      trailing: Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: (_data == null || _exporting) ? null : _exportPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
          label: Text(tr('Export PDF')),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE65353),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            minimumSize: const Size(0, 36),
          ),
        ),
        FilledButton.icon(
          onPressed: _exporting ? null : _exportExcel,
          icon: const Icon(Icons.table_view_outlined, size: 16),
          label: Text(tr('Export Excel')),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF70),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            minimumSize: const Size(0, 36),
          ),
        ),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(U.ize(tr(_selected!['desc'] as String)), style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        FutureBuilder<Map<String, dynamic>>(
          future: _reportFuture,
          builder: (context, rsnap) {
            if (rsnap.hasError) return ErrorState(rsnap.error!, onRetry: () => setState(() => _select(_selected!)));
            if (!rsnap.hasData) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
            final rawCols = (rsnap.data!['columns'] as List).cast<String>();
            final (columns, rows) = U.table(rawCols, (rsnap.data!['rows'] as List).map((r) => (r as List).cast<dynamic>()).toList());
            // money-column indexes shift when tray columns are dropped
            final dropped = U.trayColumns(rawCols);
            final moneyCols = <int>{
              for (final m in (rsnap.data!['moneyColumns'] as List? ?? const []).cast<int>())
                if (!dropped.contains(m)) m - dropped.where((d) => d < m).length,
            };
            if (rows.isEmpty) {
              return EmptyState(_emptyHint(_selected!['id'] as String? ?? ''), icon: Icons.table_rows_outlined);
            }
            return AppDataTable(columns: columns, rows: rows, moneyColumns: moneyCols);
          },
        ),
      ]),
    );
  }
}
