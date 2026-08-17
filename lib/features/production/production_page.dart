import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

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
                label: Text(s.isEmpty ? 'All' : s.replaceAll('_', ' ').toLowerCase()),
                selected: _status == s,
                onSelected: (_) => setState(() { _status = s; _future = _load(); }),
              ),
            if (auth.can('production.manage'))
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilledButton.icon(
                  onPressed: () async {
                    final saved = await showDialog<bool>(context: context, builder: (_) => const BatchFormDialog());
                    if (saved == true) _reload();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(tr('New Batch')),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Production Batches',
            child: rows.isEmpty
                ? const EmptyState('No batches')
                : AppDataTable(
                    columns: ['Batch', 'Product', 'Planned ${U.cb}', 'Produced ${U.cb}', U.tray, 'Gross kg (planned)', 'Planned Date', 'Status', 'Actions'],
                    rows: [
                      for (final b in rows)
                        [
                          Text(b['code'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                          b['product_name'],
                          qtyInt(b['planned_cb']),
                          qtyInt(b['produced_cb']),
                          qtyInt(b['produced_trays'] ?? 0),
                          qty((b['planned_cb'] as num) * (b['weight_per_cb'] as num)),
                          fmtDate(b['planned_date']),
                          StatusChip(b['status'] as String),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: 'View batch',
                              icon: const Icon(Icons.visibility_outlined, size: 19),
                              onPressed: () async {
                                await context.push('/production/batches/${b['id']}');
                                _reload();
                              },
                            ),
                            if (auth.can('production.manage') && b['status'] != 'IN_PROGRESS')
                              IconButton(
                                tooltip: 'Edit batch',
                                icon: const Icon(Icons.edit_outlined, size: 19),
                                onPressed: () async {
                                  final saved = await showDialog<bool>(context: context, builder: (_) => BatchFormDialog(batch: b));
                                  if (saved == true) _reload();
                                },
                              ),
                            if (auth.can('production.manage'))
                              IconButton(
                                tooltip: 'Delete batch',
                                icon: Icon(Icons.delete_outline_rounded, size: 19, color: Theme.of(context).colorScheme.error),
                                onPressed: () => _delete(context, b),
                              ),
                            if (canExecute && b['status'] == 'PLANNED')
                              TextButton.icon(
                                onPressed: () => _start(context, b),
                                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                label: const Text('Start'),
                              ),
                            if (canExecute && b['status'] == 'IN_PROGRESS')
                              TextButton.icon(
                                onPressed: () => _complete(context, b),
                                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                label: const Text('Complete'),
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
    final hasTray = (b['bottles_per_tray'] as num? ?? 0) > 0;
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
              Expanded(child: TextField(controller: qtyCtl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Produced ${U.carton.toLowerCase()} (${U.cb})'))),
              if (hasTray) ...[
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: trayCtl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Produced trays'))),
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
              subtitle: const Text('Bottles, caps, labels, cartons & trays are consumed automatically', style: TextStyle(fontSize: 11.5)),
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

  bool get editing => widget.batch != null;
  bool get completed => widget.batch != null && widget.batch!['status'] == 'COMPLETED';
  bool get hasTray => editing && (widget.batch!['bottles_per_tray'] as num? ?? 0) > 0;

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(editing ? 'Edit Batch ${widget.batch!['code']}' : 'Plan Production Batch'),
      content: SizedBox(
        width: 440,
        child: products.isEmpty
            ? const SizedBox(height: 90, child: Center(child: CircularProgressIndicator()))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Batch code',
                    hintText: autoCode.isEmpty ? 'Leave blank for auto code' : 'Leave blank for auto ($autoCode)',
                    helperText: editing
                        ? 'Same code is allowed again on a different date'
                        : (autoCode.isEmpty ? 'You may type your own code, e.g. SS-740-A' : 'Auto code would be $autoCode — or type your own, e.g. SS-740-A'),
                  ),
                ),
                const SizedBox(height: 12),
                if (completed)
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Product'),
                    child: Text('${widget.batch!['product_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  )
                else
                  DropdownButtonFormField<int>(
                    initialValue: productId,
                    decoration: const InputDecoration(labelText: 'Product *'),
                    items: [for (final p in products) DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String))],
                    onChanged: (v) => setState(() => productId = v),
                  ),
                const SizedBox(height: 12),
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
                    Expanded(child: TextField(controller: trays, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Produced trays'))),
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
                        decoration: const InputDecoration(labelText: 'Planned date *'),
                        child: Text(fmtDateWithDay(_plannedYmd)),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(controller: remarks, decoration: const InputDecoration(labelText: 'Remarks (optional)')),
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
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
                            'plannedCb': int.tryParse(cb.text) ?? 0,
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
          child: Text(busy ? 'Saving…' : (editing ? 'Save Changes' : 'Create Batch')),
        ),
      ],
    );
  }
}
