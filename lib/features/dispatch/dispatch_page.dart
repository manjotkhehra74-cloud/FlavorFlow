import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/scan_page.dart';
import '../../ui/widgets.dart';
import 'dispatch_pdf.dart';

/// Dispatch destinations — NEEMRANA & MATIALA are the standard ones.
const kDispatchDestinations = ['NEEMRANA', 'MATIALA', 'Other'];

/// Dedicated Dispatch Module: entry · truck loading calculator · history · reports.
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
    _tab = TabController(length: 4, vsync: this);
    if (widget.tab == 'calculator') _tab.index = 1;
    if (widget.tab == 'history') _tab.index = 2;
    if (widget.tab == 'reports') _tab.index = 3;
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthController>().can('dispatch.manage');
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
              Tab(text: canManage ? tr('Dispatch Entry') : tr('Dispatch Entry (view only)')),
              Tab(text: tr('Truck Loading Calculator')),
              Tab(text: tr('Dispatch History')),
              Tab(text: tr('Reports')),
            ],
          ),
        ),
      ),
      Expanded(
        child: TabBarView(controller: _tab, children: [
          _EntryTab(readOnly: !canManage),
          const _CalculatorTab(),
          const _HistoryTab(),
          const _ReportsTab(),
        ]),
      ),
    ]);
  }
}

/* ------------------------- shared: product line editor ------------------------- */

class _Line {
  int? productId;
  final cartons = TextEditingController();
  final trays = TextEditingController();
  final batchCode = TextEditingController();
  void dispose() { cartons.dispose(); trays.dispose(); batchCode.dispose(); }
}

Map<String, dynamic> _prod(List<Map<String, dynamic>> products, int? id) =>
    products.firstWhere((p) => p['id'] == id, orElse: () => {'bottles_per_cb': 0, 'bottles_per_tray': 0});

class _LinesEditor extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final List<_Line> lines;
  final VoidCallback onAdd, onChanged;
  final void Function(int) onRemove;
  final bool showBatch;
  const _LinesEditor({required this.products, required this.lines, required this.onAdd, required this.onRemove, required this.onChanged, this.showBatch = false});

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
                  initialValue: lines[i].productId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Product ${i + 1} *')),
                  items: [for (final p in products) DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) { lines[i].productId = v; onChanged(); },
                ),
              ),
              IconButton(
                tooltip: 'Remove line',
                onPressed: lines.length <= 1 ? null : () => onRemove(i),
                icon: Icon(Icons.remove_circle_outline_rounded, color: lines.length <= 1 ? scheme.outline : scheme.error),
              ),
            ]),
            const SizedBox(height: 10),
            // Row 2: quantities (and optional batch code) with room to breathe.
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
                if ((_prod(products, lines[i].productId)['bottles_per_tray'] as num? ?? 0) > 0) ...[
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
                if (showBatch) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: lines[i].batchCode,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Batch code',
                        hintText: 'e.g. SS-740-A',
                        helperText: 'Stock deducts batch-wise',
                        helperMaxLines: 1,
                        // QR/barcode scan — no typing on the factory floor
                        suffixIcon: IconButton(
                          tooltip: 'Scan batch code',
                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                          onPressed: () async {
                            final v = await ScanPage.scan(context, title: 'Scan batch code');
                            if (v != null) {
                              lines[i].batchCode.text = v.toUpperCase();
                              onChanged();
                            }
                          },
                        ),
                      ),
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
                Expanded(child: Text(l['productName'] as String, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                Text(lineText(l), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ]),
            ),
          const Divider(height: 18),
        ],
        row('Carton weight', '${qty(totals['cartonWeight'])} kg'),
        row('Tray weight', '${qty(totals['trayWeight'])} kg'),
        row('Total ${U.carton.toLowerCase()}', '${qtyInt(totals['totalCartons'])} ${U.cb}'),
        row('Total ${U.trayLc}', qtyInt(totals['totalTrays'])),
        row('Total ${U.piece.toLowerCase()}', qtyInt(totals['totalBottles'])),
        const Divider(height: 18),
        row('Gross loaded weight', '${qty(totals['grossWeight'])} kg', strong: true),
      ]),
    );
  }
}

