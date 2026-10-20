import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/item_code.dart';
import '../../core/platform_support.dart';
import '../../state/auth.dart';
import '../../core/offline_queue.dart';
import '../../ui/widgets.dart';
import '../../ui/windows_widgets.dart';

/// Stock Adjustments — request corrections (IN/OUT) and track their status.
/// Approval happens on the Approvals screen (authorized roles only).
class AdjustmentsPage extends StatefulWidget {
  const AdjustmentsPage({super.key});
  @override
  State<AdjustmentsPage> createState() => _AdjustmentsPageState();
}

class _AdjustmentsPageState extends State<AdjustmentsPage> {
  String _status = ''; // '', PENDING, APPROVED, REJECTED
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final q = _status.isEmpty ? '' : '?status=$_status';
    final json = await context.read<AuthController>().api.get('/adjustments$q');
    return ((json as Map)['adjustments'] as List).cast<Map<String, dynamic>>();
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        final requestTable = SectionCard(
          title: 'Adjustment Requests',
          trailing: Text('${rows.length} ${tr('requests')}'),
          padding: EdgeInsets.zero,
          child: rows.isEmpty
              ? const EmptyState('No adjustment requests')
              : AppDataTable(
                  columns: ['Code', 'Product', 'Type', U.cb, 'Reason', 'Status', 'Requested By', 'Requested On', 'Decision'],
                  rows: [
                    for (final a in rows)
                      [
                        Text(a['code'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ItemNameCell(name: '${a['product_name']}', code: '${a['item_code'] ?? ''}'),
                        StatusChip(a['adj_type'] as String),
                        qtyInt(a['qty_cb']),
                        a['reason'],
                        StatusChip(a['status'] as String),
                        a['requested_by_name'],
                        fmtDateTime(a['requested_at']),
                        if (a['status'] == 'APPROVED')
                          Text('${a['approved_by_name']} · ${fmtDate(a['approved_at'])}')
                        else if (a['status'] == 'REJECTED')
                          Text('${a['rejected_by_name']} · ${fmtDate(a['rejected_at'])}')
                        else
                          const Text('Awaiting'),
                      ],
                  ],
                ),
        );
        if (isWindowsPlatform) {
          return WindowsDocumentWorkspace(
            title: 'Stock Adjustments',
            subtitle: 'Request and audit stock corrections',
            icon: Icons.tune_rounded,
            commandBar: WindowsCommandStrip(children: [
              for (final status in ['', 'PENDING', 'APPROVED', 'REJECTED'])
                ChoiceChip(
                  label: Text(status.isEmpty ? tr('All') : tr(status.toLowerCase())),
                  selected: _status == status,
                  onSelected: (_) => setState(() { _status = status; _future = _load(); }),
                ),
              if (auth.can('adjustments.approve'))
                OutlinedButton.icon(onPressed: () => context.go('/approvals'), icon: const Icon(Icons.fact_check_outlined, size: 16), label: Text(tr('Approval queue'))),
              if (auth.can('adjustments.create'))
                FilledButton.icon(
                  onPressed: () async {
                    final saved = await showDialog<bool>(context: context, builder: (_) => const AdjustmentFormDialog());
                    if (saved == true) { _reload(); if (context.mounted) showOk(context, 'Adjustment request submitted for approval.'); }
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(tr('New Adjustment')),
                ),
            ]),
            content: ListView(padding: const EdgeInsets.all(12), children: [requestTable]),
          );
        }
        return ListView(padding: const EdgeInsets.all(20), children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final status in ['', 'PENDING', 'APPROVED', 'REJECTED'])
              ChoiceChip(
                label: Text(status.isEmpty ? tr('All') : tr(status.toLowerCase())),
                selected: _status == status,
                onSelected: (_) => setState(() { _status = status; _future = _load(); }),
              ),
            if (auth.can('adjustments.approve'))
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: OutlinedButton.icon(onPressed: () => context.go('/approvals'), icon: const Icon(Icons.fact_check_outlined, size: 18), label: Text(tr('Approval queue'))),
              ),
            if (auth.can('adjustments.create'))
              FilledButton.icon(
                onPressed: () async {
                  final saved = await showDialog<bool>(context: context, builder: (_) => const AdjustmentFormDialog());
                  if (saved == true) { _reload(); if (context.mounted) showOk(context, 'Adjustment request submitted for approval.'); }
                },
                icon: const Icon(Icons.add_rounded),
                label: Text(tr('New Adjustment')),
              ),
          ]),
          const SizedBox(height: 16),
          requestTable,
        ]);
      },
    );
  }
}

class AdjustmentFormDialog extends StatefulWidget {
  const AdjustmentFormDialog({super.key});
  @override
  State<AdjustmentFormDialog> createState() => _AdjustmentFormDialogState();
}

