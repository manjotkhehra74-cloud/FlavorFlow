import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// Product Master — Finished Goods with exact spec data (carton & tray packing).
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final json = await context.read<AuthController>().api.get('/products');
    return ((json as Map)['products'] as List).cast<Map<String, dynamic>>();
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canManage = auth.can('products.manage');
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final products = snap.data!;
        return ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            Expanded(
              child: Text('${products.length} finished goods · carton & tray weights, bottle packing',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            if (canManage)
              FilledButton.icon(
                onPressed: () async {
                  final saved = await showDialog<bool>(context: context, builder: (_) => const ProductFormDialog());
                  if (saved == true) _reload();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Product'),
              ),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Finished Goods Master',
            child: AppDataTable(
              columns: const ['Product', 'Wt per CB (kg)', 'Wt w/o CB (kg)', 'Bottles / CB', 'Bottles / Tray', 'Tray Wt (kg)', 'Min Stock (CB)', 'Stock (CB)', 'Trays', ''],
              rows: [
                for (var i = 0; i < products.length; i++)
                  [
                    Text(products[i]['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    qty(products[i]['weight_per_cb']),
                    qty(products[i]['weight_without_cb']),
                    qtyInt(products[i]['bottles_per_cb']),
                    (products[i]['bottles_per_tray'] as num) > 0 ? qtyInt(products[i]['bottles_per_tray']) : '—',
                    (products[i]['bottles_per_tray'] as num) > 0 ? qty(products[i]['tray_weight']) : '—',
                    qtyInt(products[i]['min_stock_cb']),
                    qtyInt(products[i]['qty_cb']),
                    qtyInt(products[i]['qty_trays']),
                    if (canManage)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 19),
                        tooltip: 'Edit',
                        onPressed: () async {
                          final saved = await showDialog<bool>(context: context, builder: (_) => ProductFormDialog(product: products[i]));
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

class ProductFormDialog extends StatefulWidget {
  final Map<String, dynamic>? product;
  const ProductFormDialog({super.key, this.product});
  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  late final TextEditingController name = TextEditingController(text: widget.product?['name']?.toString() ?? '');
  late final TextEditingController wcb = TextEditingController(text: widget.product?['weight_per_cb']?.toString() ?? '');
  late final TextEditingController wncb = TextEditingController(text: widget.product?['weight_without_cb']?.toString() ?? '');
  late final TextEditingController bpc = TextEditingController(text: widget.product?['bottles_per_cb']?.toString() ?? '');
  late final TextEditingController bpt = TextEditingController(
      text: (widget.product?['bottles_per_tray'] as num?) == 0 ? '' : widget.product?['bottles_per_tray']?.toString() ?? '');
  late final TextEditingController trayWt = TextEditingController(
      text: (widget.product?['tray_weight'] as num?) == 0 ? '' : widget.product?['tray_weight']?.toString() ?? '');
  late final TextEditingController minStock = TextEditingController(text: widget.product?['min_stock_cb']?.toString() ?? '0');
  bool busy = false;

  Future<void> _save() async {
    setState(() => busy = true);
    final api = context.read<AuthController>().api;
    final body = {
      'name': name.text.trim(),
      'weightPerCb': num.tryParse(wcb.text) ?? 0,
      'weightWithoutCb': num.tryParse(wncb.text) ?? 0,
      'bottlesPerCb': int.tryParse(bpc.text) ?? 0,
      'bottlesPerTray': int.tryParse(bpt.text) ?? 0,
      'trayWeight': num.tryParse(trayWt.text) ?? 0,
      'minStockCb': int.tryParse(minStock.text) ?? 0,
    };
    try {
      if (widget.product == null) {
        await api.post('/products', body);
      } else {
        await api.put('/products/${widget.product!['id']}', body);
      }
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
      title: Text(widget.product == null ? 'Add Product' : 'Edit Product'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Product name *')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: wcb, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Weight per CB (kg) *'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: wncb, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Weight w/o CB (kg) *'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: bpc, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bottles per CB *'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: minStock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Min stock (CB)'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: bpt, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bottles per tray (0 = no tray)'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: trayWt, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tray weight (kg)'))),
          ]),
          const SizedBox(height: 8),
          Text('Only Soya 740gm, Vinegar 610ml (white & brown), Soya 1.3kg and Vinegar 1.0 are tray-packed. Leave tray fields empty for others.',
              style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')),
      ],
    );
  }
}
