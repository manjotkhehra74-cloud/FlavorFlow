import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/industry_pack.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/item_code.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// The factory's shrink-tray sizes — a fixed list, the SAME for every
/// product (white vinegar or soya sauce): 610 / 740 / 1.0 L / 1.3 L.
/// Planning in trays offers only these sizes (user-specified 09-19).
const _traySizes = ['610', '740', '1.0', '1.3'];

/// Production — batch execution board (create → start → complete).
/// Completion moves finished goods (CB + trays) into inventory and can
/// auto-consume packing material per the product BOM.
class ProductionPage extends StatefulWidget {
  const ProductionPage({super.key});
  @override
  State<ProductionPage> createState() => _ProductionPageState();
}

class _ProductionPageState extends State<ProductionPage> {
  String _status = '';
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final q = _status.isEmpty ? '' : '?status=$_status';
    final json = await context.read<AuthController>().api.get('/production/batches$q');
    return ((json as Map)['batches'] as List).cast<Map<String, dynamic>>();
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canExecute = auth.can('production.execute');
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        return ListView(padding: const EdgeInsets.all(20), children: [
          // Chips in a Wrap so they never overlap the table below on narrow screens.
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final s in ['', 'PLANNED', 'IN_PROGRESS', 'COMPLETED'])
              ChoiceChip(
                label: Text(s.isEmpty ? tr('All') : tr(s.replaceAll('_', ' ').toLowerCase())),
                selected: _status == s,
                onSelected: (_) => setState(() { _status = s; _future = _load(); }),
              ),
            if (auth.can('production.manage'))
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilledButton.icon(
                  onPressed: () async {
                    final saved = await showFastDialog<bool>(context, (_) => const BatchFormDialog());
                    if (saved == true) _reload();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(U.ize(tr('New Batch'))),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: U.ize('Production Batches'),
            child: rows.isEmpty
                ? EmptyState(U.ize('No batches yet'))
                : AppDataTable(
                    columns: [U.ize('Batch'), 'Product', 'Planned ${U.cb}', 'Produced ${U.cb}', if (CompanyProfile.usesTrays) U.tray, 'Gross kg (planned)', 'Planned Date', 'Status', 'Actions'],
                    rows: [
                      for (final b in rows)
                        [
                          Text(b['code'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                          ItemNameCell(name: '${b['product_name']}', code: '${b['item_code'] ?? ''}'), // not ItemCode.of — b['code'] is the batch code
                          qtyInt(b['planned_cb']),
                          qtyInt(b['produced_cb']),
                          if (CompanyProfile.usesTrays) qtyInt(b['produced_trays'] ?? 0),
                          qty((b['planned_cb'] as num) * (b['weight_per_cb'] as num)),
                          fmtDate(b['planned_date']),
                          StatusChip(b['status'] as String),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: U.ize('View batch'),
                              icon: const Icon(Icons.visibility_outlined, size: 19),
                              onPressed: () async {
                                await context.push('/production/batches/${b['id']}');
                                _reload();
                              },
                            ),
                            if (auth.can('production.manage') && b['status'] != 'IN_PROGRESS')
                              IconButton(
                                tooltip: U.ize('Edit batch'),
                                icon: const Icon(Icons.edit_outlined, size: 19),
                                onPressed: () async {
                                  final saved = await showFastDialog<bool>(context, (_) => BatchFormDialog(batch: b));
                                  if (saved == true) _reload();
                                },
                              ),
                            if (auth.can('production.manage'))
                              IconButton(
                                tooltip: U.ize('Delete batch'),
                                icon: Icon(Icons.delete_outline_rounded, size: 19, color: Theme.of(context).colorScheme.error),
                                onPressed: () => _delete(context, b),
                              ),
                            if (canExecute && b['status'] == 'PLANNED')
                              TextButton.icon(
                                onPressed: () => _start(context, b),
                                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                label: Text(tr('Start')),
                              ),
                            if (canExecute && b['status'] == 'IN_PROGRESS')
                              TextButton.icon(
                                onPressed: () => _complete(context, b),
                                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                label: Text(tr('Complete')),
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

  Future<void> _start(BuildContext context, Map<String, dynamic> b) async {
    try {
      await context.read<AuthController>().api.post('/production/batches/${b['id']}/start');
      _reload();
      if (context.mounted) showOk(context, '${b['code']} started.');
    } catch (e) {
      if (context.mounted) showErr(context, e);
    }
  }

  Future<void> _delete(BuildContext context, Map<String, dynamic> b) async {
    final done = b['status'] == 'COMPLETED';
    final running = b['status'] == 'IN_PROGRESS';
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete ${b['code']}?'),
        content: Text(done
            ? '${b['product_name']} · produced ${qtyInt(b['produced_cb'])} ${U.cb} + ${qtyInt(b['produced_trays'] ?? 0)} ${U.trayLc}.\nDeleting removes this produced stock from Inventory and reverses the packing it consumed. If goods are already dispatched, deletion will be refused with an explanation.'
            : running
                ? '${b['product_name']} · ${qtyInt(b['planned_cb'])} ${U.cb} planned (in progress).\nNo stock has been added yet — deleting is safe and permanent.'
                : '${b['product_name']} · ${qtyInt(b['planned_cb'])} ${U.cb} planned.\nThis planned batch will be deleted permanently. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogCtx).colorScheme.error),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await context.read<AuthController>().api.delete('/production/batches/${b['id']}');
      _reload();
      if (context.mounted) showOk(context, '${b['code']} deleted.');
    } catch (e) {
      if (context.mounted) showErr(context, e);
    }
  }

  Future<void> _complete(BuildContext context, Map<String, dynamic> b) async {
    final hasTray = CompanyProfile.usesTrays && (b['bottles_per_tray'] as num? ?? 0) > 0;
    final qtyCtl = TextEditingController(text: '${b['planned_cb']}');
    final trayCtl = TextEditingController(text: '0');
    var consume = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) => AlertDialog(
          title: Text('Complete ${b['code']}?'),
          content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${b['product_name']} · planned ${qtyInt(b['planned_cb'])} ${U.cb}'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: qtyCtl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Produced ${U.carton.toLowerCase()} (${U.cb})')))),
              if (hasTray) ...[
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: trayCtl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '${tr('Produced')} ${U.trayLc}'))),
              ],
            ]),
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: consume,
              onChanged: (v) => setLocal(() => consume = v ?? true),
              title: const Text('Deduct packing material as per BOM', style: TextStyle(fontSize: 13.5)),
              subtitle: Text(IndustryPack.current.consumeNote, style: const TextStyle(fontSize: 11.5)),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  final json = await dialogCtx.read<AuthController>().api.post('/production/batches/${b['id']}/complete', {
                    'producedCb': int.tryParse(qtyCtl.text) ?? 0,
                    if (hasTray) 'producedTrays': int.tryParse(trayCtl.text) ?? 0,
                    'consumePacking': consume,
                  });
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                  final warnings = ((json as Map)['packing'] as Map?)?['warnings'];
                  if (consume && warnings is List && warnings.isNotEmpty && context.mounted) {
                    showOk(context, 'Completed — packing note: ${warnings.join('; ')}');
                  }
                } catch (e) {
                  if (dialogCtx.mounted) showErr(dialogCtx, e);
                }
              },
              child: const Text('Complete & Stock'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      _reload();
      if (context.mounted) showOk(context, '${b['code']} completed — stock updated, watchers notified.');
    }
  }
}

