import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/item_code.dart';
import '../../core/theme.dart';
import '../../core/platform_support.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import '../../ui/windows_widgets.dart';
import 'billing_page.dart' show gstStateName;
import 'invoice_pdf.dart';

class InvoiceDetailPage extends StatefulWidget {
  final int id;
  const InvoiceDetailPage({super.key, required this.id});
  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  late Future<Map<String, dynamic>> _future;
  bool busy = false;

  @override
  void initState() { super.initState(); _future = _load(); }
  Future<Map<String, dynamic>> _load() async => ((await context.read<AuthController>().api.get('/billing/invoices/${widget.id}')) as Map).cast<String, dynamic>();
  void _reload() => setState(() => _future = _load());

  Future<void> _pdf(Map<String, dynamic> payload, {bool original = true}) async {
    setState(() => busy = true);
    try {
      final bytes = await InvoicePdf.build(payload, original: original);
      final num_ = ((payload['invoice'] as Map)['number'] ?? 'invoice').toString().replaceAll('/', '-');
      await Printing.sharePdf(bytes: bytes, filename: '$num_.pdf');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _receipt(Map<String, dynamic> inv) async {
    final balance = (inv['total'] as num) - (inv['paid_amount'] as num);
    final ok = await showFastDialog<bool>(context, (_) => _ReceiptDialog(invoiceId: widget.id, balance: balance));
    if (ok == true) _reload();
  }

  Future<void> _deleteReceipt(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
          ? Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 540),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(color: const Color(0xFFE2E9EF), padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_outlined, color: AppColors.red),
                    const SizedBox(width: 10),
                    Text(tr('Delete this receipt?'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ])),
                Padding(padding: const EdgeInsets.all(20),
                  child: Text('${inr(p['amount'])} · ${(p['mode'] ?? '').toString().toUpperCase()} '
                    '${p['ref_no'] ?? ''}\n\n${tr('The invoice balance goes back up.')}')),
                const Divider(height: 1),
                Padding(padding: const EdgeInsets.all(12), child: Row(
                  mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Keep receipt'))),
                    const SizedBox(width: 8),
                    FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                      onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Delete'))),
                  ],
                )),
              ]),
            ))
          : AlertDialog(
        title: Text(tr('Delete this receipt?')),
        content: Text('${inr(p['amount'])} · ${(p['mode'] ?? '').toString().toUpperCase()} ${p['ref_no'] ?? ''}\n${tr('The invoice balance goes back up.')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Keep'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.red), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AuthController>().api.delete('/billing/invoices/${widget.id}/payments/${p['id']}');
      _reload();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _cancel(Map<String, dynamic> inv) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
          ? StatefulBuilder(builder: (ctx, refresh) => Dialog(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(color: const Color(0xFFE2E9EF), padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_outlined, color: AppColors.red),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${tr('Cancel invoice')} ${inv['number']}?',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                  ])),
                Padding(padding: const EdgeInsets.all(20), child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('The number stays in the register marked CANCELLED (GST rules). Stock deducted by this invoice is put back. This cannot be undone.')),
                    const SizedBox(height: 16),
                    TextField(controller: reason, autofocus: true,
                      decoration: InputDecoration(labelText: tr('Reason *')),
                      onChanged: (_) => refresh(() {})),
                  ])),
                const Divider(height: 1),
                Padding(padding: const EdgeInsets.all(12), child: Row(
                  mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false),
                      child: Text(tr('Keep invoice'))),
                    const SizedBox(width: 8),
                    FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                      onPressed: reason.text.trim().length < 3 ? null : () => Navigator.pop(ctx, true),
                      child: Text(tr('Cancel invoice'))),
                  ],
                )),
              ]),
            )))
          : AlertDialog(
        title: Text('${tr('Cancel invoice')} ${inv['number']}?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('The number stays in the register marked CANCELLED (GST rules). Stock deducted by this invoice is put back. This cannot be undone.')),
          const SizedBox(height: 12),
          TextField(controller: reason, autofocus: true, decoration: InputDecoration(labelText: tr('Reason *'), hintText: tr('wrong party / rate correction / goods returned'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Keep invoice'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.red), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Cancel invoice'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (reason.text.trim().length < 3) { showErr(context, tr('Please give a reason.')); return; }
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.post('/billing/invoices/${widget.id}/cancel', {'reason': reason.text.trim()});
      if (mounted) showOk(context, tr('Invoice cancelled.'));
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
        final inv = (data['invoice'] as Map).cast<String, dynamic>();
        final items = (data['items'] as List).cast<Map<String, dynamic>>();
        final payments = ((data['payments'] as List?) ?? const []).cast<Map<String, dynamic>>();
        final status = inv['status'] as String;
        final cancelled = status == 'CANCELLED';
        final intra = inv['supply_type'] != 'inter';
        final balance = (inv['total'] as num) - (inv['paid_amount'] as num);
        final tax = (inv['cgst'] as num) + (inv['sgst'] as num) + (inv['igst'] as num);
        final overdue = !cancelled && balance > 0 && (inv['due_date'] ?? '').toString().isNotEmpty && (inv['due_date'] as String).compareTo(todayYmd()) < 0;

        final pageContent = ListView(padding: const EdgeInsets.all(20), children: [
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
            IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/billing'), icon: const Icon(Icons.arrow_back_rounded)),
            Text(inv['number'] as String, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            StatusChip(status),
            if (overdue) const StatusChip('OVERDUE'),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(onPressed: busy ? null : () => _pdf(data), icon: const Icon(Icons.picture_as_pdf_rounded, size: 18), label: Text(tr('Invoice PDF'))),
            OutlinedButton.icon(onPressed: busy ? null : () => _pdf(data, original: false), icon: const Icon(Icons.copy_rounded, size: 16), label: Text(tr('Duplicate copy'))),
            if (canManage && !cancelled && balance > 0)
              FilledButton.icon(onPressed: busy ? null : () => _receipt(inv), icon: const Icon(Icons.payments_rounded, size: 18), label: Text(tr('Record receipt'))),
            if (canManage && !cancelled && payments.isEmpty)
              TextButton.icon(onPressed: busy ? null : () => _cancel(inv), style: TextButton.styleFrom(foregroundColor: AppColors.red), icon: const Icon(Icons.block_rounded, size: 18), label: Text(tr('Cancel invoice'))),
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
                  Expanded(child: Text('${tr('Cancelled')} ${fmtDateTime(inv['cancelled_at'])} · ${inv['cancel_reason'] ?? ''}', style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600))),
                ]),
              ),
            ),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: 190, child: KpiCard(label: tr('Grand total'), value: inr(inv['total'], decimals: false), icon: Icons.receipt_long_rounded, tint: AppColors.blue, sub: '${tr('Taxable')} ${inr(inv['taxable'], decimals: false)}')),
            SizedBox(width: 190, child: KpiCard(label: intra ? 'CGST + SGST' : 'IGST', value: inr(tax, decimals: false), icon: Icons.account_balance_rounded, tint: AppColors.teal, sub: intra ? '${inr(inv['cgst'])} + ${inr(inv['sgst'])}' : tr('inter-state'))),
            SizedBox(width: 190, child: KpiCard(label: tr('Received'), value: inr(inv['paid_amount'], decimals: false), icon: Icons.payments_rounded, tint: AppColors.green, sub: '${payments.length} ${tr('receipts')}')),
            SizedBox(width: 190, child: KpiCard(label: tr('Balance due'), value: inr(cancelled ? 0 : balance, decimals: false), icon: Icons.hourglass_bottom_rounded, tint: overdue ? AppColors.red : AppColors.orange, sub: (inv['due_date'] ?? '').toString().isEmpty ? '' : '${tr('Due')} ${fmtDate(inv['due_date'])}')),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: tr('Bill to'),
            child: Wrap(spacing: 28, runSpacing: 10, children: [
              _kv(tr('Party'), inv['party_name'] as String, bold: true),
              _kv('GSTIN', (inv['party_gstin'] as String? ?? '').isEmpty ? tr('Unregistered (B2C)') : inv['party_gstin'] as String),
              if ((inv['party_address'] as String? ?? '').isNotEmpty) _kv(tr('Address'), inv['party_address'] as String),
              _kv(tr('Place of supply'), gstStateName(inv['place_of_supply'] as String? ?? '')),
              _kv(tr('Invoice date'), fmtDate(inv['invoice_date'])),
              if ((inv['dispatch_code'] as String? ?? '').isNotEmpty) _kv(tr('Dispatch'), inv['dispatch_code'] as String),
              if ((inv['remarks'] as String? ?? '').isNotEmpty) _kv(tr('Remarks'), inv['remarks'] as String),
              _kv(tr('Created by'), '${inv['created_by_name'] ?? '—'} · ${fmtDateTime(inv['created_at'])}'),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: tr('Items'),
            child: AppDataTable(
              columns: ['#', tr('Description'), 'HSN', tr('Batch'), tr('Qty'), tr('Rate'), tr('Disc %'), tr('Taxable'), 'GST %', tr('Tax'), tr('Amount')],
              moneyColumns: const {5, 7, 9, 10},
              rows: [
                for (var i = 0; i < items.length; i++)
                  [
                    '${i + 1}',
                    ItemNameCell(name: '${items[i]['description']}', code: ItemCode.of(items[i])),
                    (items[i]['hsn_code'] as String? ?? '').isEmpty ? '—' : items[i]['hsn_code'],
                    (items[i]['batch_code'] as String? ?? '').isEmpty ? '—' : items[i]['batch_code'],
                    '${qty(items[i]['qty'])} ${items[i]['rate_per'] == 'piece' ? '${U.cb} (${qty((items[i]['qty'] as num) * (items[i]['pieces_per_pack'] as num? ?? 1))} ${U.piece.toLowerCase()})' : U.cb}',
                    items[i]['rate'],
                    (items[i]['discount_pct'] as num? ?? 0) > 0 ? '${qty(items[i]['discount_pct'])}%' : '—',
                    items[i]['taxable'],
                    '${qty(items[i]['gst_rate'])}%',
                    (items[i]['cgst'] as num) + (items[i]['sgst'] as num) + (items[i]['igst'] as num),
                    items[i]['total'],
                  ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: tr('Totals'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _tot(tr('Sub total'), inv['subtotal']),
              if ((inv['discount'] as num) > 0) ...[_tot(tr('Discount'), -(inv['discount'] as num)), _tot(tr('Taxable value'), inv['taxable'])],
              if (intra) ...[_tot('CGST', inv['cgst']), _tot('SGST', inv['sgst'])] else _tot('IGST', inv['igst']),
              if ((inv['round_off'] as num) != 0) _tot(tr('Round off'), inv['round_off']),
              const Divider(height: 18),
              Text('${tr('Grand total')}  ${inr(inv['total'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text(InvoicePdf.inWords(inv['total'] as num), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontStyle: FontStyle.italic)),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: tr('Receipts'),
            trailing: canManage && !cancelled && balance > 0 ? TextButton.icon(onPressed: () => _receipt(inv), icon: const Icon(Icons.add_rounded, size: 18), label: Text(tr('Add receipt'))) : null,
            child: payments.isEmpty
                ? EmptyState(cancelled ? tr('No receipts.') : tr('No payment received yet — record cheque / NEFT / cash receipts here.'), icon: Icons.payments_outlined)
                : AppDataTable(
                    columns: [tr('Date'), tr('Mode'), tr('Ref / cheque no'), tr('Bank'), tr('Amount'), tr('Note'), tr('By'), ''],
                    moneyColumns: const {4},
                    rows: [
                      for (final p in payments)
                        [
                          fmtDate(p['paid_on']),
                          (p['mode'] ?? '').toString().toUpperCase(),
                          (p['ref_no'] as String? ?? '').isEmpty ? '—' : p['ref_no'],
                          (p['bank'] as String? ?? '').isEmpty ? '—' : p['bank'],
                          p['amount'],
                          (p['note'] as String? ?? '').isEmpty ? '—' : p['note'],
                          p['created_by_name'] ?? '—',
                          canManage ? IconButton(icon: Icon(Icons.delete_outline_rounded, size: 19, color: scheme.error), tooltip: tr('Delete receipt'), onPressed: () => _deleteReceipt(p)) : const SizedBox.shrink(),
                        ],
                    ],
                  ),
          ),
          const SizedBox(height: 40),
        ]);
        if (isWindowsPlatform) {
          final desktopBillTo = SectionCard(
            title: tr('Bill to'),
            child: Wrap(spacing: 22, runSpacing: 12, children: [
              _kv(tr('Party'), inv['party_name'] as String, bold: true),
              _kv('GSTIN', (inv['party_gstin'] as String? ?? '').isEmpty ? tr('Unregistered (B2C)') : inv['party_gstin'] as String),
              if ((inv['party_address'] as String? ?? '').isNotEmpty) _kv(tr('Address'), inv['party_address'] as String),
              _kv(tr('Place of supply'), gstStateName(inv['place_of_supply'] as String? ?? '')),
              _kv(tr('Invoice date'), fmtDate(inv['invoice_date'])),
              if ((inv['dispatch_code'] as String? ?? '').isNotEmpty) _kv(tr('Dispatch'), inv['dispatch_code'] as String),
              if ((inv['remarks'] as String? ?? '').isNotEmpty) _kv(tr('Remarks'), inv['remarks'] as String),
              _kv(tr('Created by'), '${inv['created_by_name'] ?? '—'} · ${fmtDateTime(inv['created_at'])}'),
            ]),
          );
          final desktopItems = SectionCard(
            title: tr('Invoice Lines'),
            child: AppDataTable(
              columns: ['#', tr('Description'), 'HSN', tr('Batch'), tr('Qty'), tr('Rate'), tr('Disc %'), tr('Taxable'), 'GST %', tr('Tax'), tr('Amount')],
              moneyColumns: const {5, 7, 9, 10},
              rows: [
                for (var i = 0; i < items.length; i++)
                  [
                    '${i + 1}',
                    ItemNameCell(name: '${items[i]['description']}', code: ItemCode.of(items[i])),
                    (items[i]['hsn_code'] as String? ?? '').isEmpty ? '—' : items[i]['hsn_code'],
                    (items[i]['batch_code'] as String? ?? '').isEmpty ? '—' : items[i]['batch_code'],
                    '${qty(items[i]['qty'])} ${items[i]['rate_per'] == 'piece' ? '${U.cb} (${qty((items[i]['qty'] as num) * (items[i]['pieces_per_pack'] as num? ?? 1))} ${U.piece.toLowerCase()})' : U.cb}',
                    items[i]['rate'],
                    (items[i]['discount_pct'] as num? ?? 0) > 0 ? '${qty(items[i]['discount_pct'])}%' : '—',
                    items[i]['taxable'],
                    '${qty(items[i]['gst_rate'])}%',
                    (items[i]['cgst'] as num) + (items[i]['sgst'] as num) + (items[i]['igst'] as num),
                    items[i]['total'],
                  ],
              ],
            ),
          );
          final desktopTotals = SectionCard(
            title: tr('Tax & Totals'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _tot(tr('Sub total'), inv['subtotal']),
              if ((inv['discount'] as num) > 0) ...[_tot(tr('Discount'), -(inv['discount'] as num)), _tot(tr('Taxable value'), inv['taxable'])],
              if (intra) ...[_tot('CGST', inv['cgst']), _tot('SGST', inv['sgst'])] else _tot('IGST', inv['igst']),
              if ((inv['round_off'] as num) != 0) _tot(tr('Round off'), inv['round_off']),
              const Divider(height: 18),
              Text('${tr('Grand total')}  ${inr(inv['total'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text(InvoicePdf.inWords(inv['total'] as num), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontStyle: FontStyle.italic)),
              const Divider(height: 18),
              _tot(tr('Received'), inv['paid_amount']),
              _tot(tr('Balance due'), cancelled ? 0 : balance),
            ]),
          );
          final desktopReceipts = SectionCard(
            title: tr('Receipts Register'),
            trailing: canManage && !cancelled && balance > 0 ? TextButton.icon(onPressed: () => _receipt(inv), icon: const Icon(Icons.add_rounded, size: 17), label: Text(tr('Add receipt'))) : null,
            child: payments.isEmpty
                ? EmptyState(cancelled ? tr('No receipts.') : tr('No payment received yet — record cheque / NEFT / cash receipts here.'), icon: Icons.payments_outlined)
                : AppDataTable(
                    columns: [tr('Date'), tr('Mode'), tr('Ref / cheque no'), tr('Bank'), tr('Amount'), tr('Note'), tr('By'), ''],
                    moneyColumns: const {4},
                    rows: [
                      for (final p in payments)
                        [
                          fmtDate(p['paid_on']),
                          (p['mode'] ?? '').toString().toUpperCase(),
                          (p['ref_no'] as String? ?? '').isEmpty ? '—' : p['ref_no'],
                          (p['bank'] as String? ?? '').isEmpty ? '—' : p['bank'],
                          p['amount'],
                          (p['note'] as String? ?? '').isEmpty ? '—' : p['note'],
                          p['created_by_name'] ?? '—',
                          canManage ? IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 18), tooltip: tr('Delete receipt'), onPressed: () => _deleteReceipt(p)) : const SizedBox.shrink(),
                        ],
                    ],
                  ),
          );
          final desktopActions = <Widget>[
            IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/billing'), tooltip: tr('Back'), icon: const Icon(Icons.arrow_back_rounded)),
            FilledButton.tonalIcon(onPressed: busy ? null : () => _pdf(data), icon: const Icon(Icons.picture_as_pdf_rounded, size: 16), label: Text(tr('Invoice PDF'))),
            OutlinedButton.icon(onPressed: busy ? null : () => _pdf(data, original: false), icon: const Icon(Icons.copy_rounded, size: 16), label: Text(tr('Duplicate copy'))),
            if (canManage && !cancelled && balance > 0)
              FilledButton.icon(onPressed: busy ? null : () => _receipt(inv), icon: const Icon(Icons.payments_rounded, size: 16), label: Text(tr('Record receipt'))),
            if (canManage && !cancelled && payments.isEmpty)
              OutlinedButton.icon(onPressed: busy ? null : () => _cancel(inv), style: TextButton.styleFrom(foregroundColor: AppColors.red), icon: const Icon(Icons.block_rounded, size: 16), label: Text(tr('Cancel invoice'))),
          ];
          return WindowsDocumentWorkspace(
            title: 'Sales Invoice',
            subtitle: '${inv['number']} · ${inv['party_name']} · ${fmtDate(inv['invoice_date'])}',
            icon: Icons.receipt_long_outlined,
            commandBar: WindowsCommandStrip(children: [
              StatusChip(status),
              if (overdue) const StatusChip('OVERDUE'),
              Text('${tr('Balance due')}: ${inr(cancelled ? 0 : balance, decimals: false)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ...desktopActions,
            ]),
            content: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1180;
              final kpis = [
                KpiCard(label: tr('Grand total'), value: inr(inv['total'], decimals: false), icon: Icons.receipt_long_rounded, tint: AppColors.blue),
                KpiCard(label: intra ? 'CGST + SGST' : 'IGST', value: inr(tax, decimals: false), icon: Icons.account_balance_rounded, tint: AppColors.teal),
                KpiCard(label: tr('Received'), value: inr(inv['paid_amount'], decimals: false), icon: Icons.payments_rounded, tint: AppColors.green),
                KpiCard(label: tr('Balance due'), value: inr(cancelled ? 0 : balance, decimals: false), icon: Icons.hourglass_bottom_rounded, tint: overdue ? AppColors.red : AppColors.orange),
              ];
              return ListView(padding: const EdgeInsets.all(14), children: [
                Wrap(spacing: 9, runSpacing: 8, children: [for (final kpi in kpis) SizedBox(width: 205, height: 108, child: kpi)]),
                const SizedBox(height: 12),
                if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 7, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [desktopBillTo, const SizedBox(height: 10), desktopItems, const SizedBox(height: 10), desktopReceipts])),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [desktopTotals, if (cancelled) ...[const SizedBox(height: 10), _cancelledNotice(inv)]])),
                  ])
                else ...[
                  desktopBillTo,
                  const SizedBox(height: 10),
                  desktopItems,
                  const SizedBox(height: 10),
                  desktopTotals,
                  const SizedBox(height: 10),
                  desktopReceipts,
                ],
              ]);
            }),
          );
        }
        return pageContent;
      },
    );
  }

  Widget _cancelledNotice(Map<String, dynamic> inv) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.08), border: Border.all(color: AppColors.red.withValues(alpha: 0.24))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.block_rounded, color: AppColors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('${tr('Cancelled')} ${fmtDateTime(inv['cancelled_at'])} · ${inv['cancel_reason'] ?? ''}', style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600))),
        ]),
      );

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

