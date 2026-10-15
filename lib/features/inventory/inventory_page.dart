import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/download.dart';
import '../../core/company.dart';
import '../../core/industry_pack.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/platform_support.dart';
import '../../core/item_code.dart';
import '../../state/auth.dart';
import '../../core/offline_queue.dart';
import '../../ui/widgets.dart';
import '../billing/item_history_page.dart' show showItemHistory;
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
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

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
      await downloadBytes('flavorflow-stock-${todayYmd()}.xlsx', bytes,
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

  Widget _buildWindowsInventory({
    required Map<String, dynamic> summary,
    required List<Map<String, dynamic>> allItems,
    required List<Map<String, dynamic>> items,
    required bool hasCodes,
    required AuthController auth,
  }) {
    final search = TextField(
      controller: _q,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        hintText: hasCodes ? tr('Search name / item code') : tr('Search product'),
        suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () => setState(_q.clear)),
      ),
    );
    final filtersAndCommands = Wrap(spacing: 7, runSpacing: 7, crossAxisAlignment: WrapCrossAlignment.center, children: [
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
        FilledButton.icon(
          onPressed: () async {
            final saved = await showDialog<bool>(context: context, builder: (_) => const ReceiptDialog());
            if (saved == true) _reload();
          },
          icon: const Icon(Icons.add_box_outlined, size: 17),
          label: Text(tr('Receive Stock')),
        ),
      if (auth.canManageBilling)
        OutlinedButton.icon(
          onPressed: () async {
            await context.push('/billing/purchases/new');
            _reload();
          },
          icon: const Icon(Icons.receipt_long_outlined, size: 16),
          label: Text(tr('Enter Supplier Bill')),
        ),
      OutlinedButton.icon(onPressed: () => context.push('/stock'), icon: const Icon(Icons.history_rounded, size: 16), label: Text(tr('Stock Ledger'))),
      OutlinedButton.icon(
        onPressed: _exporting ? null : _exportPdf,
        icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
        label: Text(tr('Stock PDF')),
      ),
      OutlinedButton.icon(
        onPressed: _exporting ? null : _exportExcel,
        icon: const Icon(Icons.table_view_outlined, size: 16),
        label: Text(tr('Stock Excel')),
      ),
    ]);

    final stockTable = SectionCard(
      title: _lowOnly ? 'Low Stock Products' : 'Stock on Hand',
      child: items.isEmpty
          ? EmptyState(_q.text.isNotEmpty ? 'No matching products' : _lowOnly ? 'No products below minimum stock 🎉' : 'No inventory yet — add products in Products, then receive opening stock or complete a production batch.')
          : AppDataTable(
              columns: [if (hasCodes) 'Item Code', 'Product', '${U.carton} (${U.cb})', if (CompanyProfile.usesTrays) U.tray, 'Total ${U.piece}', 'Gross kg', 'Min (${U.cb})', 'Status', ''],
              rows: [
                for (final item in items)
                  [
                    if (hasCodes) ItemCodeChip(ItemCode.of(item)),
                    Text(item['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    qtyInt(item['qty_cb']),
                    if (CompanyProfile.usesTrays) qtyInt(item['qty_trays']),
                    qtyInt(item['total_bottles']),
                    qty(item['gross_kg']),
                    qtyInt(item['min_stock_cb']),
                    (item['low'] as int) == 1 ? const StatusChip('LOW') : const StatusChip('IN STOCK'),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (auth.canViewBilling)
                        IconButton(
                          tooltip: tr('Stock ledger (all in / out with doc numbers)'),
                          icon: const Icon(Icons.history_rounded, size: 17),
                          onPressed: () => showItemHistory(context, type: 'product', id: item['product_id'] as int, name: item['name'] as String),
                        ),
                      if (auth.can('inventory.manage'))
                        IconButton(
                          tooltip: 'Set exact stock',
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          onPressed: () async {
                            final saved = await showDialog<bool>(context: context, builder: (_) => SetStockDialog(item: item));
                            if (saved == true) _reload();
                          },
                        ),
                    ]),
                  ],
              ],
            ),
    );
    const batchStock = _BatchStockSection();

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1280;
      return ListView(
        padding: EdgeInsets.all(constraints.maxWidth < 640 ? 10 : 14),
        children: [
          _WindowsInventoryHeading(productCount: allItems.length, onRefresh: _reload),
          const SizedBox(height: 10),
          _WindowsInventoryMetrics(summary: summary, productCount: allItems.length),
          const SizedBox(height: 10),
          if (constraints.maxWidth >= 800)
            Row(children: [
              Expanded(flex: 3, child: search),
              const SizedBox(width: 10),
              Expanded(flex: 8, child: filtersAndCommands),
            ])
          else
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [search, const SizedBox(height: 8), filtersAndCommands]),
          const SizedBox(height: 10),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 6, child: stockTable),
              const SizedBox(width: 12),
              Expanded(flex: 5, child: batchStock),
            ])
          else ...[
            batchStock,
            const SizedBox(height: 10),
            stockTable,
          ],
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final allItems = (snap.data!['items'] as List)
            .cast<Map<String, dynamic>>()
            .where((it) => (it['active'] as num? ?? 1) != 0)
            .toList();
        final hasCodes = ItemCode.anyIn(allItems);
        final items = allItems.where((it) => ItemCode.matches(it, _q.text)).toList();
        final s = (snap.data!['summary'] as Map).cast<String, dynamic>();
        if (isWindowsPlatform) {
          return _buildWindowsInventory(summary: s, allItems: allItems, items: items, hasCodes: hasCodes, auth: auth);
        }
        return ListView(padding: const EdgeInsets.all(20), children: [
          _InventoryHealthCard(summary: s, productCount: allItems.length),
          const SizedBox(height: 12),
          SizedBox(
            height: 104,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _InventoryMetric(label: 'Low stock items', value: qtyInt(s['low_count']), icon: Icons.warning_amber_rounded, tint: AppColors.red),
                _InventoryMetric(label: 'Total products', value: qtyInt(allItems.length), icon: Icons.category_outlined, tint: AppColors.blue),
                _InventoryMetric(label: 'Total ${U.piece}', value: qtyInt(s['total_bottles']), icon: Icons.liquor_rounded, tint: AppColors.cyan),
                if (CompanyProfile.usesTrays)
                  _InventoryMetric(label: '${U.tray} on hand', value: qtyInt(s['total_trays']), icon: Icons.dinner_dining_rounded, tint: AppColors.teal),
              ],
            ),
          ),
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
            if (auth.canManageBilling)
              OutlinedButton.icon(
                onPressed: () async {
                  await context.push('/billing/purchases/new');
                  _reload();
                },
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(tr('Enter Supplier Bill')),
              ),
            OutlinedButton.icon(
              onPressed: () => context.push('/stock'),
              icon: const Icon(Icons.history_rounded, size: 18),
              label: Text(tr('Stock Ledger')),
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
          const SizedBox(height: 12),
          SizedBox(
            width: 360,
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText: hasCodes ? tr('Search name / item code') : tr('Search product'),
                suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () => setState(_q.clear)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Factory batch register comes first so current production stock is
          // visible before the detailed product table.
          const _BatchStockSection(),
          const SizedBox(height: 16),
          SectionCard(
            title: _lowOnly ? 'Low Stock Products' : 'Stock on Hand',
            child: items.isEmpty
                ? EmptyState(_lowOnly ? 'No products below minimum stock 🎉' : 'No inventory yet — add products in Products, then receive opening stock or complete a production batch.')
                : AppDataTable(
                    columns: [if (hasCodes) 'Item Code', 'Product', '${U.carton} (${U.cb})', if (CompanyProfile.usesTrays) U.tray, 'Total ${U.piece}', 'Gross kg', 'Min (${U.cb})', 'Status', ''],
                    rows: [
                      for (final it in items)
                        [
                          if (hasCodes) ItemCodeChip(ItemCode.of(it)),
                          Text(it['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                          qtyInt(it['qty_cb']),
                          if (CompanyProfile.usesTrays) qtyInt(it['qty_trays']),
                          qtyInt(it['total_bottles']),
                          qty(it['gross_kg']),
                          qtyInt(it['min_stock_cb']),
                          (it['low'] as int) == 1
                              ? const StatusChip('LOW')
                              : const StatusChip('IN STOCK'),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            if (auth.canViewBilling)
                              IconButton(
                                tooltip: tr('Stock ledger (all in / out with doc numbers)'),
                                icon: const Icon(Icons.history_rounded, size: 18),
                                onPressed: () => showItemHistory(context, type: 'product', id: it['product_id'] as int, name: it['name'] as String),
                              ),
                            if (auth.can('inventory.manage'))
                              IconButton(
                                tooltip: 'Set exact stock',
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () async {
                                  final saved = await showDialog<bool>(context: context, builder: (_) => SetStockDialog(item: it));
                                  if (saved == true) _reload();
                                },
                              ),
                          ]),
                        ],
                    ],
                  ),
          ),
        ]);
      },
    );
  }
}

