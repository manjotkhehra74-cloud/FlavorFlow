import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/industry_pack.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/item_code.dart';
import '../../core/platform_support.dart';
import '../../state/auth.dart';
import '../../ui/scan_page.dart';
import '../../core/offline_queue.dart';
import '../../ui/widgets.dart';
import '../../ui/windows_widgets.dart';
import '../drums/drum_dispatch_page.dart';
import 'batch_code.dart';
import 'destination_field.dart';

/// Destinations that older builds hard-coded for the original sauce factory
/// (purged once from other companies' phones on upgrade — see loadSavedDests).
const kLegacyDestinations = ['NEEMRANA', 'MATIALA'];

/// Dedicated Dispatch Module: entry · history · reports.
class DispatchPage extends StatefulWidget {
  final String? tab;
  const DispatchPage({super.key, this.tab});
  @override
  State<DispatchPage> createState() => _DispatchPageState();
}

class _DispatchPageState extends State<DispatchPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    if (widget.tab == 'drums') _tab.index = 1;
    if (widget.tab == 'history') _tab.index = 2;
    if (widget.tab == 'reports') _tab.index = 3;
    if (widget.tab == 'trucks') _tab.index = 4;
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthController>().can('dispatch.manage');
    final entryTitle = canManage ? 'Dispatch Entry' : 'Dispatch Entry (view only)';
    final tabs = <WindowsModuleTab>[
      WindowsModuleTab(entryTitle, Icons.local_shipping_outlined),
      const WindowsModuleTab('Drum Dispatch', Icons.inventory_2_outlined),
      const WindowsModuleTab('Dispatch History', Icons.history_rounded),
      const WindowsModuleTab('Reports', Icons.bar_chart_rounded),
      const WindowsModuleTab('Trucks', Icons.local_shipping_outlined),
    ];
    final content = TabBarView(controller: _tab, children: [
      _EntryTab(readOnly: !canManage),
      const DrumDispatchPage(),
      const _HistoryTab(),
      const _ReportsTab(),
      _TrucksTab(readOnly: !canManage),
    ]);
    if (isWindowsPlatform) {
      return AnimatedBuilder(
        animation: _tab,
        builder: (context, _) => WindowsModuleWorkspace(
          title: 'Dispatch',
          subtitle: 'CB and drum dispatch, history and transport reports',
          tabs: tabs,
          selectedIndex: _tab.index,
          onSelect: _tab.animateTo,
          content: content,
        ),
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: tr(entryTitle)),
              Tab(text: tr('Drum Dispatch')),
              Tab(text: tr('Dispatch History')),
              Tab(text: tr('Reports')),
              Tab(text: tr('Trucks')),
            ],
          ),
        ),
      ),
      Expanded(child: content),
    ]);
  }
}

/* ------------------------- shared: product line editor ------------------------- */

class _Line {
  int? productId;
  int? batchId;
  final cartons = TextEditingController();
  final trays = TextEditingController();
  final batchCode = TextEditingController();
  void dispose() { cartons.dispose(); trays.dispose(); batchCode.dispose(); }
}

Map<String, dynamic> _prod(List<Map<String, dynamic>> products, int? id) =>
    products.firstWhere((p) => p['id'] == id, orElse: () => {'bottles_per_cb': 0, 'bottles_per_tray': 0});

/// Batch dates are deliberately formatted from the date string rather than a
/// timezone-aware DateTime. A batch made late at night must still show the
/// factory date on every device (and the dispatch screen only needs dd/mm).
String _shortBatchDate(Object? raw) {
  final value = '${raw ?? ''}'.trim().split(RegExp(r'[ T]')).first;
  final m = RegExp(r'^(?:\d{4}-)?(\d{1,2})-(\d{1,2})$').firstMatch(value);
  if (m == null) return value.isEmpty ? '—' : value;
  return '${m.group(2)!.padLeft(2, '0')}/${m.group(1)!.padLeft(2, '0')}';
}

String _batchAvailability(Map<String, dynamic> batch) {
  final cb = qtyInt(batch['remaining_cb'] ?? batch['remainingCb'] ?? 0);
  final trays = qtyInt(batch['remaining_trays'] ?? batch['remainingTrays'] ?? 0);
  if (trays != '0') return '$cb ${U.cb} · $trays ${U.trayLc}';
  return '$cb ${U.cb}';
}

