import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/item_code.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import 'billing_page.dart' show gstStateName;
import 'item_history_page.dart' show showItemHistory;

/// One supplier bill: what came in, what it cost, what is still to be paid.
class PurchaseDetailPage extends StatefulWidget {
  final int id;
  const PurchaseDetailPage({super.key, required this.id});
  @override
  State<PurchaseDetailPage> createState() => _PurchaseDetailPageState();
}

class _PurchaseDetailPageState extends State<PurchaseDetailPage> {
  late Future<Map<String, dynamic>> _future;
  bool busy = false;

  @override
  void initState() { super.initState(); _future = _load(); }
  Future<Map<String, dynamic>> _load() async => ((await context.read<AuthController>().api.get('/billing/purchases/${widget.id}')) as Map).cast<String, dynamic>();
  void _reload() => setState(() => _future = _load());

  Future<void> _pay(Map<String, dynamic> p) async {
    final balance = (p['total'] as num) - (p['paid_amount'] as num);
    final ok = await showFastDialog<bool>(context, (_) => _PayDialog(purchaseId: widget.id, balance: balance, supplier: p['party_name'] as String));
    if (ok == true) _reload();
  }

  Future<void> _deletePayment(Map<String, dynamic> pay) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Delete this payment?')),
        content: Text('${inr(pay['amount'])} · ${(pay['mode'] ?? '').toString().toUpperCase()} ${pay['ref_no'] ?? ''}\n${tr('The bill balance goes back up.')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Keep'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.red), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AuthController>().api.delete('/billing/purchases/${widget.id}/payments/${pay['id']}');
      _reload();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _cancel(Map<String, dynamic> p) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${tr('Cancel purchase')} ${p['entry_no']}?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p['stock_added'] == 1
              ? tr('The quantities added by this bill are taken back out of stock and the ledger entries are removed. The entry stays in the register marked CANCELLED. This cannot be undone.')
              : tr('The entry stays in the register marked CANCELLED. This cannot be undone.')),
          const SizedBox(height: 12),
          TextField(controller: reason, autofocus: true, decoration: InputDecoration(labelText: tr('Reason *'), hintText: tr('wrong supplier / duplicate entry / goods returned'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Keep'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.red), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Cancel purchase'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (reason.text.trim().length < 3) { showErr(context, tr('Please give a reason.')); return; }
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.post('/billing/purchases/${widget.id}/cancel', {'reason': reason.text.trim()});
      if (mounted) showOk(context, tr('Purchase cancelled — stock reversed.'));
      _reload();
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canManage = auth.canManageBilling;
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final data = snap.data!;
        final p = (data['purchase'] as Map).cast<String, dynamic>();
        final items = (data['items'] as List).cast<Map<String, dynamic>>();
        final payments = ((data['payments'] as List?) ?? const []).cast<Map<String, dynamic>>();
        final status = p['status'] as String;
        final cancelled = status == 'CANCELLED';
        final intra = p['supply_type'] != 'inter';
        final balance = (p['total'] as num) - (p['paid_amount'] as num);
        final tax = (p['cgst'] as num) + (p['sgst'] as num) + (p['igst'] as num);
        final overdue = !cancelled && balance > 0 && (p['due_date'] ?? '').toString().isNotEmpty && (p['due_date'] as String).compareTo(todayYmd()) < 0;

        return ListView(padding: const EdgeInsets.all(20), children: [
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
            IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/billing?tab=purchases'), icon: const Icon(Icons.arrow_back_rounded)),
            Text('${tr('Bill')} ${p['bill_no']}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Chip(label: Text(p['entry_no'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), avatar: const Icon(Icons.tag_rounded, size: 14), visualDensity: VisualDensity.compact),
            StatusChip(status),
            if (overdue) const StatusChip('OVERDUE'),
            if (p['stock_added'] == 1 && !cancelled) const StatusChip('IN'),
            const SizedBox(width: 8),
            if (canManage && !cancelled && balance > 0)
              FilledButton.icon(onPressed: busy ? null : () => _pay(p), icon: const Icon(Icons.payments_rounded, size: 18), label: Text(tr('Record payment'))),
            if (canManage && !cancelled && payments.isEmpty)
              TextButton.icon(onPressed: busy ? null : () => _cancel(p), style: TextButton.styleFrom(foregroundColor: AppColors.red), icon: const Icon(Icons.block_rounded, size: 18), label: Text(tr('Cancel purchase'))),
          ]),
          if (cancelled)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.block_rounded, color: AppColors.red, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${tr('Cancelled')} ${fmtDateTime(p['cancelled_at'])} · ${p['cancel_reason'] ?? ''}', style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600))),
                ]),
              ),
            ),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: 190, child: KpiCard(label: tr('Bill total'), value: inr(p['total'], decimals: false), icon: Icons.receipt_long_rounded, tint: AppColors.blue, sub: '${tr('Taxable')} ${inr(p['taxable'], decimals: false)}')),
            SizedBox(width: 190, child: KpiCard(label: intra ? 'CGST + SGST' : 'IGST', value: inr(tax, decimals: false), icon: Icons.account_balance_rounded, tint: AppColors.teal, sub: intra ? '${inr(p['cgst'])} + ${inr(p['sgst'])}' : tr('inter-state'))),
            SizedBox(width: 190, child: KpiCard(label: tr('Paid'), value: inr(p['paid_amount'], decimals: false), icon: Icons.payments_rounded, tint: AppColors.green, sub: '${payments.length} ${tr('payments')}')),
            SizedBox(width: 190, child: KpiCard(label: tr('Balance to pay'), value: inr(cancelled ? 0 : balance, decimals: false), icon: Icons.hourglass_bottom_rounded, tint: overdue ? AppColors.red : AppColors.orange, sub: (p['due_date'] ?? '').toString().isEmpty ? '' : '${tr('Due')} ${fmtDate(p['due_date'])}')),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: tr('Supplier'),
            child: Wrap(spacing: 28, runSpacing: 10, children: [
              _kv(tr('Supplier'), p['party_name'] as String, bold: true),
              _kv('GSTIN', (p['party_gstin'] as String? ?? '').isEmpty ? tr('Unregistered') : p['party_gstin'] as String),
              if ((p['party_address'] as String? ?? '').isNotEmpty) _kv(tr('Address'), p['party_address'] as String),
              if ((p['party_state_code'] as String? ?? '').isNotEmpty) _kv(tr('State'), gstStateName(p['party_state_code'] as String)),
              _kv(tr("Supplier's invoice no"), p['bill_no'] as String, bold: true),
              _kv(tr('Bill date'), fmtDate(p['bill_date'])),
              if ((p['received_date'] as String? ?? '').isNotEmpty) _kv(tr('Received on'), fmtDate(p['received_date'])),
              _kv(tr('Stock'), p['stock_added'] == 1 ? (cancelled ? tr('added, then reversed on cancel') : tr('added to stock')) : tr('not added (payment record only)')),
              if ((p['remarks'] as String? ?? '').isNotEmpty) _kv(tr('Remarks'), p['remarks'] as String),
              _kv(tr('Entered by'), '${p['created_by_name'] ?? '—'} · ${fmtDateTime(p['created_at'])}'),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: tr('Items received'),
            child: AppDataTable(
              columns: ['#', tr('Item'), tr('Type'), 'HSN', tr('Batch'), tr('Qty'), tr('Rate'), tr('Disc %'), tr('Taxable'), 'GST %', tr('Tax'), tr('Amount'), ''],
              moneyColumns: const {6, 8, 10, 11},
              rows: [
                for (var i = 0; i < items.length; i++)
                  [
                    '${i + 1}',
                    ItemNameCell(name: items[i]['description'] as String, code: ItemCode.of(items[i])),
                    _typeLabel(items[i]['item_type'] as String? ?? ''),
                    (items[i]['hsn_code'] as String? ?? '').isEmpty ? '—' : items[i]['hsn_code'],
                    (items[i]['batch_code'] as String? ?? '').isEmpty ? '—' : items[i]['batch_code'],
                    '${qty(items[i]['qty'])} ${items[i]['item_type'] == 'product' ? U.cb : (items[i]['unit'] ?? '')}',
                    items[i]['rate'],
                    (items[i]['discount_pct'] as num? ?? 0) > 0 ? '${qty(items[i]['discount_pct'])}%' : '—',
                    items[i]['taxable'],
                    '${qty(items[i]['gst_rate'])}%',
                    (items[i]['cgst'] as num) + (items[i]['sgst'] as num) + (items[i]['igst'] as num),
                    items[i]['total'],
                    items[i]['item_id'] != null && items[i]['item_type'] != 'other'
                        ? IconButton(
                            tooltip: tr('Stock ledger (all in / out with doc numbers)'),
                            icon: const Icon(Icons.history_rounded, size: 19),
                            onPressed: () => showItemHistory(context, type: items[i]['item_type'] as String, id: items[i]['item_id'] as int, name: items[i]['description'] as String),
                          )
                        : const SizedBox.shrink(),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: tr('Totals'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _tot(tr('Sub total'), p['subtotal']),
              if ((p['discount'] as num) > 0) ...[_tot(tr('Discount'), -(p['discount'] as num)), _tot(tr('Taxable value'), p['taxable'])],
              if (intra) ...[_tot('CGST', p['cgst']), _tot('SGST', p['sgst'])] else _tot('IGST', p['igst']),
              if ((p['round_off'] as num) != 0) _tot(tr('Round off'), p['round_off']),
              const Divider(height: 18),
              Text('${tr('Bill total')}  ${inr(p['total'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: tr('Payments to supplier'),
            trailing: canManage && !cancelled && balance > 0 ? TextButton.icon(onPressed: () => _pay(p), icon: const Icon(Icons.add_rounded, size: 18), label: Text(tr('Add payment'))) : null,
            child: payments.isEmpty
                ? EmptyState(cancelled ? tr('No payments.') : tr('Nothing paid yet — record cheque / NEFT / cash payments here.'), icon: Icons.payments_outlined)
                : AppDataTable(
                    columns: [tr('Date'), tr('Mode'), tr('Ref / cheque no'), tr('Bank'), tr('Amount'), tr('Note'), tr('By'), ''],
                    moneyColumns: const {4},
                    rows: [
                      for (final pay in payments)
                        [
                          fmtDate(pay['paid_on']),
                          (pay['mode'] ?? '').toString().toUpperCase(),
                          (pay['ref_no'] as String? ?? '').isEmpty ? '—' : pay['ref_no'],
                          (pay['bank'] as String? ?? '').isEmpty ? '—' : pay['bank'],
                          pay['amount'],
                          (pay['note'] as String? ?? '').isEmpty ? '—' : pay['note'],
                          pay['created_by_name'] ?? '—',
                          canManage ? IconButton(icon: Icon(Icons.delete_outline_rounded, size: 19, color: scheme.error), tooltip: tr('Delete payment'), onPressed: () => _deletePayment(pay)) : const SizedBox.shrink(),
                        ],
                    ],
                  ),
          ),
          const SizedBox(height: 40),
        ]);
      },
    );
  }

  static String _typeLabel(String t) => t == 'product' ? tr('Finished goods') : t == 'material' ? tr('Material') : tr('Other / service');

  Widget _kv(String k, String v, {bool bold = false}) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 140, maxWidth: 360),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(k.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.4)),
          const SizedBox(height: 2),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 15 : 13.5)),
        ]),
      );

  Widget _tot(String label, Object? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(width: 20),
          SizedBox(width: 130, child: Text(inr(v), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

class _PayDialog extends StatefulWidget {
  final int purchaseId;
  final num balance;
  final String supplier;
  const _PayDialog({required this.purchaseId, required this.balance, required this.supplier});
  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  late final amount = TextEditingController(text: widget.balance == widget.balance.roundToDouble() ? widget.balance.toInt().toString() : widget.balance.toStringAsFixed(2));
  final ref = TextEditingController();
  final bank = TextEditingController();
  final note = TextEditingController();
  String mode = 'cheque';
  DateTime paidOn = DateTime.now();
  bool busy = false;

  static const modes = {'cheque': 'Cheque', 'neft': 'NEFT / RTGS / IMPS', 'upi': 'UPI', 'cash': 'Cash', 'other': 'Other / adjustment'};

  @override
  void dispose() { for (final c in [amount, ref, bank, note]) { c.dispose(); } super.dispose(); }

  Future<void> _save() async {
    final a = num.tryParse(amount.text.trim()) ?? 0;
    if (a <= 0) { showErr(context, tr('Enter the amount paid.')); return; }
    if (a > widget.balance + 0.01) { showErr(context, '${tr('Amount exceeds the balance')} (${inr(widget.balance)}).'); return; }
    if (mode == 'cheque' && ref.text.trim().isEmpty) { showErr(context, tr('Enter the cheque number.')); return; }
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.post('/billing/purchases/${widget.purchaseId}/payments', {
        'amount': a, 'mode': mode, 'refNo': ref.text.trim(), 'bank': bank.text.trim(), 'paidOn': ymd(paidOn), 'note': note.text.trim(),
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
      title: Text(tr('Record payment')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerLeft, child: Text('${tr('To')} ${widget.supplier} · ${tr('Balance to pay')}: ${inr(widget.balance)}', style: const TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: amount, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: '${tr('Amount')} ₹ *'))),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: InputDecoration(labelText: tr('Mode')),
                  items: [for (final e in modes.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value), overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => mode = v ?? 'cheque'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: ref, decoration: InputDecoration(labelText: mode == 'cheque' ? tr('Cheque number *') : tr('UTR / reference')))),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: paidOn, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 60)));
                    if (d != null) setState(() => paidOn = d);
                  },
                  child: InputDecorator(decoration: InputDecoration(labelText: mode == 'cheque' ? tr('Cheque date') : tr('Paid on')), child: Text(fmtDate(ymd(paidOn)))),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            if (mode == 'cheque' || mode == 'neft') TextField(controller: bank, decoration: InputDecoration(labelText: tr('Bank'))),
            if (mode == 'cheque' || mode == 'neft') const SizedBox(height: 10),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('Note'))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? tr('Saving…') : tr('Save payment'))),
      ],
    );
  }
}