class _AdjustmentFormDialogState extends State<AdjustmentFormDialog> {
  List<Map<String, dynamic>> products = [];
  int? productId;
  String stockType = 'Finished Goods';
  String materialType = 'Raw Material';
  List<Map<String, dynamic>> materials = [];
  int? materialId;
  String type = 'OUT';
  final cb = TextEditingController();
  final reason = TextEditingController();
  bool busy = false;
  XFile? photo; // damage-proof photo (camera/gallery)

  Future<void> _pickPhoto(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 80);
      if (x != null && mounted) setState(() => photo = x);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  void initState() {
    super.initState();
    context.read<AuthController>().api.get('/products').then((json) {
      setState(() {
        products = ((json as Map)['products'] as List)
            .cast<Map<String, dynamic>>()
            .where((p) => (p['active'] as num? ?? 1) != 0)
            .toList();
        productId = !isWindowsPlatform && products.isNotEmpty ? products.first['id'] as int : null;
      });
    }).catchError((e) { if (mounted) showErr(context, e); });
    if (isWindowsPlatform) {
      context.read<AuthController>().api.get('/packing/materials').then((json) {
        if (!mounted) return;
        setState(() => materials = ((json as Map)['materials'] as List)
            .cast<Map<String, dynamic>>());
      }).catchError((_) {
        // A missing materials endpoint must not block finished-goods requests.
      });
    }
  }

  Map<String, dynamic>? get _product => productId == null || products.isEmpty ? null : products.firstWhere((p) => p['id'] == productId, orElse: () => products.first);

