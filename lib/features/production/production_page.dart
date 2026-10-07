import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/industry_pack.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/item_code.dart';
import '../../core/theme.dart';
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
  String _query = '';
  int? _expandedBatchId;
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
        final visibleRows = _query.trim().isEmpty
            ? rows
            : rows.where((b) {
                final haystack = '${b['code'] ?? ''} ${b['product_name'] ?? ''} ${b['item_code'] ?? ''}'.toLowerCase();
                return haystack.contains(_query.trim().toLowerCase());
              }).toList();
        return ListView(padding: const EdgeInsets.all(20), children: [
          _ProductionHealthCard(rows: rows),
          const SizedBox(height: 14),
          _ProductionMetrics(rows: rows),
          const SizedBox(height: 16),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in ['', 'PLANNED', 'IN_PROGRESS', 'COMPLETED'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.isEmpty ? tr('All') : tr(s.replaceAll('_', ' ').toLowerCase())),
                      selected: _status == s,
                      onSelected: (_) => setState(() { _status = s; _future = _load(); }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (auth.can('production.manage'))
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final saved = await showFastDialog<bool>(context, (_) => const BatchFormDialog());
                  if (saved == true) _reload();
                },
                icon: const Icon(Icons.add_rounded),
                label: Text(U.ize(tr('New Batch'))),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: U.ize('Search batch or product'),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => setState(() => _query = '')),
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: U.ize('Batch Register'),
            child: visibleRows.isEmpty
                ? EmptyState(U.ize(_query.trim().isEmpty ? 'No batches yet' : 'No matching batches'))
                : Column(
                    children: [
                      for (var i = 0; i < visibleRows.length; i++)
                        _ProductionBatchCard(
                          batch: visibleRows[i],
                          expanded: _expandedBatchId == visibleRows[i]['id'] || (_expandedBatchId == null && i == 0),
                          canManage: auth.can('production.manage'),
                          canExecute: canExecute,
                          onToggle: () {
                            final id = visibleRows[i]['id'] as int;
                            final expanded = _expandedBatchId == id || (_expandedBatchId == null && i == 0);
                            setState(() => _expandedBatchId = expanded ? -1 : id);
                          },
                          onView: () async {
                            await context.push('/production/batches/${visibleRows[i]['id']}');
                            _reload();
                          },
                          onEdit: () async {
                            final saved = await showFastDialog<bool>(context, (_) => BatchFormDialog(batch: visibleRows[i]));
                            if (saved == true) _reload();
                          },
                          onDelete: () => _delete(context, visibleRows[i]),
                          onStart: () => _start(context, visibleRows[i]),
                          onComplete: () => _complete(context, visibleRows[i]),
                        ),
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

int _productionInt(Object? value) {
  if (value is num) return value.round();
  return int.tryParse('${value ?? ''}') ?? 0;
}

num _productionNum(Object? value) {
  if (value is num) return value;
  return num.tryParse('${value ?? ''}') ?? 0;
}

class _ProductionHealthCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _ProductionHealthCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    final planned = rows.fold<int>(0, (sum, row) => sum + _productionInt(row['planned_cb']));
    final inProgress = rows.where((row) => '${row['status']}'.toUpperCase() == 'IN_PROGRESS').length;
    final completed = rows.where((row) => '${row['status']}'.toUpperCase() == 'COMPLETED').length;
    final plannedCount = rows.where((row) => '${row['status']}'.toUpperCase() == 'PLANNED').length;

    Widget status(String value, String label) => Expanded(
          child: Column(children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
      decoration: BoxDecoration(
        gradient: AppBrand.gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppBrand.blue.withValues(alpha: .18), blurRadius: 14, offset: const Offset(0, 7))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Production Health', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(qtyInt(planned), style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, height: 1)),
          const SizedBox(width: 8),
          Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('${U.cb} planned', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 7),
        Text('${rows.length} production batches', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 14),
        Row(children: [
          status('$plannedCount', 'Planned'),
          status('$inProgress', 'In Progress'),
          status('$completed', 'Completed'),
        ]),
      ]),
    );
  }
}

