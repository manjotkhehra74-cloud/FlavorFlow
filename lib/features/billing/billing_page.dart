import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/download.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// Sales Billing — GST tax invoices, parties (customers), receipts and the
/// GST register. Works for every industry: a "pack" is whatever the company
/// ships (carton / bag / crate / bale) and rates can be per pack or per piece.
class BillingPage extends StatefulWidget {
  final String? tab;
  const BillingPage({super.key, this.tab});
  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  static const _tabs = ['invoices', 'receivables', 'parties', 'register', 'settings'];

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
              Tab(text: tr('Invoices')),
              Tab(text: tr('Outstanding')),
              Tab(text: tr('Parties')),
              Tab(text: tr('GST Register')),
              Tab(text: tr('Billing Setup')),
            ],
          ),
        ),
      ),
      Expanded(
        child: TabBarView(controller: _tab, children: const [
          _InvoicesTab(),
          _ReceivablesTab(),
          _PartiesTab(),
          _RegisterTab(),
          _SettingsTab(),
        ]),
      ),
    ]);
  }
}

// ───────────────────────── Invoices ─────────────────────────
class _InvoicesTab extends StatefulWidget {
  const _InvoicesTab();
  @override
  State<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends State<_InvoicesTab> {
  late Future<Map<String, dynamic>> _future;
  final _q = TextEditingController();
  String _status = '';

  @override
  void initState() { super.initState(); _future = _load(); }
  @override
  void dispose() { _q.dispose(); super.dispose(); }

  Future<Map<String, dynamic>> _load() async {
    final api = context.read<AuthController>().api;
    final params = <String>[
      if (_q.text.trim().isNotEmpty) 'q=${Uri.encodeQueryComponent(_q.text.trim())}',
      if (_status.isNotEmpty) 'status=$_status',
    ];
    final list = await api.get('/billing/invoices${params.isEmpty ? '' : '?${params.join('&')}'}');
    final sum = await api.get('/billing/summary');
    return {'invoices': ((list as Map)['invoices'] as List).cast<Map<String, dynamic>>(), 'summary': (sum as Map).cast<String, dynamic>()};
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canManage = auth.canManageBilling;
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!['invoices'] as List<Map<String, dynamic>>;
        final s = snap.data!['summary'] as Map<String, dynamic>;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(20), children: [
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(width: 200, child: KpiCard(label: tr('This month sales'), value: inr(s['total'], decimals: false), icon: Icons.receipt_long_rounded, tint: AppColors.blue, sub: '${s['invoices']} ${tr('invoices')}')),
              SizedBox(width: 200, child: KpiCard(label: tr('GST collected'), value: inr(s['tax'], decimals: false), icon: Icons.account_balance_rounded, tint: AppColors.teal, sub: tr('this month'))),
              SizedBox(width: 200, child: KpiCard(label: tr('Received'), value: inr(s['received'], decimals: false), icon: Icons.payments_rounded, tint: AppColors.green, sub: tr('this month'))),
              SizedBox(width: 200, child: KpiCard(label: tr('Outstanding'), value: inr(s['outstanding'], decimals: false), icon: Icons.hourglass_bottom_rounded, tint: AppColors.orange, sub: tr('all invoices'))),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _q,
                  decoration: InputDecoration(
                    hintText: tr('Search invoice no / party / dispatch'),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () { _q.clear(); _reload(); }),
                  ),
                  onSubmitted: (_) => _reload(),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _status,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: '', child: Text(tr('All'))),
                  DropdownMenuItem(value: 'ISSUED', child: Text(tr('Unpaid'))),
                  DropdownMenuItem(value: 'PARTIAL', child: Text(tr('Partly paid'))),
                  DropdownMenuItem(value: 'PAID', child: Text(tr('Paid'))),
                  DropdownMenuItem(value: 'CANCELLED', child: Text(tr('Cancelled'))),
                ],
                onChanged: (v) { _status = v ?? ''; _reload(); },
              ),
              const SizedBox(width: 10),
              if (canManage)
                FilledButton.icon(
                  onPressed: () async {
                    await context.push('/billing/new');
                    _reload();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(tr('New Invoice')),
                ),
            ]),
            const SizedBox(height: 16),
            SectionCard(
              title: tr('Tax Invoices'),
              child: rows.isEmpty
                  ? EmptyState(tr('No invoices yet — create one from a dispatch (Dispatch → open → "Make invoice") or tap New Invoice.'), icon: Icons.receipt_long_outlined)
                  : AppDataTable(
                      columns: [tr('Invoice'), tr('Date'), tr('Party'), tr('Taxable'), 'GST', tr('Total'), tr('Balance'), tr('Status'), tr('Dispatch')],
                      moneyColumns: const {3, 4, 5, 6},
                      onRowTap: (i) async {
                        await context.push('/billing/${rows[i]['id']}');
                        _reload();
                      },
                      rows: [
                        for (final r in rows)
                          [
                            Text(r['number'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                            fmtDate(r['invoice_date']),
                            r['party_name'],
                            r['taxable'],
                            ((r['cgst'] as num) + (r['sgst'] as num) + (r['igst'] as num)),
                            r['total'],
                            r['balance'],
                            StatusChip(r['status'] as String),
                            (r['dispatch_code'] as String? ?? '').isEmpty ? '—' : r['dispatch_code'],
                          ],
                      ],
                    ),
            ),
          ]),
        );
      },
    );
  }
}