class BatchFormDialog extends StatefulWidget {
  final Map<String, dynamic>? batch; // set → edit mode (planned batches only)
  const BatchFormDialog({super.key, this.batch});
  @override
  State<BatchFormDialog> createState() => _BatchFormDialogState();
}

class _BatchFormDialogState extends State<BatchFormDialog> {
  List<Map<String, dynamic>> products = [];
  int? productId;
  final cb = TextEditingController();
  final trays = TextEditingController();
  final code = TextEditingController();
  final remarks = TextEditingController();
  String autoCode = '';
  DateTime planned = DateTime.now(); // default: today (factory logs same-day)
  bool busy = false;
  // Planned-quantity unit (new batches only): 'cb' or 'tray'.
  String unit = 'cb';
  // Selected tray size from the fixed [_traySizes] list.
  String traySize = '610';

  bool get editing => widget.batch != null;
  bool get completed => widget.batch != null && widget.batch!['status'] == 'COMPLETED';
  bool get hasTray => editing && CompanyProfile.usesTrays && (widget.batch!['bottles_per_tray'] as num? ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    final b = widget.batch;
    if (b != null) {
      cb.text = completed ? '${b['produced_cb']}' : '${b['planned_cb']}';
      trays.text = '${b['produced_trays'] ?? 0}';
      code.text = b['code'] as String;
      remarks.text = b['remarks'] as String? ?? '';
      planned = DateTime.tryParse('${b['planned_date']}'.split(' ').first) ?? planned;
    }
    final api = context.read<AuthController>().api;
    api.get('/products').then((json) {
      setState(() {
        products = ((json as Map)['products'] as List).cast<Map<String, dynamic>>();
        productId = b != null
            ? b['product_id'] as int
            : (products.isNotEmpty ? products.first['id'] as int : null);
      });
    }).catchError((e) { if (mounted) showErr(context, e); });
    if (b == null) {
      api.get('/production/next-code').then((json) {
        setState(() => autoCode = '${(json as Map)['nextCode']}');
      }).catchError((_) {});
    }
  }

