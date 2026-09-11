import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import 'billing_page.dart' show PartyFormDialog, gstStateName, kGstStates;

/// GST slabs after GST 2.0 (22 Sep 2025): 0 / 5 / 18 / 40. The legacy 12 and
/// 28 slabs stay selectable for old stock / special cases.
const List<num> kGstSlabs = [0, 5, 18, 40, 12, 28];

class InvoiceLine {
  int? productId;
  final desc = TextEditingController();
  final hsn = TextEditingController();
  final qty = TextEditingController();
  final rate = TextEditingController();
  final disc = TextEditingController(text: '0');
  final batch = TextEditingController();
  num piecesPerPack = 1;
  String ratePer = 'pack';
  num gstRate = 5;

  void dispose() { for (final c in [desc, hsn, qty, rate, disc, batch]) { c.dispose(); } }

  num get q => num.tryParse(qty.text.trim()) ?? 0;
  num get r => num.tryParse(rate.text.trim()) ?? 0;
  num get d => (num.tryParse(disc.text.trim()) ?? 0).clamp(0, 100);
  num get units => ratePer == 'piece' ? q * (piecesPerPack <= 0 ? 1 : piecesPerPack) : q;
  num get gross => units * r;
  num get taxable => gross * (1 - d / 100);
  num get tax => taxable * gstRate / 100;

  Map<String, dynamic> toJson() => {
        'productId': productId, 'description': desc.text.trim(), 'hsnCode': hsn.text.trim(), 'qty': q,
        'piecesPerPack': piecesPerPack, 'ratePer': ratePer, 'rate': r, 'discountPct': d, 'gstRate': gstRate, 'batchCode': batch.text.trim(),
      };
}

/// New tax invoice. `dispatchId` prefills the lines from a dispatch (qty,
/// batch, product HSN / GST / rate) and links the invoice to it.
class InvoiceFormPage extends StatefulWidget {
  final int? dispatchId;
  const InvoiceFormPage({super.key, this.dispatchId});
  @override
  State<InvoiceFormPage> createState() => _InvoiceFormPageState();
}

class _InvoiceFormPageState extends State<InvoiceFormPage> {
  bool loading = true, busy = false;
  String? error;
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> parties = [];
  Map<String, dynamic> settings = {};
  Map<String, dynamic>? dispatch;
  Map<String, dynamic>? alreadyInvoiced;
  String nextNumber = '';