// ───────────────────────── Receivables ─────────────────────────
class _ReceivablesTab extends StatefulWidget {
  const _ReceivablesTab();
  @override
  State<_ReceivablesTab> createState() => _ReceivablesTabState();
}

class _ReceivablesTabState extends State<_ReceivablesTab> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() { super.initState(); _future = _load(); }
  Future<Map<String, dynamic>> _load() async => ((await context.read<AuthController>().api.get('/billing/receivables')) as Map).cast<String, dynamic>();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: () => setState(() => _future = _load()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final d = snap.data!;
        final rows = (d['receivables'] as List).cast<Map<String, dynamic>>();
        final byParty = (d['byParty'] as List).cast<Map<String, dynamic>>();
        final b = (d['buckets'] as Map).cast<String, dynamic>();
        return ListView(padding: const EdgeInsets.all(20), children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: 200, child: KpiCard(label: tr('Total outstanding'), value: inr(d['total'], decimals: false), icon: Icons.account_balance_wallet_rounded, tint: AppColors.orange, sub: '${rows.length} ${tr('open invoices')}')),
            SizedBox(width: 160, child: KpiCard(label: '0–30 ${tr('days')}', value: inr(b['0-30'], decimals: false), icon: Icons.timelapse_rounded, tint: AppColors.green)),
            SizedBox(width: 160, child: KpiCard(label: '31–60 ${tr('days')}', value: inr(b['31-60'], decimals: false), icon: Icons.timelapse_rounded, tint: AppColors.amber)),
            SizedBox(width: 160, child: KpiCard(label: '61–90 ${tr('days')}', value: inr(b['61-90'], decimals: false), icon: Icons.timelapse_rounded, tint: AppColors.orange)),
            SizedBox(width: 160, child: KpiCard(label: '90+ ${tr('days')}', value: inr(b['90+'], decimals: false), icon: Icons.warning_amber_rounded, tint: AppColors.red)),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: tr('Party-wise outstanding'),
            child: byParty.isEmpty
                ? EmptyState(tr('Nothing pending — all invoices are paid 🎉'), icon: Icons.check_circle_outline_rounded)
                : AppDataTable(
                    columns: [tr('Party'), tr('Invoices'), tr('Balance'), tr('Oldest')],
                    moneyColumns: const {2},
                    rows: [for (final p in byParty) [Text(p['party'] as String, style: const TextStyle(fontWeight: FontWeight.w600)), qtyInt(p['invoices']), p['balance'], fmtDate(p['oldest'])]],
                  ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: tr('Open invoices'),
            child: rows.isEmpty
                ? const SizedBox.shrink()
                : AppDataTable(
                    columns: [tr('Invoice'), tr('Date'), tr('Due'), tr('Party'), tr('Total'), tr('Balance'), tr('Days')],
                    moneyColumns: const {4, 5},
                    highlight: (i) => rows[i]['overdue'] == true,
                    onRowTap: (i) async { await context.push('/billing/${rows[i]['id']}'); if (mounted) setState(() => _future = _load()); },
                    rows: [
                      for (final r in rows)
                        [
                          Text(r['number'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                          fmtDate(r['invoice_date']),
                          Text(fmtDate(r['due_date']), style: TextStyle(color: r['overdue'] == true ? AppColors.red : null, fontWeight: r['overdue'] == true ? FontWeight.w700 : null)),
                          r['party_name'],
                          r['total'],
                          r['balance'],
                          '${r['days']}',
                        ],
                    ],
                  ),
          ),
        ]);
      },
    );
  }
}

