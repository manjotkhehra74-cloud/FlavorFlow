import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/industry_pack.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import '../billing/item_history_page.dart' show showItemHistory;

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

  Future<void> _deleteProduct(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Delete ${p['name']}?'),
            content: const Text('The product will be removed from the Product Master, all dropdowns AND its stock will be removed from Inventory.\n\nPast dispatches, batches and reports that used it are kept unchanged.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    try {
      await context.read<AuthController>().api.delete('/products/${p['id']}');
      if (mounted) {
        showOk(context, '${p['name']} deleted.');
        _reload();
      }
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

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
              child: Text('${products.length} ${tr('finished goods')} · ${U.carton.toLowerCase()} ${CompanyProfile.usesTrays ? '& ${U.trayLc} ' : ''}${tr('weights')}, ${U.piece.toLowerCase()} ${tr('packing')}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            if (auth.canManageBilling)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final saved = await showDialog<bool>(context: context, builder: (_) => ProductRatesDialog(products: products));
                    if (saved == true) _reload();
                  },
                  icon: const Icon(Icons.currency_rupee_rounded, size: 18),
                  label: Text(tr('Rates & GST')),
                ),
              ),
            if (canManage)
              FilledButton.icon(
                onPressed: () async {
                  final saved = await showDialog<bool>(context: context, builder: (_) => const ProductFormDialog());
                  if (saved == true) _reload();
                },
                icon: const Icon(Icons.add_rounded),
                label: Text(tr('Add Product')),
              ),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: IndustryPack.current.productsTitle,
            child: AppDataTable(
              columns: ['Product', 'Wt per ${U.cb} (kg)', 'Wt w/o ${U.cb} (kg)', '${U.piece} / ${U.cb}', if (CompanyProfile.usesTrays) '${U.piece} / ${U.tray}', if (CompanyProfile.usesTrays) '${U.tray} Wt (kg)', 'Min Stock (${U.cb})', 'Stock (${U.cb})', if (CompanyProfile.usesTrays) U.tray, ''],
              rows: [
                for (var i = 0; i < products.length; i++)
                  [
                    Text(products[i]['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    qty(products[i]['weight_per_cb']),
                    qty(products[i]['weight_without_cb']),
                    qtyInt(products[i]['bottles_per_cb']),
                    if (CompanyProfile.usesTrays) (products[i]['bottles_per_tray'] as num) > 0 ? qtyInt(products[i]['bottles_per_tray']) : '—',
                    if (CompanyProfile.usesTrays) (products[i]['bottles_per_tray'] as num) > 0 ? qty(products[i]['tray_weight']) : '—',
                    qtyInt(products[i]['min_stock_cb']),
                    qtyInt(products[i]['qty_cb']),
                    if (CompanyProfile.usesTrays) qtyInt(products[i]['qty_trays']),
                    if (canManage || auth.canViewBilling)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (auth.canViewBilling)
                          IconButton(
                            icon: const Icon(Icons.history_rounded, size: 19),
                            tooltip: tr('Stock ledger (all in / out with doc numbers)'),
                            onPressed: () => showItemHistory(context, type: 'product', id: products[i]['id'] as int, name: products[i]['name'] as String),
                          ),
                        if (canManage)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 19),
                          tooltip: 'Edit',
                          onPressed: () async {
                            final saved = await showDialog<bool>(context: context, builder: (_) => ProductFormDialog(product: products[i]));
                            if (saved == true) _reload();
                          },
                        ),
                        if (canManage)
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded, size: 19, color: Theme.of(context).colorScheme.error),
                          tooltip: 'Delete',
                          onPressed: () => _deleteProduct(products[i]),
                        ),
                      ])
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
      'bottlesPerTray': CompanyProfile.usesTrays ? (int.tryParse(bpt.text) ?? 0) : 0,
      'trayWeight': CompanyProfile.usesTrays ? (num.tryParse(trayWt.text) ?? 0) : 0,
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
          TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Product name *'), hintText: IndustryPack.eg(IndustryPack.current.productExamples))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: wcb, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Weight per ${U.cb} (kg) *')))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: wncb, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Weight w/o ${U.cb} (kg) *')))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: bpc, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('${U.piece} per ${U.cb} *')))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: minStock, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Min stock (${U.cb})')))),
          ]),
          if (CompanyProfile.usesTrays) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: bpt, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('${U.piece} per ${U.trayLc} (0 = no ${U.trayLc})')))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: trayWt, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('${U.tray} weight (kg)')))),
            ]),
          ],
          const SizedBox(height: 8),
          Text(IndustryPack.current.productNote,
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

/// Billing master per product: HSN code, GST %, sale rate (per pack or per
/// piece). Saved through the billing module — the invoice form and the
/// dispatch → invoice prefill read these.
class ProductRatesDialog extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  const ProductRatesDialog({super.key, required this.products});
  @override
  State<ProductRatesDialog> createState() => _ProductRatesDialogState();
}