int _batchNumber(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

class _LinesEditor extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final List<_Line> lines;
  final VoidCallback onAdd, onChanged, onBatchChanged;
  final void Function(int) onRemove;
  /// Product changes clear the previous batch and load the new product's
  /// available batches. This avoids dispatching a code belonging to another
  /// product after the operator changes the product dropdown.
  final void Function(int i, int productId) onProductChanged;
  final bool showBatch;
  final Map<int, List<Map<String, dynamic>>> batchOptions;
  final Set<int> batchLoading;
  final Set<int> batchLoadFailed;
  final void Function(int productId) onRetryBatches;
  const _LinesEditor({
    required this.products,
    required this.lines,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
    required this.onBatchChanged,
    required this.onProductChanged,
    this.showBatch = false,
    this.batchOptions = const {},
    this.batchLoading = const {},
    this.batchLoadFailed = const {},
    required this.onRetryBatches,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < lines.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(children: [
            // Row 1: full-width product selector so long names are never cut off.
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('dl-$i-${lines[i].productId}'),
                  initialValue: lines[i].productId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Product ${i + 1} *'), suffixIcon: ScanPickButton(rows: products, onPicked: (p) => onProductChanged(i, p['id'] as int))),
                  items: [for (final p in products) DropdownMenuItem(value: p['id'] as int, child: Text(ItemCode.pick(p), overflow: TextOverflow.ellipsis))],
                  onChanged: (v) {
                    if (v != null) onProductChanged(i, v);
                  },
                ),
              ),
              IconButton(
                tooltip: 'Remove line',
                onPressed: lines.length <= 1 ? null : () => onRemove(i),
                icon: Icon(Icons.remove_circle_outline_rounded, color: lines.length <= 1 ? scheme.outline : scheme.error),
              ),
            ]),
            // Keep a real vertical gap between stacked fields on phones. The
            // calculator has no batch selector, so its quantity field needs
            // the same separation that the entry tab gives the batch field.
            if (!showBatch) const SizedBox(height: 12),
            if (showBatch) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _BatchField(
                  line: lines[i],
                  batches: batchOptions[lines[i].productId] ?? const [],
                  loading: lines[i].productId != null && batchLoading.contains(lines[i].productId),
                  loadFailed: lines[i].productId != null && batchLoadFailed.contains(lines[i].productId),
                  onRetry: () {
                    final productId = lines[i].productId;
                    if (productId != null) onRetryBatches(productId);
                  },
                  onChanged: (value) {
                    final code = normalizeDispatchBatchCode(value?['code'] ?? value?['batch_code'] ?? value?['batchCode']);
                    if (lines[i].batchCode.text != code) lines[i].batchCode.text = code;
                    lines[i].batchId = dispatchBatchId(value);
                    onBatchChanged();
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
            // CB and trays are entered on their own row below the batch.
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    controller: lines[i].cartons,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: U.carton, helperText: lines[i].productId == null ? null : '${_prod(products, lines[i].productId)['bottles_per_cb']}/${U.cb}', helperMaxLines: 1),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                if (CompanyProfile.usesTrays && (_prod(products, lines[i].productId)['bottles_per_tray'] as num? ?? 0) > 0) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: lines[i].trays,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: U.tray, helperText: lines[i].productId == null ? null : '${_prod(products, lines[i].productId)['bottles_per_tray']}/${U.trayLc}', helperMaxLines: 1),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded, size: 18), label: Text(tr('Add product line'))),
    ]);
  }
}

/// Batch selector for a dispatch line. The server supplies only COMPLETED
/// batches with remaining stock; each option keeps the short manufacturing date
/// visible so an operator can distinguish old stock from a newer batch.
class _BatchField extends StatelessWidget {
  final _Line line;
  final List<Map<String, dynamic>> batches;
  final bool loading;
  final bool loadFailed;
  final VoidCallback onRetry;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  const _BatchField({
    required this.line,
    required this.batches,
    required this.loading,
    required this.loadFailed,
    required this.onRetry,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedCode = normalizeDispatchBatchCode(line.batchCode.text);
    Map<String, dynamic>? selectedById;
    if (line.batchId != null) {
      for (final batch in batches) {
        if (dispatchBatchId(batch) == line.batchId) {
          selectedById = batch;
          break;
        }
      }
    }
    final selectedBatch = selectedById ?? dispatchBatchByCode(batches, selectedCode);
    if (loading) {
      return TextField(
        readOnly: true,
        decoration: InputDecoration(
          labelText: U.ize('Batch code · date · available stock'),
          hintText: 'Loading batches…',
          suffixIcon: const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      );
    }
    final codeFormatters = <TextInputFormatter>[
      TextInputFormatter.withFunction(
        (oldValue, newValue) => newValue.copyWith(text: newValue.text.toUpperCase()),
      ),
    ];
    Widget cameraButton() => IconButton(
          tooltip: U.ize('Scan batch code'),
          icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
          onPressed: () async {
            final value = await ScanPage.scan(context, title: U.ize('Scan batch code'));
            if (value == null) return;
            final code = normalizeDispatchBatchCode(value);
            onChanged(
              code.isEmpty ? null : (dispatchBatchByCode(batches, code) ?? {'code': code}),
            );
          },
        );
    Widget? suffixIcon() {
      if (!isPhonePlatform && !loadFailed) return null;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        if (loadFailed)
          IconButton(
            tooltip: U.ize('Retry loading batches'),
            icon: const Icon(Icons.refresh_rounded, size: 19),
            onPressed: onRetry,
          ),
        if (isPhonePlatform) cameraButton(),
      ]);
    }

    if (batches.isEmpty) {
      // Opening stock can legitimately have no production batch list. If both
      // batch endpoints failed, make that explicit and require a manual code.
      return TextField(
        controller: line.batchCode,
        inputFormatters: codeFormatters,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: U.ize('Batch code · date · available stock'),
          hintText: loadFailed ? 'Batch list unavailable — enter code' : 'No batch list — enter code if known',
          helperText: loadFailed
              ? U.ize('Could not load available batches. Enter the exact code or retry before dispatch.')
              : isDesktopPlatform
                  ? 'Type a code or scan it with a USB barcode scanner.'
                  : U.ize('Stock deducts batch-wise'),
          helperMaxLines: 2,
          suffixIcon: suffixIcon(),
        ),
        onChanged: (_) {
          final code = normalizeDispatchBatchCode(line.batchCode.text);
          onChanged(code.isEmpty ? null : {'code': code});
        },
      );
    }
    final optionsKey = batches
        .map((b) => '${dispatchBatchId(b)}:${b['code'] ?? b['batch_code']}:${b['planned_date'] ?? b['plannedDate']}')
        .join('|');
    final dropdown = DropdownButtonFormField<int>(
      key: ValueKey('batch-${line.productId}-${dispatchBatchId(selectedBatch) ?? 'none'}-$optionsKey'),
      initialValue: dispatchBatchId(selectedBatch),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: U.ize('Batch code · date · available stock'),
        helperText: selectedBatch == null
            ? selectedCode.isEmpty
                ? U.ize('Select batch to deduct stock')
                : 'No available batch exactly matches "$selectedCode".'
            : 'Available: ${_batchAvailability(selectedBatch)}',
        helperMaxLines: 1,
        suffixIcon: isPhonePlatform ? cameraButton() : null,
      ),
      items: [
        for (final batch in batches.where((b) => dispatchBatchId(b) != null))
          DropdownMenuItem<int>(
            value: dispatchBatchId(batch)!,
            child: Text(
              '${batch['code'] ?? batch['batch_code'] ?? batch['batchCode']} · ${_shortBatchDate(batch['planned_date'] ?? batch['plannedDate'])} · ${_batchAvailability(batch)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (id) => onChanged(id == null ? null : batches.firstWhere((b) => dispatchBatchId(b) == id)),
    );
    if (!isDesktopPlatform) return dropdown;

    Map<String, dynamic>? matchingBatch(String code) => dispatchBatchByCode(batches, code);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      dropdown,
      const SizedBox(height: 8),
      TextField(
        controller: line.batchCode,
        inputFormatters: codeFormatters,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: U.ize('Enter batch code'),
          hintText: 'Type or scan with a USB barcode scanner',
          helperText: line.batchCode.text.trim().isEmpty
              ? 'Use the dropdown or enter the exact code printed on the batch label.'
              : matchingBatch(line.batchCode.text) == null
                  ? 'No available batch exactly matches this code.'
                  : 'Available: ${_batchAvailability(matchingBatch(line.batchCode.text)!)}',
          helperMaxLines: 2,
        ),
        onChanged: (raw) {
          final code = normalizeDispatchBatchCode(raw);
          onChanged(code.isEmpty ? null : (matchingBatch(code) ?? {'code': code}));
        },
      ),
    ]);
  }
}