class _ProductionMetrics extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _ProductionMetrics({required this.rows});

  @override
  Widget build(BuildContext context) {
    final planned = rows.fold<int>(0, (sum, row) => sum + _productionInt(row['planned_cb']));
    final produced = rows.fold<int>(0, (sum, row) => sum + _productionInt(row['produced_cb']));
    final inProgress = rows.where((row) => '${row['status']}'.toUpperCase() == 'IN_PROGRESS').length;
    final completed = rows.where((row) => '${row['status']}'.toUpperCase() == 'COMPLETED').length;
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900 ? 4 : 2;
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: columns == 2 ? 2.1 : 2.15,
        children: [
          _ProductionMetric(label: 'Planned ${U.cb}', value: qtyInt(planned), icon: Icons.event_note_outlined, tint: AppColors.blue),
          _ProductionMetric(label: 'Produced ${U.cb}', value: qtyInt(produced), icon: Icons.factory_outlined, tint: AppColors.teal),
          _ProductionMetric(label: 'In progress', value: '$inProgress', icon: Icons.pending_actions_rounded, tint: AppColors.orange),
          _ProductionMetric(label: 'Completed', value: '$completed', icon: Icons.check_circle_outline_rounded, tint: AppColors.green),
        ],
      );
    });
  }
}

