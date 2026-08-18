import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/download.dart';
import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import '../reports/report_pdf.dart';
import 'stock_pdf.dart';

/// Inventory — finished goods stock (cartons + trays) with low-stock highlighting.
/// Deep link target for low-stock notifications (?filter=low).
class InventoryPage extends StatefulWidget {
  final bool lowOnly;
  const InventoryPage({super.key, this.lowOnly = false});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late bool _lowOnly;
  bool _first = true;
  Future<Map<String, dynamic>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_first) {
      _lowOnly = widget.lowOnly;
      _future = _load();
      _first = false;
    }
  }

  Future<Map<String, dynamic>> _load() async {
    final json = await context.read<AuthController>().api.get('/inventory${_lowOnly ? '?filter=low' : ''}');
    return (json as Map).cast<String, dynamic>();
  }

  void _reload() => setState(() => _future = _load());

  bool _exporting = false;

  Future<void> _exportExcel() async {
    setState(() => _exporting = true);
    try {
      final bytes = await context.read<AuthController>().api.getBytes('/inventory/stock.xlsx');
      downloadBytes('flavorflow-stock-${todayYmd()}.xlsx', bytes,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final json = await context.read<AuthController>().api.get('/inventory');
      final m = (json as Map).cast<String, dynamic>();
      final bytes = await StockPdf.build(
        (m['items'] as List).cast<Map<String, dynamic>>(),
        (m['summary'] as Map).cast<String, dynamic>(),
      );
      await Printing.sharePdf(bytes: bytes, filename: 'flavorflow-stock-${todayYmd()}.pdf');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = (snap.data!['items'] as List).cast<Map<String, dynamic>>();
        final s = (snap.data!['summary'] as Map).cast<String, dynamic>();
        return ListView(padding: const EdgeInsets.all(20), children: [
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth > 1000 ? 4 : 2;
            final ratio = ((c.maxWidth - (cols - 1) * 12) / cols / 84).clamp(1.6, 5.0);
            return GridView.count(
              crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: ratio,
              children: [
                KpiCard(label: 'Stock on Hand (${U.cb})', value: qtyInt(s['total_cb']), icon: Icons.warehouse_rounded, tint: AppColors.cyan),
                KpiCard(label: '${U.tray} on Hand', value: qtyInt(s['total_trays']), icon: Icons.dinner_dining_rounded, tint: AppColors.teal),
                KpiCard(label: 'Total ${U.piece}', value: qtyInt(s['total_bottles']), icon: Icons.liquor_rounded, tint: AppColors.blue),
                KpiCard(label: 'Low Stock Items', value: qtyInt(s['low_count']), icon: Icons.warning_amber_rounded, tint: AppColors.red),
              ],
            );
          }),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ChoiceChip(
              label: Text(tr('All products')),
              selected: !_lowOnly,
              onSelected: (_) => setState(() { _lowOnly = false; _future = _load(); }),
            ),
            ChoiceChip(
              label: Text(tr('Low stock only')),
              selected: _lowOnly,
              avatar: const Icon(Icons.warning_amber_rounded, size: 16),
              onSelected: (_) => setState(() { _lowOnly = true; _future = _load(); }),
            ),
            if (auth.can('inventory.manage'))
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilledButton.icon(
                  onPressed: () async {
                    final saved = await showDialog<bool>(context: context, builder: (_) => const ReceiptDialog());
                    if (saved == true) _reload();
                  },
                  icon: const Icon(Icons.add_box_outlined, size: 19),
                  label: Text(tr('Receive Stock')),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _exporting ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(tr('Stock PDF')),
            ),
            OutlinedButton.icon(
              onPressed: _exporting ? null : _exportExcel,
              icon: const Icon(Icons.table_view_outlined, size: 18),
              label: Text(tr('Stock Excel')),
            ),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: _lowOnly ? 'Low Stock Products' : 'Stock on Hand',
            child: items.isEmpty
                ? EmptyState(_lowOnly ? 'No products below minimum stock 🎉' : 'No inventory yet')
                : AppDataTable(
                    columns: ['Product', '${U.carton} (${U.cb})', U.tray, 'Total ${U.piece}', 'Gross kg', 'Min (${U.cb})', 'Status', ''],
                    rows: [
                      for (final it in items)
                        [
                          Text(it['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                          qtyInt(it['qty_cb']),
                          qtyInt(it['qty_trays']),
                          qtyInt(it['total_bottles']),
                          qty(it['gross_kg']),
                          qtyInt(it['min_stock_cb']),
                          (it['low'] as int) == 1
                              ? const StatusChip('LOW')
                              : const StatusChip('IN STOCK'),
                          if (auth.can('inventory.manage'))
                            IconButton(
                              tooltip: 'Set exact stock',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () async {
                                final saved = await showDialog<bool>(context: context, builder: (_) => SetStockDialog(item: it));
                                if (saved == true) _reload();
                              },
                            )
                          else
                            const SizedBox.shrink(),
                        ],
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          // Batch-wise stock (factory register style) below Stock on Hand.
          const _BatchStockSection(),
        ]);
      },
    );
  }
}

/// Batch-wise Stock on the Inventory page — same server report the Reports
/// section uses: product header rows, batches oldest-first, per-product
/// TOTAL and GRAND TOTAL. Own PDF/Excel export buttons.
class _BatchStockSection extends StatefulWidget {
  const _BatchStockSection();
  @override
  State<_BatchStockSection> createState() => _BatchStockSectionState();
}

class _BatchStockSectionState extends State<_BatchStockSection> {
  late Future<Map<String, dynamic>> _future;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final json = await context.read<AuthController>().api.get('/reports/batch-stock');
    return (json as Map).cast<String, dynamic>();
  }

  Future<void> _export(Map<String, dynamic> data, {required bool pdf}) async {
    setState(() => _exporting = true);
    try {
      final date = todayYmd();
      if (pdf) {
        final bytes = await ReportPdf.build(
          title: data['title'] as String? ?? 'Batch-wise Stock',
          desc: data['desc'] as String? ?? '',
          columns: (data['columns'] as List).cast<String>(),
          rows: (data['rows'] as List).map((r) => (r as List).cast<dynamic>()).toList(),
        );
        await Printing.sharePdf(bytes: bytes, filename: 'flavorflow-batch-stock-$date.pdf');
      } else {
        final bytes = await context.read<AuthController>().api.getBytes('/reports/batch-stock.xlsx');
        downloadBytes('flavorflow-batch-stock-$date.xlsx', bytes,
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        if (mounted) showOk(context, 'Excel file downloaded.');
      }
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return SectionCard(
            title: 'Batch-wise Stock',
            child: ErrorState(snap.error!, onRetry: () => setState(() => _future = _load())),
          );
        }
        if (!snap.hasData) {
          return const SectionCard(
            title: 'Batch-wise Stock',
            child: SizedBox(height: 70, child: Center(child: CircularProgressIndicator())),
          );
        }
        final data = snap.data!;
        final columns = (data['columns'] as List).cast<String>();
        final rows = (data['rows'] as List).map((r) => (r as List).cast<dynamic>()).toList();
        return SectionCard(
          title: 'Batch-wise Stock',
          trailing: Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: _exporting ? null : () => _export(data, pdf: true),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: Text(tr('PDF')),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB91C1C),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: const Size(0, 32),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _exporting ? null : () => _export(data, pdf: false),
              icon: const Icon(Icons.table_view_outlined, size: 16),
              label: Text(tr('Excel')),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF047857),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: const Size(0, 32),
              ),
            ),
          ]),
          child: rows.isEmpty
              ? const EmptyState('No completed batches with remaining stock')
              : AppDataTable(
                  columns: columns,
                  rows: [
                    for (final r in rows)
                      [
                        // product headers / totals bold, batch rows normal
                        r[0].toString().startsWith('▶') || r[0] == 'TOTAL' || r[0] == 'GRAND TOTAL'
                            ? Text('${r[0]}', style: const TextStyle(fontWeight: FontWeight.w800))
                            : '${r[0]}',
                        for (var c = 1; c < r.length; c++) r[c],
                      ],
                  ],
                ),
        );
      },
    );
  }
}