/// Shown in place of the product lines when the company has no finished
/// goods yet (fresh SaaS tenant) — tells them exactly what to do first.
class _NoProductsHint extends StatelessWidget {
  final VoidCallback onAdd;
  const _NoProductsHint({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.inventory_2_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('No products yet'), style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface))),
        ]),
        const SizedBox(height: 6),
        Text('Add your finished goods first (${IndustryPack.eg(IndustryPack.current.productExamples)}) with ${U.piece.toLowerCase()} per ${U.cb} and ${U.cb} weight — dispatch lines and weights are calculated from that.',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(onPressed: onAdd, icon: const Icon(Icons.add_rounded, size: 18), label: Text(tr('Add Product'))),
      ]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic> totals;
  final List<Map<String, dynamic>> lines;
  const _SummaryCard({required this.totals, required this.lines});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, fontWeight: strong ? FontWeight.w700 : FontWeight.w500))),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: strong ? 16 : 13.5, color: strong ? scheme.primary : null)),
          ]),
        );
    String lineText(Map<String, dynamic> l) {
      final parts = <String>['${qtyInt(l['cartons'])} ${U.cb}'];
      if ((l['trays'] as num? ?? 0) > 0) parts.add('${qtyInt(l['trays'])} ${U.trayLc}');
      return '${parts.join(' + ')} → ${qty(l['grossWeight'])} kg';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.scale_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Text('Loading Summary', style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary, fontSize: 14)),
        ]),
        const SizedBox(height: 10),
        if (lines.isNotEmpty) ...[
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(l['productName'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                Flexible(child: Text(lineText(l), textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant))),
              ]),
            ),
          const Divider(height: 18),
        ],
        row('${U.carton} weight', '${qty(totals['cartonWeight'])} kg'),
        if (CompanyProfile.usesTrays) row('${U.tray} weight', '${qty(totals['trayWeight'])} kg'),
        row('Total ${U.carton.toLowerCase()}', '${qtyInt(totals['totalCartons'])} ${U.cb}'),
        if (CompanyProfile.usesTrays) row('Total ${U.trayLc}', qtyInt(totals['totalTrays'])),
        row('Total ${U.piece.toLowerCase()}', qtyInt(totals['totalBottles'])),
        const Divider(height: 18),
        row('Gross loaded weight', '${qty(totals['grossWeight'])} kg', strong: true),
      ]),
    );
  }
}