class _WindowsInventoryHeading extends StatelessWidget {
  final int productCount;
  final VoidCallback onRefresh;
  const _WindowsInventoryHeading({required this.productCount, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: LayoutBuilder(builder: (context, constraints) {
          final title = Row(children: [
            Container(width: 4, height: 38, color: AppBrand.blue),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Inventory Workspace', style: TextStyle(color: scheme.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
              Text('$productCount active products · ${fmtDate(todayYmd())}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
            ])),
          ]);
          final refresh = OutlinedButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded, size: 16), label: Text(tr('Refresh')));
          if (constraints.maxWidth < 520) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 8), Align(alignment: Alignment.centerRight, child: refresh)]);
          }
          return Row(children: [Expanded(child: title), const SizedBox(width: 10), refresh]);
        }),
      ),
    );
  }
}

class _WindowsInventoryMetrics extends StatelessWidget {
  final Map<String, dynamic> summary;
  final int productCount;
  const _WindowsInventoryMetrics({required this.summary, required this.productCount});

  @override
  Widget build(BuildContext context) {
    final metrics = <(String, String, IconData, Color)>[
      ('Low stock alerts', qtyInt(summary['low_count']), Icons.warning_amber_rounded, AppColors.red),
      ('Products tracked', qtyInt(productCount), Icons.category_outlined, AppColors.blue),
      ('${U.piece} on hand', qtyInt(summary['total_bottles']), Icons.inventory_2_outlined, AppColors.cyan),
      if (CompanyProfile.usesTrays) ('${U.tray} on hand', qtyInt(summary['total_trays']), Icons.dinner_dining_outlined, AppColors.teal),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900 ? metrics.length : constraints.maxWidth >= 540 ? 2 : 1;
      const gap = 8.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final metric in metrics)
          SizedBox(
            width: width,
            height: 62,
            child: _WindowsInventoryMetric(label: metric.$1, value: metric.$2, icon: metric.$3, tint: metric.$4),
          ),
      ]);
    });
  }
}

