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
import 'billing_page.dart' show PartyFormDialog, gstStateName;
import 'invoice_form.dart' show kGstSlabs;

/// One line of a supplier bill. `itemType` is 'material' (raw / packing
/// material from the store), 'product' (finished / trading goods → inventory)
/// or 'other' (freight, service — no stock effect).
class PurchaseLine {
  String itemType = 'material';
  int? itemId;
  final desc = TextEditingController();
  final hsn = TextEditingController();
  final qty = TextEditingController();
  final rate = TextEditingController();
  final disc = TextEditingController(text: '0');
  final batch = TextEditingController();
  String unit = '';
  num gstRate = 5;
  num stock = 0;

  void dispose() { for (final c in [desc, hsn, qty, rate, disc, batch]) { c.dispose(); } }

  num get q => num.tryParse(qty.text.trim()) ?? 0;
  num get r => num.tryParse(rate.text.trim()) ?? 0;
  num get d => (num.tryParse(disc.text.trim()) ?? 0).clamp(0, 100);
  num get gross => q * r;
  num get taxable => gross * (1 - d / 100);
  num get tax => taxable * gstRate / 100;

  Map<String, dynamic> toJson() => {
        'itemType': itemType, 'itemId': itemType == 'other' ? null : itemId, 'description': desc.text.trim(), 'hsnCode': hsn.text.trim(),
        'qty': q, 'unit': unit, 'rate': r, 'discountPct': d, 'gstRate': gstRate, 'batchCode': batch.text.trim(),
      };
}

/// Enter a supplier's bill (inward). Every line adds to stock — raw material
/// and packing material go to the store ledger (as RECEIVED against the
/// supplier's invoice number), finished / trading goods go to inventory.
class PurchaseFormPage extends StatefulWidget {
  /// Preselect an item: 'material:12' or 'product:3' (from the stock screens).
  final String? item;
  const PurchaseFormPage({super.key, this.item});
  @override
  State<PurchaseFormPage> createState() => _PurchaseFormPageState();
}

class _PurchaseFormPageState extends State<PurchaseFormPage> {
  bool loading = true, busy = false;
  String? error;
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> materials = [];
  List<Map<String, dynamic>> suppliers = [];
  Map<String, dynamic> settings = {};
  num defaultGst = 5;
  String nextNumber = '';