mixin _CalcMixin<T extends StatefulWidget> on State<T> {
  List<Map<String, dynamic>> products = [];
  /// Available stock-bearing batches, keyed by product id. This is loaded
  /// lazily when a product is selected so a large product master does not
  /// make Dispatch fire dozens of requests on open.
  final Map<int, List<Map<String, dynamic>>> batchOptions = {};
  final Set<int> batchLoading = {};
  final Set<int> batchLoadFailed = {};
  final Map<int, int> _batchRequestVersions = {};
  /// true once /products answered — an empty master then shows a hint
  /// instead of spinning forever (new companies start with zero products).
  bool productsLoaded = false;
  final List<_Line> lines = [_Line()];
  Map<String, dynamic>? calc;
  Timer? _debounce;
  int _calcRequestVersion = 0;

  Future<void> loadProducts() async {
    try {
      final json = await context.read<AuthController>().api.get('/products');
      if (!mounted) return;
      setState(() {
        products = ((json as Map)['products'] as List)
            .cast<Map<String, dynamic>>()
            .where((p) => (p['active'] as num? ?? 1) != 0)
            .toList();
        productsLoaded = true;
        for (final l in lines) { l.productId ??= products.isNotEmpty ? products.first['id'] as int : null; }
      });
      for (final l in lines) {
        if (l.productId != null) loadBatches(l.productId!);
      }
      if (products.isNotEmpty) recalc();
    } catch (e) {
      if (mounted) { setState(() => productsLoaded = true); showErr(context, e); }
    }
  }

  List<Map<String, dynamic>> _batchRows(dynamic response) {
    if (response is! Map || response['batches'] is! List) return const [];
    return (response['batches'] as List)
        .whereType<Map>()
        .map((row) {
          final batch = row.cast<String, dynamic>();
          final code = batch['code'] ?? batch['batch_code'] ?? batch['batchCode'];
          return code == null ? batch : {...batch, 'code': code};
        })
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchBatchOptions(int productId) async {
    final api = context.read<AuthController>().api;
    List<Map<String, dynamic>>? dispatchRows;
    Object? dispatchError;
    try {
      dispatchRows = _batchRows(await api.get('/dispatch/batches?productId=$productId'));
      if (dispatchRows.isNotEmpty) return dispatchRows;
    } catch (e) {
      dispatchError = e;
    }

    // Some older factory servers do not expose the dispatch-specific batch
    // route (or return no rows for a product that does have completed stock).
    // Fall back to the production register and derive the remaining quantity.
    try {
      final completed = _batchRows(await api.get('/production/batches?status=COMPLETED'));
      final available = <Map<String, dynamic>>[];
      for (final batch in completed) {
        if ('${batch['status'] ?? ''}'.toUpperCase() != 'COMPLETED') continue;
        if (_batchNumber(batch['product_id'] ?? batch['productId']) != productId) continue;
        final code = normalizeDispatchBatchCode(batch['code']);
        if (code.isEmpty) continue;
        final remainingCb = _batchNumber(batch['produced_cb'] ?? batch['producedCb']) -
            _batchNumber(batch['used_cb'] ?? batch['usedCb']);
        final remainingTrays = _batchNumber(batch['produced_trays'] ?? batch['producedTrays']) -
            _batchNumber(batch['used_trays'] ?? batch['usedTrays']);
        if (remainingCb <= 0 && remainingTrays <= 0) continue;
        available.add({
          ...batch,
          'code': code,
          'remaining_cb': remainingCb > 0 ? remainingCb : 0,
          'remaining_trays': remainingTrays > 0 ? remainingTrays : 0,
        });
      }
      if (available.isNotEmpty || dispatchRows == null) return available;
      return dispatchRows;
    } catch (_) {
      // A successful empty dispatch response is still useful (e.g. this
      // product has opening/unassigned stock only). Only mark loading as failed
      // when neither endpoint could be read.
      if (dispatchRows != null) return dispatchRows;
      throw dispatchError ?? StateError('Could not load available batches.');
    }
  }

  Future<void> loadBatches(int productId, {bool refresh = false}) async {
    if (!refresh && (batchOptions.containsKey(productId) || batchLoading.contains(productId))) return;
    if (!mounted) return;
    final requestVersion = (_batchRequestVersions[productId] ?? 0) + 1;
    _batchRequestVersions[productId] = requestVersion;
    setState(() {
      batchLoading.add(productId);
      batchLoadFailed.remove(productId);
    });
    try {
      final rows = await _fetchBatchOptions(productId);
      if (!mounted || _batchRequestVersions[productId] != requestVersion) return;
      setState(() {
        batchOptions[productId] = rows;
        batchLoadFailed.remove(productId);
      });
    } catch (_) {
      if (!mounted || _batchRequestVersions[productId] != requestVersion) return;
      setState(() {
        batchOptions[productId] = const [];
        batchLoadFailed.add(productId);
      });
    } finally {
      if (mounted && _batchRequestVersions[productId] == requestVersion) {
        setState(() => batchLoading.remove(productId));
      }
    }
  }

  void selectProduct(int i, int productId) {
    if (i >= lines.length) return;
    setState(() {
      lines[i].productId = productId;
      lines[i].batchId = null;
      // Never carry a batch from the previous product into the new line.
      lines[i].batchCode.clear();
    });
    loadBatches(productId, refresh: true);
    recalcDebounced();
  }

  List<Map<String, dynamic>> items() => [
        for (final l in lines)
          {
            'productId': l.productId,
            'cartons': int.tryParse(l.cartons.text) ?? 0,
            'trays': int.tryParse(l.trays.text) ?? 0,
            if (normalizeDispatchBatchCode(l.batchCode.text).isNotEmpty)
              'batchCode': normalizeDispatchBatchCode(l.batchCode.text),
            if (l.batchId != null) 'batchId': l.batchId,
          },
      ];

  List<Map<String, dynamic>> nonZeroItems() =>
      items().where((l) => (l['cartons'] as int) > 0 || (l['trays'] as int) > 0).toList();

  void recalcDebounced() {
    _calcRequestVersion++; // invalidate an older calculation immediately
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), recalc);
  }

  Future<void> recalc() async {
    final requestVersion = ++_calcRequestVersion;
    final list = nonZeroItems();
    if (list.isEmpty || !mounted) {
      if (mounted && calc != null) setState(() => calc = null);
      return;
    }
    try {
      final json = await context.read<AuthController>().api.post('/dispatch/calculate', {'items': list});
      if (mounted && requestVersion == _calcRequestVersion) {
        setState(() => calc = (json as Map).cast<String, dynamic>());
      }
    } catch (_) {
      if (mounted && requestVersion == _calcRequestVersion) setState(() => calc = null);
    }
  }

  void addLine() {
    final line = _Line()..productId = products.isNotEmpty ? products.first['id'] as int : null;
    setState(() => lines.add(line));
    if (line.productId != null) loadBatches(line.productId!);
  }

  void removeLine(int i) {
    setState(() => lines.removeAt(i).dispose());
    recalcDebounced();
  }

  void disposeLines() {
    _debounce?.cancel();
    _calcRequestVersion++;
    for (final l in lines) { l.dispose(); }
  }
}

