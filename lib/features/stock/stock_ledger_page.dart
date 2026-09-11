import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/download.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import '../billing/item_history_page.dart';

/// Stock Ledger — the SAP-style movement register for the whole factory:
///   • Movements: every inward / outward of every item in a period, with the
///     document number (supplier bill, dispatch, invoice, batch, adjustment),
///     party, user and the running balance after each line (MB51).
///   • Balances: opening / in / out / closing per item for the period plus
///     the live stock (MB5B / MMBE).
///   • Documents: one line per document number — how many items, total in / out.
/// Tap any item to open its complete per-item ledger; tap a document to open it.
class StockLedgerPage extends StatefulWidget {
  final String? tab;
  const StockLedgerPage({super.key, this.tab});
  @override
  State<StockLedgerPage> createState() => _StockLedgerPageState();
}

class _StockLedgerPageState extends State<StockLedgerPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  static const _tabs = ['movements', 'balances', 'documents'];

  @override
  void initState() {
    super.initState();
    final i = _tabs.indexOf(widget.tab ?? '');
    _tab = TabController(length: _tabs.length, vsync: this, initialIndex: i < 0 ? 0 : i);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Material(
        color: Theme.of(context).colorScheme.surface,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: tr('Movements')),
              Tab(text: tr('Period Balances')),
              Tab(text: tr('Documents')),
            ],
          ),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: TabBarView(controller: _tab, children: const [
          _MovementsTab(),
          _BalancesTab(),
          _DocumentsTab(),
        ]),
      ),
    ]);
  }
}

/// Shared period + filters state helpers.
mixin _PeriodMixin<T extends StatefulWidget> on State<T> {
  late DateTime from;
  late DateTime to;

  void initPeriod() {
    final now = DateTime.now();
    from = DateTime(now.year, now.month, 1);
    to = now;
  }

  String get periodQuery => 'from=${ymd(from)}&to=${ymd(to)}';

  Future<bool> pickDate(bool isFrom) async {
    final d = await showDatePicker(context: context, initialDate: isFrom ? from : to, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (d == null) return false;
    setState(() { if (isFrom) { from = d; } else { to = d; } });
    return true;
  }

  void setPreset(int which) {
    final now = DateTime.now();
    setState(() {
      switch (which) {
        case 0: from = DateTime(now.year, now.month, now.day); to = now; break; // today
        case 1: from = now.subtract(const Duration(days: 6)); to = now; break; // 7 days
        case 2: from = DateTime(now.year, now.month, 1); to = now; break; // this month
        case 3: from = DateTime(now.year, now.month - 1, 1); to = DateTime(now.year, now.month, 0); break; // last month
        case 4: from = DateTime(now.month >= 4 ? now.year : now.year - 1, 4, 1); to = now; break; // FY
      }
    });
  }

  List<Widget> periodButtons(VoidCallback reload) => [
        OutlinedButton.icon(onPressed: () async { if (await pickDate(true)) reload(); }, icon: const Icon(Icons.calendar_today_rounded, size: 16), label: Text('${tr('From')} ${fmtDate(ymd(from))}')),
        OutlinedButton.icon(onPressed: () async { if (await pickDate(false)) reload(); }, icon: const Icon(Icons.calendar_today_rounded, size: 16), label: Text('${tr('To')} ${fmtDate(ymd(to))}')),
        PopupMenuButton<int>(
          tooltip: tr('Quick period'),
          onSelected: (i) { setPreset(i); reload(); },
          itemBuilder: (_) => [
            PopupMenuItem(value: 0, child: Text(tr('Today'))),
            PopupMenuItem(value: 1, child: Text(tr('Last 7 days'))),
            PopupMenuItem(value: 2, child: Text(tr('This month'))),
            PopupMenuItem(value: 3, child: Text(tr('Last month'))),
            PopupMenuItem(value: 4, child: Text(tr('This financial year'))),
          ],
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.date_range_rounded, size: 18), const SizedBox(width: 4), Text(tr('Quick period'))])),
        ),
      ];
}