mixin _CalcMixin<T extends StatefulWidget> on State<T> {
  List<Map<String, dynamic>> products = [];
  final List<_Line> lines = [_Line()];
  Map<String, dynamic>? calc;
  Timer? _debounce;

  Future<void> loadProducts() async {
    try {
      final json = await context.read<AuthController>().api.get('/products');
      setState(() {
        products = ((json as Map)['products'] as List).cast<Map<String, dynamic>>();
        for (final l in lines) { l.productId ??= products.isNotEmpty ? products.first['id'] as int : null; }
      });
      recalc();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  List<Map<String, dynamic>> items() => [
        for (final l in lines)
          {
            'productId': l.productId,
            'cartons': int.tryParse(l.cartons.text) ?? 0,
            'trays': int.tryParse(l.trays.text) ?? 0,
            if (l.batchCode.text.trim().isNotEmpty) 'batchCode': l.batchCode.text.trim().toUpperCase(),
          },
      ];

  List<Map<String, dynamic>> nonZeroItems() =>
      items().where((l) => (l['cartons'] as int) > 0 || (l['trays'] as int) > 0).toList();

  void recalcDebounced() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), recalc);
  }

  Future<void> recalc() async {
    final list = nonZeroItems();
    if (list.isEmpty || !mounted) {
      setState(() => calc = null);
      return;
    }
    try {
      final json = await context.read<AuthController>().api.post('/dispatch/calculate', {'items': list});
      if (mounted) setState(() => calc = (json as Map).cast<String, dynamic>());
    } catch (_) {
      if (mounted) setState(() => calc = null);
    }
  }

  void addLine() => setState(() => lines.add(_Line()..productId = products.isNotEmpty ? products.first['id'] as int : null));
  void removeLine(int i) => setState(() { lines.removeAt(i).dispose(); recalc(); });
  void disposeLines() { _debounce?.cancel(); for (final l in lines) { l.dispose(); } }
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