/// Date picker field that always shows the weekday with the date.
class _DateField extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onPick;
  const _DateField({required this.date, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final d = await showDatePicker(
          context: context, initialDate: date,
          firstDate: DateTime(DateTime.now().year, DateTime.now().month - 1, 1),
          lastDate: DateTime.now().add(const Duration(days: 90)),
        );
        if (d != null) onPick(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: tr('Dispatch date *')),
        child: Row(children: [
          Icon(Icons.today_rounded, size: 17, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(fmtDateWithDay(ymd(date)), overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}

/* ------------------------------- entry tab ------------------------------- */

class _EntryTab extends StatefulWidget {
  final bool readOnly;
  const _EntryTab({required this.readOnly});
  @override
  State<_EntryTab> createState() => _EntryTabState();
}

class _EntryTabState extends State<_EntryTab> with _CalcMixin {
  final truck = TextEditingController();
  final destination = TextEditingController();
  final remarks = TextEditingController();
  DateTime date = DateTime.now();
  bool saving = false;
  /// Truck master list (number + destination) — dropdown filters by the
  /// selected destination; 'Other/new' falls back to free typing.
  List<Map<String, dynamic>> _trucks = [];

  /// Suggestions from the company's truck master + destinations typed before
  /// on this device (persisted). They never preselect a destination.
  static List<String> _savedDests = [];
  List<String> get _destOptions {
    final set = <String>{};
    for (final t in _trucks) {
      final d = '${t['destination'] ?? ''}'.trim().toUpperCase();
      if (d.isNotEmpty && !_isLegacyDest(d)) set.add(d); // old-build forced choices stay hidden
    }
    set.addAll(_savedDests); // typed on THIS build → always shown (even Neemrana, if real)
    final l = set.toList()..sort();
    return l;
  }

  /// Old builds hard-coded the original sauce factory's NEEMRANA / MATIALA
  /// as defaults, so phones of OTHER companies may have them saved without
  /// anyone ever typing them. Purged ONCE on upgrade (food industry keeps
  /// them — they are real depots there); after that nothing is filtered, so
  /// a company that really ships to Neemrana can type it and keep it.
  static bool _isLegacyDest(String d) =>
      CompanyProfile.current.industry != 'food' && kLegacyDestinations.contains(d.trim().toUpperCase());

  static Future<void> loadSavedDests() async {
    try {
      final p = await SharedPreferences.getInstance();
      var list = p.getStringList('dispatch_dests') ?? [];
      // purge pending until a NON-food industry is actually known (profile
      // may still be loading on the very first launch after upgrade)
      if (CompanyProfile.current.industry != 'food' && !(p.getBool('dispatch_dests_v2') ?? false)) {
        final cleaned = list.where((d) => !_isLegacyDest(d)).toList();
        if (cleaned.length != list.length) await p.setStringList('dispatch_dests', cleaned);
        await p.setBool('dispatch_dests_v2', true);
        list = cleaned;
      }
      _savedDests = list
          .map(normalizeDispatchDestination)
          .where((d) => d.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
    } catch (_) {}
  }

  static Future<void> rememberDest(String d) async {
    d = normalizeDispatchDestination(d);
    if (d.isEmpty || _savedDests.contains(d)) return;
    _savedDests = [..._savedDests, d]..sort();
    try { await (await SharedPreferences.getInstance()).setStringList('dispatch_dests', _savedDests); } catch (_) {}
  }

  /// DRAFT: the half-filled entry survives leaving this screen (e.g. going
  /// to Production to create the missing batch) — restored on return,
  /// cleared after a successful dispatch.
  /// Persisted to SharedPreferences so it survives app restarts too.
  static Map<String, dynamic>? _draft;
  static const _draftKey = 'dispatch_entry_draft';
  bool _hasDraft = false; // drives the draft banner

  bool get _formHasData =>
      truck.text.trim().isNotEmpty ||
      destination.text.trim().isNotEmpty ||
      remarks.text.trim().isNotEmpty ||
      lines.any((l) => l.cartons.text.trim().isNotEmpty || l.trays.text.trim().isNotEmpty || l.batchCode.text.trim().isNotEmpty);

  void _saveDraft() {
    if (!_formHasData) { _clearDraft(); return; } // empty form → no draft
    _draft = {
      'truck': truck.text,
      'destination': destination.text,
      'remarks': remarks.text,
      'date': date.toIso8601String(),
      'lines': [
        for (final l in lines)
          {'productId': l.productId, 'batchId': l.batchId, 'cartons': l.cartons.text, 'trays': l.trays.text, 'batchCode': l.batchCode.text},
      ],
    };
    // survive app restarts too (fire-and-forget)
    SharedPreferences.getInstance().then((p) => p.setString(_draftKey, jsonEncode(_draft))).catchError((_) => false);
  }

  void _clearDraft() {
    _draft = null;
    SharedPreferences.getInstance().then((p) => p.remove(_draftKey)).catchError((_) => false);
  }

  /// Return to a clean entry after a successful dispatch or explicit draft
  /// deletion. The next form starts with one blank product line.
  void _resetEntryForm() {
    _clearDraft();
    setState(() {
      truck.clear();
      destination.clear();
      remarks.clear();
      date = DateTime.now();
      for (final l in lines) { l.dispose(); }
      lines
        ..clear()
        ..add(_Line()..productId = products.isNotEmpty ? products.first['id'] as int : null);
      _debounce?.cancel();
      _calcRequestVersion++;
      calc = null;
      _hasDraft = false;
    });
  }

  void _deleteDraftAndReset() => _resetEntryForm();

  /// Load the draft saved on disk (app was closed) if the in-memory one is gone.
  Future<void> _restorePersistedDraft() async {
    if (_draft != null) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_draftKey);
      if (raw == null || raw.isEmpty) return;
      _draft = (jsonDecode(raw) as Map).cast<String, dynamic>();
      if (mounted) setState(() { _restoreDraft(); _hasDraft = _formHasData; });
      recalcDebounced();
    } catch (_) {}
  }

  void _restoreDraft() {
    final d = _draft;
    if (d == null) return;
    truck.text = d['truck'] as String? ?? '';
    // Older drafts stored "Other" separately from the manually entered name.
    // Restore those drafts without carrying the old industry-first default into
    // new blank entries.
    final savedDestination = d['destination'] as String? ?? '';
    final hadLegacyOtherField = d.containsKey('otherDest') && savedDestination.toUpperCase() == 'OTHER';
    destination.text = hadLegacyOtherField
        ? (d['otherDest'] as String? ?? '')
        : savedDestination;
    if (_isLegacyDest(destination.text) && !_destOptions.contains(normalizeDispatchDestination(destination.text))) {
      destination.clear();
    }
    remarks.text = d['remarks'] as String? ?? '';
    date = DateTime.tryParse(d['date'] as String? ?? '') ?? DateTime.now();
    final ls = (d['lines'] as List?) ?? const [];
    if (ls.isNotEmpty) {
      lines.clear();
      for (final ld in ls.cast<Map<String, dynamic>>()) {
        final l = _Line();
        l.productId = ld['productId'] as int?;
        l.batchId = ld['batchId'] as int?;
        l.cartons.text = ld['cartons'] as String? ?? '';
        l.trays.text = ld['trays'] as String? ?? '';
        l.batchCode.text = ld['batchCode'] as String? ?? '';
        lines.add(l);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _restoreDraft();
    _hasDraft = _draft != null;
    _restorePersistedDraft(); // app-restart case (async)
    loadSavedDests().then((_) { if (mounted) setState(() {}); });
    if (!widget.readOnly) {
      loadProducts();
      _loadTrucks();
    }
  }

  Future<void> _loadTrucks() async {
    try {
      final json = await context.read<AuthController>().api.get('/dispatch/trucks');
      if (!mounted) return;
      setState(() => _trucks = ((json as Map)['trucks'] as List).cast<Map<String, dynamic>>());
    } catch (_) {/* server route optional until ff-truckfix runs */}
  }

  /// Trucks registered for the currently selected destination.
  List<String> get _destTrucks => [
        for (final t in _trucks)
          if (normalizeDispatchDestination('${t['destination'] ?? ''}') == _destination) '${t['number']}',
      ];

  @override
  void dispose() {
    // keep the half-filled form for when the user comes back
    _saveDraft();
    disposeLines();
    truck.dispose();
    destination.dispose();
    remarks.dispose();
    super.dispose();
  }

  String get _destination => normalizeDispatchDestination(destination.text);

  /// Best-effort GPS stamp (lat,long) — never blocks the dispatch.
  Future<String> _locationStamp() async {
    if (!isPhonePlatform) return '';
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return '';
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 5)),
      );
      return '[loc ${pos.latitude.toStringAsFixed(5)},${pos.longitude.toStringAsFixed(5)}]';
    } catch (_) {
      return '';
    }
  }

  Future<void> _submit() async {
    final dispatchDestination = _destination;
    if (dispatchDestination.isEmpty) {
      showErr(context, tr('Please enter the destination company or place.'));
      return;
    }
    final list = nonZeroItems();
    if (list.isEmpty) {
      showErr(context, 'Add at least one quantity before dispatch.');
      return;
    }
    // A product with production batches must never be dispatched without a
    // matching code; otherwise inventory falls while its batch still looks full.
    // If both batch-list endpoints are unavailable, require an exact manual
    // code rather than silently creating an un-attributed dispatch line.
    for (final item in list) {
      final pid = item['productId'] as int?;
      if (pid == null) continue;
      if (batchLoading.contains(pid)) {
        showErr(context, 'Batch stock is still loading. Please select a batch and try again.');
        return;
      }
      final code = normalizeDispatchBatchCode(item['batchCode']);
      if (batchLoadFailed.contains(pid) && code.isEmpty) {
        showErr(context, 'Could not load available batches. Enter the exact batch code or retry loading batches.');
        return;
      }
      final availableBatches = batchOptions[pid] ?? const <Map<String, dynamic>>[];
      if (availableBatches.isNotEmpty) {
        if (code.isEmpty) {
          showErr(context, 'Select or enter a batch code for every product line before dispatch.');
          return;
        }
        if (dispatchBatchByCode(availableBatches, code) == null) {
          showErr(context, 'No available batch matches "$code". Choose a batch with remaining stock.');
          return;
        }
      }
    }
    setState(() => saving = true);
    try {
      final loc = await _locationStamp();
      // MAN-13: no connection → kept on this device and sent automatically later.
      final sent = await OfflineQueue.instance.submit(
        context.read<AuthController>(),
        method: 'POST',
        path: '/dispatch',
        label: 'Dispatch',
        body: {
          'dispatchDate': ymd(date),
          'destination': dispatchDestination,
          'truckNumber': truck.text.trim(),
          'remarks': ('${remarks.text.trim()} $loc').trim(),
          'items': list,
        },
      );
      if (!mounted) return;
      if (sent.queued) {
        rememberDest(dispatchDestination);
        _resetEntryForm();
        showOk(context, 'Dispatch saved on this device — it will sync automatically when internet returns.');
        return;
      }
      final json = sent.json;
      final id = (json as Map)['id'];
      rememberDest(dispatchDestination); // company's own list grows automatically
      _resetEntryForm();
      for (final productId in list.map((item) => item['productId']).whereType<int>().toSet()) {
        unawaited(loadBatches(productId, refresh: true));
      }
      showOk(context, '${json['code']} dispatched to $dispatchDestination · ${qty(json['totals']['grossWeight'])} kg gross (${json['weekday']}).');
      context.push('/dispatch/$id');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline_rounded, size: 42, color: AppColors.slate),
            SizedBox(height: 12),
            Text('Your role can view dispatches but cannot create them.', textAlign: TextAlign.center),
            SizedBox(height: 4),
            Text('Use the Calculator, History and Reports tabs.', style: TextStyle(fontSize: 12.5)),
          ]),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(20), children: [
      // DRAFT banner — restored half-filled entry: keep typing or delete it.
      if (_hasDraft && _formHasData)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.amber.withValues(alpha: 0.45)),
          ),
          child: Row(children: [
            const Icon(Icons.history_edu_rounded, size: 20, color: AppColors.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('Draft restored — your last unsent entry. Continue filling or delete it.'),
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurface)),
            ),
            TextButton.icon(
              onPressed: _deleteDraftAndReset,
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.red),
              label: Text(tr('Delete draft'), style: const TextStyle(color: AppColors.red)),
            ),
          ]),
        ),
      LayoutBuilder(builder: (context, c) {
        final wide = isWindowsPlatform ? c.maxWidth >= 760 : c.maxWidth > 900;
        final compact = isWindowsPlatform ? c.maxWidth < 540 : c.maxWidth < 600;
        final truckField = _destTrucks.isEmpty
            ? TextField(controller: truck, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('Truck / Vehicle No. *'), hintText: 'PB-08-AB-1234'), onChanged: (_) => setState(() {}))
            : DropdownButtonFormField<String>(
                key: ValueKey('truckdd-$_destination'),
                initialValue: _destTrucks.contains(truck.text) ? truck.text : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Truck / Vehicle No. *')),
                items: [
                  for (final n in _destTrucks) DropdownMenuItem(value: n, child: Text(n)),
                  DropdownMenuItem(value: '__other__', child: Text(tr('Other / new truck…'))),
                ],
                onChanged: (v) async {
                  if (v == '__other__') {
                    truck.clear();
                    final typed = await showDialog<String>(
                      context: context,
                      builder: (ctx) {
                        final c = TextEditingController();
                        return AlertDialog(
                          title: Text(tr('Truck / Vehicle No. *')),
                          content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(hintText: 'PB-08-AB-1234')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
                            FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim().toUpperCase()), child: Text(tr('OK'))),
                          ],
                        );
                      },
                    );
                    if (typed != null && typed.isNotEmpty) setState(() => truck.text = typed);
                  } else if (v != null) {
                    setState(() => truck.text = v);
                  }
                },
              );
        final dateField = _DateField(date: date, onPick: (d) => setState(() => date = d));
        final destinationField = DispatchDestinationField(
          controller: destination,
          suggestions: _destOptions,
          onChanged: (_) => setState(() {}),
        );
        final remarksField = TextField(controller: remarks, decoration: InputDecoration(labelText: tr('Remarks')));
        final form = SectionCard(title: 'Dispatch Entry', child: Column(children: [
          if (compact) ...[
            truckField,
            const SizedBox(height: 12),
            dateField,
          ] else
            Row(children: [Expanded(child: truckField), const SizedBox(width: 12), Expanded(child: dateField)]),
          const SizedBox(height: 12),
          if (compact) ...[
            destinationField,
            const SizedBox(height: 12),
            remarksField,
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: destinationField), const SizedBox(width: 12), Expanded(child: remarksField)]),
          const SizedBox(height: 20),
          Align(alignment: Alignment.centerLeft, child: Text(CompanyProfile.usesTrays ? '${tr('Loading lines')} (${U.carton.toLowerCase()} & ${U.trayLc})' : '${tr('Loading lines')} (${U.carton.toLowerCase()})', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface))),
          const SizedBox(height: 10),
          products.isEmpty
              ? (productsLoaded
                  ? _NoProductsHint(onAdd: () => context.go('/products'))
                  : const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())))
              : _LinesEditor(
                  products: products,
                  lines: lines,
                  onAdd: addLine,
                  onRemove: removeLine,
                  onChanged: recalcDebounced,
                  onBatchChanged: () {
                    setState(() {});
                    recalcDebounced();
                  },
                  onProductChanged: selectProduct,
                  batchOptions: batchOptions,
                  batchLoading: batchLoading,
                  batchLoadFailed: batchLoadFailed,
                  onRetryBatches: (productId) => loadBatches(productId, refresh: true),
                  showBatch: true,
                ),
        ]));
        final side = SectionCard(title: 'Before you dispatch', child: Column(children: [
          if (calc != null) ...[
            _SummaryCard(totals: (calc!['totals'] as Map).cast<String, dynamic>(), lines: (calc!['lines'] as List).cast<Map<String, dynamic>>()),
            const SizedBox(height: 14),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
              child: Text(CompanyProfile.usesTrays
                      ? 'Add ${U.carton.toLowerCase()} or ${U.trayLc} to see the live weight summary.'
                      : 'Add ${U.carton.toLowerCase()} to see the live weight summary.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saving || calc == null ? null : _submit,
              icon: const Icon(Icons.local_shipping_rounded, size: 19),
              label: Text(saving ? 'Dispatching…' : tr('Confirm & Dispatch')),
            ),
          ),
          const SizedBox(height: 8),
          Text(tr('Date & day are stamped automatically. Stock is deducted and the team is notified.'),
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
        ]));
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: form), const SizedBox(width: 16), Expanded(flex: 2, child: side)]);
        }
        return Column(children: [form, const SizedBox(height: 16), side]);
      }),
    ]);
  }
}