  Future<void> _save() async {
    if (isWindowsPlatform && stockType != 'Finished Goods') {
      showErr(context, 'Material adjustments require the server approval and ledger API update. No request was submitted.');
      return;
    }
    if (productId == null || !products.any((p) => p['id'] == productId)) {
      showErr(context, 'Select a finished-goods SKU.');
      return;
    }
    setState(() => busy = true);
    try {
      // MAN-13: no connection → kept on this device; the request still needs approval.
      final sent = await OfflineQueue.instance.submit(
        context.read<AuthController>(),
        method: 'POST',
        path: '/adjustments',
        label: 'Stock adjustment request',
        body: {
          'productId': productId,
          'adjType': type,
          'qtyCb': int.tryParse(cb.text) ?? 0,
          'reason': reason.text.trim() + (photo != null ? ' [photo attached]' : ''),
        },
      );
      if (mounted && sent.queued) showOk(context, 'Request saved on this device — it will sync when internet returns.');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _windowsForm(BuildContext context) {
    final matches = materials.where((m) => materialType == 'Raw Material'
      ? m['category'] == 'Raw Material' : m['category'] != 'Raw Material').toList();
    final selected = matches.where((m) => m['id'] == materialId).toList();
    final material = selected.isEmpty ? null : selected.first;
    final scheme = Theme.of(context).colorScheme;
    return Dialog(insetPadding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 780, maxHeight: 720),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: const Color(0xFFE2E9EF),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Request Stock Adjustment'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Request only — stock changes after approval.',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
          ])),
        Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Top row: Stock type + Material type + Material (mirrors concept's 3-column header)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: DropdownButtonFormField<String>(initialValue: stockType,
                decoration: const InputDecoration(labelText: 'Stock type *'),
                items: const [
                  DropdownMenuItem(value: 'Finished Goods', child: Text('Finished Goods')),
                  DropdownMenuItem(value: 'Semi-finished Goods', child: Text('Semi-finished Goods')),
                ], onChanged: (v) => setState(() {
                  stockType = v ?? 'Finished Goods';
                  materialId = null;
                }))),
              const SizedBox(width: 12),
              if (stockType != 'Finished Goods') ...[
                Expanded(child: DropdownButtonFormField<String>(initialValue: materialType,
                  decoration: const InputDecoration(labelText: 'Material type *'),
                  items: const [
                    DropdownMenuItem(value: 'Raw Material', child: Text('Raw Material')),
                    DropdownMenuItem(value: 'Packing Material', child: Text('Packing Material')),
                  ], onChanged: (v) => setState(() {
                    materialType = v ?? 'Raw Material'; materialId = null;
                  }))),
                const SizedBox(width: 12),
                Expanded(child: DropdownButtonFormField<int>(key: ValueKey('material-$materialType'),
                  initialValue: materialId, isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Material *', hintText: 'Select a material'),
                  items: [for (final m in matches)
                    DropdownMenuItem(value: m['id'] as int,
                      child: Text('${m['name']}', overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => materialId = v))),
              ] else
                Expanded(child: DropdownButtonFormField<int>(
                  key: ValueKey('windows-adj-$productId'), initialValue: productId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'SKU *', hintText: 'Select a SKU'),
                  items: [for (final p in products)
                    DropdownMenuItem(value: p['id'] as int,
                      child: Text(ItemCode.pick(p), overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => productId = v),
                )),
            ]),
            if (stockType != 'Finished Goods')
              Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
                TextButton(onPressed: null, style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                  child: const Text('+ Show Finished goods flow', style: TextStyle(fontSize: 11.5))),
                const SizedBox(width: 16),
                TextButton(onPressed: null, style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                  child: const Text('+ Add material', style: TextStyle(fontSize: 11.5))),
              ]))
            else
              Padding(padding: const EdgeInsets.only(top: 6),
                child: TextButton(onPressed: null, style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                  child: const Text('+ Show Finished goods flow', style: TextStyle(fontSize: 11.5)))),
            const SizedBox(height: 12),
            // Current stock grey field with unit hint (kg / m / pcs)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Current stock', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFF0F2F4), border: Border.all(color: const Color(0xFFD0D7DD)), borderRadius: BorderRadius.circular(4)),
                child: Text(
                  stockType == 'Finished Goods'
                    ? (_product == null ? '—' : '${qtyInt(_product!['qty_cb'])} ${U.cb}')
                    : (material == null ? '—' : '${material['stock']} ${material['unit']}'),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
              Padding(padding: const EdgeInsets.only(top: 4),
                child: Text('( kg / m / pcs )', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant))),
            ]),
            const SizedBox(height: 16),
            Text('Adjustment', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: scheme.onSurface)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: SegmentedButton<String>(segments: const [
                ButtonSegment(value: 'IN', label: Text('Stock IN')),
                ButtonSegment(value: 'OUT', label: Text('Stock OUT')),
              ], selected: {type}, onSelectionChanged: (v) => setState(() => type = v.first))),
              const SizedBox(width: 12),
              Expanded(child: Row(children: [
                const Text('Adjustment quantity *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: cb, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)))),
                const SizedBox(width: 6),
                Text('( kg / m / pcs )', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
              ])),
            ]),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 12), child: Text('Reason *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: reason, maxLines: 4,
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)))),
            ]),
            Align(alignment: Alignment.centerLeft,
              child: TextButton(onPressed: null,
                child: const Text('+ Photo / Gallery', style: TextStyle(fontSize: 11.5)))),
            if (stockType != 'Finished Goods')
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6), border: Border.all(color: scheme.outlineVariant)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Material adjustment requires API support through approval and stock ledger; unavailable server must block submission, never update a different SKU.',
                    style: TextStyle(fontSize: 11.5, height: 1.35))),
                ]),
              ),
          ]),
        )),
        const Divider(height: 1),
        Padding(padding: const EdgeInsets.all(12), child: Row(
          mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: busy || stockType != 'Finished Goods' || productId == null
              ? null : _save,
              child: Text(busy ? 'Submitting…' : 'Submit for Approval')),
          ],
        )),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (isWindowsPlatform) return _windowsForm(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(tr('Request Stock Adjustment')),
      content: SizedBox(
        width: 420,
        child: products.isEmpty
            ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                DropdownButtonFormField<int>(
                  key: ValueKey('adj-$productId'),
                  initialValue: productId,
                  decoration: InputDecoration(labelText: tr('Product *'), suffixIcon: ScanPickButton(rows: products, onPicked: (p) => setState(() => productId = p['id'] as int))),
                  isExpanded: true,
                  items: [for (final p in products) DropdownMenuItem(value: p['id'] as int, child: Text(ItemCode.pick(p), overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => productId = v),
                ),
                if (_product != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('In stock: ${qtyInt(_product!['qty_cb'])} ${U.cb}${CompanyProfile.usesTrays && (_product!['qty_trays'] as num? ?? 0) > 0 ? ' + ${qtyInt(_product!['qty_trays'])} ${U.trayLc}' : ''}',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                  ),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'IN', label: Text(tr('Stock IN')), icon: const Icon(Icons.south_west_rounded, size: 17)),
                    ButtonSegment(value: 'OUT', label: Text(tr('Stock OUT')), icon: const Icon(Icons.north_east_rounded, size: 17)),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => setState(() => type = s.first),
                ),
                const SizedBox(height: 14),
                TextField(controller: cb, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('${U.carton} (${U.cb})'))),
                const SizedBox(height: 12),
                TextField(controller: reason, maxLines: 2, decoration: InputDecoration(labelText: tr('Reason *'), hintText: 'e.g. Damaged ${U.carton.toLowerCase()}, QC sample, sales return…')),
                if (isPhonePlatform) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickPhoto(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(tr('Photo')),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _pickPhoto(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: Text(tr('Gallery')),
                    ),
                    if (photo != null) ...[
                      const SizedBox(width: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: FutureBuilder(
                          future: photo!.readAsBytes(),
                          builder: (c, s) => s.hasData
                              ? Image.memory(s.data!, width: 42, height: 42, fit: BoxFit.cover)
                              : const SizedBox(width: 42, height: 42),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 17),
                        onPressed: () => setState(() => photo = null),
                      ),
                    ],
                  ]),
                  Text('Damage/QC proof photo — approver nu record vaste (phone ch save rahegi).',
                      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                ],
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Submitting…' : 'Submit for Approval')),
      ],
    );
  }
}
