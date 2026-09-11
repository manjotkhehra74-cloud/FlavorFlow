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
    // what this industry runs (no Loss % sheet for mills, no recipe reports
    // for discrete industries, no tray registers where trays don't exist).
    final list = [
      for (final r in ((json as Map)['reports'] as List).cast<Map<String, dynamic>>())
        if (_reportVisible(r)) r,
    ];
    if (list.isNotEmpty) _select(list.first);
    return list;
  }

  static bool _reportVisible(Map<String, dynamic> r) {
    final key = '${r['id'] ?? ''} ${r['title'] ?? ''}'.toLowerCase();
    if (!CompanyProfile.usesLossPct && key.contains('loss')) return false;
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
        title: U.ize(_data!['title'] as String),
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
            if (!wide) ...[
              Wrap(spacing: 7, runSpacing: 7, children: [for (final r in reports) _reportChip(r)]),
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
        child: Text(U.ize(tr(r['title'] as String)),
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
            Text(U.ize(tr(r['title'] as String)),
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
      title: U.ize(_selected!['title'] as String),
      stackTrailingOnNarrow: true,
      trailing: Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: (_data == null || _exporting) ? null : _exportPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
          label: Text(tr('Export PDF')),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFB91C1C),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 32),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _exporting ? null : _exportExcel,
          icon: const Icon(Icons.table_view_outlined, size: 16),
          label: Text(tr('Export Excel')),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF047857),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 32),
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