/* ------------------------------ history tab ------------------------------ */

class _HistoryTab extends StatefulWidget {
  const _HistoryTab();
  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  late Future<List<Map<String, dynamic>>> _future;

  void _reload() => setState(() => _future = _load());

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final json = await context.read<AuthController>().api.get('/dispatch');
    return ((json as Map)['dispatches'] as List).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: () => setState(() => _future = _load()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const EmptyState('No dispatches yet', icon: Icons.local_shipping_rounded);
        return ListView(padding: const EdgeInsets.all(20), children: [
          SectionCard(
            title: 'Dispatch History',
            child: AppDataTable(
              columns: ['Code', 'Date', 'Day', 'Truck', 'Destination', U.carton, if (CompanyProfile.usesTrays) U.tray, U.piece, 'Gross kg', 'By'],
              rows: [
                for (final d in rows)
                  [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(d['code'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Open dispatch',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        onPressed: () async {
                          await context.push('/dispatch/${d['id']}');
                          _reload();
                        },
                      ),
                    ]),
                    fmtDate(d['dispatch_date']),
                    d['weekday'] ?? weekdayOf(d['dispatch_date']),
                    d['truck_number'],
                    Text(d['destination'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                    qtyInt(d['total_cartons']),
                    if (CompanyProfile.usesTrays) qtyInt(d['total_trays'] ?? 0),
                    qtyInt(d['total_bottles']),
                    qty(d['gross_weight']),
                    d['created_by_name'] ?? '—',
                  ],
              ],
            ),
          ),
        ]);
      },
    );
  }
}

