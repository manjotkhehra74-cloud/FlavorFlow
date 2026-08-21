import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import 'dispatch_pdf.dart';

/// Dispatch detail — deep link target of dispatch notifications. PDF challan export.
class DispatchDetailPage extends StatefulWidget {
  final int id;
  const DispatchDetailPage({super.key, required this.id});
  @override
  State<DispatchDetailPage> createState() => _DispatchDetailPageState();
}

class _DispatchDetailPageState extends State<DispatchDetailPage> {
  late Future<Map<String, dynamic>> _future;
  bool exporting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final json = await context.read<AuthController>().api.get('/dispatch/${widget.id}');
    return (json as Map).cast<String, dynamic>();
  }

  Future<void> _exportPdf(Map<String, dynamic> d, List<Map<String, dynamic>> items) async {
    setState(() => exporting = true);
    try {
      final bytes = await DispatchPdf.challan(d, items);
      await Printing.sharePdf(bytes: bytes, filename: '${d['code']}-packing-slip.pdf');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: () => setState(() => _future = _load()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final d = (snap.data!['dispatch'] as Map).cast<String, dynamic>();
        final items = (snap.data!['items'] as List).cast<Map<String, dynamic>>();
        final dayName = d['weekday'] as String? ?? weekdayOf(d['dispatch_date']);
        return ListView(padding: const EdgeInsets.all(20), children: [
          // Wrap: on narrow phones the Export button drops to its own line
          // instead of overflowing off-screen.
          Wrap(spacing: 4, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            IconButton(
              onPressed: () => context.canPop() ? context.pop() : context.go('/dispatch?tab=history'),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Text(d['code'] as String, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            const SizedBox(width: 8),
            StatusChip(d['status'] as String),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: exporting ? null : () => _exportPdf(d, items),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 19),
              label: Text(exporting ? 'Preparing…' : 'Export PDF'),
            ),
          ]),
          const SizedBox(height: 18),
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth > 900;
            final meta = SectionCard(title: 'Vehicle & Invoice', child: Column(children: [
              _row('Truck Number', d['truck_number'] as String),
              _row('Destination', d['destination'] as String? ?? '—'),
              _row('Dispatch Date', dayName.isEmpty ? fmtDate(d['dispatch_date']) : '$dayName, ${fmtDate(d['dispatch_date'])}'),
              if ((d['remarks'] as String).isNotEmpty) _row('Remarks', d['remarks'] as String),
              _row('Created by', '${d['created_by_name'] ?? '—'} · ${fmtDateTime(d['created_at'])}'),
            ]));
            final totals = SectionCard(
              title: 'Weight & Quantity Summary',
              child: Column(children: [
                _BigStat(label: 'Gross Weight', value: '${qty(d['gross_weight'])} kg', tint: AppColors.orange),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _BigStat(label: 'Carton Weight', value: '${qty(d['carton_weight'])} kg', tint: AppColors.blue, small: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _BigStat(label: 'Tray Weight', value: '${qty(d['tray_weight'])} kg', tint: AppColors.teal, small: true)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _BigStat(label: 'Total Cartons', value: '${qtyInt(d['total_cartons'])} CB', tint: AppColors.violet, small: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _BigStat(label: 'Total Trays', value: qtyInt(d['total_trays'] ?? 0), tint: AppColors.pink, small: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _BigStat(label: 'Total Bottles', value: qtyInt(d['total_bottles']), tint: AppColors.cyan, small: true)),
                ]),
              ]),
            );
            if (wide) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: meta), const SizedBox(width: 16), Expanded(flex: 2, child: totals)]);
            }
            return Column(children: [meta, const SizedBox(height: 16), totals]);
          }),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Loaded Items',
            child: AppDataTable(
              columns: ['Product', 'Batch', U.carton, U.tray, U.piece, '${U.cb} kg', '${U.tray} kg', 'Gross kg'],
              rows: [
                for (final it in items)
                  [
                    Text(it['product_name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    (it['batch_code'] ?? '—').toString(),
                    qtyInt(it['cartons']),
                    qtyInt(it['trays'] ?? 0),
                    qtyInt(it['total_bottles']),
                    qty(it['carton_weight']),
                    qty(it['tray_weight'] ?? 0),
                    qty(it['gross_weight']),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('Weights computed from the Product Master: cartons × weight/CB and trays × tray weight.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ]);
      },
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 140, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
        ]),
      );
}

class _BigStat extends StatelessWidget {
  final String label, value;
  final Color tint;
  final bool small;
  const _BigStat({required this.label, required this.value, required this.tint, this.small = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(small ? 12 : 16),
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(12), border: Border.all(color: tint.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: small ? 15.5 : 22, fontWeight: FontWeight.w800, color: tint, letterSpacing: -0.3)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: tint.withValues(alpha: 0.9))),
      ]),
    );
  }
}