Widget _notPatched(BuildContext context, Object error, VoidCallback retry) {
  if (error is ApiException && error.status == 404) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: EmptyState(
        tr('The stock ledger is not enabled on this server yet. Ask your admin to run the stock-ledger update (tools/ff-stockledger.sh) — after that every stock movement is recorded here automatically.'),
        icon: Icons.history_rounded,
      ),
    );
  }
  return ErrorState(error, onRetry: retry);
}

Future<void> _exportCsv(BuildContext context, String path, String filename, ValueChanged<bool> busy) async {
  busy(true);
  try {
    final bytes = await context.read<AuthController>().api.getBytes(path);
    downloadBytes(filename, bytes, 'text/csv');
    if (context.mounted) showOk(context, tr('Exported (CSV) — open in Excel or share.'));
  } catch (e) {
    if (context.mounted) showErr(context, e);
  } finally {
    busy(false);
  }
}

// ---------------------------------------------------------------- Movements
class _MovementsTab extends StatefulWidget {
  const _MovementsTab();
  @override
  State<_MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends State<_MovementsTab> with _PeriodMixin, AutomaticKeepAliveClientMixin {
  Future<Map<String, dynamic>>? _future;
  String _dir = '';
  String _kind = '';
  String _type = '';
  final _q = TextEditingController();
  bool _exporting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); initPeriod(); _future = _load(); }

  @override
  void dispose() { _q.dispose(); super.dispose(); }

  String get _filters => '$periodQuery${_dir.isEmpty ? '' : '&dir=$_dir'}${_kind.isEmpty ? '' : '&kind=$_kind'}${_type.isEmpty ? '' : '&type=$_type'}${_q.text.trim().isEmpty ? '' : '&q=${Uri.encodeQueryComponent(_q.text.trim())}'}';

  Future<Map<String, dynamic>> _load() async => ((await context.read<AuthController>().api.get('/stock/register?$_filters')) as Map).cast<String, dynamic>();
  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ...periodButtons(_reload),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: '', label: Text(tr('All'))),
            ButtonSegment(value: 'in', label: Text(tr('In')), icon: const Icon(Icons.south_west_rounded, size: 16)),
            ButtonSegment(value: 'out', label: Text(tr('Out')), icon: const Icon(Icons.north_east_rounded, size: 16)),
          ],
          selected: {_dir},
          showSelectedIcon: false,
          onSelectionChanged: (v) { _dir = v.first; _reload(); },
        ),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: '', label: Text(tr('All items'))),
            ButtonSegment(value: 'product', label: Text(tr('Products'))),
            ButtonSegment(value: 'material', label: Text(tr('Materials'))),
          ],
          selected: {_type},
          showSelectedIcon: false,
          onSelectionChanged: (v) { _type = v.first; _reload(); },
        ),
        SizedBox(
          width: 260,
          child: TextField(
            controller: _q,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              hintText: tr('Bill / dispatch / invoice no, party, note…'),
              suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear_rounded, size: 16), onPressed: () { _q.clear(); _reload(); }),
            ),
            onSubmitted: (_) => _reload(),
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: _exporting ? null : () => _exportCsv(context, '/stock/register.csv?$_filters', 'stock-register-${ymd(from)}-to-${ymd(to)}.csv', (b) { if (mounted) setState(() => _exporting = b); }),
          icon: const Icon(Icons.table_view_rounded, size: 18),
          label: Text(_exporting ? tr('Preparing…') : tr('Export CSV')),
        ),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        FilterChip(label: Text(tr('All types')), selected: _kind.isEmpty, onSelected: (_) { _kind = ''; _reload(); }),
        for (final k in StockKinds.filterKinds)
          FilterChip(avatar: Icon(StockKinds.icon(k), size: 15), label: Text(StockKinds.label(k)), selected: _kind == k, onSelected: (_) { _kind = _kind == k ? '' : k; _reload(); }),
      ]),
      const SizedBox(height: 6),
      Text(tr('Every stock change of every product and material, with its document number and the balance after the movement — like an SAP material document list (MB51). Tap the item to open its full ledger; tap the document number to open the bill / dispatch / batch.'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
      const SizedBox(height: 16),
      FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return _notPatched(context, snap.error!, _reload);
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
          final d = snap.data!;
          final rows = (d['rows'] as List).cast<Map<String, dynamic>>();
          final kinds = ((d['kinds'] as Map?) ?? {}).cast<String, dynamic>();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(width: 170, child: KpiCard(label: tr('Movements'), value: '${d['count']}', icon: Icons.history_rounded, tint: AppColors.blue, sub: '${fmtDate(d['from'])} – ${fmtDate(d['to'])}')),
              SizedBox(width: 170, child: KpiCard(label: tr('Total in'), value: '+${qty(d['totalIn'])}', icon: Icons.south_west_rounded, tint: AppColors.green, sub: tr('all units summed'))),
              SizedBox(width: 170, child: KpiCard(label: tr('Total out'), value: '−${qty(d['totalOut'])}', icon: Icons.north_east_rounded, tint: AppColors.red, sub: tr('all units summed'))),
              SizedBox(width: 170, child: KpiCard(label: tr('Movement types'), value: '${kinds.length}', icon: Icons.category_rounded, tint: AppColors.violet, sub: kinds.entries.map((e) => '${StockKinds.label(e.key)} ${e.value}').take(3).join(' · '))),
            ]),
            const SizedBox(height: 16),
            SectionCard(
              title: tr('Movement register'),
              child: rows.isEmpty
                  ? EmptyState(tr('No stock movements in this period.'), icon: Icons.history_rounded)
                  : AppDataTable(
                      columns: [tr('Date'), tr('Item'), tr('Movement'), tr('In / Out'), tr('Qty'), tr('Balance'), tr('Doc / Bill no'), tr('Party / Destination'), tr('Note'), tr('By')],
                      pageSize: 100,
                      onRowTap: (i) => showItemHistory(context, type: rows[i]['type'] as String, id: rows[i]['itemId'] as int, name: rows[i]['item'] as String),
                      rows: [
                        for (final r in rows)
                          [
                            Tooltip(message: (r['at'] ?? '').toString().isEmpty ? '' : '${tr('Recorded')} ${fmtDateTime(r['at'])}', child: Text(fmtDate(r['date']))),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text(r['item'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('${r['type'] == 'product' ? tr('Product') : tr('Material')}${(r['code'] ?? '').toString().isEmpty ? '' : ' · ${r['code']}'}', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                            ]),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(StockKinds.icon(r['kind'] as String), size: 16, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(StockKinds.label(r['kind'] as String)),
                            ]),
                            StatusChip(r['dir'] == 'in' ? 'IN' : 'OUT'),
                            Text('${r['dir'] == 'in' ? '+' : '−'}${qty(r['qty'])} ${r['unit']}', style: TextStyle(fontWeight: FontWeight.w700, color: r['dir'] == 'in' ? AppColors.green : AppColors.red)),
                            Text('${qty(r['balance'])} ${r['unit']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            _DocLink(r),
                            (r['party'] as String? ?? '').isEmpty ? '—' : r['party'],
                            (r['note'] as String? ?? '').isEmpty ? '—' : r['note'],
                            (r['by'] as String? ?? '').isEmpty ? '—' : r['by'],
                          ],
                      ],
                    ),
            ),
          ]);
        },
      ),
    ]);
  }
}

