import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/download.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import '../reports/report_pdf.dart';

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
            tabs: [
              Tab(text: tr('Packing Stock')),
              Tab(text: tr('Packing per Product (BOM)')),
              Tab(text: tr('Ledger')),
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

/// Raw Material — its own section in the menu. Same stock engine as packing
/// (receive / consume / recipes) but shows ONLY the "Raw Material" category.
/// Tabs: Stock (with recipe tools) + Ledger (raw-only receipts/consumption).
class RawMaterialPage extends StatefulWidget {
  const RawMaterialPage({super.key});
  @override
  State<RawMaterialPage> createState() => _RawMaterialPageState();
}

class _RawMaterialPageState extends State<RawMaterialPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
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
            tabs: [
              Tab(text: tr('Raw Material Stock')),
              Tab(text: tr('Ledger')),
            ],
          ),
        ),
      ),
      Expanded(
        child: TabBarView(controller: _tab, children: const [
          _StockTab(rawOnly: true),
          _LedgerTab(rawOnly: true),
        ]),
      ),
    ]);
  }
}

/* ------------------------------- stock tab ------------------------------- */

class _StockTab extends StatefulWidget {
  final bool lowOnly;
  final bool rawOnly;
  const _StockTab({this.lowOnly = false, this.rawOnly = false});
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

  bool _exporting = false;