class _ProductionMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  const _ProductionMetric({required this.label, required this.value, required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: .06), blurRadius: 7, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 18, color: tint), const Spacer(), Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: tint))]),
        const Spacer(),
        Text(value, style: TextStyle(color: scheme.onSurface, fontSize: 20, fontWeight: FontWeight.w800)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _ProductionBatchCard extends StatelessWidget {
  final Map<String, dynamic> batch;
  final bool expanded;
  final bool canManage;
  final bool canExecute;
  final VoidCallback onToggle;
  final Future<void> Function() onView;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;
  final Future<void> Function() onStart;
  final Future<void> Function() onComplete;

  const _ProductionBatchCard({
    required this.batch,
    required this.expanded,
    required this.canManage,
    required this.canExecute,
    required this.onToggle,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onStart,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = '${batch['status'] ?? ''}';
    final product = '${batch['product_name'] ?? 'Product'}';
    final batchCode = '${batch['code'] ?? '—'}';
    final planned = _productionNum(batch['planned_cb']);
    final weightPerCb = _productionNum(batch['weight_per_cb']);
    final gross = planned * weightPerCb;
    final hasTray = CompanyProfile.usesTrays && (_productionNum(batch['bottles_per_tray']) > 0 || _productionNum(batch['produced_trays']) > 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: .06), blurRadius: 7, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: onToggle,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 8, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 4, height: 46, decoration: BoxDecoration(gradient: AppBrand.gradient, borderRadius: BorderRadius.circular(8))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$product Batch', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('Batch Code: $batchCode', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
              ])),
              IconButton(tooltip: expanded ? 'Collapse' : 'Expand', onPressed: onToggle, icon: Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 14, 12),
          child: Row(children: [
            Expanded(child: Text('Mfg. Date: ${fmtDate(batch['planned_date'])}', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
            if (status.isNotEmpty) StatusChip(status),
          ]),
        ),
        if (expanded) ...[
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 13, 14, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _quantity('Planned ${U.cb}', qtyInt(batch['planned_cb']), scheme)),
              Expanded(child: _quantity('Produced ${U.cb}', qtyInt(batch['produced_cb']), scheme)),
              if (hasTray) Expanded(child: _quantity(U.tray, qtyInt(batch['produced_trays']), scheme)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 2, 14, 4),
            child: Text('Gross planned: ${qty(gross)} kg', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 13),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (canExecute && status == 'PLANNED')
                FilledButton.icon(onPressed: onStart, icon: const Icon(Icons.play_arrow_rounded, size: 17), label: Text(tr('Start'))),
              if (canExecute && status == 'IN_PROGRESS')
                FilledButton.icon(onPressed: onComplete, icon: const Icon(Icons.check_circle_outline_rounded, size: 17), label: Text(tr('Complete'))),
              OutlinedButton.icon(onPressed: onView, icon: const Icon(Icons.visibility_outlined, size: 17), label: Text(tr('View'))),
              if (canManage)
                PopupMenuButton<String>(
                  tooltip: U.ize('More actions'),
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text(U.ize('Edit batch'))),
                    PopupMenuItem(value: 'delete', child: Text(U.ize('Delete batch'))),
                  ],
                  child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.more_horiz_rounded)),
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _quantity(String label, String value, ColorScheme scheme) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontSize: 18, color: scheme.onSurface, fontWeight: FontWeight.w800)),
      ]);
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
      // Batches planned in trays (server: plan_unit/planned_trays) reopen in
      // the same unit, with the quantity shown in that unit.
      final storedUnit = b['plan_unit']?.toString() ?? 'cb';
      if (!completed && storedUnit == 'tray') unit = 'tray';
      cb.text = completed
          ? '${b['produced_cb']}'
          : (unit == 'tray' ? '${b['planned_trays'] ?? 0}' : '${b['planned_cb']}');
      trays.text = '${b['produced_trays'] ?? 0}';
      code.text = b['code'] as String;
      remarks.text = b['remarks'] as String? ?? '';
      planned = DateTime.tryParse('${b['planned_date']}'.split(' ').first) ?? planned;
      final ps = _canonicalTraySize(_productSize(b['product_name']?.toString() ?? ''));
      if (ps != null) traySize = ps;
    }
    final api = context.read<AuthController>().api;
    api.get('/products').then((json) {
      setState(() {
        products = ((json as Map)['products'] as List)
            .cast<Map<String, dynamic>>()
            .where((p) => (p['active'] as num? ?? 1) != 0)
            .toList();
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

  /// The selected product's name (product master once loaded, else the
  /// batch's stored product_name in edit mode).
  String get _selName => _selProduct?['name']?.toString() ?? widget.batch?['product_name']?.toString() ?? '';

  /// Maps a raw product size ('610', '1', '1.3', '740'…) onto the canonical
  /// tray-size list by NUMBER — '1' and '1.0' are the same tray.
  static String? _canonicalTraySize(String? raw) {
    if (raw == null) return null;
    final v = double.tryParse(raw);
    if (v == null) return null;
    for (final t in _traySizes) {
      if (double.tryParse(t) == v) return t;
    }
    return null;
  }

  /// Tray planning exists only for the four tray sizes — Soya 740 / 1.3 and
  /// Vinegar 610 / 1.0 (size is the one embedded in the product name).
  bool get _trayEligible => _canonicalTraySize(_productSize(_selName)) != null;

  /// The tray size follows the product (Soya Sauce 1.3kg → '1.3'); picking a
  /// product without a tray size silently falls back to CB planning.
  void _followTraySize() {
    final c = _canonicalTraySize(_productSize(_selName));
    if (c == null) {
      if (unit == 'tray') unit = 'cb';
    } else {
      traySize = c;
    }
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
      final ps = _canonicalTraySize(_productSize(p!['name'] as String));
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
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*(ml|gm|kg|ltr|litre|litres|l)\b', caseSensitive: false).firstMatch(name);
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    if (v == null) return null;
    if (m.group(2)!.toLowerCase().startsWith('l')) {
      final liters = v >= 100 ? v / 1000 : v;
      return liters.toStringAsFixed(1);
    }
    if (m.group(2)!.toLowerCase() == 'ml' && v >= 1000 && v.truncateToDouble() % 1000 == 0) {
      return (v / 1000).toStringAsFixed(1); // 1000ml → 1.0 L
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
            // Scrollable: on phones a tall dialog can overlap its own
            // buttons — scrolling keeps fields inside while the IME resizes the window.
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
                    onChanged: (v) => setState(() {
                          productId = v;
                          _followTraySize();
                        }),
                  ),
                const SizedBox(height: 12),
                if (!completed) ...[
                  // Plan in CB or in Trays (fixed sizes 610 / 740 / 1.0 / 1.3).
                  // Tray is offered only for the tray-size products (Soya
                  // 740 / 1.3, Vinegar 610 / 1.0) — see [_trayEligible].
                  Row(children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: unit,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: tr('Planned in *')),
                        items: [
                          DropdownMenuItem(value: 'cb', child: Text(U.cb)),
                          if (CompanyProfile.usesTrays && _trayEligible) DropdownMenuItem(value: 'tray', child: Text(U.trayLc)),
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
                            // Unit the quantity was entered in (server: same
                            // code+product+date is allowed once per unit).
                            'plannedUnit': unit,
                            'plannedTrays': unit == 'tray' ? (int.tryParse(cb.text) ?? 0) : 0,
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