class _WindowsInventoryMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  const _WindowsInventoryMetric({required this.label, required this.value, required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.surface, border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(3)),
      child: Row(children: [
        Container(width: 3, height: double.infinity, color: tint),
        const SizedBox(width: 10),
        Icon(icon, size: 19, color: tint),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5, fontWeight: FontWeight.w600)),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 17, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
        ])),
        const SizedBox(width: 8),
      ]),
    );
  }
}

class _InventoryHealthCard extends StatelessWidget {
  final Map<String, dynamic> summary;
  final int productCount;
  const _InventoryHealthCard({required this.summary, required this.productCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
      decoration: BoxDecoration(
        gradient: AppBrand.gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppBrand.blue.withValues(alpha: .18), blurRadius: 14, offset: const Offset(0, 7))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Stock Health', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
            child: Text(fmtDate(todayYmd()), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(qtyInt(summary['total_cb']), style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, height: 1)),
          const SizedBox(width: 8),
          Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('${U.cb} on hand', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(height: 7, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .23)), child: FractionallySizedBox(widthFactor: 1, alignment: Alignment.centerLeft, child: Container(decoration: const BoxDecoration(color: Color(0xFF63E6C1))))),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text('$productCount products tracked', style: const TextStyle(color: Colors.white, fontSize: 12.5))),
          Text('${qtyInt(summary['low_count'])} low stock alerts', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}

class _InventoryMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  const _InventoryMetric({required this.label, required this.value, required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 166,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: .06), blurRadius: 7, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 18, color: tint), const Spacer(), Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: tint))]),
        const Spacer(),
        Text(value, style: TextStyle(color: scheme.onSurface, fontSize: 20, fontWeight: FontWeight.w800)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]),
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

