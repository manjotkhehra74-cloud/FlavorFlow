import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final list = ((json as Map)['reports'] as List).cast<Map<String, dynamic>>();
    if (list.isNotEmpty) _select(list.first);
    return list;
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

  List<String> get _columns => (_data?['columns'] as List? ?? const []).cast<String>();
  List<List<dynamic>> get _rows =>
      ((_data?['rows'] as List? ?? const [])).map((r) => (r as List).cast<dynamic>()).toList();

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
        title: _data!['title'] as String,
        desc: _selected!['desc'] as String? ?? '',
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
        child: Text(tr(r['title'] as String),
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
            Text(tr(r['title'] as String),
                style: TextStyle(fontSize: 12.6, fontWeight: FontWeight.w600, color: sel ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 2),
            Text(tr(r['desc'] as String),
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
      title: _selected!['title'] as String,
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
        Text(tr(_selected!['desc'] as String), style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        FutureBuilder<Map<String, dynamic>>(
          future: _reportFuture,
          builder: (context, rsnap) {
            if (rsnap.hasError) return ErrorState(rsnap.error!, onRetry: () => setState(() => _select(_selected!)));
            if (!rsnap.hasData) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
            final columns = (rsnap.data!['columns'] as List).cast<String>();
            final rows = (rsnap.data!['rows'] as List).map((r) => (r as List).cast<dynamic>()).toList();
            final moneyCols = <int>{for (final i in (rsnap.data!['moneyColumns'] as List? ?? const [])) i as int};
            if (rows.isEmpty) {
              return const EmptyState('No data yet — it appears here as you start working.', icon: Icons.table_rows_outlined);
            }
            return AppDataTable(columns: columns, rows: rows, moneyColumns: moneyCols);
          },
        ),
      ]),
    );
  }
}
