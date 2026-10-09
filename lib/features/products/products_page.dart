import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/industry_pack.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/item_code.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import '../billing/item_history_page.dart' show showItemHistory;
import 'import_dialog.dart';
import 'label_dialog.dart';

/// Product Master — Finished Goods with exact spec data (carton & tray packing).
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  final _q = TextEditingController();
  bool _lowOnly = false;
  bool _bomOnly = false;

  bool _hasBom(Map<String, dynamic> product) {
    final bom = product['bom'] ?? product['bomItems'] ?? product['bom_count'] ?? product['has_bom'];
    if (bom is List) return bom.isNotEmpty;
    if (bom is num) return bom > 0;
    return bom == true;
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final api = context.read<AuthController>().api;
    final json = await api.get('/products');
    final products = ((json as Map)['products'] as List)
        .cast<Map<String, dynamic>>()
        .where((p) => (p['active'] as num? ?? 1) != 0)
        .toList();

    // Load BOM mapping from /packing/bom to correctly show Linked status
    // The /products endpoint does not include BOM data, so we merge it here
    try {
      final bomJson = await api.get('/packing/bom');
      final bomList = ((bomJson as Map)['bom'] as List).cast<Map<String, dynamic>>();
      final bomProductIds = <int>{};
      final bomCounts = <int, int>{};
      for (final entry in bomList) {
        final prod = entry['product'] as Map?;
        final items = entry['items'] as List?;
        if (prod != null && prod['id'] is int) {
          final pid = prod['id'] as int;
          final count = items?.length ?? 0;
          if (count > 0) {
            bomProductIds.add(pid);
            bomCounts[pid] = count;
          }
        } else if (entry['product_id'] is int) {
          final pid = entry['product_id'] as int;
          final count = (entry['items'] as List?)?.length ?? (entry['count'] as int? ?? 0);
          if (count > 0) {
            bomProductIds.add(pid);
            bomCounts[pid] = count;
          }
        }
      }
      // Merge BOM info into products
      for (final p in products) {
        final pid = p['id'] as int?;
        if (pid != null && bomProductIds.contains(pid)) {
          p['has_bom'] = true;
          p['bom_count'] = bomCounts[pid] ?? 1;
          p['bom'] = List.filled(bomCounts[pid] ?? 1, {});
        }
      }
    } catch (_) {
      // If BOM fetch fails, keep products as is — will show Not linked (graceful)
    }

    return products;
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
        final all = snap.data!;
        final hasCodes = ItemCode.anyIn(all);
        final bomKnown = all.any((p) => p.containsKey('bom') || p.containsKey('bomItems') || p.containsKey('bom_count') || p.containsKey('has_bom'));
        final products = all.where((p) {
          if (!ItemCode.matches(p, _q.text)) return false;
          if (_lowOnly && !((p['min_stock_cb'] as num? ?? 0) > 0 && (p['qty_cb'] as num? ?? 0) <= (p['min_stock_cb'] as num? ?? 0))) return false;
          if (_bomOnly && !_hasBom(p)) return false;
          return true;
        }).toList();
        final bomCount = all.where(_hasBom).length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            _ProductOverview(total: all.length, bomCount: bomCount, bomKnown: bomKnown),
            const SizedBox(height: 14),
            TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: hasCodes ? tr('Search name / item code') : tr('Search product'),
                suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => setState(_q.clear)),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: Text(tr('All products')),
                selected: !_lowOnly && !_bomOnly,
                onSelected: (_) => setState(() { _lowOnly = false; _bomOnly = false; }),
              ),
              if (bomKnown)
                ChoiceChip(
                  label: Text(tr('With BOM')),
                  selected: _bomOnly,
                  avatar: const Icon(Icons.account_tree_outlined, size: 16),
                  onSelected: (_) => setState(() { _bomOnly = !_bomOnly; _lowOnly = false; }),
                ),
              ChoiceChip(
                label: Text(tr('Low stock')),
                selected: _lowOnly,
                avatar: const Icon(Icons.warning_amber_rounded, size: 16),
                onSelected: (_) => setState(() { _lowOnly = !_lowOnly; _bomOnly = false; }),
              ),
            ]),
            const SizedBox(height: 14),
            SectionCard(
              title: IndustryPack.current.productsTitle,
              trailing: Text('${products.length} ${tr('items')}'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (canManage)
                    FilledButton.icon(
                      onPressed: () async {
                        final saved = await showDialog<bool>(context: context, builder: (_) => const ProductFormDialog());
                        if (saved == true) _reload();
                      },
                      icon: const Icon(Icons.add_rounded, size: 19),
                      label: Text(tr('Add Product')),
                    ),
                  if (canManage)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final saved = await showImportDialog(context, ImportKind.products);
                        if (saved == true) _reload();
                      },
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: Text(tr('Import')),
                    ),
                  if (auth.canManageBilling)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final saved = await showDialog<bool>(context: context, builder: (_) => ProductRatesDialog(products: products));
                        if (saved == true) _reload();
                      },
                      icon: const Icon(Icons.currency_rupee_rounded, size: 18),
                      label: Text(tr('Rates & GST')),
                    ),
                  if (hasCodes)
                    OutlinedButton.icon(
                      onPressed: () => showLabelDialog(context, products),
                      icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                      label: Text(tr('Labels')),
                    ),
                ]),
                const SizedBox(height: 14),
                if (products.isEmpty)
                  EmptyState(_q.text.isEmpty && !_lowOnly && !_bomOnly ? tr('No products yet') : tr('No matching products'), icon: Icons.inventory_2_outlined)
                else
                  for (var i = 0; i < products.length; i++) ...[
                    _ProductTile(
                      product: products[i],
                      hasBom: _hasBom(products[i]),
                      canManage: canManage,
                      canViewHistory: auth.canViewBilling,
                      onHistory: () => showItemHistory(context, type: 'product', id: products[i]['id'] as int, name: products[i]['name'] as String),
                      onEdit: () async {
                        final saved = await showDialog<bool>(context: context, builder: (_) => ProductFormDialog(product: products[i]));
                        if (saved == true) _reload();
                      },
                      onDelete: () => _deleteProduct(products[i]),
                    ),
                    if (i != products.length - 1) const SizedBox(height: 10),
                  ],
              ]),
            ),
          ],
        );
      },
    );
  }
}