String _shortRegisterDate(String raw) {
  final m = RegExp(r'^\d{4}-(\d{1,2})-(\d{1,2})').firstMatch(raw.trim());
  if (m == null) return raw.isEmpty ? '—' : raw;
  return '${m.group(2)!.padLeft(2, '0')}/${m.group(1)!.padLeft(2, '0')}';
}

class _BatchStockSectionState extends State<_BatchStockSection> {
  late Future<Map<String, dynamic>> _future;
  bool _exporting = false;
  final Set<String> _collapsed = <String>{};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final api = context.read<AuthController>().api;
    final report = (await api.get('/reports/batch-stock') as Map).cast<String, dynamic>();
    // Keep the register correct for legacy/backdated completion rows while
    // the server reconciler is being rolled out. The production endpoint is
    // read-only here; it lets us restore a missing batch row instead of
    // presenting its produced stock as "Unassigned".
    List<Map<String, dynamic>> completedBatches = const [];
    try {
      final production = await api.get('/production/batches');
      final raw = production is Map ? production['batches'] : null;
      if (raw is List) {
        completedBatches = [
          for (final row in raw)
            if (row is Map && '${row['status'] ?? ''}'.toUpperCase() == 'COMPLETED') row.cast<String, dynamic>(),
        ];
      }
    } catch (_) {
      // The batch report remains usable when the user lacks production.view.
    }
    return {...report, '_completedProductionBatches': completedBatches};
  }

  Future<void> _export(Map<String, dynamic> data, {required bool pdf}) async {
    setState(() => _exporting = true);
    try {
      final date = todayYmd();
      if (pdf) {
        final (pcols, prows) = U.table(
          (data['columns'] as List).cast<String>(),
          (data['rows'] as List).map((r) => (r as List).cast<dynamic>()).toList(),
        );
        final bytes = await ReportPdf.build(
          title: U.ize(data['title'] as String? ?? 'Batch-wise Stock'),
          desc: U.ize(data['desc'] as String? ?? ''),
          columns: pcols,
          rows: prows,
        );
        await Printing.sharePdf(bytes: bytes, filename: 'flavorflow-batch-stock-$date.pdf');
      } else {
        final bytes = await context.read<AuthController>().api.getBytes('/reports/batch-stock.xlsx');
        await downloadBytes('flavorflow-batch-stock-$date.xlsx', bytes,
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        if (mounted) showOk(context, 'Excel file downloaded.');
      }
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<_BatchRegisterGroup> _parseGroups(Map<String, dynamic> data) {
    final groups = <_BatchRegisterGroup>[];
    _BatchRegisterGroup? current;
    final raw = (data['rows'] as List?) ?? const [];
    for (final rawRow in raw) {
      final row = (rawRow as List).cast<dynamic>();
      if (row.isEmpty) continue;
      final first = '${row[0] ?? ''}';
      if (first.startsWith('▶')) {
        current = _BatchRegisterGroup(first.replaceFirst('▶', '').trim());
        groups.add(current);
        continue;
      }
      if (first == 'TOTAL' || first == 'GRAND TOTAL' || first.isEmpty) {
        if (first == 'TOTAL' && current != null && row.length > 2) {
          current.totalCb = row[2];
          current.totalTrays = row.length > 3 ? row[3] : null;
        }
        continue;
      }
      if (current != null && row.length > 2) {
        current.entries.add(_BatchRegisterEntry(
          date: _shortRegisterDate('${row[0] ?? '—'}'),
          code: '${row.length > 1 ? row[1] ?? '—' : '—'}',
          cb: row[2],
          trays: row.length > 3 ? row[3] : null,
        ));
      }
    }
    // A backdated production completion can already be present in
    // /production/batches while an older batch-stock report still places its
    // quantity in the product's Unassigned row. Reconcile that display-only
    // gap using the authoritative completed batch list. Opening stock stays
    // Unassigned unless a matching completed batch is missing from the report.
    final completed = (data['_completedProductionBatches'] as List?)?.whereType<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
    num number(dynamic value) => value is num ? value : num.tryParse('${value ?? 0}') ?? 0;
    String normal(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    for (final batch in completed) {
      final remainingCb = number(batch['produced_cb']) - number(batch['used_cb']);
      final remainingTrays = number(batch['produced_trays']) - number(batch['used_trays']);
      if (remainingCb <= 0 && remainingTrays <= 0) continue;
      final productName = normal('${batch['product_name'] ?? batch['product'] ?? ''}');
      _BatchRegisterGroup? group;
      for (final candidate in groups) {
        if (normal(candidate.name) == productName) {
          group = candidate;
          break;
        }
      }
      if (group == null) continue;
      final code = '${batch['code'] ?? '—'}'.trim();
      final date = _shortRegisterDate('${batch['planned_date'] ?? batch['plannedDate'] ?? ''}');
      if (group.entries.any((entry) => entry.code == code && entry.date == date)) continue;
      // Only consume an Unassigned row when its amount matches this missing
      // completed batch. This avoids hiding legitimate opening adjustments.
      final unassignedIndex = group.entries.indexWhere((entry) =>
          entry.code.toLowerCase().contains('unassigned') && number(entry.cb) >= remainingCb && number(entry.trays) >= remainingTrays);
      if (unassignedIndex != -1) group.entries.removeAt(unassignedIndex);
      group.entries.add(_BatchRegisterEntry(
        date: date,
        code: code,
        cb: remainingCb,
        trays: remainingTrays,
      ));
    }
    return groups;
  }

  Widget _textCell(String value, {required int flex, TextAlign align = TextAlign.left, bool strong = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        textAlign: align,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5, fontWeight: strong ? FontWeight.w700 : FontWeight.w500),
      ),
    );
  }

  Widget _group(BuildContext context, _BatchRegisterGroup group, bool showTrays) {
    final scheme = Theme.of(context).colorScheme;
    final collapsed = _collapsed.contains(group.name);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() {
              if (collapsed) {
                _collapsed.remove(group.name);
              } else {
                _collapsed.add(group.name);
              }
            }),
            child: Ink(
              decoration: const BoxDecoration(gradient: AppBrand.gradient),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                Icon(collapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded, color: Colors.white, size: 21),
                const SizedBox(width: 8),
                Expanded(child: Text(group.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5, letterSpacing: .2))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(20)),
                  child: Text('${qtyInt(group.totalCb)} ${U.cb}', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ]),
            ),
          ),
        ),
        if (!collapsed) ...[
          Container(
            color: scheme.primaryContainer.withValues(alpha: .55),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(children: [
              _textCell('Mfg. Date', flex: 2, strong: true),
              _textCell('Batch Code', flex: 3, strong: true),
              _textCell('Stock (${U.cb})', flex: 2, align: TextAlign.right, strong: true),
              if (showTrays) _textCell(U.tray, flex: 1, align: TextAlign.right, strong: true),
            ]),
          ),
          for (var i = 0; i < group.entries.length; i++)
            Container(
              color: i.isEven ? scheme.surface : scheme.primaryContainer.withValues(alpha: .22),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Expanded(
                  flex: 2,
                  child: Row(children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: i.isEven ? AppColors.blue : AppColors.teal)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(group.entries[i].date, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500))),
                  ]),
                ),
                _textCell(group.entries[i].code, flex: 3, strong: true),
                _textCell(qtyInt(group.entries[i].cb), flex: 2, align: TextAlign.right),
                if (showTrays) _textCell(qtyInt(group.entries[i].trays), flex: 1, align: TextAlign.right),
              ]),
            ),
          Container(
            color: scheme.secondaryContainer.withValues(alpha: .65),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              _textCell('TOTAL', flex: 5, strong: true),
              _textCell('${qtyInt(group.totalCb)} ${U.cb}', flex: 2, align: TextAlign.right, strong: true),
              if (showTrays) _textCell(qtyInt(group.totalTrays), flex: 1, align: TextAlign.right, strong: true),
            ]),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return SectionCard(
            title: IndustryPack.current.runStockTitle,
            child: ErrorState(snap.error!, onRetry: () => setState(() => _future = _load())),
          );
        }
        if (!snap.hasData) {
          return SectionCard(
            title: IndustryPack.current.runStockTitle,
            child: const SizedBox(height: 70, child: Center(child: CircularProgressIndicator())),
          );
        }
        final data = snap.data!;
        final groups = _parseGroups(data);
        final columns = (data['columns'] as List?)?.cast<String>() ?? const <String>[];
        final showTrays = CompanyProfile.usesTrays && columns.length >= 4;
        return SectionCard(
          title: IndustryPack.current.runStockTitle,
          stackTrailingOnNarrow: true,
          trailing: Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: _exporting ? null : () => _export(data, pdf: true),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: Text(tr('PDF')),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB91C1C), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), minimumSize: const Size(0, 32)),
            ),
            OutlinedButton.icon(
              onPressed: _exporting ? null : () => _export(data, pdf: false),
              icon: const Icon(Icons.table_view_outlined, size: 16),
              label: Text(tr('Excel')),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF047857), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), minimumSize: const Size(0, 32)),
            ),
          ]),
          child: groups.isEmpty
              ? EmptyState(U.ize('No completed batches with remaining stock'))
              : Column(children: [for (final group in groups) _group(context, group, showTrays)]),
        );
      },
    );
  }
}