/// Document number that opens the document (bill / invoice / dispatch / batch) when tapped.
class _DocLink extends StatelessWidget {
  final Map<String, dynamic> r;
  const _DocLink(this.r);
  @override
  Widget build(BuildContext context) {
    final ref = (r['ref'] as String? ?? '').trim();
    final doc2 = (r['doc2'] as String? ?? '').trim();
    final link = (r['link'] as String? ?? '');
    if (ref.isEmpty && doc2.isEmpty) return const Text('—');
    final primary = Theme.of(context).colorScheme.primary;
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (ref.isNotEmpty) Text(ref, style: TextStyle(fontWeight: FontWeight.w700, color: link.isNotEmpty ? primary : null, decoration: link.isNotEmpty ? TextDecoration.underline : null, decorationColor: primary)),
      if (doc2.isNotEmpty) Text(doc2, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
    if (link.isEmpty) return Tooltip(message: StockKinds.docLabel((r['kind'] ?? '').toString()), child: text);
    return Tooltip(
      message: '${StockKinds.docLabel((r['kind'] ?? '').toString())} · ${tr('tap to open')}',
      child: InkWell(onTap: () => context.push(link), borderRadius: BorderRadius.circular(6), child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: text)),
    );
  }
}

// ---------------------------------------------------------------- Balances
class _BalancesTab extends StatefulWidget {
  const _BalancesTab();
  @override
  State<_BalancesTab> createState() => _BalancesTabState();
}

