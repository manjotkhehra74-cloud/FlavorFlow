import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// Opens the IN / OUT history of one item (finished product or raw / packing
/// material) as a full-height sheet: purchases (with the supplier's bill
/// number), production, dispatches, sales, manual receipts and consumption —
/// newest first, with a running balance that ends at today's stock.
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

  @override
  void initState() { super.initState(); _future = _load(); }
  Future<Map<String, dynamic>> _load() async => ((await context.read<AuthController>().api.get('/billing/ledger?type=${widget.type}&id=${widget.id}')) as Map).cast<String, dynamic>();

  static String kindLabel(String k) {
    switch (k) {
      case 'PURCHASE': return tr('Purchase (supplier bill)');
      case 'PRODUCTION': return tr('Production');
      case 'DISPATCH': return tr('Dispatch');
      case 'SALE': return tr('Sale (invoice)');
      case 'RECEIVED': return tr('Received (manual)');
      case 'CONSUMED': return tr('Consumed');
      case 'OPENING': return tr('Opening / adjustment');
    }
    return k;
  }

  static IconData kindIcon(String k) {
    switch (k) {
      case 'PURCHASE': return Icons.receipt_long_rounded;
      case 'PRODUCTION': return Icons.precision_manufacturing_rounded;
      case 'DISPATCH': return Icons.local_shipping_rounded;
      case 'SALE': return Icons.point_of_sale_rounded;
      case 'RECEIVED': return Icons.south_west_rounded;
      case 'CONSUMED': return Icons.north_east_rounded;
    }
    return Icons.tune_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canBill = context.watch<AuthController>().canManageBilling;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
        child: Row(children: [
          Icon(widget.type == 'product' ? Icons.inventory_2_rounded : Icons.widgets_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('${widget.name} · ${tr('In / Out history')}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
          if (canBill)
            TextButton.icon(
              onPressed: () {
                final router = GoRouter.of(context); // grab before the sheet's context is disposed
                Navigator.pop(context);
                router.push('/billing/purchases/new?item=${widget.type}:${widget.id}');
              },
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
            final rows = _dir.isEmpty ? all : all.where((r) => r['dir'] == _dir).toList();
            return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(width: 170, child: KpiCard(label: tr('In stock now'), value: '${qty(d['stock'])} $unit', icon: Icons.warehouse_rounded, tint: AppColors.blue)),
                SizedBox(width: 170, child: KpiCard(label: tr('Total in'), value: '+${qty(d['totalIn'])}', icon: Icons.south_west_rounded, tint: AppColors.green, sub: '${all.where((r) => r['dir'] == 'in' && r['kind'] != 'OPENING').length} ${tr('entries')}')),
                SizedBox(width: 170, child: KpiCard(label: tr('Total out'), value: '−${qty(d['totalOut'])}', icon: Icons.north_east_rounded, tint: AppColors.red, sub: '${all.where((r) => r['dir'] == 'out').length} ${tr('entries')}')),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final e in {'': tr('All'), 'in': tr('In only'), 'out': tr('Out only')}.entries)
                  ChoiceChip(label: Text(e.value), selected: _dir == e.key, onSelected: (_) => setState(() => _dir = e.key)),
              ]),
              const SizedBox(height: 12),
              SectionCard(
                title: tr('Movements (newest first)'),
                child: rows.isEmpty
                    ? EmptyState(tr('No movements yet — enter a supplier bill to receive stock against an invoice number.'), icon: Icons.history_rounded)
                    : AppDataTable(
                        columns: [tr('Date'), tr('Type'), tr('In / Out'), tr('Qty'), tr('Balance'), tr('Bill / Ref no'), tr('Party / Destination'), tr('Note'), tr('By')],
                        onRowTap: (i) {
                          final link = (rows[i]['link'] ?? '').toString();
                          if (link.isEmpty) return;
                          final router = GoRouter.of(context);
                          Navigator.pop(context);
                          router.push(link);
                        },
                        rows: [
                          for (final r in rows)
                            [
                              fmtDateWithDay(r['date']),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(kindIcon(r['kind'] as String), size: 16, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text(kindLabel(r['kind'] as String)),
                              ]),
                              StatusChip(r['dir'] == 'in' ? 'IN' : 'OUT'),
                              Text('${r['dir'] == 'in' ? '+' : '−'}${qty(r['qty'])} $unit', style: TextStyle(fontWeight: FontWeight.w700, color: r['dir'] == 'in' ? AppColors.green : AppColors.red)),
                              Text('${qty(r['balance'])} $unit', style: const TextStyle(fontWeight: FontWeight.w600)),
                              (r['ref'] as String? ?? '').isEmpty
                                  ? '—'
                                  : Text(r['ref'] as String, style: TextStyle(fontWeight: FontWeight.w700, color: r['kind'] == 'PURCHASE' ? scheme.primary : null)),
                              (r['party'] as String? ?? '').isEmpty ? '—' : r['party'],
                              (r['note'] as String? ?? '').isEmpty ? '—' : r['note'],
                              (r['by'] as String? ?? '').isEmpty ? '—' : r['by'],
                            ],
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              Text(tr('Tap a purchase / dispatch / production row to open it. "Opening / adjustment" is the balancing figure for stock set manually before history was kept.'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ]);
          },
        ),
      ),
    ]);
  }
}