/// Destination selector: NEEMRANA / MATIALA / Other (free text).
class _DestinationField extends StatelessWidget {
  final String value;
  final TextEditingController otherCtl;
  final ValueChanged<String> onChanged;
  const _DestinationField({required this.value, required this.otherCtl, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: tr('Destination *')),
        items: [
          for (final d in kDispatchDestinations)
            DropdownMenuItem(value: d, child: Text(d == 'Other' ? 'Other (type below)' : '${d[0]}${d.substring(1).toLowerCase()}')),
        ],
        onChanged: (v) => onChanged(v ?? 'NEEMRANA'),
      ),
      if (value == 'Other') ...[
        const SizedBox(height: 12),
        TextField(
          controller: otherCtl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: tr('Destination name *'), hintText: 'e.g. LUDHIANA'),
          onChanged: onChanged,
        ),
      ],
    ]);
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
  final otherDest = TextEditingController();
  final remarks = TextEditingController();
  String destination = 'NEEMRANA';
  DateTime date = DateTime.now();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    if (!widget.readOnly) loadProducts();
  }

  @override
  void dispose() {
    disposeLines();
    super.dispose();
  }

  String get _destination {
    if (destination != 'Other') return destination;
    return otherDest.text.trim().toUpperCase();
  }

  /// Best-effort GPS stamp (lat,long) — never blocks the dispatch.
  Future<String> _locationStamp() async {
    if (kIsWeb) return '';
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
    if (destination == 'Other' && _destination.isEmpty) {
      showErr(context, 'Please type the destination name.');
      return;
    }
    setState(() => saving = true);
    try {
      final list = nonZeroItems();
      final loc = await _locationStamp();
      final json = await context.read<AuthController>().api.post('/dispatch', {
        'dispatchDate': ymd(date),
        'destination': _destination,
        'truckNumber': truck.text.trim(),
        'remarks': ('${remarks.text.trim()} $loc').trim(),
        'items': list,
      });
      if (!mounted) return;
      final id = (json as Map)['id'];
      showOk(context, '${json['code']} dispatched to $_destination · ${qty(json['totals']['grossWeight'])} kg gross (${json['weekday']}).');
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
      LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 900;
        final form = SectionCard(title: 'Dispatch Entry', child: Column(children: [
          Row(children: [
            Expanded(child: TextField(controller: truck, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('Truck / Vehicle No. *'), hintText: 'PB-08-AB-1234'), onChanged: (_) => setState(() {}))),
            const SizedBox(width: 12),
            Expanded(child: _DateField(date: date, onPick: (d) => setState(() => date = d))),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _DestinationField(value: destination, otherCtl: otherDest, onChanged: (v) => setState(() {
              if (kDispatchDestinations.contains(v)) {
                destination = v;
              } else {
                otherDest.text = v;
              }
            }))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: remarks, decoration: InputDecoration(labelText: tr('Remarks')))),
          ]),
          const SizedBox(height: 20),
          Align(alignment: Alignment.centerLeft, child: Text(tr('Loading lines (cartons & trays)'), style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface))),
          const SizedBox(height: 10),
          products.isEmpty
              ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
              : _LinesEditor(products: products, lines: lines, onAdd: addLine, onRemove: removeLine, onChanged: recalcDebounced, showBatch: true),
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
              child: Text('Add cartons or trays to see the live weight summary.',
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
          Text('Date & day are stamped automatically. Stock is deducted and the team is notified.',
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

/* ----------------------------- calculator tab ----------------------------- */

class _CalculatorTab extends StatefulWidget {
  const _CalculatorTab();
  @override
  State<_CalculatorTab> createState() => _CalculatorTabState();
}

class _CalculatorTabState extends State<_CalculatorTab> with _CalcMixin {
  final truck = TextEditingController();
  final otherDest = TextEditingController();
  String destination = 'NEEMRANA';
  DateTime date = DateTime.now();
  bool exporting = false;

  @override
  void initState() {
    super.initState();
    loadProducts();
  }

  @override
  void dispose() {
    disposeLines();
    super.dispose();
  }

  Future<void> _exportPdf() async {
    if (calc == null) return;
    setState(() => exporting = true);
    try {
      final dest = destination == 'Other' ? otherDest.text.trim().toUpperCase() : destination;
      final bytes = await DispatchPdf.estimate(
        lines: (calc!['lines'] as List).cast<Map<String, dynamic>>(),
        totals: (calc!['totals'] as Map).cast<String, dynamic>(),
        truckNumber: truck.text.trim(),
        destination: dest,
        dispatchDate: ymd(date),
      );
      await Printing.sharePdf(bytes: bytes, filename: 'truck-loading-${truck.text.trim().isEmpty ? 'plan' : truck.text.trim()}.pdf');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(20), children: [
      LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 900;
        final form = SectionCard(title: 'Truck Loading Calculator', child: Column(children: [
          Row(children: [
            Expanded(child: TextField(controller: truck, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('Truck number'), hintText: 'PB-08-AB-1234'))),
            const SizedBox(width: 12),
            Expanded(child: _DateField(date: date, onPick: (d) => setState(() => date = d))),
          ]),
          const SizedBox(height: 12),
          _DestinationField(value: destination, otherCtl: otherDest, onChanged: (v) => setState(() {
            if (kDispatchDestinations.contains(v)) {
              destination = v;
            } else {
              otherDest.text = v;
            }
          })),
          const SizedBox(height: 16),
          products.isEmpty
              ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
              : _LinesEditor(products: products, lines: lines, onAdd: addLine, onRemove: removeLine, onChanged: recalcDebounced),
        ]));
        final side = SectionCard(title: 'Calculated Weights', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (calc != null) ...[
            _SummaryCard(totals: (calc!['totals'] as Map).cast<String, dynamic>(), lines: (calc!['lines'] as List).cast<Map<String, dynamic>>()),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: exporting ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 19),
              label: Text(exporting ? 'Preparing PDF…' : 'Export Loading Plan (PDF)'),
            ),
            const SizedBox(height: 8),
            Text('Shares/prints a pre-dispatch loading plan with per-line and total weights.',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(children: [
                Icon(Icons.calculate_outlined, size: 38, color: scheme.outline),
                const SizedBox(height: 8),
                Text('Enter cartons / trays to auto-calculate\nweights, bottles and carton counts.',
                    textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              ]),
            ),
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
              columns: ['Code', 'Date', 'Day', 'Truck', 'Destination', U.carton, U.tray, U.piece, 'Gross kg', 'By'],
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
                    qtyInt(d['total_trays'] ?? 0),
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
        final columns = (snap.data!['columns'] as List).cast<String>();
        final rows = (snap.data!['rows'] as List).map((r) => (r as List).cast<dynamic>()).toList();
        return ListView(padding: const EdgeInsets.all(20), children: [
          SectionCard(
            title: snap.data!['title'] as String,
            child: rows.isEmpty ? const EmptyState('No data') : AppDataTable(columns: columns, rows: rows),
          ),
        ]);
      },
    );
  }
}
