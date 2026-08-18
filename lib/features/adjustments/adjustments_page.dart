import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

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
        return ListView(padding: const EdgeInsets.all(20), children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final s in ['', 'PENDING', 'APPROVED', 'REJECTED'])
              ChoiceChip(
                label: Text(s.isEmpty ? tr('All') : tr(s.toLowerCase())),
                selected: _status == s,
                onSelected: (_) => setState(() { _status = s; _future = _load(); }),
              ),
            if (auth.can('adjustments.approve'))
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/approvals'),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text(tr('Approval queue')),
                ),
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
          SectionCard(
            title: 'Adjustment Requests',
            child: rows.isEmpty
                ? const EmptyState('No adjustment requests')
                : AppDataTable(
                    columns: ['Code', 'Product', 'Type', U.cb, 'Reason', 'Status', 'Requested By', 'Requested On', 'Decision'],
                    rows: [
                      for (final a in rows)
                        [
                          Text(a['code'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                          a['product_name'],
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
          ),
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
        products = ((json as Map)['products'] as List).cast<Map<String, dynamic>>();
        productId = products.isNotEmpty ? products.first['id'] as int : null;
      });
    }).catchError((e) { if (mounted) showErr(context, e); });
  }

  Map<String, dynamic>? get _product => productId == null ? null : products.firstWhere((p) => p['id'] == productId, orElse: () => products.first);

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.post('/adjustments', {
        'productId': productId,
        'adjType': type,
        'qtyCb': int.tryParse(cb.text) ?? 0,
        'reason': reason.text.trim() + (photo != null ? ' [photo attached]' : ''),
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
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(tr('Request Stock Adjustment')),
      content: SizedBox(
        width: 420,
        child: products.isEmpty
            ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                DropdownButtonFormField<int>(
                  initialValue: productId,
                  decoration: InputDecoration(labelText: tr('Product *')),
                  items: [for (final p in products) DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String))],
                  onChanged: (v) => setState(() => productId = v),
                ),
                if (_product != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('In stock: ${qtyInt(_product!['qty_cb'])} CB${(_product!['qty_trays'] as num? ?? 0) > 0 ? ' + ${qtyInt(_product!['qty_trays'])} trays' : ''}',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                  ),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'IN', label: Text(tr('Stock IN')), icon: Icon(Icons.south_west_rounded, size: 17)),
                    ButtonSegment(value: 'OUT', label: Text(tr('Stock OUT')), icon: Icon(Icons.north_east_rounded, size: 17)),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => setState(() => type = s.first),
                ),
                const SizedBox(height: 14),
                TextField(controller: cb, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('${U.carton} (${U.cb})'))),
                const SizedBox(height: 12),
                TextField(controller: reason, maxLines: 2, decoration: InputDecoration(labelText: tr('Reason *'), hintText: 'e.g. Damaged cartons, QC sample, sales return…')),
                if (!kIsWeb) ...[
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
                        child: Image.file(File(photo!.path), width: 42, height: 42, fit: BoxFit.cover),
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