class _ProductOverview extends StatelessWidget {
  final int total;
  final int bomCount;
  final bool bomKnown;
  const _ProductOverview({required this.total, required this.bomCount, required this.bomKnown});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
      decoration: BoxDecoration(
        gradient: AppBrand.gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppBrand.blue.withValues(alpha: .18), blurRadius: 14, offset: const Offset(0, 7))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Product Master', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(IndustryPack.current.productsTitle, style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 13)),
        const SizedBox(height: 15),
        Row(children: [
          Expanded(child: _ProductOverviewMetric(label: tr('Active products'), value: qtyInt(total))),
          const SizedBox(width: 10),
          Expanded(child: _ProductOverviewMetric(label: tr('BOM linked'), value: bomKnown ? qtyInt(bomCount) : '—')),
        ]),
      ]),
    );
  }
}

class _ProductOverviewMetric extends StatelessWidget {
  final String label;
  final String value;
  const _ProductOverviewMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(11)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .84), fontSize: 10.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _ProductTile extends StatelessWidget {
  final Map<String, dynamic> product;
  final bool hasBom;
  final bool canManage;
  final bool canViewHistory;
  final VoidCallback? onHistory;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _ProductTile({required this.product, required this.hasBom, required this.canManage, required this.canViewHistory, this.onHistory, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final low = (product['min_stock_cb'] as num? ?? 0) > 0 && (product['qty_cb'] as num? ?? 0) <= (product['min_stock_cb'] as num? ?? 0);
    final accent = low ? AppColors.red : AppColors.green;
    final code = ItemCode.of(product);
    final pieces = qtyInt(product['bottles_per_cb']);
    final trays = (product['bottles_per_tray'] as num? ?? 0) > 0 ? qtyInt(product['bottles_per_tray']) : '';
    final packing = trays.isEmpty ? '$pieces / ${U.cb}' : '$pieces / ${U.cb} · $trays / ${U.trayLc}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 11),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: .06), blurRadius: 7, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 35, height: 35, decoration: BoxDecoration(color: accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)), child: Icon(Icons.inventory_2_outlined, color: accent, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product['name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 14, fontWeight: FontWeight.w800)),
            if (code.isNotEmpty) Text(code, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ])),
          if (canViewHistory) IconButton(visualDensity: VisualDensity.compact, tooltip: tr('Stock ledger'), onPressed: onHistory, icon: const Icon(Icons.history_rounded, size: 18)),
          if (canManage) IconButton(visualDensity: VisualDensity.compact, tooltip: tr('Edit'), onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 18)),
          if (canManage) IconButton(visualDensity: VisualDensity.compact, tooltip: tr('Delete'), onPressed: onDelete, icon: Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _ProductStat(label: tr('Stock on hand'), value: '${qtyInt(product['qty_cb'])} ${U.cb}', color: accent)),
          Expanded(child: _ProductStat(label: tr('Packing'), value: packing, color: scheme.onSurface)),
          Expanded(child: _ProductStat(label: tr('BOM'), value: hasBom ? tr('Linked') : tr('Not linked'), color: hasBom ? AppColors.green : scheme.onSurfaceVariant)),
        ]),
      ]),
    );
  }
}