/* ------------------------------ reports tab ------------------------------ */

class _ReportsTab extends StatelessWidget {
  const _ReportsTab();
  @override
  Widget build(BuildContext context) {
    return const _EmbeddedReport(reportId: 'dispatch-register');
  }
}

class _EmbeddedReport extends StatefulWidget {
  final String reportId;
  const _EmbeddedReport({required this.reportId});
  @override
  State<_EmbeddedReport> createState() => _EmbeddedReportState();
}

class _EmbeddedReportState extends State<_EmbeddedReport> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final json = await context.read<AuthController>().api.get('/reports/${widget.reportId}');
    return (json as Map).cast<String, dynamic>();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorState('${snap.error!}\n\nThe dispatch report is available to Dispatch Manager, Store Manager, Admin, Super Admin and Director.', onRetry: () => setState(() => _future = _load()));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (columns, rows) = U.table(
          (snap.data!['columns'] as List).cast<String>(),
          (snap.data!['rows'] as List).map((r) => (r as List).cast<dynamic>()).toList(),
        );
        return ListView(padding: const EdgeInsets.all(20), children: [
          SectionCard(
            title: U.ize(snap.data!['title'] as String),
            child: rows.isEmpty ? const EmptyState('No data') : AppDataTable(columns: columns, rows: rows),
          ),
        ]);
      },
    );
  }
}

