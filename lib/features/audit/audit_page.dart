import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// Audit Log — every mutating action, with actor, role and timestamp.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  String _entity = '';
  late Future<List<Map<String, dynamic>>> _future;

  static const _entities = ['', 'adjustment', 'dispatch', 'batch', 'user', 'product', 'inventory', 'packing', 'report', 'system'];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final q = _entity.isEmpty ? '' : '?entity=$_entity';
    final json = await context.read<AuthController>().api.get('/audit$q');
    return ((json as Map)['logs'] as List).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: () => setState(() => _future = _load()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final logs = snap.data!;
        return ListView(padding: const EdgeInsets.all(20), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _entities)
              ChoiceChip(
                label: Text(e.isEmpty ? 'All' : e[0].toUpperCase() + e.substring(1)),
                selected: _entity == e,
                onSelected: (_) => setState(() { _entity = e; _future = _load(); }),
              ),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Audit Trail',
            child: logs.isEmpty
                ? const EmptyState('No audit entries')
                : AppDataTable(
                    columns: const ['When', 'User', 'Role', 'Action', 'Entity', 'Ref', 'Details'],
                    rows: [
                      for (final l in logs)
                        [
                          fmtDateTime(l['created_at']),
                          Text(l['user_name'] as String? ?? 'system', style: const TextStyle(fontWeight: FontWeight.w600)),
                          (l['role'] as String? ?? '').replaceAll('_', ' '),
                          StatusChip(l['action'] as String),
                          l['entity'],
                          l['entity_id'],
                          l['details'],
                        ],
                    ],
                  ),
          ),
        ]);
      },
    );
  }
}
