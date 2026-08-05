import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/download.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
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
                KpiCard(label: 'Stock on Hand (CB)', value: qtyInt(s['total_cb']), icon: Icons.warehouse_rounded, tint: AppColors.cyan),
                KpiCard(label: 'Trays on Hand', value: qtyInt(s['total_trays']), icon: Icons.dinner_dining_rounded, tint: AppColors.teal),
                KpiCard(label: 'Total Bottles', value: qtyInt(s['total_bottles']), icon: Icons.liquor_rounded, tint: AppColors.blue),
                KpiCard(label: 'Low Stock Items', value: qtyInt(s['low_count']), icon: Icons.warning_amber_rounded, tint: AppColors.red),
              ],
            );
          }),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ChoiceChip(
              label: const Text('All products'),
              selected: !_lowOnly,
              onSelected: (_) => setState(() { _lowOnly = false; _future = _load(); }),
            ),
            ChoiceChip(
              label: const Text('Low stock only'),
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
                  label: const Text('Receive Stock'),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _exporting ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Stock PDF'),
            ),
            OutlinedButton.icon(
              onPressed: _exporting ? null : _exportExcel,
              icon: const Icon(Icons.table_view_outlined, size: 18),
              label: const Text('Stock Excel'),
            ),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: _lowOnly ? 'Low Stock Products' : 'Stock on Hand',
            child: items.isEmpty
                ? EmptyState(_lowOnly ? 'No products below minimum stock 🎉' : 'No inventory yet')
                : AppDataTable(
                    columns: const ['Product', 'Cartons (CB)', 'Trays', 'Total Bottles', 'Gross kg', 'Min (CB)', 'Status', ''],
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
        ]);
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
            Expanded(child: TextField(controller: cb, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cartons (CB) *'))),
            if (_hasTray) ...[
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: trays, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Trays'))),
            ],
          ]),
          const SizedBox(height: 12),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. Opening stock 04 Aug 2026')),
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
      title: const Text('Receive Stock'),
      content: SizedBox(
        width: 400,
        child: loadError != null
            ? Text(loadError!)
            : products.isEmpty
                ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<int>(
                      initialValue: productId,
                      decoration: const InputDecoration(labelText: 'Product *'),
                      items: [for (final p in products) DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String))],
                      onChanged: (v) => setState(() => productId = v),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: TextField(controller: cb, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cartons (CB)'))),
                      if (_hasTray) ...[
                        const SizedBox(width: 12),
                        Expanded(child: TextField(controller: trays, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Trays'))),
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
                    TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
                  ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Receive')),
      ],
    );
  }
}