  /// Export the raw-material stock as PDF (client-built) or Excel (server report).
  Future<void> _exportRaw(List<Map<String, dynamic>> items, {required bool pdf}) async {
    setState(() => _exporting = true);
    try {
      final date = todayYmd();
      if (pdf) {
        final bytes = await ReportPdf.build(
          title: 'Raw Material Stock',
          desc: 'Current balance of every raw material (recipe consumption draws from here).',
          columns: const ['Material', 'Unit', 'Balance', 'Minimum', 'Status'],
          rows: [
            for (final m in items)
              [m['name'], m['unit'], m['stock'], m['min_stock'], (m['low'] as int? ?? 0) == 1 ? 'LOW' : 'OK'],
          ],
        );
        await Printing.sharePdf(bytes: bytes, filename: 'flavorflow-raw-material-$date.pdf');
      } else {
        final bytes = await context.read<AuthController>().api.getBytes('/reports/raw-material-stock.xlsx');
        downloadBytes('flavorflow-raw-material-$date.xlsx', bytes,
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        if (mounted) showOk(context, 'Excel file downloaded.');
      }
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

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
    final canManage = widget.rawOnly ? auth.canOr('raw.manage', 'packing.manage') : auth.can('packing.manage');
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        var all = (snap.data!['materials'] as List).cast<Map<String, dynamic>>();
        // Raw Material lives in its own menu section; the packing screen
        // hides it, and the raw screen shows ONLY it.
        all = widget.rawOnly
            ? all.where((m) => m['category'] == 'Raw Material').toList()
            : all.where((m) => m['category'] != 'Raw Material').toList();
        final s = (snap.data!['summary'] as Map).cast<String, dynamic>();
        final lowCount = all.where((m) => (m['low'] as int? ?? 0) == 1).length;
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
                KpiCard(label: widget.rawOnly ? 'Raw Materials' : 'Packing Items', value: qtyInt(all.length), icon: widget.rawOnly ? Icons.science_rounded : Icons.widgets_rounded, tint: AppColors.blue),
                KpiCard(label: 'Categories', value: qtyInt(categories.length), icon: Icons.category_rounded, tint: AppColors.teal),
                KpiCard(label: 'Running Low', value: qtyInt(lowCount), icon: Icons.warning_amber_rounded, tint: AppColors.red),
              ],
            );
          }),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ChoiceChip(label: Text(tr('All')), selected: _category.isEmpty && !_lowOnly, onSelected: (_) => setState(() { _category = ''; _lowOnly = false; _future = _load(); })),
            ChoiceChip(
              label: Text(tr('Low stock')),
              selected: _lowOnly,
              avatar: const Icon(Icons.warning_amber_rounded, size: 16),
              onSelected: (_) => setState(() { _lowOnly = true; _category = ''; _future = _load(); }),
            ),
            if (!widget.rawOnly)
              for (final cat in categories)
                ChoiceChip(label: Text(tr(cat)), selected: !_lowOnly && _category == cat, onSelected: (_) => setState(() { _category = cat; _lowOnly = false; _future = _load(); })),
            if (canManage) ...[
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilledButton.icon(
                  onPressed: () async {
                    final saved = await showDialog<bool>(context: context, builder: (_) => _TxnDialog(kind: 'receive', rawOnly: widget.rawOnly));
                    if (saved == true) _reload();
                  },
                  icon: const Icon(Icons.south_west_rounded, size: 18),
                  label: Text(tr('Receive Stock')),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final saved = await showDialog<bool>(context: context, builder: (_) => _TxnDialog(kind: 'consume', rawOnly: widget.rawOnly));
                  if (saved == true) _reload();
                },
                icon: const Icon(Icons.north_east_rounded, size: 18),
                label: Text(tr('Record Consumption')),
              ),
              if (widget.rawOnly && CompanyProfile.usesRecipes) ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    final saved = await showDialog<bool>(context: context, builder: (_) => const _RecipeConsumeDialog());
                    if (saved == true) _reload();
                  },
                  icon: const Icon(Icons.science_rounded, size: 18),
                  label: Text(tr('Recipe Consumption')),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final saved = await showDialog<bool>(context: context, builder: (_) => const _RecipeEditDialog());
                    if (saved == true) _reload();
                  },
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: Text(tr('Edit Recipes')),
                ),
              ],
              if (widget.rawOnly) ...[
                OutlinedButton.icon(
                  onPressed: _exporting ? null : () => _exportRaw(all, pdf: true),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: Text(tr('Export PDF')),
                ),
                OutlinedButton.icon(
                  onPressed: _exporting ? null : () => _exportRaw(all, pdf: false),
                  icon: const Icon(Icons.table_view_outlined, size: 18),
                  label: Text(tr('Export Excel')),
                ),
              ],
              OutlinedButton.icon(
                onPressed: () async {
                  final saved = await showDialog<bool>(context: context, builder: (_) => const _MaterialFormDialog());
                  if (saved == true) _reload();
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(tr('New Material')),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: widget.rawOnly
                ? (_lowOnly ? 'Low Stock Raw Material' : 'Raw Material Stock')
                : (_lowOnly ? 'Low Stock Packing Material' : 'Packing Material Stock'),
            child: rows.isEmpty
                ? EmptyState(_lowOnly ? 'Nothing running low 🎉' : (widget.rawOnly ? 'No raw material yet' : 'No packing material yet'))
                : AppDataTable(
                    columns: const ['Material', 'Category', 'In Stock', 'Unit', 'Min Stock', 'Status', ''],
                    rows: [
                      for (final m in rows)
                        [
                          Text(m['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                          tr('${m['category']}'),
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
                            tr('${i['category']}'),
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
  final bool rawOnly;
  const _LedgerTab({this.rawOnly = false});
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
    final api = context.read<AuthController>().api;
    final json = await api.get('/packing/ledger${_type.isEmpty ? '' : '?type=$_type'}');
    var rows = ((json as Map)['txns'] as List).cast<Map<String, dynamic>>();
    // Raw section: only raw-material entries; packing section: everything else.
    final mats = await api.get('/packing/materials');
    final rawNames = <String>{
      for (final m in ((mats as Map)['materials'] as List).cast<Map<String, dynamic>>())
        if (m['category'] == 'Raw Material') m['name'] as String,
    };
    rows = widget.rawOnly
        ? rows.where((t) => rawNames.contains(t['material_name'])).toList()
        : rows.where((t) => !rawNames.contains(t['material_name'])).toList();
    return rows;
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
                label: Text(t.isEmpty ? tr('All') : tr(t.toLowerCase())),
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
  final bool rawOnly; // Raw Material screen → only raw materials in the list
  const _TxnDialog({required this.kind, this.rawOnly = false});
  @override
  State<_TxnDialog> createState() => _TxnDialogState();
}

class _TxnDialogState extends State<_TxnDialog> {
  List<Map<String, dynamic>> materials = [];
  int? materialId;
  List<Map<String, dynamic>> products = [];
  int? productId; // consumption is tagged to ONE product (no sharing in Loss%)
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
        var list = ((json as Map)['materials'] as List).cast<Map<String, dynamic>>();
        // Raw screen shows only raw materials; packing screen hides them.
        list = widget.rawOnly
            ? list.where((m) => m['category'] == 'Raw Material').toList()
            : list.where((m) => m['category'] != 'Raw Material').toList();
        materials = list;
        materialId = materials.isNotEmpty ? materials.first['id'] as int : null;
      });
    }).catchError((e) { setState(() => loadError = '$e'); });
    if (widget.kind == 'consume' && !widget.rawOnly) {
      context.read<AuthController>().api.get('/products').then((json) {
        if (!mounted) return;
        setState(() => products = ((json as Map)['products'] as List).cast<Map<String, dynamic>>());
      }).catchError((_) {});
    }
  }

  Map<String, dynamic>? get _material =>
      materialId == null ? null : materials.firstWhere((m) => m['id'] == materialId, orElse: () => materials.first);

  Future<void> _save() async {
    if (!isReceive && !widget.rawOnly && productId == null) {
      showErr(context, 'Choose which product this consumption is for (Loss% sheet).');
      return;
    }
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.post('/packing/${isReceive ? 'receive' : 'consume'}', {
        'materialId': materialId,
        if (!isReceive && productId != null) 'productId': productId,
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
      title: Text(isReceive
          ? (widget.rawOnly ? 'Receive Raw Material' : 'Receive Packing Stock')
          : 'Record Consumption'),
      content: SizedBox(
        width: 400,
        child: loadError != null
            ? Text(loadError!)
            : materials.isEmpty
                ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
                : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    DropdownButtonFormField<int>(
                      initialValue: materialId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: tr('Material *')),
                      // Raw screen: category suffix skipped so the full name fits.
                      items: [for (final m in materials) DropdownMenuItem(value: m['id'] as int, child: Text(widget.rawOnly ? '${m['name']}' : '${m['name']} (${m['category']})', overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => setState(() => materialId = v),
                    ),
                    if (widget.kind == 'consume' && !widget.rawOnly) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: productId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: tr('For product * (Loss% sheet)')),
                        items: [for (final p in products) DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String, overflow: TextOverflow.ellipsis))],
                        onChanged: (v) => setState(() => productId = v),
                      ),
                    ],
                    if (_material != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('In stock: ${qtyInt(_material!['stock'])} ${_material!['unit']}',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                      ),
                    const SizedBox(height: 12),
                    TextField(controller: qty, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '${tr('Quantity')} (${_material?['unit'] ?? 'pcs'}) *')),
                    const SizedBox(height: 12),
                    if (isReceive)
                      TextField(controller: reference, decoration: InputDecoration(labelText: tr('Reference (PO no. / supplier)'), hintText: 'e.g. PO-1187 / Kapoor Plastics'))
                    else
                      TextField(controller: reference, decoration: InputDecoration(labelText: tr('Reference (batch / purpose)'), hintText: 'e.g. B-2603 / QC samples')),
                    const SizedBox(height: 12),
                    TextField(controller: remark, decoration: InputDecoration(labelText: tr('Remark (optional)'))),
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

  static const categories = ['Bottles', 'Jerry Cans', 'Caps', 'Labels', 'Holograms', 'Plugs', 'Sleeves', 'Cartons', 'Trays', 'Tray Caps', 'Raw Material', 'Other'];

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
          TextField(controller: name, decoration: InputDecoration(labelText: tr('Material name *'), hintText: 'e.g. Cap Green 500ml')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: InputDecoration(labelText: tr('Category')),
            items: [for (final c in categories) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => category = v ?? 'Other'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: stock, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Opening stock (pcs)')))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: minStock, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Minimum stock')))),
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

/// Recipe-based raw material consumption: pick a recipe (e.g. "Soya Sauce
/// 740gm — 300kg batch"), enter the TOTAL production quantity (e.g. 15000 kg);
/// batches = total ÷ batch size, and every raw material in the recipe is
/// consumed automatically (qty/batch × batches). Water is not tracked.
class _RecipeConsumeDialog extends StatefulWidget {
  const _RecipeConsumeDialog();
  @override
  State<_RecipeConsumeDialog> createState() => _RecipeConsumeDialogState();
}

class _RecipeConsumeDialogState extends State<_RecipeConsumeDialog> {
  List<Map<String, dynamic>> recipes = [];
  List<Map<String, dynamic>> rawMaterials = []; // for "add material" picker
  int? recipeId;
  final qty = TextEditingController();
  final remark = TextEditingController();
  /// materialId → custom TOTAL consumption typed by the user (override).
  final Map<int, TextEditingController> overrides = {};
  /// Extra raw materials added manually (not part of the selected recipe).
  final List<int> extraIds = [];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final api = context.read<AuthController>().api;
    api.get('/packing/recipes').then((json) {
      if (!mounted) return;
      setState(() {
        recipes = ((json as Map)['recipes'] as List).cast<Map<String, dynamic>>();
        if (recipes.isNotEmpty) recipeId = recipes.first['id'] as int;
      });
    }).catchError((e) {
      if (mounted) showErr(context, e);
    });
    api.get('/packing/materials').then((json) {
      if (!mounted) return;
      setState(() {
        rawMaterials = ((json as Map)['materials'] as List)
            .cast<Map<String, dynamic>>()
            .where((m) => m['category'] == 'Raw Material')
            .toList();
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    qty.dispose();
    remark.dispose();
    for (final c in overrides.values) { c.dispose(); }
    super.dispose();
  }

  Map<String, dynamic>? get _recipe =>
      recipes.where((r) => r['id'] == recipeId).cast<Map<String, dynamic>?>().firstOrNull;

  double get _batches {
    final r = _recipe;
    final q = double.tryParse(qty.text) ?? 0;
    if (r == null || q <= 0) return 0;
    final size = (r['batch_size'] as num).toDouble();
    return size > 0 ? q / size : 0;
  }

  TextEditingController _ovCtl(int materialId) =>
      overrides.putIfAbsent(materialId, () => TextEditingController());

  Future<void> _submit() async {
    final q = double.tryParse(qty.text) ?? 0;
    if (recipeId == null || q <= 0) {
      showErr(context, 'Enter the total production quantity.');
      return;
    }
    // collect non-empty overrides: materialId → custom total qty
    // (0 is allowed = skip that material entirely)
    final ov = <String, num>{};
    overrides.forEach((mid, ctl) {
      final v = double.tryParse(ctl.text.trim());
      if (v != null && v >= 0) ov['$mid'] = v;
    });
    setState(() => busy = true);
    try {
      final json = await context.read<AuthController>().api.post('/packing/recipe-consume', {
        'recipeId': recipeId,
        'totalQty': q,
        'remark': remark.text.trim(),
        if (ov.isNotEmpty) 'overrides': ov,
      });
      if (!mounted) return;
      final j = (json as Map).cast<String, dynamic>();
      final warnings = (j['warnings'] as List?)?.cast<String>() ?? const [];
      Navigator.pop(context, true);
      showOk(context, 'Raw material consumed for ${j['batches']} batches.'
          '${warnings.isEmpty ? '' : '\n⚠ ${warnings.join(' · ')}'}');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = _recipe;
    final batches = _batches;
    return AlertDialog(
      title: Text(tr('Recipe Consumption (Raw Material)')),
      content: SizedBox(
        width: 480,
        child: recipes.isEmpty
            ? const SizedBox(height: 90, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DropdownButtonFormField<int>(
                    initialValue: recipeId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Recipe *')),
                    items: [
                      for (final rec in recipes)
                        DropdownMenuItem(value: rec['id'] as int, child: Text(rec['name'] as String, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => recipeId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Total production (${r?['batch_unit'] ?? 'kg'}) *',
                      hintText: 'e.g. 15000',
                      helperText: r == null
                          ? null
                          : '1 batch = ${qty2(r['batch_size'])} ${r['batch_unit']}'
                            '${batches > 0 ? ' → ${qty2(batches)} batches' : ''}',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: remark, decoration: InputDecoration(labelText: tr('Remark'), hintText: 'optional')),
                  if (r != null && batches > 0) ...[
                    const SizedBox(height: 14),
                    Text('WILL CONSUME:', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final l in (r['lines'] as List).cast<Map<String, dynamic>>())
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              Expanded(child: Text(l['name'] as String, style: const TextStyle(fontSize: 12))),
                              SizedBox(
                                width: 108,
                                child: TextField(
                                  controller: _ovCtl(l['material_id'] as int),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    // recipe-calculated qty shows as hint; type to override
                                    hintText: qty2((l['qty_per_batch'] as num) * batches),
                                    suffixText: '${l['unit']}',
                                    suffixStyle: const TextStyle(fontSize: 10.5),
                                  ),
                                ),
                              ),
                            ]),
                          ),
                        // extra raw materials added by the user (not in the recipe)
                        for (final mid in extraIds)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              Expanded(
                                child: Text(
                                  '${rawMaterials.where((m) => m['id'] == mid).firstOrNull?['name'] ?? '?'} +',
                                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                                ),
                              ),
                              SizedBox(
                                width: 108,
                                child: TextField(
                                  controller: _ovCtl(mid),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    hintText: '0',
                                    suffixText: '${rawMaterials.where((m) => m['id'] == mid).firstOrNull?['unit'] ?? ''}',
                                    suffixStyle: const TextStyle(fontSize: 10.5),
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close_rounded, size: 16),
                                onPressed: () => setState(() {
                                  extraIds.remove(mid);
                                  overrides[mid]?.clear();
                                }),
                              ),
                            ]),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                            onPressed: () async {
                              final lineIds = {for (final l in (r['lines'] as List).cast<Map<String, dynamic>>()) l['material_id'] as int};
                              final options = rawMaterials.where((m) => !lineIds.contains(m['id']) && !extraIds.contains(m['id'])).toList();
                              if (options.isEmpty) return;
                              final picked = await showDialog<int>(
                                context: context,
                                builder: (ctx) => SimpleDialog(
                                  title: Text(tr('Material *')),
                                  children: [
                                    for (final m in options)
                                      SimpleDialogOption(
                                        onPressed: () => Navigator.pop(ctx, m['id'] as int),
                                        child: Text('${m['name']} (${qtyInt(m['stock'])} ${m['unit']})'),
                                      ),
                                  ],
                                ),
                              );
                              if (picked != null) setState(() => extraIds.add(picked));
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: Text(tr('Add material')),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(tr('Amounts are as per recipe — type in any box to give that material a specific consumption instead. 0 = skip.'),
                            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                        Text(tr('Water is not tracked — only listed raw materials are consumed.'),
                            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                      ]),
                    ),
                  ],
                ]),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy || batches <= 0 ? null : _submit, child: Text(busy ? 'Consuming…' : 'Consume')),
      ],
    );
  }
}