class _ProductRatesDialogState extends State<ProductRatesDialog> {
  static const slabs = <num>[0, 5, 18, 40, 12, 28];
  List<Map<String, dynamic>> rows = [];
  final hsn = <int, TextEditingController>{};
  final rate = <int, TextEditingController>{};
  final gst = <int, num>{};
  final per = <int, String>{};
  bool loading = true, busy = false;
  String? error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { for (final c in [...hsn.values, ...rate.values]) { c.dispose(); } super.dispose(); }

  Future<void> _load() async {
    try {
      final j = await context.read<AuthController>().api.get('/billing/products');
      rows = ((j as Map)['products'] as List).cast<Map<String, dynamic>>();
      for (final p in rows) {
        final id = p['id'] as int;
        hsn[id] = TextEditingController(text: (p['hsn_code'] ?? '').toString());
        final sr = (p['sale_rate'] as num?) ?? 0;
        rate[id] = TextEditingController(text: sr == 0 ? '' : (sr == sr.roundToDouble() ? sr.toInt().toString() : sr.toString()));
        final g = p['gst_rate'] as num?;
        gst[id] = g != null && slabs.contains(g) ? g : 5;
        per[id] = p['rate_per'] == 'piece' ? 'piece' : 'pack';
      }
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    setState(() => busy = true);
    final api = context.read<AuthController>().api;
    var n = 0;
    try {
      for (final p in rows) {
        final id = p['id'] as int;
        final h = hsn[id]!.text.trim(), r = num.tryParse(rate[id]!.text.trim()) ?? 0;
        final changed = h != (p['hsn_code'] ?? '').toString() || r != ((p['sale_rate'] as num?) ?? 0) || gst[id] != (p['gst_rate'] as num?) || per[id] != (p['rate_per'] ?? 'pack');
        if (!changed) continue;
        await api.put('/billing/products/$id/rates', {'hsnCode': h, 'gstRate': gst[id], 'saleRate': r, 'ratePer': per[id]});
        n++;
      }
      if (mounted) { showOk(context, '$n ${tr('products updated')}'); Navigator.pop(context, true); }
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    return AlertDialog(
      title: Text(tr('Rates & GST (for invoices)')),
      content: SizedBox(
        width: 720,
        height: 460,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? ErrorState(error!, onRetry: () { setState(() { loading = true; error = null; }); _load(); })
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('HSN code and GST % print on every tax invoice. GST 2.0 slabs: 0 / 5 / 18 / 40 (12 and 28 marked * are legacy). Sale rate is the default — it can be changed on each invoice.'), style: TextStyle(fontSize: 12.5, color: sub)),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (context, index) => const Divider(height: 14),
                        itemBuilder: (_, i) {
                          final p = rows[i];
                          final id = p['id'] as int;
                          return Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            SizedBox(width: 200, child: Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: 100, child: TextField(controller: hsn[id], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'HSN', isDense: true))),
                            SizedBox(
                              width: 100,
                              child: DropdownButtonFormField<num>(
                                initialValue: gst[id],
                                decoration: const InputDecoration(labelText: 'GST %', isDense: true),
                                items: [for (final g in slabs) DropdownMenuItem(value: g, child: Text('$g%${g == 12 || g == 28 ? ' *' : ''}'))],
                                onChanged: (v) => setState(() => gst[id] = v ?? 5),
                              ),
                            ),
                            SizedBox(width: 110, child: TextField(controller: rate[id], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: '${tr('Rate')} ₹', isDense: true))),
                            SizedBox(
                              width: 150,
                              child: DropdownButtonFormField<String>(
                                initialValue: per[id],
                                isExpanded: true,
                                decoration: InputDecoration(labelText: tr('per'), isDense: true),
                                items: [
                                  DropdownMenuItem(value: 'pack', child: Text(U.cb)),
                                  DropdownMenuItem(value: 'piece', child: Text('${U.piece} (${qtyInt(p['bottles_per_cb'])}/${U.cb})', overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (v) => setState(() => per[id] = v ?? 'pack'),
                              ),
                            ),
                          ]);
                        },
                      ),
                    ),
                  ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Close'))),
        FilledButton(onPressed: busy || loading || error != null ? null : _save, child: Text(busy ? tr('Saving…') : tr('Save rates'))),
      ],
    );
  }
}