  final billNo = TextEditingController();
  DateTime billDate = DateTime.now();
  DateTime receivedDate = DateTime.now();
  int partyId = 0; // 0 = one-time supplier (typed)
  final walkInName = TextEditingController();
  final walkInGstin = TextEditingController();
  final remarks = TextEditingController();
  final creditDays = TextEditingController();
  String supplyType = ''; // '' auto | intra | inter
  bool addStock = true;
  final lines = <PurchaseLine>[];

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    for (final l in lines) { l.dispose(); }
    for (final c in [billNo, walkInName, walkInGstin, remarks, creditDays]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AuthController>().api;
    try {
      final res = await Future.wait([
        api.get('/billing/items'),
        api.get('/billing/parties?kind=supplier'),
        api.get('/billing/settings'),
        api.get('/billing/purchases/next-number?date=${ymd(billDate)}'),
      ]);
      final items = (res[0] as Map).cast<String, dynamic>();
      products = (items['products'] as List).cast<Map<String, dynamic>>();
      materials = (items['materials'] as List).cast<Map<String, dynamic>>();
      defaultGst = (items['defaultGstRate'] as num?) ?? 5;
      suppliers = ((res[1] as Map)['parties'] as List).cast<Map<String, dynamic>>();
      settings = ((res[2] as Map)['billing'] as Map).cast<String, dynamic>();
      nextNumber = ((res[3] as Map)['number'] ?? '').toString();
      final pre = widget.item ?? '';
      if (pre.contains(':')) {
        final t = pre.split(':')[0];
        final id = int.tryParse(pre.split(':')[1]);
        final l = _blank();
        if (id != null && (t == 'material' || t == 'product')) {
          l.itemType = t;
          _applyItem(l, id, refresh: false);
          lines.add(l);
        }
      }
      if (lines.isEmpty) lines.add(_blank());
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  PurchaseLine _blank() {
    final l = PurchaseLine();
    l.gstRate = kGstSlabs.contains(defaultGst) ? defaultGst : 5;
    // Companies without a raw / packing store bill finished goods first.
    if (materials.isEmpty) l.itemType = 'product';
    return l;
  }

  List<Map<String, dynamic>> _choices(String type) => type == 'product' ? products : type == 'material' ? materials : const [];

  void _applyItem(PurchaseLine l, int? id, {bool refresh = true}) {
    final p = _choices(l.itemType).where((e) => e['id'] == id).firstOrNull;
    l.itemId = p == null ? null : id; // never keep an id the dropdown cannot show
    if (p != null) {
      l.desc.text = p['name'] as String;
      l.hsn.text = (p['hsn_code'] ?? '').toString();
      l.unit = (p['unit'] ?? '').toString();
      l.stock = (p['stock'] as num?) ?? 0;
      final g = (p['gst_rate'] as num?) ?? defaultGst;
      l.gstRate = kGstSlabs.contains(g) ? g : 5;
      final pr = (p['purchase_rate'] as num?) ?? 0;
      if (pr > 0) l.rate.text = _numText(pr);
    }
    if (refresh) setState(() {});
  }

  static String _numText(Object? v) {
    final n = v is num ? v : num.tryParse('$v') ?? 0;
    if (n == 0) return '';
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }

  Map<String, dynamic>? get supplier => partyId == 0 ? null : suppliers.where((p) => p['id'] == partyId).firstOrNull;

  String get myState {
    final g = (settings['gstin'] ?? '').toString();
    final s = (settings['stateCode'] ?? '').toString();
    return s.isNotEmpty ? s : (g.length >= 2 ? g.substring(0, 2) : '');
  }

  String get supplierState {
    final p = supplier;
    if (p != null && (p['state_code'] as String? ?? '').isNotEmpty) return p['state_code'] as String;
    final g = p == null ? walkInGstin.text.trim() : (p['gstin'] as String? ?? '');
    if (g.length >= 2) return g.substring(0, 2);
    return '';
  }

  bool get intra {
    if (supplyType == 'intra') return true;
    if (supplyType == 'inter') return false;
    final s = supplierState;
    return myState.isEmpty || s.isEmpty || myState == s;
  }

  Future<void> _addSupplier() async {
    final saved = await showFastDialog<bool>(context, (_) => const PartyFormDialog(asSupplier: true));
    if (saved != true || !mounted) return;
    try {
      final j = await context.read<AuthController>().api.get('/billing/parties?kind=supplier');
      suppliers = ((j as Map)['parties'] as List).cast<Map<String, dynamic>>();
      setState(() => partyId = suppliers.isEmpty ? 0 : suppliers.map((p) => p['id'] as int).reduce((a, b) => a > b ? a : b));
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _save() async {
    final active = lines.where((l) => l.q > 0).toList();
    if (billNo.text.trim().isEmpty) { showErr(context, tr("Enter the supplier's invoice / bill number.")); return; }
    if (partyId == 0 && walkInName.text.trim().isEmpty) { showErr(context, tr('Select a supplier or type the supplier name.')); return; }
    if (active.isEmpty) { showErr(context, tr('Add at least one item with quantity.')); return; }
    for (final l in active) {
      if (l.itemType != 'other' && l.itemId == null) { showErr(context, tr('Pick the item from the list for every line (or choose "Other / service").')); return; }
      if (l.desc.text.trim().isEmpty) { showErr(context, tr('Every line needs a description.')); return; }
      if (l.r <= 0) { showErr(context, tr('Rate is missing for ${l.desc.text.trim()}.')); return; }
    }
    setState(() => busy = true);
    try {
      final j = await context.read<AuthController>().api.post('/billing/purchases', {
        'billNo': billNo.text.trim().toUpperCase(),
        'billDate': ymd(billDate),
        'receivedDate': ymd(receivedDate),
        'partyId': partyId == 0 ? null : partyId,
        'partyName': walkInName.text.trim(),
        'partyGstin': walkInGstin.text.trim().toUpperCase(),
        'supplyType': supplyType,
        'addStock': addStock,
        if (creditDays.text.trim().isNotEmpty) 'creditDays': int.tryParse(creditDays.text.trim()) ?? 0,
        'remarks': remarks.text.trim(),
        'items': [for (final l in active) l.toJson()],
      });
      if (!mounted) return;
      showOk(context, '${tr('Purchase')} ${(j as Map)['number']} ${tr('saved')} · ${inr(j['total'])}${addStock ? ' · ${tr('stock updated')}' : ''}');
      context.pushReplacement('/billing/purchases/${j['id']}');
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
    final subtotal = lines.fold<num>(0, (s, l) => s + l.taxable);
    final tax = lines.fold<num>(0, (s, l) => s + l.tax);
    final raw = subtotal + tax;
    final total = settings['roundOff'] == false ? raw : raw.round();
    final wide = MediaQuery.sizeOf(context).width > 820;
    final stockLines = lines.where((l) => l.q > 0 && l.itemType != 'other' && l.itemId != null).length;

    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        IconButton(onPressed: () => context.canPop() ? context.pop(false) : context.go('/billing?tab=purchases'), icon: const Icon(Icons.arrow_back_rounded)),
        const SizedBox(width: 4),
        Expanded(child: Text(tr('New Purchase (Inward)'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
        if (nextNumber.isNotEmpty) Chip(label: Text(nextNumber, style: const TextStyle(fontWeight: FontWeight.w700)), avatar: const Icon(Icons.tag_rounded, size: 16)),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 12, top: 4),
        child: Text(tr("Enter the supplier's bill exactly as printed — every line adds to stock (raw / packing material → store ledger, finished goods → inventory) with the bill number as reference."), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: tr('Supplier & bill'),
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(
            width: wide ? 380 : double.infinity,
            child: Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('sup-$partyId-${suppliers.length}'),
                  initialValue: partyId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Supplier *')),
                  items: [
                    DropdownMenuItem<int>(value: 0, child: Text(tr('One-time / type name below'))),
                    for (final p in suppliers) DropdownMenuItem<int>(value: p['id'] as int, child: Text(p['name'] as String, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => partyId = v ?? 0),
                ),
              ),
              IconButton(tooltip: tr('Add Supplier'), onPressed: _addSupplier, icon: const Icon(Icons.person_add_alt_1_rounded)),
            ]),
          ),
          if (partyId == 0) ...[
            SizedBox(width: wide ? 260 : double.infinity, child: TextField(controller: walkInName, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Supplier name *'), hintText: tr('e.g. Ambala Sugar Mills')))),
            SizedBox(width: wide ? 220 : double.infinity, child: TextField(controller: walkInGstin, textCapitalization: TextCapitalization.characters, maxLength: 15, decoration: InputDecoration(labelText: '${tr('Supplier')} GSTIN', hintText: tr('blank = unregistered'), counterText: ''), onChanged: (_) => setState(() {}))),
          ] else
            SizedBox(
              width: wide ? 400 : double.infinity,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  [
                    if ((supplier!['gstin'] as String? ?? '').isNotEmpty) 'GSTIN ${supplier!['gstin']}' else tr('Unregistered'),
                    if ((supplier!['state_code'] as String? ?? '').isNotEmpty) gstStateName(supplier!['state_code'] as String),
                    if ((supplier!['credit_days'] ?? 0) != 0) '${tr('Credit')} ${supplier!['credit_days']} ${tr('days')}',
                    if (((supplier!['payable'] as num?) ?? 0) > 0) '${tr('Payable')} ${inr(supplier!['payable'])}',
                  ].join(' · '),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                ),
              ),
            ),
          SizedBox(
            width: wide ? 240 : double.infinity,
            child: TextField(
              controller: billNo,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: tr("Supplier's invoice no *"), hintText: 'e.g. ASM/1187', prefixIcon: const Icon(Icons.receipt_outlined, size: 18)),
            ),
          ),
          _dateField(tr('Bill date'), billDate, (d) async {
            setState(() => billDate = d);
            try {
              final j = await context.read<AuthController>().api.get('/billing/purchases/next-number?date=${ymd(d)}');
              if (mounted) setState(() => nextNumber = ((j as Map)['number'] ?? '').toString());
            } catch (_) {}
          }, wide),
          _dateField(tr('Received on'), receivedDate, (d) => setState(() => receivedDate = d), wide),
          SizedBox(
            width: wide ? 250 : double.infinity,
            child: DropdownButtonFormField<String>(
              key: ValueKey('st-$supplyType'),
              initialValue: supplyType,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Tax type'), helperText: intra ? 'CGST + SGST' : 'IGST', helperStyle: TextStyle(color: intra ? AppColors.green : AppColors.orange, fontWeight: FontWeight.w700)),
              items: [
                DropdownMenuItem(value: '', child: Text('${tr('Auto')} · ${supplierState.isEmpty ? tr('same state') : gstStateName(supplierState)}', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 'intra', child: Text(tr('Same state (CGST + SGST)'))),
                DropdownMenuItem(value: 'inter', child: Text(tr('Other state (IGST)'))),
              ],
              onChanged: (v) => setState(() => supplyType = v ?? ''),
            ),
          ),
          SizedBox(width: wide ? 160 : double.infinity, child: TextField(controller: creditDays, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Credit days'), hintText: partyId == 0 ? '0' : '${supplier!['credit_days'] ?? 0}', helperText: tr('blank = supplier default')))),
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: tr('Items received'),
        trailing: TextButton.icon(onPressed: () => setState(() => lines.add(_blank())), icon: const Icon(Icons.add_rounded, size: 18), label: Text(tr('Add line'))),
        child: Column(children: [
          for (var i = 0; i < lines.length; i++) _lineEditor(i, scheme, wide),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: addStock,
            onChanged: (v) => setState(() => addStock = v),
            title: Text(tr('Add these quantities to stock')),
            subtitle: Text(
              addStock
                  ? '$stockLines ${tr('line(s) will be added to stock — the ledger shows the bill number as reference.')}'
                  : tr('Off — bill is recorded for payment only (use when the stock was already received manually).'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          TextField(controller: remarks, decoration: InputDecoration(labelText: tr('Remarks (vehicle, GRN no, e-way bill…)')), maxLines: 2),
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _tot(tr('Taxable value'), subtotal),
          if (intra) ...[_tot('CGST', tax / 2), _tot('SGST', tax / 2)] else _tot('IGST', tax),
          if (settings['roundOff'] != false) _tot(tr('Round off'), total - raw),
          const Divider(height: 18),
          Text('${tr('Bill total')}  ${inr(total)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(tr('Check this matches the total printed on the supplier\'s bill.'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => context.canPop() ? context.pop(false) : context.go('/billing?tab=purchases'), child: Text(tr('Cancel'))),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: busy ? null : _save,
              icon: const Icon(Icons.south_west_rounded, size: 18),
              label: Text(busy ? tr('Saving…') : tr('Save & add to stock')),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 40),
    ]);
  }

  Widget _dateField(String label, DateTime value, ValueChanged<DateTime> onPick, bool wide) => SizedBox(
        width: wide ? 200 : double.infinity,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: value, firstDate: DateTime(DateTime.now().year - 2, 4, 1), lastDate: DateTime.now().add(const Duration(days: 7)));
            if (d != null && mounted) onPick(d);
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18)),
            child: Text(fmtDate(ymd(value))),
          ),
        ),
      );

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
    final choices = _choices(l.itemType);
    final unitLabel = l.itemType == 'product' ? U.cb : (l.unit.isEmpty ? tr('unit') : l.unit);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: scheme.outlineVariant)),
      child: Column(children: [
        Row(children: [
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              key: ValueKey('t-$i-${l.itemType}'),
              initialValue: l.itemType,
              decoration: InputDecoration(labelText: '${tr('Line')} ${i + 1}'),
              items: [
                DropdownMenuItem(value: 'material', child: Text(tr('Material'))),
                DropdownMenuItem(value: 'product', child: Text(tr('Finished goods'))),
                DropdownMenuItem(value: 'other', child: Text(tr('Other / service'))),
              ],
              onChanged: (v) => setState(() {
                l.itemType = v ?? 'material';
                l.itemId = null; l.unit = ''; l.stock = 0; l.desc.clear(); l.hsn.clear(); l.rate.clear();
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: l.itemType == 'other'
                ? TextField(controller: l.desc, decoration: InputDecoration(labelText: tr('Description *'), hintText: tr('Freight / loading / service')), onChanged: (_) => setState(() {}))
                : DropdownButtonFormField<int>(
                    key: ValueKey('it-$i-${l.itemType}-${l.itemId}'),
                    initialValue: l.itemId ?? 0,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l.itemType == 'product' ? tr('Product *') : tr('Raw / packing material *')),
                    items: [
                      DropdownMenuItem<int>(value: 0, child: Text(tr('— select —'))),
                      for (final p in choices)
                        DropdownMenuItem<int>(
                          value: p['id'] as int,
                          child: Text(l.itemType == 'material' && (p['category'] as String? ?? '').isNotEmpty ? '${ItemCode.pick(p)}  ·  ${tr(p['category'] as String)}' : ItemCode.pick(p), overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => _applyItem(l, v == null || v == 0 ? null : v),
                  ),
          ),
          IconButton(
            tooltip: tr('Remove line'),
            onPressed: lines.length <= 1 ? null : () => setState(() { lines.removeAt(i).dispose(); }),
            icon: Icon(Icons.remove_circle_outline_rounded, color: lines.length <= 1 ? scheme.outline : scheme.error),
          ),
        ]),
        if (l.itemType != 'other' && l.itemId != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${tr('In stock now')}: ${qty(l.stock)} $unitLabel${l.q > 0 && addStock ? '  →  ${qty(l.stock + l.q)} $unitLabel ${tr('after this bill')}' : ''}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (l.itemType != 'other') SizedBox(width: wide ? 260 : double.infinity, child: TextField(controller: l.desc, decoration: InputDecoration(labelText: tr('Description on bill')), onChanged: (_) => setState(() {}))),
          SizedBox(width: 110, child: TextField(controller: l.hsn, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'HSN'))),
          SizedBox(width: 130, child: TextField(controller: l.qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: '${tr('Qty')} ($unitLabel) *'), onChanged: (_) => setState(() {}))),
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
          if (l.itemType != 'other') SizedBox(width: 130, child: TextField(controller: l.batch, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('Batch / lot')))),
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
