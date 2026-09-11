import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/company.dart';
import '../../core/download.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// Opens the complete stock ledger of one item (finished product or raw /
/// packing material) as a full-height sheet — SAP "material document" style:
/// every inward (supplier bill no., production batch, receipt / GRN, void,
/// cancelled invoice) and every outward (dispatch no., sale invoice no.,
/// issue / consumption, adjustment) with a running balance that ends at
/// today's stock. Newest first; tap a row to open its document.
Future<void> showItemHistory(BuildContext context, {required String type, required int id, required String name}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width > 1100 ? 1080 : double.infinity),
    builder: (_) => FractionallySizedBox(heightFactor: 0.92, child: ItemHistoryView(type: type, id: id, name: name)),
  );
}

/// Movement kind → label / icon / colour, shared by the item sheet and the
/// Stock Ledger screen (register + balances).
class StockKinds {
  static String label(String k) {
    switch (k) {
      case 'PURCHASE': return tr('Purchase (supplier bill)');
      case 'PURCHASE_CANCEL': return tr('Purchase cancelled (reversed)');
      case 'RECEIPT': return tr('Receipt (GRN)');
      case 'RECEIVED': return tr('Received (manual)');
      case 'OPENING': return tr('Opening stock');
      case 'PRODUCTION': return tr('Production');
      case 'CONSUMED': return tr('Issue / consumed');
      case 'RECIPE': return tr('Recipe consumption');
      case 'DISPATCH': return tr('Dispatch');
      case 'DISPATCH_VOID': return tr('Dispatch voided (returned)');
      case 'SALE': return tr('Sale (invoice)');
      case 'SALE_CANCEL': return tr('Invoice cancelled (restored)');
      case 'ADJUSTMENT': return tr('Adjustment (approved)');
      case 'SET_STOCK': return tr('Stock set (physical count)');
      case 'REVERSAL': return tr('Reversal');
      case 'DELETED': return tr('Item deleted');
      case 'SYNC': return tr('Balance synced');
      case 'EXTERNAL': return tr('Changed outside the app');
      case 'BILLING': return tr('Billing');
      case 'OTHER': return tr('Other');
    }
    return k;
  }

  static IconData icon(String k) {
    switch (k) {
      case 'PURCHASE': return Icons.receipt_long_rounded;
      case 'PURCHASE_CANCEL': return Icons.receipt_long_outlined;
      case 'RECEIPT': case 'RECEIVED': return Icons.south_west_rounded;
      case 'OPENING': return Icons.flag_rounded;
      case 'PRODUCTION': return Icons.precision_manufacturing_rounded;
      case 'CONSUMED': case 'RECIPE': return Icons.north_east_rounded;
      case 'DISPATCH': return Icons.local_shipping_rounded;
      case 'DISPATCH_VOID': return Icons.undo_rounded;
      case 'SALE': return Icons.point_of_sale_rounded;
      case 'SALE_CANCEL': return Icons.replay_rounded;
      case 'ADJUSTMENT': return Icons.fact_check_rounded;
      case 'SET_STOCK': return Icons.edit_note_rounded;
      case 'DELETED': return Icons.delete_outline_rounded;
      case 'SYNC': case 'EXTERNAL': return Icons.sync_problem_rounded;
    }
    return Icons.tune_rounded;
  }

  /// Which document number a movement carries (for the "Doc no" column header / tooltip).
  static String docLabel(String k) {
    switch (k) {
      case 'PURCHASE': case 'PURCHASE_CANCEL': return tr('Supplier bill no');
      case 'SALE': case 'SALE_CANCEL': return tr('Invoice no');
      case 'DISPATCH': case 'DISPATCH_VOID': return tr('Dispatch no');
      case 'PRODUCTION': return tr('Batch code');
      case 'ADJUSTMENT': return tr('Adjustment no');
      case 'RECIPE': return tr('Recipe');
    }
    return tr('Reference');
  }

  /// Filter chips shown on the ledger screens (most used first).
  static const filterKinds = ['PURCHASE', 'PRODUCTION', 'RECEIPT', 'RECEIVED', 'DISPATCH', 'SALE', 'CONSUMED', 'RECIPE', 'ADJUSTMENT', 'SET_STOCK', 'DISPATCH_VOID', 'SALE_CANCEL', 'PURCHASE_CANCEL', 'OPENING', 'EXTERNAL'];
}

class ItemHistoryView extends StatefulWidget {
  final String type; // 'product' | 'material'
  final int id;
  final String name;
  const ItemHistoryView({super.key, required this.type, required this.id, required this.name});
  @override
  State<ItemHistoryView> createState() => _ItemHistoryViewState();
}