  DateTime date = DateTime.now();
  int partyId = 0; // 0 = walk-in (typed name)
  final walkInName = TextEditingController();
  final walkInGstin = TextEditingController();
  final remarks = TextEditingController();
  String placeOfSupply = '';
  bool deductStock = true;
  final lines = <InvoiceLine>[];

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    for (final l in lines) { l.dispose(); }
    walkInName.dispose(); walkInGstin.dispose(); remarks.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AuthController>().api;
    try {
      final res = await Future.wait([
        api.get('/billing/products'),
        api.get('/billing/parties'),
        api.get('/billing/settings'),
        api.get('/billing/next-number?date=${ymd(date)}'),
        if (widget.dispatchId != null) api.get('/billing/from-dispatch/${widget.dispatchId}'),
      ]);
      products = ((res[0] as Map)['products'] as List).cast<Map<String, dynamic>>();
      parties = ((res[1] as Map)['parties'] as List).cast<Map<String, dynamic>>();
      settings = ((res[2] as Map)['billing'] as Map).cast<String, dynamic>();
      nextNumber = ((res[3] as Map)['number'] ?? '').toString();
      if (widget.dispatchId != null) {
        final fd = (res[4] as Map).cast<String, dynamic>();
        dispatch = (fd['dispatch'] as Map).cast<String, dynamic>();
        alreadyInvoiced = (fd['alreadyInvoiced'] as Map?)?.cast<String, dynamic>();
        for (final l in (fd['lines'] as List).cast<Map<String, dynamic>>()) {
          lines.add(_lineFrom(l));
        }
        // A dispatch usually goes to one party — preselect it when the destination matches a party name.
        final dest = (dispatch!['destination'] ?? '').toString().toLowerCase();
        for (final p in parties) {
          if (dest.isNotEmpty && (p['name'] as String).toLowerCase() == dest) { partyId = p['id'] as int; break; }
        }
      }
      if (lines.isEmpty) lines.add(_blank());
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  InvoiceLine _blank() {
    final l = InvoiceLine();
    l.gstRate = num.tryParse('${settings['defaultGstRate'] ?? 5}') ?? 5;
    return l;
  }

  InvoiceLine _lineFrom(Map<String, dynamic> j) {
    final l = InvoiceLine()
      ..productId = j['productId'] as int?
      ..piecesPerPack = (j['piecesPerPack'] as num?) ?? 1
      ..ratePer = j['ratePer'] == 'piece' ? 'piece' : 'pack'
      ..gstRate = (j['gstRate'] as num?) ?? 5;
    l.desc.text = (j['description'] ?? '').toString();
    l.hsn.text = (j['hsnCode'] ?? '').toString();
    l.qty.text = _numText(j['qty']);
    l.rate.text = _numText(j['rate']);
    l.batch.text = (j['batchCode'] ?? '').toString();
    return l;
  }

  static String _numText(Object? v) {
    final n = v is num ? v : num.tryParse('$v') ?? 0;
    if (n == 0) return '';
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }

  void _applyProduct(InvoiceLine l, int? id) {
    l.productId = id;
    final p = products.where((e) => e['id'] == id).firstOrNull;
    if (p == null) return;
    l.desc.text = p['name'] as String;
    l.hsn.text = (p['hsn_code'] ?? '').toString();
    l.piecesPerPack = (p['bottles_per_cb'] as num?) ?? 1;
    l.ratePer = p['rate_per'] == 'piece' ? 'piece' : 'pack';
    l.gstRate = p['gst_rate'] == null ? (num.tryParse('${settings['defaultGstRate'] ?? 5}') ?? 5) : (p['gst_rate'] as num);
    if (!kGstSlabs.contains(l.gstRate)) l.gstRate = 5;
    final sr = (p['sale_rate'] as num?) ?? 0;
    if (sr > 0) l.rate.text = _numText(sr);
    setState(() {});
  }

  Map<String, dynamic>? get party => partyId == 0 ? null : parties.where((p) => p['id'] == partyId).firstOrNull;

  String get myState {
    final g = (settings['gstin'] ?? '').toString();
    final s = (settings['stateCode'] ?? '').toString();
    return s.isNotEmpty ? s : (g.length >= 2 ? g.substring(0, 2) : '');
  }

  String get effectivePos {
    if (placeOfSupply.isNotEmpty) return placeOfSupply;
    final p = party;
    if (p != null && (p['state_code'] as String? ?? '').isNotEmpty) return p['state_code'] as String;
    final g = p == null ? walkInGstin.text.trim() : (p['gstin'] as String? ?? '');
    if (g.length >= 2) return g.substring(0, 2);
    return myState;
  }

  bool get intra => myState.isEmpty || effectivePos.isEmpty || myState == effectivePos;

  Future<void> _save() async {
    final active = lines.where((l) => l.q > 0).toList();
    if (active.isEmpty) { showErr(context, tr('Add at least one item with quantity.')); return; }
    if (partyId == 0 && walkInName.text.trim().isEmpty) { showErr(context, tr('Select a party or type a customer name.')); return; }
    for (final l in active) {
      if (l.desc.text.trim().isEmpty) { showErr(context, tr('Every line needs a description.')); return; }
      if (l.r <= 0) { showErr(context, tr('Rate is missing for ${l.desc.text.trim()}.')); return; }
    }
    setState(() => busy = true);
    try {
      final j = await context.read<AuthController>().api.post('/billing/invoices', {
        'invoiceDate': ymd(date),
        'partyId': partyId == 0 ? null : partyId,
        'partyName': walkInName.text.trim(),
        'partyGstin': walkInGstin.text.trim().toUpperCase(),
        'placeOfSupply': placeOfSupply,
        'dispatchId': widget.dispatchId,
        'deductStock': widget.dispatchId == null && deductStock,
        'remarks': remarks.text.trim(),
        'items': [for (final l in active) l.toJson()],
      });
      if (!mounted) return;
      showOk(context, '${tr('Invoice')} ${(j as Map)['number']} ${tr('created')} · ${inr(j['total'])}');
      context.pushReplacement('/billing/${j['id']}');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return ErrorState(error!, onRetry: () { setState(() { loading = true; error = null; }); _load(); });
    final gstinMissing = (settings['gstin'] ?? '').toString().isEmpty;
    final subtotal = lines.fold<num>(0, (s, l) => s + l.taxable);
    final tax = lines.fold<num>(0, (s, l) => s + l.tax);
    final raw = subtotal + tax;
    final total = settings['roundOff'] == false ? raw : raw.round();
    final wide = MediaQuery.sizeOf(context).width > 820;

    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        IconButton(onPressed: () => context.canPop() ? context.pop(false) : context.go('/billing'), icon: const Icon(Icons.arrow_back_rounded)),
        const SizedBox(width: 4),
        Expanded(child: Text(tr('New Tax Invoice'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
        if (nextNumber.isNotEmpty) Chip(label: Text(nextNumber, style: const TextStyle(fontWeight: FontWeight.w700)), avatar: const Icon(Icons.tag_rounded, size: 16)),
      ]),
      if (gstinMissing)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: MaterialBanner(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            backgroundColor: AppColors.amber.withValues(alpha: 0.12),
            leading: const Icon(Icons.info_outline_rounded, color: AppColors.amber),
            content: Text(tr('Company GSTIN is not set — the invoice will print without a tax split. Set it in Billing → Billing Setup.')),
            actions: [TextButton(onPressed: () => context.push('/billing?tab=settings'), child: Text(tr('Open setup')))],
          ),
        ),
      if (alreadyInvoiced != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: MaterialBanner(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            backgroundColor: AppColors.red.withValues(alpha: 0.10),
            leading: const Icon(Icons.block_rounded, color: AppColors.red),
            content: Text('${tr('This dispatch is already invoiced as')} ${alreadyInvoiced!['number']}. ${tr('Cancel that invoice first to bill it again.')}'),
            actions: [TextButton(onPressed: () => context.pushReplacement('/billing/${alreadyInvoiced!['id']}'), child: Text(tr('Open invoice')))],
          ),
        ),
      const SizedBox(height: 14),
      SectionCard(
        title: tr('Bill to'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (dispatch != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                const Icon(Icons.local_shipping_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('${tr('From dispatch')} ${dispatch!['code']} · ${fmtDate(dispatch!['date'])} · ${dispatch!['destination']}${(dispatch!['truck'] ?? '').toString().isEmpty ? '' : ' · ${dispatch!['truck']}'}', style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(
              width: wide ? 380 : double.infinity,
              child: Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('party-$partyId-${parties.length}'),
                    initialValue: partyId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Party (customer)')),
                    items: [
                      DropdownMenuItem<int>(value: 0, child: Text(tr('Walk-in / type name below'))),
                      for (final p in parties) DropdownMenuItem<int>(value: p['id'] as int, child: Text(p['name'] as String, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => partyId = v ?? 0),
                  ),
                ),
                IconButton(
                  tooltip: tr('Add Party'),
                  onPressed: () async {
                    final saved = await showFastDialog<bool>(context, (_) => const PartyFormDialog());
                    if (saved != true || !mounted) return;
                    final j = await context.read<AuthController>().api.get('/billing/parties');
                    parties = ((j as Map)['parties'] as List).cast<Map<String, dynamic>>();
                    setState(() => partyId = parties.isEmpty ? 0 : parties.map((p) => p['id'] as int).reduce((a, b) => a > b ? a : b));
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                ),
              ]),
            ),
            if (partyId == 0) ...[
              SizedBox(width: wide ? 260 : double.infinity, child: TextField(controller: walkInName, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Customer name *'), hintText: tr('Cash sale / walk-in')))),
              SizedBox(width: wide ? 220 : double.infinity, child: TextField(controller: walkInGstin, textCapitalization: TextCapitalization.characters, maxLength: 15, decoration: const InputDecoration(labelText: 'GSTIN (optional)', counterText: ''), onChanged: (_) => setState(() {}))),
            ] else
              SizedBox(
                width: wide ? 400 : double.infinity,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    [if ((party!['gstin'] as String? ?? '').isNotEmpty) 'GSTIN ${party!['gstin']}', if ((party!['address'] as String? ?? '').isNotEmpty) party!['address'] as String, if ((party!['credit_days'] ?? 0) != 0) '${tr('Credit')} ${party!['credit_days']} ${tr('days')}'].join(' · '),
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                  ),
                ),
              ),
            SizedBox(
              width: wide ? 220 : double.infinity,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(DateTime.now().year - 1, 4, 1), lastDate: DateTime.now().add(const Duration(days: 7)));
                  if (d == null || !mounted) return;
                  setState(() => date = d);
                  try {
                    final j = await context.read<AuthController>().api.get('/billing/next-number?date=${ymd(d)}');
                    if (mounted) setState(() => nextNumber = ((j as Map)['number'] ?? '').toString());
                  } catch (_) {}
                },
                child: InputDecorator(
                  decoration: InputDecoration(labelText: tr('Invoice date'), suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18)),
                  child: Text(fmtDate(ymd(date))),
                ),
              ),
            ),
            SizedBox(
              width: wide ? 300 : double.infinity,
              child: DropdownButtonFormField<String>(
                key: ValueKey('pos-$placeOfSupply'),
                initialValue: placeOfSupply,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Place of supply'), helperText: intra ? 'CGST + SGST' : 'IGST', helperStyle: TextStyle(color: intra ? AppColors.green : AppColors.orange, fontWeight: FontWeight.w700)),
                items: [
                  DropdownMenuItem(value: '', child: Text('${tr('Auto')} · ${gstStateName(effectivePos)}', overflow: TextOverflow.ellipsis)),
                  for (final e in kGstStates.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} · ${e.value}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => placeOfSupply = v ?? ''),
              ),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: tr('Items'),
        trailing: TextButton.icon(onPressed: () => setState(() => lines.add(_blank())), icon: const Icon(Icons.add_rounded, size: 18), label: Text(tr('Add line'))),
        child: Column(children: [
          for (var i = 0; i < lines.length; i++) _lineEditor(i, scheme, wide),
          if (widget.dispatchId == null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: deductStock,
              onChanged: (v) => setState(() => deductStock = v),
              title: Text(tr('Reduce finished-goods stock for these items')),
              subtitle: Text(tr('Turn off when the goods already left through a dispatch entry.'), style: const TextStyle(fontSize: 12)),
            ),
          TextField(controller: remarks, decoration: InputDecoration(labelText: tr('Remarks (PO no, vehicle, e-way bill…)')), maxLines: 2),
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _tot(tr('Taxable value'), subtotal),
          if (intra) ...[_tot('CGST', tax / 2), _tot('SGST', tax / 2)] else _tot('IGST', tax),
          if (settings['roundOff'] != false) _tot(tr('Round off'), total - raw),
          const Divider(height: 18),
          Text('${tr('Grand total')}  ${inr(total)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => context.canPop() ? context.pop(false) : context.go('/billing'), child: Text(tr('Cancel'))),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: busy || alreadyInvoiced != null ? null : _save,
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: Text(busy ? tr('Saving…') : tr('Create Invoice')),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 40),
    ]);
  }

  Widget _tot(String label, num v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(width: 20),
          SizedBox(width: 130, child: Text(inr(v), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _lineEditor(int i, ColorScheme scheme, bool wide) {
    final l = lines[i];
    final packLabel = U.carton;
    final pieceLabel = U.piece;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: scheme.outlineVariant)),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey('p-$i-${l.productId}'),
              initialValue: l.productId ?? 0,
              isExpanded: true,
              decoration: InputDecoration(labelText: '${tr('Item')} ${i + 1}'),
              items: [
                DropdownMenuItem<int>(value: 0, child: Text(tr('Other / free text'))),
                for (final p in products) DropdownMenuItem<int>(value: p['id'] as int, child: Text(p['name'] as String, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => _applyProduct(l, v == null || v == 0 ? null : v),
            ),
          ),
          IconButton(
            tooltip: tr('Remove line'),
            onPressed: lines.length <= 1 ? null : () => setState(() { lines.removeAt(i).dispose(); }),
            icon: Icon(Icons.remove_circle_outline_rounded, color: lines.length <= 1 ? scheme.outline : scheme.error),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(width: wide ? 320 : double.infinity, child: TextField(controller: l.desc, decoration: InputDecoration(labelText: tr('Description *')), onChanged: (_) => setState(() {}))),
          SizedBox(width: 110, child: TextField(controller: l.hsn, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'HSN'))),
          SizedBox(width: 120, child: TextField(controller: l.qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: '${tr('Qty')} ($packLabel) *'), onChanged: (_) => setState(() {}))),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              key: ValueKey('rp-$i-${l.ratePer}'),
              initialValue: l.ratePer,
              decoration: InputDecoration(labelText: tr('Rate per')),
              items: [
                DropdownMenuItem(value: 'pack', child: Text(packLabel)),
                DropdownMenuItem(value: 'piece', child: Text('$pieceLabel (${_numText(l.piecesPerPack).isEmpty ? 1 : _numText(l.piecesPerPack)}/${U.cb})', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => l.ratePer = v ?? 'pack'),
            ),
          ),
          SizedBox(width: 130, child: TextField(controller: l.rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: '${tr('Rate')} ₹ *'), onChanged: (_) => setState(() {}))),
          SizedBox(width: 90, child: TextField(controller: l.disc, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('Disc %')), onChanged: (_) => setState(() {}))),
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<num>(
              key: ValueKey('g-$i-${l.gstRate}'),
              initialValue: kGstSlabs.contains(l.gstRate) ? l.gstRate : 5,
              decoration: const InputDecoration(labelText: 'GST %'),
              items: [for (final g in kGstSlabs) DropdownMenuItem(value: g, child: Text('$g%${g == 12 || g == 28 ? ' *' : ''}'))],
              onChanged: (v) => setState(() => l.gstRate = v ?? 5),
            ),
          ),
          SizedBox(width: 130, child: TextField(controller: l.batch, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('Batch / lot')))),
          SizedBox(
            width: 170,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text('${inr(l.taxable)} + ${tr('GST')} ${inr(l.tax)}', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, fontSize: 12.5)),
            ),
          ),
        ]),
      ]),
    );
  }
}