  String get _plannedYmd => '${planned.year}-${planned.month.toString().padLeft(2, '0')}-${planned.day.toString().padLeft(2, '0')}';

  Map<String, dynamic>? get _selProduct {
    for (final p in products) {
      if (p['id'] == productId) return p;
    }
    return null;
  }

  /// Live trays→CB math + validation, shown under the quantity field in tray
  /// mode. Derived entirely from the product master's packing spec
  /// (bottles per tray / per CB / kg per CB) — no hidden constants.
  Widget _trayPlanHint() {
    final p = _selProduct;
    final n = int.tryParse(cb.text) ?? 0;
    final bpt = (p?['bottles_per_tray'] as num? ?? 0).toDouble();
    final bpc = (p?['bottles_per_cb'] as num? ?? 0).toDouble();
    final wpc = (p?['weight_per_cb'] as num? ?? 0).toDouble();
    final base = TextStyle(fontSize: 11.5);
    if (bpt <= 0 || bpc <= 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          tr('This product has no tray packing (bottles per tray = 0). Set it in Products, or plan in CB.'),
          style: base.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    final lines = <Text>[];
    if (n <= 0) {
      lines.add(Text('Enter the number of ${U.trayLc} — the ${U.cb.toLowerCase()} equivalent shows here.', style: base.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)));
    } else {
      final cbEq = (n * bpt / bpc).ceil();
      var t = '$n ${U.trayLc} ($traySize) × $bpt ${U.piece} ÷ $bpc/${U.cb.toLowerCase()} = $cbEq ${U.cb}';
      if (wpc > 0) t += ' (~${qty(cbEq * wpc)} kg)';
      lines.add(Text(t, style: base.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)));
      final ps = _productSize(p!['name'] as String);
      if (ps != null && ps != traySize) {
        lines.add(Text('Heads-up: this product looks like size $ps, but tray $traySize is selected.', style: base.copyWith(color: const Color(0xFFD98200))));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
    );
  }