// ───────────────────────── Parties ─────────────────────────
class _PartiesTab extends StatefulWidget {
  const _PartiesTab();
  @override
  State<_PartiesTab> createState() => _PartiesTabState();
}

class _PartiesTabState extends State<_PartiesTab> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() { super.initState(); _future = _load(); }
  Future<List<Map<String, dynamic>>> _load() async {
    final j = await context.read<AuthController>().api.get('/billing/parties');
    return ((j as Map)['parties'] as List).cast<Map<String, dynamic>>();
  }
  void _reload() => setState(() => _future = _load());

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${tr('Remove')} ${p['name']}?'),
        content: Text(tr('The party is hidden from new invoices. Old invoices keep their details.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.red), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Remove'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AuthController>().api.delete('/billing/parties/${p['id']}');
      _reload();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canManage = auth.canManageBilling;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        return ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            Expanded(child: Text('${rows.length} ${tr('parties')} · ${tr('customers, distributors, dealers — GSTIN, address, credit days')}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
            if (canManage)
              FilledButton.icon(
                onPressed: () async {
                  final saved = await showFastDialog<bool>(context, (_) => const PartyFormDialog());
                  if (saved == true) _reload();
                },
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(tr('Add Party')),
              ),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: tr('Party Master'),
            child: rows.isEmpty
                ? EmptyState(tr('No parties yet — add your customers here (or type a name on the invoice; walk-in sales need no party).'), icon: Icons.storefront_outlined)
                : AppDataTable(
                    columns: [tr('Party'), 'GSTIN', tr('State'), tr('Phone'), tr('Credit days'), tr('Invoices'), tr('Outstanding'), ''],
                    moneyColumns: const {6},
                    rows: [
                      for (final p in rows)
                        [
                          Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                          (p['gstin'] as String? ?? '').isEmpty ? Text(tr('Unregistered (B2C)'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)) : p['gstin'],
                          gstStateName(p['state_code'] as String? ?? ''),
                          (p['phone'] as String? ?? '').isEmpty ? '—' : p['phone'],
                          '${p['credit_days'] ?? 0}',
                          qtyInt(p['invoices']),
                          p['outstanding'],
                          if (canManage)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(icon: const Icon(Icons.edit_outlined, size: 19), tooltip: tr('Edit'), onPressed: () async {
                                final saved = await showFastDialog<bool>(context, (_) => PartyFormDialog(party: p));
                                if (saved == true) _reload();
                              }),
                              IconButton(icon: Icon(Icons.delete_outline_rounded, size: 19, color: Theme.of(context).colorScheme.error), tooltip: tr('Remove'), onPressed: () => _delete(p)),
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

/// GST state codes (first two digits of a GSTIN).
const Map<String, String> kGstStates = {
  '01': 'Jammu & Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh', '05': 'Uttarakhand', '06': 'Haryana',
  '07': 'Delhi', '08': 'Rajasthan', '09': 'Uttar Pradesh', '10': 'Bihar', '11': 'Sikkim', '12': 'Arunachal Pradesh', '13': 'Nagaland',
  '14': 'Manipur', '15': 'Mizoram', '16': 'Tripura', '17': 'Meghalaya', '18': 'Assam', '19': 'West Bengal', '20': 'Jharkhand',
  '21': 'Odisha', '22': 'Chhattisgarh', '23': 'Madhya Pradesh', '24': 'Gujarat', '26': 'Dadra & Nagar Haveli and Daman & Diu',
  '27': 'Maharashtra', '29': 'Karnataka', '30': 'Goa', '31': 'Lakshadweep', '32': 'Kerala', '33': 'Tamil Nadu', '34': 'Puducherry',
  '35': 'Andaman & Nicobar', '36': 'Telangana', '37': 'Andhra Pradesh', '38': 'Ladakh', '97': 'Other Territory',
};
String gstStateName(String code) => code.isEmpty ? '—' : '$code · ${kGstStates[code] ?? code}';

class PartyFormDialog extends StatefulWidget {
  final Map<String, dynamic>? party;
  const PartyFormDialog({super.key, this.party});
  @override
  State<PartyFormDialog> createState() => _PartyFormDialogState();
}

class _PartyFormDialogState extends State<PartyFormDialog> {
  late final name = TextEditingController(text: widget.party?['name']?.toString() ?? '');
  late final gstin = TextEditingController(text: widget.party?['gstin']?.toString() ?? '');
  late final address = TextEditingController(text: widget.party?['address']?.toString() ?? '');
  late final phone = TextEditingController(text: widget.party?['phone']?.toString() ?? '');
  late final email = TextEditingController(text: widget.party?['email']?.toString() ?? '');
  late final credit = TextEditingController(text: '${widget.party?['credit_days'] ?? 0}');
  late String state = (widget.party?['state_code']?.toString() ?? '').isEmpty ? '' : widget.party!['state_code'].toString();
  bool busy = false;

  @override
  void dispose() { for (final c in [name, gstin, address, phone, email, credit]) { c.dispose(); } super.dispose(); }

  Future<void> _save() async {
    if (name.text.trim().length < 2) { showErr(context, tr('Party name is required.')); return; }
    setState(() => busy = true);
    final body = {
      'name': name.text.trim(), 'gstin': gstin.text.trim().toUpperCase(), 'address': address.text.trim(),
      'stateCode': state, 'phone': phone.text.trim(), 'email': email.text.trim(), 'creditDays': int.tryParse(credit.text) ?? 0,
    };
    try {
      final api = context.read<AuthController>().api;
      if (widget.party == null) {
        await api.post('/billing/parties', body);
      } else {
        await api.put('/billing/parties/${widget.party!['id']}', body);
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
      title: Text(widget.party == null ? tr('Add Party') : tr('Edit Party')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Party name *'), hintText: 'e.g. Guru Nanak Traders')),
            const SizedBox(height: 10),
            TextField(
              controller: gstin,
              textCapitalization: TextCapitalization.characters,
              maxLength: 15,
              decoration: InputDecoration(labelText: 'GSTIN', hintText: tr('blank = unregistered (B2C)'), counterText: ''),
              onChanged: (v) {
                final s = v.trim();
                if (s.length >= 2 && kGstStates.containsKey(s.substring(0, 2)) && state.isEmpty) setState(() => state = s.substring(0, 2));
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('st-$state'),
              initialValue: state,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('State (place of supply)')),
              items: [
                DropdownMenuItem(value: '', child: Text(tr('Same as company'))),
                for (final e in kGstStates.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} · ${e.value}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => state = v ?? ''),
            ),
            const SizedBox(height: 10),
            TextField(controller: address, maxLines: 2, decoration: InputDecoration(labelText: tr('Billing address'))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Phone')))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: credit, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Credit days'), helperText: tr('0 = due on invoice date')))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('Email'))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? tr('Saving…') : tr('Save'))),
      ],
    );
  }
}

// ───────────────────────── GST Register ─────────────────────────
class _RegisterTab extends StatefulWidget {
  const _RegisterTab();
  @override
  State<_RegisterTab> createState() => _RegisterTabState();
}

class _RegisterTabState extends State<_RegisterTab> {
  late DateTime from;
  late DateTime to;
  Future<Map<String, dynamic>>? _future;
  bool exporting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    from = DateTime(now.year, now.month, 1);
    to = now;
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async =>
      ((await context.read<AuthController>().api.get('/billing/register?from=${ymd(from)}&to=${ymd(to)}')) as Map).cast<String, dynamic>();

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(context: context, initialDate: isFrom ? from : to, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (d == null) return;
    setState(() { if (isFrom) { from = d; } else { to = d; } _future = _load(); });
  }

  Future<void> _csv() async {
    setState(() => exporting = true);
    try {
      final bytes = await context.read<AuthController>().api.getBytes('/billing/register.csv?from=${ymd(from)}&to=${ymd(to)}');
      downloadBytes('gst-register-${ymd(from)}-to-${ymd(to)}.csv', bytes, 'text/csv');
      if (mounted) showOk(context, tr('GST register exported (CSV) — open in Excel / share with your CA.'));
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.calendar_today_rounded, size: 16), label: Text('${tr('From')} ${fmtDate(ymd(from))}')),
        OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.calendar_today_rounded, size: 16), label: Text('${tr('To')} ${fmtDate(ymd(to))}')),
        FilledButton.tonalIcon(onPressed: exporting ? null : _csv, icon: const Icon(Icons.table_view_rounded, size: 18), label: Text(exporting ? tr('Preparing…') : tr('Export CSV (GSTR-1 data)'))),
      ]),
      const SizedBox(height: 6),
      Text(tr('Outward supplies for the period — B2B (with GSTIN) and B2C rows, rate-wise tax summary. Cancelled invoices are listed but not totalled.'), style: TextStyle(fontSize: 12.5, color: sub)),
      const SizedBox(height: 16),
      FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(snap.error!, onRetry: () => setState(() => _future = _load()));
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
          final d = snap.data!;
          final rows = (d['rows'] as List).cast<Map<String, dynamic>>();
          final byRate = (d['byRate'] as List).cast<Map<String, dynamic>>();
          final t = (d['totals'] as Map).cast<String, dynamic>();
          return Column(children: [
            SectionCard(
              title: tr('Rate-wise summary'),
              child: byRate.isEmpty
                  ? EmptyState(tr('No invoices in this period'))
                  : AppDataTable(
                      columns: ['GST %', tr('Taxable'), 'CGST', 'SGST', 'IGST', tr('Total tax')],
                      moneyColumns: const {1, 2, 3, 4, 5},
                      rows: [
                        for (final r in byRate) ['${r['rate']}%', r['taxable'], r['cgst'], r['sgst'], r['igst'], (r['cgst'] as num) + (r['sgst'] as num) + (r['igst'] as num)],
                        [Text(tr('TOTAL'), style: const TextStyle(fontWeight: FontWeight.w800)), t['taxable'], t['cgst'], t['sgst'], t['igst'], (t['cgst'] as num) + (t['sgst'] as num) + (t['igst'] as num)],
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: tr('Invoice-wise register'),
              child: rows.isEmpty
                  ? const SizedBox.shrink()
                  : AppDataTable(
                      columns: [tr('Invoice'), tr('Date'), tr('Party'), 'GSTIN', tr('Type'), 'HSN', 'GST %', tr('Taxable'), 'CGST', 'SGST', 'IGST', tr('Status')],
                      moneyColumns: const {7, 8, 9, 10},
                      rows: [
                        for (final r in rows)
                          [
                            r['number'], fmtDate(r['invoice_date']), r['party_name'], (r['party_gstin'] as String? ?? '').isEmpty ? '—' : r['party_gstin'],
                            r['kind'], (r['hsn_code'] as String? ?? '').isEmpty ? '—' : r['hsn_code'], '${r['gst_rate']}%',
                            r['taxable'], r['cgst'], r['sgst'], r['igst'], StatusChip(r['status'] as String),
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

// ───────────────────────── Billing settings ─────────────────────────
class _SettingsTab extends StatefulWidget {
  const _SettingsTab();
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final c = {for (final k in ['prefix', 'gstin', 'legalName', 'address', 'phone', 'email', 'bankName', 'accountNo', 'ifsc', 'upiId', 'terms', 'defaultGstRate', 'creditDays']) k: TextEditingController()};
  bool roundOff = true;
  bool loading = true, busy = false;
  String? error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { for (final x in c.values) { x.dispose(); } super.dispose(); }

  Future<void> _load() async {
    try {
      final j = await context.read<AuthController>().api.get('/billing/settings');
      final b = ((j as Map)['billing'] as Map).cast<String, dynamic>();
      final co = (j['company'] as Map?)?.cast<String, dynamic>() ?? {};
      for (final e in c.entries) { e.value.text = '${b[e.key] ?? ''}'; }
      if (c['legalName']!.text.isEmpty) c['legalName']!.text = (co['name'] ?? CompanyProfile.current.name).toString();
      if (c['address']!.text.isEmpty) c['address']!.text = (co['address'] ?? CompanyProfile.current.address).toString();
      roundOff = b['roundOff'] != false;
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.put('/billing/settings', {
        for (final e in c.entries) e.key: e.value.text.trim(),
        'defaultGstRate': num.tryParse(c['defaultGstRate']!.text) ?? 5,
        'creditDays': int.tryParse(c['creditDays']!.text) ?? 0,
        'roundOff': roundOff,
      });
      if (mounted) showOk(context, tr('Billing settings saved.'));
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
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return ErrorState(error!, onRetry: () { setState(() { loading = true; error = null; }); _load(); });
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget f(String k, String label, {String? hint, String? helper, TextInputType? type, int maxLines = 1, bool caps = false}) => TextField(
          controller: c[k], enabled: canManage, maxLines: maxLines, keyboardType: type,
          textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
          decoration: InputDecoration(labelText: label, hintText: hint, helperText: helper, helperMaxLines: 2),
        );
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(tr('Printed on every tax invoice. Fill once — GSTIN decides CGST+SGST (same state) vs IGST (other state) automatically.'), style: TextStyle(color: sub, fontSize: 13)),
      const SizedBox(height: 14),
      SectionCard(title: tr('Seller details'), child: Column(children: [
        f('legalName', tr('Legal name (as on GST certificate) *')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(flex: 3, child: f('gstin', 'GSTIN', hint: '03ABCDE1234F1Z5', helper: tr('blank = composition / unregistered — invoices print without tax split'), caps: true)),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: f('prefix', tr('Invoice prefix'), hint: 'INV', helper: 'INV/26-27/0001', caps: true)),
        ]),
        const SizedBox(height: 10),
        f('address', tr('Address'), maxLines: 2),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: f('phone', tr('Phone'), type: TextInputType.phone)),
          const SizedBox(width: 10),
          Expanded(child: f('email', tr('Email'), type: TextInputType.emailAddress)),
        ]),
      ])),
      const SizedBox(height: 14),
      SectionCard(title: tr('Bank details (for payment by cheque / NEFT)'), child: Column(children: [
        f('bankName', tr('Bank & branch'), hint: 'State Bank of India, Amritsar'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: f('accountNo', tr('Account number'), type: TextInputType.number)),
          const SizedBox(width: 10),
          Expanded(child: f('ifsc', 'IFSC', caps: true)),
        ]),
        const SizedBox(height: 10),
        f('upiId', 'UPI ID', hint: 'company@sbi'),
      ])),
      const SizedBox(height: 14),
      SectionCard(title: tr('Defaults'), child: Column(children: [
        Row(children: [
          Expanded(child: f('defaultGstRate', tr('Default GST % for new products'), type: TextInputType.number, helper: tr('per product HSN / GST % is set in Products → ₹ Rates'))),
          const SizedBox(width: 10),
          Expanded(child: f('creditDays', tr('Default credit days'), type: TextInputType.number, helper: tr('party-wise credit days override this'))),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: roundOff,
          onChanged: canManage ? (v) => setState(() => roundOff = v) : null,
          title: Text(tr('Round off invoice total to the nearest rupee')),
        ),
        f('terms', tr('Terms & conditions (printed at the bottom)'), maxLines: 3),
      ])),
      const SizedBox(height: 16),
      if (canManage)
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: busy ? null : _save, icon: const Icon(Icons.save_rounded, size: 18), label: Text(busy ? tr('Saving…') : tr('Save billing settings')))),
    ]);
  }
}