/// Set exact stock (opening stock / correction) — replaces current quantities.
class SetStockDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  const SetStockDialog({super.key, required this.item});
  @override
  State<SetStockDialog> createState() => _SetStockDialogState();
}

class _SetStockDialogState extends State<SetStockDialog> {
  late final TextEditingController cb = TextEditingController(text: '${widget.item['qty_cb']}');
  late final TextEditingController trays = TextEditingController(text: '${widget.item['qty_trays']}');
  final note = TextEditingController();
  bool busy = false;

  bool get _hasTray => (widget.item['bottles_per_tray'] as num? ?? 0) > 0;

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.put('/inventory/stock', {
        'productId': widget.item['product_id'],
        'qtyCb': int.tryParse(cb.text) ?? 0,
        'qtyTrays': _hasTray ? (int.tryParse(trays.text) ?? 0) : 0,
        'note': note.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Set Stock — ${widget.item['name']}'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Current: ${qtyInt(widget.item['qty_cb'])} CB + ${qtyInt(widget.item['qty_trays'])} trays. Enter the exact real stock below — it replaces the current numbers.',
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: TextField(controller: cb, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('${U.carton} (${U.cb}) *')))),
            if (_hasTray) ...[
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: trays, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: U.tray))),
            ],
          ]),
          const SizedBox(height: 12),
          TextField(controller: note, decoration: InputDecoration(labelText: tr('Note (optional)'), hintText: 'e.g. Opening stock 04 Aug 2026')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Set Stock')),
      ],
    );
  }
}

