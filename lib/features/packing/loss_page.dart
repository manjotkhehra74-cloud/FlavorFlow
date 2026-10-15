import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../core/platform_support.dart';
import '../../ui/widgets.dart';
import '../../ui/windows_widgets.dart';
import '../reports/report_pdf.dart';

num _lossNumber(Object? value) => value is num ? value : num.tryParse('${value ?? ''}') ?? 0;

num _lossClosingTotal(List<Map<String, dynamic>> top) => top
    .where((row) => row['productId'] != 0)
    .fold<num>(0, (sum, row) => sum + _lossNumber(row['closing']));

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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (key.startsWith('act:'))
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Saving Actual recalculates this product’s BOM-based material CB and resets any manual CB overrides for this product.',
                ),
              ),
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('Value')),
            ),
          ],
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
      final columns = ['Product / Material', 'Projection·${U.cb}', 'Opening·Extra', 'Actual·Total', 'Op+Act·Loss%', '%Adh', 'Closing'];
      final rows = <List<dynamic>>[];
      final top = (data['top'] as List).cast<Map<String, dynamic>>();
      final closingTotal = _lossClosingTotal(top);
      for (final t in top) {
        final closing = t['productId'] == 0
            ? (num.tryParse('${t['closing']}') ?? closingTotal)
            : t['closing'];
        rows.add([t['name'], t['projection'], t['opening'], t['actual'], t['openingActual'], ((t['adherence'] as num?) ?? 0).toStringAsFixed(1), closing]);
      }
      // Per-product material blocks as proper PDF sections: heading stays with
      // its rows across page breaks, and pages pack fully (no half-empty pages).
      final sections = <PdfSection>[
        for (final s in (data['sections'] as List).cast<Map<String, dynamic>>())
          PdfSection(
            title: '${s['name']}',
            columns: [U.cb, 'Extra', 'Total used', 'Loss%'],
            rows: [
              for (final r in (s['rows'] as List).cast<Map<String, dynamic>>())
                [r['name'], r['cb'], r['extra'], r['total'], '${((r['lossPct'] as num?) ?? 0).toStringAsFixed(2)}%'],
            ],
          ),
      ];
      final bytes = await ReportPdf.build(
        title: 'Packing Loss% — $ym',
        desc: 'Projection vs production, ${U.cb} (as per BOM) vs Extra (manual consumption), Loss% per material.',
        columns: columns,
        rows: rows,
        sections: sections,
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
    final canManage = context.watch<AuthController>().canOr('loss.manage', 'packing.manage');
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final data = snap.data!;
        final top = (data['top'] as List).cast<Map<String, dynamic>>();
        final closingTotal = _lossClosingTotal(top);
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

        final monthPicker = DropdownButton<String>(
          value: _viewYm,
          hint: Text(tr('Current month')),
          items: [
            DropdownMenuItem<String>(value: null, child: Text(tr('Current month'))),
            for (final a in archives) DropdownMenuItem(value: a, child: Text(a)),
          ],
          onChanged: (v) {
            // Wait until the menu route is closed before replacing the report.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() { _viewYm = v; _future = _load(); });
            });
          },
        );
        final exportButton = OutlinedButton.icon(
          onPressed: _busy ? null : () => _export(data, pdf: true),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
          label: Text(tr('Export PDF')),
        );
        final closeButton = FilledButton.icon(
          onPressed: !canEdit || _busy ? null : () => _closeMonth(data),
          icon: const Icon(Icons.lock_clock_rounded, size: 17),
          label: Text(tr('Close month')),
        );
        final productionCard = SectionCard(
          title: '${tr('Production & Stock')} (${data['ym']})',
          child: AppDataTable(
            columns: const ['Product', 'Projection', 'Opening', 'Actual', 'Opening+Actual', '%Adherence', 'Closing'],
            rows: [
              for (final t in top)
                [
                  t['name'] == 'Total'
                      ? Text(tr('Total'), style: const TextStyle(fontWeight: FontWeight.w800))
                      : Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  t['name'] == 'Total' ? qtyInt(t['projection']) : edit('proj:${t['productId']}', (t['projection'] as num?) ?? 0, '${t['name']} — Projection'),
                  t['name'] == 'Total' ? qtyInt(t['opening']) : edit('open:${t['productId']}', (t['opening'] as num?) ?? 0, '${t['name']} — Opening (last month closing + depot stock)'),
                  t['name'] == 'Total' ? qtyInt(t['actual']) : edit('act:${t['productId']}', (t['actual'] as num?) ?? 0, '${t['name']} — Actual production (month total)'),
                  qtyInt(t['openingActual']),
                  ((t['adherence'] as num?) ?? 0).toStringAsFixed(1),
                  t['name'] == 'Total'
                      ? qtyInt(num.tryParse('${t['closing']}') ?? closingTotal)
                      : edit('close:${t['productId']}', num.tryParse('${t['closing']}') ?? 0, '${t['name']} — Closing'),
                ],
            ],
          ),
        );
        final materialCards = <Widget>[
          for (final s in sections)
            SectionCard(
              title: '${s['name']}',
              child: AppDataTable(
                columns: ['Material', U.cb, 'Extra', 'Total used', 'Loss %'],
                rows: [
                  for (final r in (s['rows'] as List).cast<Map<String, dynamic>>())
                    [
                      '${r['name']}',
                      edit('cb:${s['productId']}:${r['materialId']}', (r['cb'] as num?) ?? 0, '${r['name']} — ${U.cb} (as per BOM × production)'),
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
        ];
        final explanation = Text(
          '${U.cb} = BOM × displayed Actual production (manual override included; tray use stays per recorded trays) · Extra = manual Extra Consumption entries · Loss% = Extra ÷ ${U.cb}. Har number edit ho sakda (product name nahi). Close month: export pehla, fer closing → next month opening.',
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        );

        if (isWindowsPlatform) {
          return WindowsDocumentWorkspace(
            title: 'Packing Loss %',
            subtitle: '${tr('Production & Stock')} · ${_isArchive ? tr('Archived month') : tr('Current month')}',
            icon: Icons.percent_rounded,
            commandBar: WindowsCommandStrip(children: [
              Text('${tr('Month')}: ${data['ym']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (archives.isNotEmpty || _isArchive) monthPicker,
              exportButton,
              if (canEdit) closeButton,
            ]),
            content: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1120;
              return ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Row(children: [
                    Expanded(child: _lossMetric(label: 'Products', value: '${top.where((r) => r['name'] != 'Total').length}', icon: Icons.inventory_2_outlined)),
                    const SizedBox(width: 8),
                    Expanded(child: _lossMetric(label: 'Actual production', value: qtyInt(top.where((r) => r['name'] != 'Total').fold<num>(0, (sum, r) => sum + _lossNumber(r['actual']))), icon: Icons.factory_outlined)),
                    const SizedBox(width: 8),
                    Expanded(child: _lossMetric(label: 'Closing total', value: qty(closingTotal), icon: Icons.warehouse_outlined)),
                  ]),
                  const SizedBox(height: 12),
                  productionCard,
                  const SizedBox(height: 10),
                  if (wide)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 7, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final card in materialCards) ...[card, const SizedBox(height: 10)]])),
                      const SizedBox(width: 12),
                      Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SectionCard(title: tr('Calculation notes'), child: explanation),
                        const SizedBox(height: 10),
                        SectionCard(
                          title: tr('Month status'),
                          child: Text(_isArchive ? tr('This month is archived. Values are read-only.') : tr('This is the current open month.'),
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                        ),
                      ])),
                    ])
                  else ...[
                    for (final card in materialCards) ...[card, const SizedBox(height: 10)],
                    SectionCard(title: tr('Calculation notes'), child: explanation),
                  ],
                ],
              );
            }),
          );
        }

        return ListView(padding: const EdgeInsets.all(18), children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${tr('Month')}: ${data['ym']}${_isArchive ? '  (archived)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (archives.isNotEmpty || _isArchive) monthPicker,
            exportButton,
            if (canEdit) closeButton,
          ]),
          const SizedBox(height: 12),
          productionCard,
          const SizedBox(height: 14),
          for (final card in materialCards) ...[card, const SizedBox(height: 12)],
          explanation,
        ]);
      },
    );
  }

  Widget _lossMetric({required String label, required String value, required IconData icon}) => Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFF2F5F8), border: Border.all(color: const Color(0xFFC7D1DB))),
        child: Row(children: [
          Icon(icon, size: 17, color: const Color(0xFF214E6B)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF627588))),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF26394A))),
          ])),
        ]),
      );
}