String qty2(Object? v) {
  final n = v is num ? v : num.tryParse('$v') ?? 0;
  final r = (n * 100).round() / 100;
  return r == r.roundToDouble() ? '${r.round()}' : '$r';
}

/// Edit recipes: pick a recipe, change the batch size and each material's
/// qty per batch (0 removes the line). For when the factory recipe changes.
class _RecipeEditDialog extends StatefulWidget {
  const _RecipeEditDialog();
  @override
  State<_RecipeEditDialog> createState() => _RecipeEditDialogState();
}

class _RecipeEditDialogState extends State<_RecipeEditDialog> {
  List<Map<String, dynamic>> recipes = [];
  int? recipeId;
  final batchSize = TextEditingController();
  final Map<int, TextEditingController> lineCtls = {};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _loadRecipes();
  }

  Future<void> _loadRecipes() async {
    try {
      final json = await context.read<AuthController>().api.get('/packing/recipes');
      if (!mounted) return;
      setState(() {
        recipes = ((json as Map)['recipes'] as List).cast<Map<String, dynamic>>();
        if (recipes.isNotEmpty && recipeId == null) _select(recipes.first['id'] as int);
      });
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  void _select(int id) {
    recipeId = id;
    final r = recipes.firstWhere((x) => x['id'] == id);
    batchSize.text = qty2(r['batch_size']);
    for (final c in lineCtls.values) { c.dispose(); }
    lineCtls.clear();
    for (final l in (r['lines'] as List).cast<Map<String, dynamic>>()) {
      lineCtls[l['material_id'] as int] = TextEditingController(text: qty2(l['qty_per_batch']));
    }
    setState(() {});
  }

  @override
  void dispose() {
    batchSize.dispose();
    for (final c in lineCtls.values) { c.dispose(); }
    super.dispose();
  }

  Map<String, dynamic>? get _recipe =>
      recipes.where((r) => r['id'] == recipeId).cast<Map<String, dynamic>?>().firstOrNull;

  Future<void> _save() async {
    final r = _recipe;
    if (r == null) return;
    final size = double.tryParse(batchSize.text) ?? 0;
    if (size <= 0) {
      showErr(context, 'Batch size must be greater than 0.');
      return;
    }
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.put('/packing/recipes/${r['id']}', {
        'batchSize': size,
        'lines': [
          for (final e in lineCtls.entries)
            {'materialId': e.key, 'qtyPerBatch': double.tryParse(e.value.text) ?? 0},
        ],
      });
      if (!mounted) return;
      Navigator.pop(context, true);
      showOk(context, 'Recipe updated.');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = _recipe;
    return AlertDialog(
      title: Text(tr('Edit Recipes')),
      content: SizedBox(
        width: 480,
        child: recipes.isEmpty
            ? const SizedBox(height: 90, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DropdownButtonFormField<int>(
                    initialValue: recipeId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Recipe *')),
                    items: [
                      for (final rec in recipes)
                        DropdownMenuItem(value: rec['id'] as int, child: Text(rec['name'] as String, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) { if (v != null) _select(v); },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: batchSize,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: '${tr('Batch size')} (${r?['batch_unit'] ?? 'kg'}) *'),
                  ),
                  if (r != null) ...[
                    const SizedBox(height: 14),
                    Text('QTY PER BATCH (0 = remove):',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    for (final l in (r['lines'] as List).cast<Map<String, dynamic>>())
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Expanded(child: Text(l['name'] as String, style: const TextStyle(fontSize: 12.5))),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: lineCtls[l['material_id'] as int],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                suffixText: '${l['unit']}',
                                suffixStyle: const TextStyle(fontSize: 10.5),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    const SizedBox(height: 6),
                    Text('Changes apply to future consumptions only — past ledger entries stay unchanged.',
                        style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                  ],
                ]),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy || r == null ? null : _save, child: Text(busy ? 'Saving…' : 'Save Recipe')),
      ],
    );
  }
}
