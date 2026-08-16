import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// Packing Material — stock of bottles, caps, labels, cartons, trays etc.
/// Receipts & consumption feed a ledger; batch completion auto-consumes per BOM.
class PackingPage extends StatefulWidget {
  final bool lowOnly;
  const PackingPage({super.key, this.lowOnly = false});
  @override
  State<PackingPage> createState() => _PackingPageState();
}

class _PackingPageState extends State<PackingPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Packing Stock'),
              Tab(text: 'Packing per Product (BOM)'),
              Tab(text: 'Ledger'),
            ],
          ),
        ),
      ),
      Expanded(
        child: TabBarView(controller: _tab, children: [
          _StockTab(lowOnly: widget.lowOnly),
          const _BomTab(),
          const _LedgerTab(),
        ]),
      ),
    ]);
  }
}

/* ------------------------------- stock tab ------------------------------- */

class _StockTab extends StatefulWidget {
  final bool lowOnly;
  const _StockTab({this.lowOnly = false});
  @override
  State<_StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<_StockTab> {
  late bool _lowOnly;
  String _category = '';
  Future<Map<String, dynamic>>? _future;
  bool _first = true;

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
    final json = await context.read<AuthController>().api.get('/packing/materials${_lowOnly ? '?filter=low' : ''}');
    return (json as Map).cast<String, dynamic>();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _deleteMaterial(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Delete ${m['name']}?'),
            content: const Text('The material will be removed from stock and BOM dropdowns.\n\nPast ledger entries are kept unchanged.'),
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
      await context.read<AuthController>().api.delete('/packing/materials/${m['id']}');
      if (mounted) {
        showOk(context, '${m['name']} deleted.');
        _reload();
      }
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canManage = auth.can('packing.manage');
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = (snap.data!['materials'] as List).cast<Map<String, dynamic>>();
        final s = (snap.data!['summary'] as Map).cast<String, dynamic>();
        final categories = <String>{for (final m in all) m['category'] as String};
        final rows = _category.isEmpty ? all : all.where((m) => m['category'] == _category).toList();
        // Pair every "Tray (X)" with its "Tray Cap (X)" right below it —
        // e.g. Tray (740/610) → Tray Cap (740/610), Tray (1.3/1 Ltr) → Tray Cap (1.3/1 Ltr).
        String pairKey(Map<String, dynamic> m) {
          final n = (m['name'] as String).trim();
          final cap = RegExp(r'^Tray\s*Cap\s*\((.+)\)$', caseSensitive: false).firstMatch(n);
          if (cap != null) return 'TRAY ${cap.group(1)!.toUpperCase()}~1';
          final tray = RegExp(r'^Tray\s*\((.+)\)$', caseSensitive: false).firstMatch(n);
          if (tray != null) return 'TRAY ${tray.group(1)!.toUpperCase()}~0';
          return n.toUpperCase();
        }
        rows.sort((a, b) => pairKey(a).compareTo(pairKey(b)));
        return ListView(padding: const EdgeInsets.all(20), children: [
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth > 1000 ? 3 : 1;
            final ratio = ((c.maxWidth - (cols - 1) * 12) / cols / 84).clamp(1.6, 5.0);
            return GridView.count(
              crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: ratio,
              children: [
                KpiCard(label: 'Packing Items', value: qtyInt(s['items']), icon: Icons.widgets_rounded, tint: AppColors.blue),
                KpiCard(label: 'Categories', value: qtyInt(s['categories']), icon: Icons.category_rounded, tint: AppColors.teal),
                KpiCard(label: 'Running Low', value: qtyInt(s['low_count']), icon: Icons.warning_amber_rounded, tint: AppColors.red),
              ],
            );
          }),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ChoiceChip(label: const Text('All'), selected: _category.isEmpty && !_lowOnly, onSelected: (_) => setState(() { _category = ''; _lowOnly = false; _future = _load(); })),
            ChoiceChip(
              label: const Text('Low stock'),
              selected: _lowOnly,
              avatar: const Icon(Icons.warning_amber_rounded, size: 16),
              onSelected: (_) => setState(() { _lowOnly = true; _category = ''; _future = _load(); }),
            ),
            for (final cat in categories)
              ChoiceChip(label: Text(cat), selected: !_lowOnly && _category == cat, onSelected: (_) => setState(() { _category = cat; _lowOnly = false; _future = _load(); })),
            if (canManage) ...[
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilledButton.icon(
                  onPressed: () async {
                    final saved = await showDialog<bool>(context: context, builder: (_) => const _TxnDialog(kind: 'receive'));
                    if (saved == true) _reload();
                  },
                  icon: const Icon(Icons.south_west_rounded, size: 18),
                  label: const Text('Receive Stock'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final saved = await showDialog<bool>(context: context, builder: (_) => const _TxnDialog(kind: 'consume'));
                  if (saved == true) _reload();
                },
                icon: const Icon(Icons.north_east_rounded, size: 18),
                label: const Text('Record Consumption'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final saved = await showDialog<bool>(context: context, builder: (_) => const _MaterialFormDialog());
                  if (saved == true) _reload();
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Material'),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: _lowOnly ? 'Low Stock Packing Material' : 'Packing Material Stock',
            child: rows.isEmpty
                ? EmptyState(_lowOnly ? 'Nothing running low 🎉' : 'No packing material yet')
                : AppDataTable(
                    columns: const ['Material', 'Category', 'In Stock', 'Unit', 'Min Stock', 'Status', ''],
                    rows: [
                      for (final m in rows)
                        [
                          Text(m['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                          m['category'],
                          Text(qtyInt(m['stock']), style: TextStyle(fontWeight: FontWeight.w700, color: (m['low'] as int) == 1 ? AppColors.red : null)),
                          m['unit'],
                          qtyInt(m['min_stock']),
                          (m['low'] as int) == 1 ? const StatusChip('LOW') : const StatusChip('IN STOCK'),
                          if (canManage)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: 'Edit material & stock',
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () async {
                                  final saved = await showDialog<bool>(context: context, builder: (_) => _MaterialFormDialog(material: m));
                                  if (saved == true) _reload();
                                },
                              ),
                              IconButton(
                                tooltip: 'Delete material',
                                icon: Icon(Icons.delete_outline_rounded, size: 18, color: Theme.of(context).colorScheme.error),
                                onPressed: () => _deleteMaterial(m),
                              ),
                            ])
                          else
                            const SizedBox.shrink(),
                        ],
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          Text('When a production batch is completed with “Deduct packing material” ticked, stock is consumed automatically as per the product BOM.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]);
      },
    );
  }
}

/* -------------------------------- BOM tab -------------------------------- */

class _BomTab extends StatefulWidget {
  const _BomTab();
  @override
  State<_BomTab> createState() => _BomTabState();
}

class _BomTabState extends State<_BomTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final json = await context.read<AuthController>().api.get('/packing/bom');
    return ((json as Map)['bom'] as List).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: () => setState(() => _future = _load()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final bom = snap.data!;
        return ListView(padding: const EdgeInsets.all(20), children: [
          Text('Packing material needed to pack 1 CB and 1 tray of each product (from your Packing Material sheet).',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 14),
          for (final entry in bom) ...[
            SectionCard(
              title: entry['product']['name'] as String,
              trailing: Text('${qtyInt(entry['product']['bottles_per_cb'])}/CB'
                  '${(entry['product']['bottles_per_tray'] as num) > 0 ? ' · ${qtyInt(entry['product']['bottles_per_tray'])}/tray' : ''}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: (entry['items'] as List).isEmpty
                  ? Text('No BOM recorded.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5))
                  : AppDataTable(
                      columns: ['Material', 'Category', 'Per ${U.cb}', 'Per ${U.tray}', 'Unit', 'In Stock'],
                      rows: [
                        for (final i in (entry['items'] as List).cast<Map<String, dynamic>>())
                          [
                            Text(i['material'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                            i['category'],
                            (i['perCb'] as num) > 0 ? qty(i['perCb']) : '—',
                            (i['perTray'] as num) > 0 ? qty(i['perTray']) : '—',
                            i['unit'],
                            qtyInt(i['inStock']),
                          ],
                      ],
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ]);
      },
    );
  }
}

/* ------------------------------- ledger tab ------------------------------ */

class _LedgerTab extends StatefulWidget {
  const _LedgerTab();
  @override
  State<_LedgerTab> createState() => _LedgerTabState();
}

class _LedgerTabState extends State<_LedgerTab> {
  String _type = '';
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final json = await context.read<AuthController>().api.get('/packing/ledger${_type.isEmpty ? '' : '?type=$_type'}');
    return ((json as Map)['txns'] as List).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: () => setState(() => _future = _load()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        return ListView(padding: const EdgeInsets.all(20), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in ['', 'RECEIVED', 'CONSUMED'])
              ChoiceChip(
                label: Text(t.isEmpty ? 'All' : t.toLowerCase()),
                selected: _type == t,
                onSelected: (_) => setState(() { _type = t; _future = _load(); }),
              ),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Receipts & Consumption Ledger',
            child: rows.isEmpty
                ? const EmptyState('No entries yet')
                : AppDataTable(
                    columns: const ['Date', 'Material', 'Type', 'Qty', 'Reference', 'Batch', 'By'],
                    rows: [
                      for (final t in rows)
                        [
                          fmtDateWithDay(t['txn_date']),
                          Text(t['material_name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                          StatusChip(t['txn_type'] == 'RECEIVED' ? 'IN' : 'OUT'),
                          Text('${t['txn_type'] == 'RECEIVED' ? '+' : '−'}${qtyInt(t['qty'])}',
                              style: TextStyle(fontWeight: FontWeight.w700, color: t['txn_type'] == 'RECEIVED' ? AppColors.green : AppColors.red)),
                          (t['reference'] as String? ?? '').isEmpty ? ((t['remark'] as String? ?? '').isEmpty ? '—' : t['remark']) : t['reference'],
                          t['batch_code'] ?? '—',
                          t['created_by_name'] ?? '—',
                        ],
                    ],
                  ),
          ),
        ]);
      },
    );
  }
}

/* ------------------------- receive / consume dialog ------------------------- */

class _TxnDialog extends StatefulWidget {
  final String kind; // 'receive' | 'consume'
  const _TxnDialog({required this.kind});
  @override
  State<_TxnDialog> createState() => _TxnDialogState();
}

class _TxnDialogState extends State<_TxnDialog> {
  List<Map<String, dynamic>> materials = [];
  int? materialId;
  final qty = TextEditingController();
  final reference = TextEditingController();
  final remark = TextEditingController();
  bool busy = false;
  String? loadError;

  bool get isReceive => widget.kind == 'receive';

  @override
  void initState() {
    super.initState();
    context.read<AuthController>().api.get('/packing/materials').then((json) {
      setState(() {
        materials = ((json as Map)['materials'] as List).cast<Map<String, dynamic>>();
        materialId = materials.isNotEmpty ? materials.first['id'] as int : null;
      });
    }).catchError((e) { setState(() => loadError = '$e'); });
  }

  Map<String, dynamic>? get _material =>
      materialId == null ? null : materials.firstWhere((m) => m['id'] == materialId, orElse: () => materials.first);

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.post('/packing/${isReceive ? 'receive' : 'consume'}', {
        'materialId': materialId,
        'qty': num.tryParse(qty.text) ?? 0,
        'reference': reference.text.trim(),
        'remark': remark.text.trim(),
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
      title: Text(isReceive ? 'Receive Packing Stock' : 'Record Consumption'),
      content: SizedBox(
        width: 400,
        child: loadError != null
            ? Text(loadError!)
            : materials.isEmpty
                ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
                : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    DropdownButtonFormField<int>(
                      initialValue: materialId,
                      decoration: const InputDecoration(labelText: 'Material *'),
                      items: [for (final m in materials) DropdownMenuItem(value: m['id'] as int, child: Text('${m['name']} (${m['category']})', overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => setState(() => materialId = v),
                    ),
                    if (_material != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('In stock: ${qtyInt(_material!['stock'])} ${_material!['unit']}',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                      ),
                    const SizedBox(height: 12),
                    TextField(controller: qty, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Quantity (${_material?['unit'] ?? 'pcs'}) *')),
                    const SizedBox(height: 12),
                    if (isReceive)
                      TextField(controller: reference, decoration: const InputDecoration(labelText: 'Reference (PO no. / supplier)', hintText: 'e.g. PO-1187 / Kapoor Plastics'))
                    else
                      TextField(controller: reference, decoration: const InputDecoration(labelText: 'Reference (batch / purpose)', hintText: 'e.g. B-2603 / QC samples')),
                    const SizedBox(height: 12),
                    TextField(controller: remark, decoration: const InputDecoration(labelText: 'Remark (optional)')),
                  ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : (isReceive ? 'Receive' : 'Consume'))),
      ],
    );
  }
}

class _MaterialFormDialog extends StatefulWidget {
  final Map<String, dynamic>? material; // set → edit mode
  const _MaterialFormDialog({this.material});
  @override
  State<_MaterialFormDialog> createState() => _MaterialFormDialogState();
}

class _MaterialFormDialogState extends State<_MaterialFormDialog> {
  late final TextEditingController name = TextEditingController(text: widget.material?['name']?.toString() ?? '');
  late String category = widget.material?['category']?.toString() ?? 'Other';
  late final TextEditingController stock = TextEditingController(text: widget.material != null ? '${widget.material!['stock']}' : '0');
  late final TextEditingController minStock = TextEditingController(text: widget.material != null ? '${widget.material!['min_stock']}' : '0');
  bool busy = false;

  bool get editing => widget.material != null;

  static const categories = ['Bottles', 'Jerry Cans', 'Caps', 'Labels', 'Holograms', 'Plugs', 'Sleeves', 'Cartons', 'Trays', 'Tray Caps', 'Other'];

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final body = {
        'name': name.text.trim(),
        'category': category,
        'stock': num.tryParse(stock.text) ?? 0,
        'minStock': num.tryParse(minStock.text) ?? 0,
      };
      if (editing) {
        await context.read<AuthController>().api.put('/packing/materials/${widget.material!['id']}', body);
      } else {
        await context.read<AuthController>().api.post('/packing/materials', body);
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
      title: Text(editing ? 'Edit Packing Material' : 'New Packing Material'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (editing)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Stock entered here replaces the current count (use for opening stock / corrections).',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Material name *', hintText: 'e.g. Cap Green 500ml')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final c in categories) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => category = v ?? 'Other'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Opening stock (pcs)'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: minStock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum stock'))),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : (editing ? 'Save Changes' : 'Add Material'))),
      ],
    );
  }
}