class _BatchRegisterGroup {
  final String name;
  final List<_BatchRegisterEntry> entries = [];
  dynamic totalCb;
  dynamic totalTrays;
  _BatchRegisterGroup(this.name);
}

class _BatchRegisterEntry {
  final String date;
  final String code;
  final dynamic cb;
  final dynamic trays;
  const _BatchRegisterEntry({required this.date, required this.code, required this.cb, required this.trays});
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
  final reference = TextEditingController();
  bool busy = false;

  bool get _hasTray => CompanyProfile.usesTrays && (widget.item['bottles_per_tray'] as num? ?? 0) > 0;

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      // Set-to-count (absolute quantity, no deduction) — safe to send later.
      final sent = await OfflineQueue.instance.submit(
        context.read<AuthController>(),
        method: 'PUT',
        path: '/inventory/stock',
        label: 'Stock count',
        body: {
          'productId': widget.item['product_id'],
          'qtyCb': int.tryParse(cb.text) ?? 0,
          'qtyTrays': _hasTray ? (int.tryParse(trays.text) ?? 0) : 0,
          'note': note.text.trim(),
          'reference': reference.text.trim(), // stock-ledger doc no (count sheet / memo)
        },
      );
      if (mounted && sent.queued) showOk(context, 'Stock count saved on this phone — it will sync when internet returns.');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktopForm = isWindowsPlatform && MediaQuery.sizeOf(context).width >= 760;
    final referenceField = TextField(controller: reference, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('Reference / count sheet no (optional)'), hintText: 'e.g. PC-0912', prefixIcon: const Icon(Icons.tag_rounded, size: 18)));
    final noteField = TextField(controller: note, decoration: InputDecoration(labelText: tr('Note (optional)'), hintText: 'e.g. Opening stock 04 Aug 2026'));
    return AlertDialog(
      title: Text('Set Stock — ${widget.item['name']}'),
      content: SizedBox(
        width: desktopForm ? 720 : 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_hasTray
                  ? 'Current: ${qtyInt(widget.item['qty_cb'])} ${U.cb} + ${qtyInt(widget.item['qty_trays'])} ${U.trayLc}. Enter the exact real stock below — it replaces the current numbers.'
                  : 'Current: ${qtyInt(widget.item['qty_cb'])} ${U.cb}. Enter the exact real stock below — it replaces the current numbers.',
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
          if (desktopForm)
            Row(children: [
              Expanded(child: referenceField),
              const SizedBox(width: 12),
              Expanded(child: noteField),
            ])
          else ...[
            referenceField,
            const SizedBox(height: 12),
            noteField,
          ],
          const SizedBox(height: 8),
          Text(tr('The difference is posted to the stock ledger as "Stock set (physical count)" with this reference.'), style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
  final reference = TextEditingController();
  final party = TextEditingController();
  bool busy = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    context.read<AuthController>().api.get('/products').then((json) {
      setState(() {
        products = ((json as Map)['products'] as List)
            .cast<Map<String, dynamic>>()
            .where((p) => (p['active'] as num? ?? 1) != 0)
            .toList();
        productId = products.isNotEmpty ? products.first['id'] as int : null;
      });
    }).catchError((e) {
      setState(() => loadError = '$e');
    });
  }

  Map<String, dynamic>? get _product =>
      productId == null ? null : products.firstWhere((p) => p['id'] == productId, orElse: () => products.first);

  bool get _hasTray => CompanyProfile.usesTrays && (_product?['bottles_per_tray'] as num? ?? 0) > 0;

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      // MAN-13: no connection → kept on this phone and sent automatically later.
      final sent = await OfflineQueue.instance.submit(
        context.read<AuthController>(),
        method: 'POST',
        path: '/inventory/receipt',
        label: 'Stock receipt',
        body: {
          'productId': productId,
          'qtyCb': int.tryParse(cb.text) ?? 0,
          if (_hasTray) 'qtyTrays': int.tryParse(trays.text) ?? 0,
          'note': note.text.trim(),
          'reference': reference.text.trim(), // stock-ledger doc no (GRN / challan / return memo)
          'party': party.text.trim(),
        },
      );
      if (mounted && sent.queued) showOk(context, 'Receipt saved on this phone — it will sync when internet returns.');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktopForm = isWindowsPlatform && MediaQuery.sizeOf(context).width >= 760;
    final productField = DropdownButtonFormField<int>(
      key: ValueKey('rcpt-$productId'),
      initialValue: productId,
      isExpanded: true,
      decoration: InputDecoration(labelText: tr('Product *'), suffixIcon: ScanPickButton(rows: products, onPicked: (p) => setState(() => productId = p['id'] as int))),
      items: [for (final p in products) DropdownMenuItem(value: p['id'] as int, child: Text(ItemCode.pick(p), overflow: TextOverflow.ellipsis))],
      onChanged: (v) => setState(() => productId = v),
    );
    final quantities = Row(children: [
      Expanded(child: TextField(controller: cb, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('${U.carton} (${U.cb})')))),
      if (_hasTray) ...[
        const SizedBox(width: 12),
        Expanded(child: TextField(controller: trays, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: U.tray))),
      ],
    ]);
    final referenceField = TextField(controller: reference, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('GRN / challan / ref no'), hintText: 'e.g. GRN-0451', prefixIcon: const Icon(Icons.tag_rounded, size: 18)));
    final partyField = TextField(controller: party, decoration: InputDecoration(labelText: tr('From (party / depot)'), hintText: tr('optional')));
    final trayHint = _hasTray
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('1 ${U.trayLc} = ${_product!['bottles_per_tray']} ${U.piece.toLowerCase()}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          )
        : const SizedBox.shrink();
    return AlertDialog(
      title: Text(tr('Receive Stock')),
      content: SizedBox(
        width: desktopForm ? 760 : 400,
        child: loadError != null
            ? Text(loadError!)
            : products.isEmpty
                ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    if (desktopForm)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: productField),
                        const SizedBox(width: 12),
                        Expanded(child: Column(children: [quantities, trayHint])),
                      ])
                    else ...[
                      productField,
                      const SizedBox(height: 12),
                      quantities,
                      if (_hasTray) trayHint,
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: referenceField),
                      const SizedBox(width: 12),
                      Expanded(child: partyField),
                    ]),
                    const SizedBox(height: 12),
                    TextField(controller: note, decoration: InputDecoration(labelText: tr('Note (optional)'))),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(tr('Goods received against a supplier invoice? Use Billing → Purchases (Inward) instead — it records the bill number, GST and payable too.'),
                          style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                  ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Receive')),
      ],
    );
  }
}