class _ProductStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ProductStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
        ]),
      );
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
  late final TextEditingController wncb = TextEditingController(text: widget.product?['weight_without_cb']?.toString() ?? widget.product?['net_weight_per_cb']?.toString() ?? '');
  late final TextEditingController netFrom = TextEditingController(text: _dateValue('net_weight_effective_from', 'netWeightEffectiveFrom'));
  late final TextEditingController netTo = TextEditingController(text: _dateValue('net_weight_effective_to', 'netWeightEffectiveTo'));
  late final TextEditingController bpc = TextEditingController(text: widget.product?['bottles_per_cb']?.toString() ?? '');
  late final TextEditingController bpt = TextEditingController(
      text: (widget.product?['bottles_per_tray'] as num?) == 0 ? '' : widget.product?['bottles_per_tray']?.toString() ?? '');
  late final TextEditingController trayWt = TextEditingController(
      text: (widget.product?['tray_weight'] as num?) == 0 ? '' : widget.product?['tray_weight']?.toString() ?? '');
  late final TextEditingController minStock = TextEditingController(text: widget.product?['min_stock_cb']?.toString() ?? '0');
  late final TextEditingController code = TextEditingController(text: ItemCode.of(widget.product));
  bool busy = false;

  String _dateValue(String snake, String camel) {
    final value = widget.product?[snake] ?? widget.product?[camel];
    return value == null ? '' : '$value'.split(RegExp(r'[T ]')).first;
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final value = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (value != null) controller.text = '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    setState(() => busy = true);
    final api = context.read<AuthController>().api;
    final body = {
      'name': name.text.trim(),
      'weightPerCb': num.tryParse(wcb.text) ?? 0,
      // weightWithoutCb is the legacy API name for the net bottle weight.
      // Keep it for old servers, and send the explicit productivity name for
      // servers that support effective-dated weight configuration.
      'weightWithoutCb': num.tryParse(wncb.text) ?? 0,
      'netWeightPerCb': num.tryParse(wncb.text) ?? 0,
      'netWeightEffectiveFrom': netFrom.text.trim().isEmpty ? null : netFrom.text.trim(),
      'netWeightEffectiveTo': netTo.text.trim().isEmpty ? null : netTo.text.trim(),
      'bottlesPerCb': int.tryParse(bpc.text) ?? 0,
      'bottlesPerTray': CompanyProfile.usesTrays ? (int.tryParse(bpt.text) ?? 0) : 0,
      'trayWeight': CompanyProfile.usesTrays ? (num.tryParse(trayWt.text) ?? 0) : 0,
      'minStockCb': int.tryParse(minStock.text) ?? 0,
      'itemCode': ItemCode.normalize(code.text),
    };
    final fromDate = DateTime.tryParse(netFrom.text.trim());
    final toDate = DateTime.tryParse(netTo.text.trim());
    if (fromDate != null && toDate != null && toDate.isBefore(fromDate)) {
      showErr(context, 'Net weight effective-to date cannot be before effective-from date.');
      setState(() => busy = false);
      return;
    }
    final codeErr = ItemCode.validate(code.text);
    if (codeErr != null) {
      showErr(context, '${tr('Item code')}: $codeErr');
      setState(() => busy = false);
      return;
    }
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
  void dispose() {
    for (final c in [name, wcb, wncb, netFrom, netTo, bpc, bpt, trayWt, minStock, code]) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'Add Product' : 'Edit Product'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Product name *'), hintText: IndustryPack.eg(IndustryPack.current.productExamples))),
          const SizedBox(height: 12),
          ItemCodeField(controller: code, seriesPrefix: 'FG', editing: widget.product != null),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: wcb, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Gross / with-${U.cb} reference (kg)')))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: wncb, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Net bottle weight per ${U.cb} (kg) *')))),
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
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: netFrom, readOnly: true, onTap: () => _pickDate(netFrom), decoration: const InputDecoration(labelText: 'Net weight effective from', suffixIcon: Icon(Icons.calendar_month_outlined, size: 18)))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: netTo, readOnly: true, onTap: () => _pickDate(netTo), decoration: const InputDecoration(labelText: 'Net weight effective to', suffixIcon: Icon(Icons.calendar_month_outlined, size: 18)))),
          ]),
          const SizedBox(height: 8),
          Text('Productivity uses only the net bottle weight per CB. With-CB/carton weight is reference data and is never included.',
              style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(IndustryPack.current.productNote,
              style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
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
                            SizedBox(width: 200, child: ItemNameCell(name: p['name'] as String, code: ItemCode.of(p))),
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