class _BalancesTabState extends State<_BalancesTab> with _PeriodMixin, AutomaticKeepAliveClientMixin {
  Future<Map<String, dynamic>>? _future;
  String _type = '';
  bool _movedOnly = false;
  final _q = TextEditingController();
  bool _exporting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); initPeriod(); _future = _load(); }

  @override
  void dispose() { _q.dispose(); super.dispose(); }

  String get _filters => '$periodQuery${_type.isEmpty ? '' : '&type=$_type'}${_movedOnly ? '&moved=1' : ''}${_q.text.trim().isEmpty ? '' : '&q=${Uri.encodeQueryComponent(_q.text.trim())}'}';
  Future<Map<String, dynamic>> _load() async => ((await context.read<AuthController>().api.get('/stock/balances?$_filters')) as Map).cast<String, dynamic>();
  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ...periodButtons(_reload),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: '', label: Text(tr('All items'))),
            ButtonSegment(value: 'product', label: Text(tr('Products'))),
            ButtonSegment(value: 'material', label: Text(tr('Materials'))),
          ],
          selected: {_type},
          showSelectedIcon: false,
          onSelectionChanged: (v) { _type = v.first; _reload(); },
        ),
        FilterChip(label: Text(tr('Moved in period only')), selected: _movedOnly, onSelected: (v) { _movedOnly = v; _reload(); }),
        SizedBox(
          width: 220,
          child: TextField(
            controller: _q,
            decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search_rounded, size: 18), hintText: tr('Item name / code'), suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear_rounded, size: 16), onPressed: () { _q.clear(); _reload(); })),
            onSubmitted: (_) => _reload(),
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: _exporting ? null : () => _exportCsv(context, '/stock/balances.csv?$_filters', 'stock-balances-${ymd(from)}-to-${ymd(to)}.csv', (b) { if (mounted) setState(() => _exporting = b); }),
          icon: const Icon(Icons.table_view_rounded, size: 18),
          label: Text(_exporting ? tr('Preparing…') : tr('Export CSV')),
        ),
      ]),
      const SizedBox(height: 6),
      Text(tr('Opening balance, total in, total out and closing balance of every item for the period, next to the live stock (MB5B). Opening = balance before the From date. Tap an item for its full ledger.'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
      const SizedBox(height: 16),
      FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return _notPatched(context, snap.error!, _reload);
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
          final d = snap.data!;
          final rows = (d['rows'] as List).cast<Map<String, dynamic>>();
          final products = rows.where((r) => r['type'] == 'product').toList();
          final materials = rows.where((r) => r['type'] == 'material').toList();
          Widget table(List<Map<String, dynamic>> list) => AppDataTable(
                columns: [tr('Item'), tr('Unit'), tr('Opening'), tr('In'), tr('Out'), tr('Closing'), tr('Stock now'), tr('Movements'), tr('Last movement')],
                pageSize: 100,
                highlight: (i) => (list[i]['closing'] as num) != (list[i]['stock'] as num),
                onRowTap: (i) => showItemHistory(context, type: list[i]['type'] as String, id: list[i]['itemId'] as int, name: list[i]['item'] as String),
                rows: [
                  for (final r in list)
                    [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(r['item'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if ((r['code'] ?? '').toString().isNotEmpty || (r['category'] ?? '').toString().isNotEmpty)
                          Text([if ((r['code'] ?? '').toString().isNotEmpty) r['code'], if ((r['category'] ?? '').toString().isNotEmpty) r['category']].join(' · '), style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                      ]),
                      r['unit'],
                      qty(r['opening']),
                      Text('+${qty(r['qin'])}', style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
                      Text('−${qty(r['qout'])}', style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
                      Text(qty(r['closing']), style: const TextStyle(fontWeight: FontWeight.w700)),
                      qty(r['stock']),
                      qtyInt(r['moves']),
                      (r['last'] ?? '').toString().isEmpty ? '—' : fmtDate(r['last']),
                    ],
                ],
              );
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(width: 170, child: KpiCard(label: tr('Items'), value: '${d['count']}', icon: Icons.inventory_2_rounded, tint: AppColors.blue, sub: '${products.length} ${tr('products')} · ${materials.length} ${tr('materials')}')),
              SizedBox(width: 170, child: KpiCard(label: tr('Total in'), value: '+${qty(d['totalIn'])}', icon: Icons.south_west_rounded, tint: AppColors.green, sub: tr('all units summed'))),
              SizedBox(width: 170, child: KpiCard(label: tr('Total out'), value: '−${qty(d['totalOut'])}', icon: Icons.north_east_rounded, tint: AppColors.red, sub: tr('all units summed'))),
              SizedBox(width: 170, child: KpiCard(label: tr('Movements'), value: '${d['moves']}', icon: Icons.history_rounded, tint: AppColors.violet, sub: '${fmtDate(d['from'])} – ${fmtDate(d['to'])}')),
            ]),
            const SizedBox(height: 16),
            if (products.isNotEmpty) ...[SectionCard(title: tr('Finished products'), child: table(products)), const SizedBox(height: 16)],
            if (materials.isNotEmpty) SectionCard(title: tr('Raw & packing materials'), child: table(materials)),
            if (rows.isEmpty) SectionCard(child: EmptyState(tr('No items match.'), icon: Icons.inventory_2_outlined)),
            const SizedBox(height: 8),
            Text(tr('A highlighted row means the closing balance on the To date differs from today\'s stock — movements after the To date, or a change made outside the app.'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ]);
        },
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Documents
class _DocumentsTab extends StatefulWidget {
  const _DocumentsTab();
  @override
  State<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<_DocumentsTab> with _PeriodMixin, AutomaticKeepAliveClientMixin {
  Future<Map<String, dynamic>>? _future;
  final _q = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); initPeriod(); _future = _load(); }

  @override
  void dispose() { _q.dispose(); super.dispose(); }

  Future<Map<String, dynamic>> _load() async => ((await context.read<AuthController>().api.get('/stock/documents?$periodQuery')) as Map).cast<String, dynamic>();
  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ...periodButtons(_reload),
        SizedBox(
          width: 260,
          child: TextField(
            controller: _q,
            decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search_rounded, size: 18), hintText: tr('Find a bill / dispatch / invoice / batch no'), suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear_rounded, size: 16), onPressed: () => setState(_q.clear))),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Text(tr('One line per document number in the period — supplier bills, dispatches, invoices, production batches, adjustments — with the number of item lines and the quantity moved. Tap to open the document.'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
      const SizedBox(height: 16),
      FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return _notPatched(context, snap.error!, _reload);
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
          final q = _q.text.trim().toLowerCase();
          final rows = (snap.data!['rows'] as List).cast<Map<String, dynamic>>().where((r) {
            if (q.isEmpty) return true;
            return '${r['ref']} ${r['doc2']} ${r['party']} ${StockKinds.label(r['kind'] as String)}'.toLowerCase().contains(q);
          }).toList();
          return SectionCard(
            title: '${tr('Documents')} · ${rows.length}',
            child: rows.isEmpty
                ? EmptyState(tr('No documents in this period.'), icon: Icons.description_outlined)
                : AppDataTable(
                    columns: [tr('Date'), tr('Movement'), tr('Doc / Bill no'), tr('Party / Destination'), tr('Item lines'), tr('Qty in'), tr('Qty out')],
                    pageSize: 100,
                    onRowTap: (i) { final l = (rows[i]['link'] ?? '').toString(); if (l.isNotEmpty) context.push(l); },
                    rows: [
                      for (final r in rows)
                        [
                          fmtDate(r['date']),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(StockKinds.icon(r['kind'] as String), size: 16, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(StockKinds.label(r['kind'] as String)),
                          ]),
                          _DocLink(r),
                          (r['party'] as String? ?? '').isEmpty ? '—' : r['party'],
                          qtyInt(r['lines']),
                          (r['qin'] as num) == 0 ? '—' : Text('+${qty(r['qin'])}', style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
                          (r['qout'] as num) == 0 ? '—' : Text('−${qty(r['qout'])}', style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
                        ],
                    ],
                  ),
          );
        },
      ),
    ]);
  }
}
