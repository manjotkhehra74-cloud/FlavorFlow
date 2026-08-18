import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// Production batch detail — deep link target of "Production Completed" notifications.
class ProductionDetailPage extends StatefulWidget {
  final int id;
  const ProductionDetailPage({super.key, required this.id});
  @override
  State<ProductionDetailPage> createState() => _ProductionDetailPageState();
}

class _ProductionDetailPageState extends State<ProductionDetailPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final json = await context.read<AuthController>().api.get('/production/batches/${widget.id}');
    return ((json as Map)['batch'] as Map).cast<String, dynamic>();
  }

  void _reload() => setState(() => _future = _load());

  void _back() {
    if (context.canPop()) { context.pop(); } else { context.go('/production'); }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final b = snap.data!;
        final scheme = Theme.of(context).colorScheme;
        final auth = context.watch<AuthController>();
        final progress = (b['planned_cb'] as num) == 0 ? 0.0 : ((b['produced_cb'] as num) / (b['planned_cb'] as num)).clamp(0.0, 1.0);
        return ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back_rounded)),
            const SizedBox(width: 4),
            Text(b['code'] as String, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            const SizedBox(width: 12),
            StatusChip(b['status'] as String),
            const Spacer(),
            if (auth.can('production.execute') && b['status'] == 'PLANNED')
              FilledButton.icon(
                onPressed: () async {
                  try {
                    await context.read<AuthController>().api.post('/production/batches/${b['id']}/start');
                    _reload();
                  } catch (e) { if (context.mounted) showErr(context, e); }
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(tr('Start Batch')),
              ),
            if (auth.can('production.execute') && b['status'] == 'IN_PROGRESS')
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                onPressed: _back,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(tr('Complete from board')),
              ),
          ]),
          const SizedBox(height: 18),
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth > 860;
            final left = SectionCard(title: 'Batch', child: Column(children: [
              _row('Product', b['product_name'] as String),
              _row('Planned quantity', '${qtyInt(b['planned_cb'])} CB (${qty((b['planned_cb'] as num) * (b['weight_per_cb'] as num))} kg)'),
              _row('Produced quantity', (b['produced_trays'] as num? ?? 0) > 0
                  ? '${qtyInt(b['produced_cb'])} CB + ${qtyInt(b['produced_trays'])} trays'
                  : '${qtyInt(b['produced_cb'])} CB'),
              _row('Planned date', b['planned_date'] == null ? '—' : fmtDateWithDay(b['planned_date'])),
              if ((b['remarks'] as String?)?.isNotEmpty ?? false) _row('Remarks', b['remarks'] as String),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: scheme.surfaceContainerHighest),
              ),
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerRight, child: Text('${(progress * 100).toStringAsFixed(0)}% complete', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
            ]));
            final right = SectionCard(title: 'Activity & Ownership', child: Column(children: [
              _row('Created by', '${b['created_by_name'] ?? '—'} · ${fmtDateTime(b['created_at'])}'),
              _row('Started by', b['started_by_name'] == null ? 'Not started' : '${b['started_by_name']} · ${fmtDateTime(b['started_at'])}'),
              _row('Completed by', b['completed_by_name'] == null ? 'Not completed' : '${b['completed_by_name']} · ${fmtDateTime(b['completed_at'])}'),
              const Divider(height: 26),
              Row(children: [
                Icon(Icons.info_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text('Completing a batch adds produced CB directly into finished-goods inventory and notifies store and dispatch teams.',
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant))),
              ]),
            ]));
            if (wide) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: left), const SizedBox(width: 16), Expanded(child: right)]);
            }
            return Column(children: [left, const SizedBox(height: 16), right]);
          }),
        ]);
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 150, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
      ]),
    );
  }
}