/* ------------------------------- trucks tab ------------------------------- */

/// Truck master: register each truck against its destination (route) so the
/// Dispatch Entry shows a destination-filtered dropdown.
class _TrucksTab extends StatefulWidget {
  final bool readOnly;
  const _TrucksTab({required this.readOnly});
  @override
  State<_TrucksTab> createState() => _TrucksTabState();
}

class _TrucksTabState extends State<_TrucksTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final json = await context.read<AuthController>().api.get('/dispatch/trucks');
    return ((json as Map)['trucks'] as List).cast<Map<String, dynamic>>();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _add() async {
    final number = TextEditingController();
    final destination = TextEditingController();
    String? truckError;
    String? destinationError;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Add Truck')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: number,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: tr('Truck / Vehicle No. *'),
                hintText: 'PB-08-AB-1234',
                errorText: truckError == null ? null : tr(truckError!),
              ),
              onChanged: (_) => setD(() => truckError = null),
            ),
            const SizedBox(height: 12),
            DispatchDestinationField(
              controller: destination,
              suggestions: _EntryTabState._savedDests,
              errorText: destinationError,
              onChanged: (_) => setD(() => destinationError = null),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(
              onPressed: () async {
                final n = number.text.trim().toUpperCase();
                final d = normalizeDispatchDestination(destination.text);
                if (n.isEmpty || d.isEmpty) {
                  setD(() {
                    truckError = n.isEmpty ? 'Truck number is required.' : null;
                    destinationError = d.isEmpty ? 'Destination is required.' : null;
                  });
                  return;
                }
                try {
                  await ctx.read<AuthController>().api.post('/dispatch/trucks', {'number': n, 'destination': d});
                  await _EntryTabState.rememberDest(d); // typed here = real destination → shown in entry suggestions
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) showErr(ctx, e);
                }
              },
              child: Text(tr('Save')),
            ),
          ],
        ),
      ),
    );
    number.dispose();
    destination.dispose();
    if (saved == true && mounted) _reload();
  }

  Future<void> _remove(Map<String, dynamic> t) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${tr('Delete')} ${t['number']}?'),
        content: Text(tr('The truck will no longer appear in the dispatch dropdown.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Delete'))),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await context.read<AuthController>().api.delete('/dispatch/trucks/${t['id']}');
      _reload();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final trucks = snap.data!;
        return ListView(padding: const EdgeInsets.all(20), children: [
          if (!widget.readOnly)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(tr('Add Truck')),
              ),
            ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Truck Master (destination-wise)',
            child: trucks.isEmpty
                ? EmptyState(tr('No trucks yet — add each truck with its destination'), icon: Icons.local_shipping_outlined)
                : AppDataTable(
                    columns: ['Truck', 'Destination', if (!widget.readOnly) ''],
                    rows: [
                      for (final t in trucks)
                        [
                          Text('${t['number']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          '${t['destination']}',
                          if (!widget.readOnly)
                            IconButton(
                              tooltip: 'Remove truck',
                              icon: Icon(Icons.delete_outline_rounded, size: 18, color: Theme.of(context).colorScheme.error),
                              onPressed: () => _remove(t),
                            ),
                        ],
                    ],
                  ),
          ),
        ]);
      },
    );
  }
}