class ReceiptDialog extends StatefulWidget {
  const ReceiptDialog({super.key});
  @override
  State<ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<ReceiptDialog> {
  List<Map<String, dynamic>> products = [];
  int? productId;
  final cb = TextEditingController();
  final trays = TextEditingController();
  final note = TextEditingController();
  bool busy = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    context.read<AuthController>().api.get('/products').then((json) {
      setState(() {
        products = ((json as Map)['products'] as List).cast<Map<String, dynamic>>();
        productId = products.isNotEmpty ? products.first['id'] as int : null;
      });
    }).catchError((e) {
      setState(() => loadError = '$e');
    });
  }

  Map<String, dynamic>? get _product =>
      productId == null ? null : products.firstWhere((p) => p['id'] == productId, orElse: () => products.first);

  bool get _hasTray => (_product?['bottles_per_tray'] as num? ?? 0) > 0;

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.post('/inventory/receipt', {
        'productId': productId,
        'qtyCb': int.tryParse(cb.text) ?? 0,
        if (_hasTray) 'qtyTrays': int.tryParse(trays.text) ?? 0,
        'note': note.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Receive Stock')),
      content: SizedBox(
        width: 400,
        child: loadError != null
            ? Text(loadError!)
            : products.isEmpty
                ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<int>(
                      initialValue: productId,
                      decoration: InputDecoration(labelText: tr('Product *')),
                      items: [for (final p in products) DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String))],
                      onChanged: (v) => setState(() => productId = v),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: TextField(controller: cb, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('${U.carton} (${U.cb})')))),
                      if (_hasTray) ...[
                        const SizedBox(width: 12),
                        Expanded(child: TextField(controller: trays, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: U.tray))),
                      ],
                    ]),
                    if (_hasTray)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('1 tray = ${_product!['bottles_per_tray']} bottles',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(controller: note, decoration: InputDecoration(labelText: tr('Note (optional)'))),
                  ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Receive')),
      ],
    );
  }
}