class _ReceiptDialog extends StatefulWidget {
  final int invoiceId;
  final num balance;
  const _ReceiptDialog({required this.invoiceId, required this.balance});
  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  late final amount = TextEditingController(text: widget.balance == widget.balance.roundToDouble() ? widget.balance.toInt().toString() : widget.balance.toStringAsFixed(2));
  final ref = TextEditingController();
  final bank = TextEditingController();
  final note = TextEditingController();
  String mode = 'cheque';
  DateTime paidOn = DateTime.now();
  bool busy = false;

  static const modes = {'cheque': 'Cheque', 'neft': 'NEFT / RTGS / IMPS', 'upi': 'UPI', 'cash': 'Cash', 'card': 'Card', 'other': 'Other / adjustment'};

  @override
  void dispose() { for (final c in [amount, ref, bank, note]) { c.dispose(); } super.dispose(); }

  Future<void> _save() async {
    final a = num.tryParse(amount.text.trim()) ?? 0;
    if (a <= 0) { showErr(context, tr('Enter the amount received.')); return; }
    if (a > widget.balance + 0.01) { showErr(context, '${tr('Amount exceeds the balance')} (${inr(widget.balance)}).'); return; }
    if (mode == 'cheque' && ref.text.trim().isEmpty) { showErr(context, tr('Enter the cheque number.')); return; }
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.post('/billing/invoices/${widget.invoiceId}/payments', {
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 700),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(color: const Color(0xFF243B50), padding: const EdgeInsets.all(18),
            child: Text(tr('Record receipt'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${tr('Balance due')}: ${inr(widget.balance)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(controller: amount, autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: '${tr('Amount')} ₹ *')),
                const SizedBox(height: 18),
                Text(tr('Mode'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 7, runSpacing: 6, children: [
                  for (final e in modes.entries)
                    ChoiceChip(label: Text(tr(e.value)), selected: mode == e.key,
                      onSelected: busy ? null : (_) => setState(() => mode = e.key)),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: TextField(controller: ref,
                    decoration: InputDecoration(labelText: mode == 'cheque'
                      ? tr('Cheque number *') : tr('UTR / reference')))),
                  const SizedBox(width: 12),
                  Expanded(child: InkWell(onTap: busy ? null : () async {
                    final d = await showDatePicker(context: context, initialDate: paidOn,
                      firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 60)));
                    if (d != null) setState(() => paidOn = d);
                  }, child: InputDecorator(
                    decoration: InputDecoration(labelText: mode == 'cheque'
                      ? tr('Cheque date') : tr('Received on')),
                    child: Text(fmtDate(ymd(paidOn)))))),
                ]),
                if (mode == 'cheque' || mode == 'neft') ...[
                  const SizedBox(height: 12),
                  TextField(controller: bank, decoration: InputDecoration(labelText: tr('Bank (drawn on)'))),
                ],
                const SizedBox(height: 12),
                TextField(controller: note, decoration: InputDecoration(labelText: tr('Note'))),
              ]))),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: Text(tr('Cancel'))),
              const SizedBox(width: 8),
              FilledButton(onPressed: busy ? null : _save,
                child: Text(busy ? tr('Saving…') : tr('Save receipt'))),
            ])),
        ]),
      ));
    }
    return AlertDialog(
      title: Text(tr('Record receipt')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerLeft, child: Text('${tr('Balance due')}: ${inr(widget.balance)}', style: const TextStyle(fontWeight: FontWeight.w700))),
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
                  child: InputDecorator(decoration: InputDecoration(labelText: mode == 'cheque' ? tr('Cheque date') : tr('Received on')), child: Text(fmtDate(ymd(paidOn)))),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            if (mode == 'cheque' || mode == 'neft') TextField(controller: bank, decoration: InputDecoration(labelText: tr('Bank (drawn on)'))),
            if (mode == 'cheque' || mode == 'neft') const SizedBox(height: 10),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('Note'))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? tr('Saving…') : tr('Save receipt'))),
      ],
    );
  }
}
