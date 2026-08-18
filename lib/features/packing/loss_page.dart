import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/download.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import '../reports/report_pdf.dart';

/// Packing LOSS% — factory sheet:
///  Top: Product · Projection · Opening · Actual · Opening+Actual ·
///       %Adherence · Closing   (per month)
///  Then one section per product: Material · CB · Extra · Total used · Loss%
///  Every number editable (long-press / tap edit) except names.
///  Month close: export → archive → closings roll into next month's openings.
class LossPage extends StatefulWidget {
  const LossPage({super.key});
  @override
  State<LossPage> createState() => _LossPageState();
}

class _LossPageState extends State<LossPage> {
  Future<Map<String, dynamic>>? _future;
  String? _viewYm; // null = current open month
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final q = _viewYm == null ? '' : '?ym=$_viewYm';
    final json = await context.read<AuthController>().api.get('/packing/loss$q');
    return (json as Map).cast<String, dynamic>();
  }

  void _reload() => setState(() => _future = _load());

  bool get _isArchive => _viewYm != null;

  Future<void> _editCell(String key, num current, String label) async {
    final ctl = TextEditingController(text: '$current');
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tr('Value')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctl.text)), child: const Text('Save')),
        ],
      ),
    );
    if (v == null || !mounted) return;
    try {
      await context.read<AuthController>().api.put('/packing/loss/cell', {'key': key, 'value': v});
      _reload();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _export(Map<String, dynamic> data, {required bool pdf}) async {
    setState(() => _busy = true);
    try {
      final ym = data['ym'];
      final columns = ['Product / Material', 'Projection·CB', 'Opening·Extra', 'Actual·Total', 'Op+Act·Loss%', '%Adh', 'Closing'];
      final rows = <List<dynamic>>[];
      for (final t in (data['top'] as List).cast<Map<String, dynamic>>()) {
        rows.add([t['name'], t['projection'], t['opening'], t['actual'], t['openingActual'], ((t['adherence'] as num?) ?? 0).toStringAsFixed(1), t['closing']]);
      }
      rows.add(['', '', '', '', '', '', '']);
      for (final s in (data['sections'] as List).cast<Map<String, dynamic>>()) {
        rows.add(['▶ ${s['name']}', 'CB', 'Extra', 'Total used', 'Loss%', '', '']);
        for (final r in (s['rows'] as List).cast<Map<String, dynamic>>()) {
          rows.add([r['name'], r['cb'], r['extra'], r['total'], '${((r['lossPct'] as num?) ?? 0).toStringAsFixed(2)}%', '', '']);
        }
        rows.add(['', '', '', '', '', '', '']);
      }
      final bytes = await ReportPdf.build(
        title: 'Packing Loss% — $ym',
        desc: 'Projection vs production, CB (as per BOM) vs Extra (manual consumption), Loss% per material.',
        columns: columns,
        rows: rows,
      );
      await Printing.sharePdf(bytes: bytes, filename: 'flavorflow-loss-$ym.pdf');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeMonth(Map<String, dynamic> data) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Close month ${data['ym']}?'),
            content: const Text(
                'Pehla PDF export kar leya? Month close hon te:\n\n• Eh month archive ho jayega (baad ch vi dekh sakde ho)\n• Har product di Closing agle month di Opening ban jayegi\n• Nava month fresh shuru hovega — purane ch kuch merge nahi hunda'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close month')),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthController>().api.post('/packing/loss/close');
      if (mounted) {
        showOk(context, 'Month closed — closings rolled into the new month\'s openings.');
        _reload();
      }
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthController>().can('packing.manage');
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final data = snap.data!;
        final top = (data['top'] as List).cast<Map<String, dynamic>>();
        final sections = (data['sections'] as List).cast<Map<String, dynamic>>();
        final archives = ((data['archives'] as List?) ?? const []).cast<String>();
        final scheme = Theme.of(context).colorScheme;
        final canEdit = canManage && !_isArchive;

        Widget num0(Object? v) => Text(qty(v), style: const TextStyle(fontFeatures: []));
        Widget edit(String key, num v, String label) => canEdit
            ? InkWell(
                onTap: () => _editCell(key, v, label),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(qty(v)),
                  Icon(Icons.edit_outlined, size: 12, color: scheme.outline),
                ]),
              )
            : num0(v);

        return ListView(padding: const EdgeInsets.all(18), children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${tr('Month')}: ${data['ym']}${_isArchive ? '  (archived)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (archives.isNotEmpty || _isArchive)
              DropdownButton<String>(
                value: _viewYm,
                hint: const Text('Current'),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('Current month')),
                  for (final a in archives) DropdownMenuItem(value: a, child: Text(a)),
                ],
                onChanged: (v) => setState(() { _viewYm = v; _future = _load(); }),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _export(data, pdf: true),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: Text(tr('Export PDF')),
            ),
            if (canEdit)
              FilledButton.icon(
                onPressed: _busy ? null : () => _closeMonth(data),
                icon: const Icon(Icons.lock_clock_rounded, size: 17),
                label: Text(tr('Close month')),
              ),
          ]),
          const SizedBox(height: 12),
          SectionCard(
            title: '${tr('Production & Stock')} (${data['ym']})',
            child: AppDataTable(
              columns: const ['Product', 'Projection', 'Opening', 'Actual', 'Opening+Actual', '%Adherence', 'Closing'],
              rows: [
                for (final t in top)
                  [
                    t['name'] == 'Total'
                        ? const Text('Total', style: TextStyle(fontWeight: FontWeight.w800))
                        : Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    t['name'] == 'Total' ? qtyInt(t['projection']) : edit('proj:${t['productId']}', (t['projection'] as num?) ?? 0, '${t['name']} — Projection'),
                    t['name'] == 'Total' ? qtyInt(t['opening']) : edit('open:${t['productId']}', (t['opening'] as num?) ?? 0, '${t['name']} — Opening (last month closing + Neemrana/Matiala stock)'),
                    t['name'] == 'Total' ? qtyInt(t['actual']) : edit('act:${t['productId']}', (t['actual'] as num?) ?? 0, '${t['name']} — Actual production (month total)'),
                    qtyInt(t['openingActual']),
                    ((t['adherence'] as num?) ?? 0).toStringAsFixed(1),
                    t['name'] == 'Total' ? '' : edit('close:${t['productId']}', num.tryParse('${t['closing']}') ?? 0, '${t['name']} — Closing'),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final s in sections) ...[
            SectionCard(
              title: '${s['name']}',
              child: AppDataTable(
                columns: const ['Material', 'CB', 'Extra', 'Total used', 'Loss %'],
                rows: [
                  for (final r in (s['rows'] as List).cast<Map<String, dynamic>>())
                    [
                      '${r['name']}',
                      edit('cb:${s['productId']}:${r['materialId']}', (r['cb'] as num?) ?? 0, '${r['name']} — CB (as per BOM × production)'),
                      edit('extra:${s['productId']}:${r['materialId']}', (r['extra'] as num?) ?? 0, '${r['name']} — Extra (manual consumption)'),
                      qty(r['total']),
                      Text('${((r['lossPct'] as num?) ?? 0).toStringAsFixed(2)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: ((r['lossPct'] as num?) ?? 0) > 2 ? AppColors.red : AppColors.green,
                          )),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'CB = BOM × month production (sare batch codes da jod) · Extra = manual Record Consumption entries · Loss% = Extra ÷ CB. Har number edit ho sakda (product name nahi). Close month: export pehla, fer closing → next month opening.',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ]);
      },
    );
  }
}