  /// Size embedded in a product name — "White Vinegar 610ml" → '610',
  /// "Dark Soya 1 Ltr" → '1.0', "Vinegar 1000ml" → '1.0'. null when absent.
  static String? _productSize(String name) {
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*(ml|gm|ltr|litre|litres|l)\b', caseSensitive: false).firstMatch(name);
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    if (v == null) return null;
    if (m.group(2)!.toLowerCase().startsWith('l')) {
      final liters = v >= 100 ? v / 1000 : v; // 1000ml → 1.0 L
      return liters.toStringAsFixed(1);
    }
    return v == v.roundToDouble() ? v.round().toString() : v.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(U.ize(editing ? 'Edit Batch ${widget.batch!['code']}' : 'Plan Production Batch')),
      content: SizedBox(
        width: 440,
        child: products.isEmpty
            ? const SizedBox(height: 90, child: Center(child: CircularProgressIndicator()))
            // Scrollable: on phones (adjustPan + frozen insets) a tall dialog
            // could overlap its own buttons — scrolling keeps fields inside.
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: U.ize('Batch code'),
                    hintText: autoCode.isEmpty ? 'Leave blank for auto code' : 'Leave blank for auto ($autoCode)',
                    helperText: editing
                        ? 'Same code is allowed again on a different date'
                        : (autoCode.isEmpty ? 'You may type your own code, e.g. SS-740-A' : 'Auto code would be $autoCode — or type your own, e.g. SS-740-A'),
                  ),
                ),
                const SizedBox(height: 12),
                if (completed)
                  InputDecorator(
                    decoration: InputDecoration(labelText: tr('Product')),
                    child: Text('${widget.batch!['product_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  )
                else
                  DropdownButtonFormField<int>(
                    key: ValueKey('prod-$productId'),
                    initialValue: productId,
                    decoration: InputDecoration(labelText: tr('Product *'), suffixIcon: ScanPickButton(rows: products, onPicked: (p) => setState(() => productId = p['id'] as int))),
                    isExpanded: true,
                    items: [for (final p in products) DropdownMenuItem(value: p['id'] as int, child: Text(ItemCode.pick(p), overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => productId = v),
                  ),
                const SizedBox(height: 12),
                if (!editing) ...[
                  // Plan in CB or in Trays (fixed sizes 610 / 740 / 1.0 / 1.3).
                  Row(children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: unit,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: tr('Planned in *')),
                        items: [
                          DropdownMenuItem(value: 'cb', child: Text(U.cb)),
                          if (CompanyProfile.usesTrays) DropdownMenuItem(value: 'tray', child: Text(U.trayLc)),
                        ],
                        onChanged: (v) => setState(() => unit = v ?? 'cb'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: cb,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: unit == 'tray' ? tr('Planned quantity (Trays) *') : 'Planned quantity (${U.cb}) *'),
                      ),
                    ),
                    if (unit == 'tray') ...[
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: traySize,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: tr('Tray size')),
                          items: [for (final s in _traySizes) DropdownMenuItem(value: s, child: Text(s))],
                          onChanged: (v) => setState(() => traySize = v ?? '610'),
                        ),
                      ),
                    ],
                  ]),
                  if (unit == 'tray') _trayPlanHint(),
                ] else
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: cb,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: completed ? 'Produced ${U.carton.toLowerCase()} (${U.cb}) *' : 'Planned quantity (${U.cb}) *'),
                      ),
                    ),
                    if (completed && hasTray) ...[
                      const SizedBox(width: 12),
                      Expanded(child: TextField(controller: trays, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '${tr('Produced')} ${U.trayLc}'))),
                    ],
                  ]),
                if (completed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Changing produced quantities moves finished-goods stock by the difference.',
                          style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                  ),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: planned, firstDate: DateTime(DateTime.now().year, DateTime.now().month - 1, 1), lastDate: DateTime.now().add(const Duration(days: 365)));
                        if (d != null) setState(() => planned = d);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(labelText: tr('Planned date *')),
                        child: Text(fmtDateWithDay(_plannedYmd)),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(controller: remarks, decoration: InputDecoration(labelText: tr('Remarks (optional)'))),
              ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    // Tray plan → the server's plannedCb via the product's
                    // packing spec (trays × bottles/tray ÷ bottles/CB, ceil).
                    int plannedCb = int.tryParse(cb.text) ?? 0;
                    if (!completed && unit == 'tray') {
                      final p = _selProduct;
                      final bpt = (p?['bottles_per_tray'] as num? ?? 0).toDouble();
                      final bpc = (p?['bottles_per_cb'] as num? ?? 0).toDouble();
                      if (bpt <= 0 || bpc <= 0) {
                        showErr(context, tr('Set tray packing on the product first (Products → edit → bottles per tray), or plan in CB.'));
                        return;
                      }
                      plannedCb = (plannedCb * bpt / bpc).ceil();
                    }
                    final body = completed
                        ? {
                            'code': code.text.trim(),
                            'remarks': remarks.text.trim(),
                            'plannedDate': _plannedYmd,
                            'producedCb': int.tryParse(cb.text) ?? 0,
                            'producedTrays': hasTray ? (int.tryParse(trays.text) ?? 0) : 0,
                          }
                        : {
                            'code': code.text.trim(),
                            'productId': productId,
                            'plannedCb': plannedCb,
                            'plannedDate': _plannedYmd,
                            'remarks': remarks.text.trim(),
                          };
                    if (editing) {
                      await context.read<AuthController>().api.put('/production/batches/${widget.batch!['id']}', body);
                    } else {
                      await context.read<AuthController>().api.post('/production/batches', body);
                    }
                    if (mounted) Navigator.pop(context, true);
                  } catch (e) {
                    if (mounted) showErr(context, e);
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? 'Saving…' : (editing ? 'Save Changes' : U.ize('Create Batch'))),
        ),
      ],
    );
  }
}