class _ItemHistoryViewState extends State<ItemHistoryView> {
  late Future<Map<String, dynamic>> _future;
  String _dir = ''; // '' | in | out
  String _kind = '';
  DateTime? _from;
  DateTime? _to;
  bool _legacy = false; // server without ff-stockledger → derived history from /billing/ledger
  bool _exporting = false;

  @override
  void initState() { super.initState(); _future = _load(); }

  String get _range => '${_from == null ? '' : '&from=${ymd(_from!)}'}${_to == null ? '' : '&to=${ymd(_to!)}'}';

  Future<Map<String, dynamic>> _load() async {
    final api = context.read<AuthController>().api;
    try {
      final d = ((await api.get('/stock/ledger?type=${widget.type}&id=${widget.id}$_range')) as Map).cast<String, dynamic>();
      _legacy = false;
      return d;
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
    }
    // Older server: the billing module's derived IN/OUT history (no receipts / adjustments detail).
    final d = ((await api.get('/billing/ledger?type=${widget.type}&id=${widget.id}')) as Map).cast<String, dynamic>();
    _legacy = true;
    return d;
  }

  Future<void> _pick(bool isFrom) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: (isFrom ? _from : _to) ?? now, firstDate: DateTime(2020), lastDate: now.add(const Duration(days: 1)));
    if (d == null) return;
    setState(() { if (isFrom) { _from = d; } else { _to = d; } _future = _load(); });
  }

  Future<void> _csv() async {
    setState(() => _exporting = true);
    try {
      final bytes = await context.read<AuthController>().api.getBytes('/stock/ledger.csv?type=${widget.type}&id=${widget.id}');
      downloadBytes('stock-ledger-${widget.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}.csv', bytes, 'text/csv');
      if (mounted) showOk(context, tr('Ledger exported (CSV) — open in Excel or share.'));
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _open(String link) {
    if (link.isEmpty) return;
    final router = GoRouter.of(context);
    Navigator.pop(context);
    router.push(link);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthController>();
    final canBill = auth.canManageBilling;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
        child: Row(children: [
          Icon(widget.type == 'product' ? Icons.inventory_2_rounded : Icons.widgets_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('${widget.name} · ${tr('Stock ledger')}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
          if (!_legacy)
            IconButton(tooltip: tr('Export CSV'), onPressed: _exporting ? null : _csv, icon: const Icon(Icons.table_view_rounded)),
          if (canBill)
            TextButton.icon(
              onPressed: () => _open('/billing/purchases/new?item=${widget.type}:${widget.id}'),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(tr('Enter supplier bill')),
            ),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      Expanded(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorState(snap.error!, onRetry: () => setState(() => _future = _load()));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final d = snap.data!;
            final unit = (d['unit'] ?? '').toString();
            final all = (d['rows'] as List).cast<Map<String, dynamic>>();
            final kindsHere = <String>{for (final r in all) (r['kind'] ?? '').toString()};
            final rows = all.where((r) => (_dir.isEmpty || r['dir'] == _dir) && (_kind.isEmpty || r['kind'] == _kind)).toList();
            final drift = (d['drift'] as num?) ?? 0;
            final ranged = _from != null || _to != null;
            return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(width: 170, child: KpiCard(label: tr('In stock now'), value: '${qty(d['stock'])} $unit', icon: Icons.warehouse_rounded, tint: AppColors.blue, sub: (d['code'] ?? '').toString().isEmpty ? null : '${tr('Code')} ${d['code']}')),
                if (ranged) SizedBox(width: 170, child: KpiCard(label: tr('Opening (period)'), value: '${qty(d['opening'])} $unit', icon: Icons.flag_rounded, tint: AppColors.amber)),
                SizedBox(width: 170, child: KpiCard(label: ranged ? tr('In (period)') : tr('Total in'), value: '+${qty(d['totalIn'])}', icon: Icons.south_west_rounded, tint: AppColors.green, sub: '${all.where((r) => r['dir'] == 'in' && r['kind'] != 'OPENING').length} ${tr('entries')}')),
                SizedBox(width: 170, child: KpiCard(label: ranged ? tr('Out (period)') : tr('Total out'), value: '−${qty(d['totalOut'])}', icon: Icons.north_east_rounded, tint: AppColors.red, sub: '${all.where((r) => r['dir'] == 'out').length} ${tr('entries')}')),
                if (ranged) SizedBox(width: 170, child: KpiCard(label: tr('Closing (period)'), value: '${qty(d['closing'])} $unit', icon: Icons.assignment_turned_in_rounded, tint: AppColors.blue)),
              ]),
              if (drift != 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.amber),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${tr('Stock differs from the ledger balance by')} ${qty(drift)} $unit — ${tr('a SYNC line will be posted at the next server restart.')}', style: const TextStyle(fontSize: 12.5))),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final e in {'': tr('All'), 'in': tr('In only'), 'out': tr('Out only')}.entries)
                  ChoiceChip(label: Text(e.value), selected: _dir == e.key, onSelected: (_) => setState(() => _dir = e.key)),
                if (!_legacy) ...[
                  const SizedBox(width: 6),
                  OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.calendar_today_rounded, size: 16), label: Text(_from == null ? tr('From') : fmtDate(ymd(_from!)))),
                  OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.calendar_today_rounded, size: 16), label: Text(_to == null ? tr('To') : fmtDate(ymd(_to!)))),
                  if (ranged) IconButton(tooltip: tr('Clear dates'), onPressed: () => setState(() { _from = null; _to = null; _future = _load(); }), icon: const Icon(Icons.clear_rounded, size: 18)),
                ],
              ]),
              if (kindsHere.length > 1) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  FilterChip(label: Text(tr('All types')), selected: _kind.isEmpty, onSelected: (_) => setState(() => _kind = '')),
                  for (final k in StockKinds.filterKinds.where(kindsHere.contains))
                    FilterChip(avatar: Icon(StockKinds.icon(k), size: 15), label: Text(StockKinds.label(k)), selected: _kind == k, onSelected: (_) => setState(() => _kind = _kind == k ? '' : k)),
                ]),
              ],
              const SizedBox(height: 12),
              SectionCard(
                title: '${tr('Movements (newest first)')} · ${rows.length}',
                child: rows.isEmpty
                    ? EmptyState(tr('No movements yet — enter a supplier bill to receive stock against an invoice number.'), icon: Icons.history_rounded)
                    : AppDataTable(
                        columns: [tr('Date'), tr('Movement'), tr('In / Out'), tr('Qty'), tr('Balance'), tr('Doc / Bill no'), tr('Party / Destination'), tr('Note'), tr('By')],
                        onRowTap: (i) => _open((rows[i]['link'] ?? '').toString()),
                        pageSize: 100,
                        rows: [
                          for (final r in rows)
                            [
                              Tooltip(message: (r['at'] ?? '').toString().isEmpty ? '' : '${tr('Recorded')} ${fmtDateTime(r['at'])}', child: Text(fmtDateWithDay(r['date']))),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(StockKinds.icon(r['kind'] as String), size: 16, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text(StockKinds.label(r['kind'] as String)),
                              ]),
                              StatusChip(r['dir'] == 'in' ? 'IN' : 'OUT'),
                              Text('${r['dir'] == 'in' ? '+' : '−'}${qty(r['qty'])} $unit${(r['qty2'] as num? ?? 0) != 0 ? '  (${(r['qty2'] as num) > 0 ? '+' : ''}${qty(r['qty2'])} ${U.trayLc})' : ''}',
                                  style: TextStyle(fontWeight: FontWeight.w700, color: r['dir'] == 'in' ? AppColors.green : AppColors.red)),
                              Text('${qty(r['balance'])} $unit', style: const TextStyle(fontWeight: FontWeight.w600)),
                              _DocCell(r),
                              (r['party'] as String? ?? '').isEmpty ? '—' : r['party'],
                              (r['note'] as String? ?? '').isEmpty ? '—' : r['note'],
                              (r['by'] as String? ?? '').isEmpty ? '—' : r['by'],
                            ],
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                _legacy
                    ? tr('This server has not been updated with the stock ledger yet — showing the derived purchase / production / dispatch / sale history. Ask your admin to run the stock-ledger update.')
                    : tr('Every stock change is recorded automatically with its document number — supplier bill, dispatch no., invoice no., batch code, adjustment code. Tap a row to open the document. "Opening stock" is the balance carried from before the ledger started.'),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}

/// Document number cell: bill / invoice / dispatch / batch no. (+ our entry
/// no. for purchases) — highlighted when it links to a document.
class _DocCell extends StatelessWidget {
  final Map<String, dynamic> r;
  const _DocCell(this.r);
  @override
  Widget build(BuildContext context) {
    final ref = (r['ref'] as String? ?? '').trim();
    final doc2 = (r['doc2'] as String? ?? '').trim();
    final link = (r['link'] as String? ?? '');
    if (ref.isEmpty && doc2.isEmpty) return const Text('—');
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: StockKinds.docLabel((r['kind'] ?? '').toString()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (ref.isNotEmpty)
          Text(ref, style: TextStyle(fontWeight: FontWeight.w700, color: link.isNotEmpty ? primary : null, decoration: link.isNotEmpty ? TextDecoration.underline : null, decorationColor: primary)),
        if (doc2.isNotEmpty) Text(doc2, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}
