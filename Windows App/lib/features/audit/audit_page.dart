import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/platform_support.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import '../../ui/windows_widgets.dart';

/// Audit Log — every mutating action, with actor, role and timestamp.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  String _entity = '';
  Map<String, dynamic>? _selected;
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
        final table = SectionCard(
          title: 'Audit Trail',
          trailing: Text('${logs.length} ${tr('events')}'),
          padding: EdgeInsets.zero,
          child: logs.isEmpty
              ? const EmptyState('No audit entries')
              : AppDataTable(
                  columns: const ['When', 'User', 'Role', 'Action', 'Entity', 'Ref', 'Details'],
                  rows: [
                    for (final l in logs)
                      [
                        fmtDateTime(l['created_at']),
                        InkWell(
                          onTap: isWindowsPlatform ? () => setState(() => _selected = l) : null,
                          child: Text(l['user_name'] as String? ?? 'system',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        (l['role'] as String? ?? '').replaceAll('_', ' '),
                        StatusChip(l['action'] as String),
                        l['entity'],
                        l['entity_id'],
                        l['details'],
                      ],
                  ],
                ),
        );
        if (isWindowsPlatform) {
          return WindowsDocumentWorkspace(
            title: 'Audit Trail',
            subtitle: 'Immutable record of actions and references',
            icon: Icons.history_rounded,
            commandBar: WindowsCommandStrip(children: [
              for (final e in _entities)
                ChoiceChip(
                  label: Text(e.isEmpty ? tr('All') : tr(e[0].toUpperCase() + e.substring(1))),
                  selected: _entity == e,
                  onSelected: (_) => setState(() { _entity = e; _selected = null; _future = _load(); }),
                ),
            ]),
            content: LayoutBuilder(builder: (context, size) {
              // The inspector is read-only; the audit API does not expose
              // editing or deletion. Discard a stale selection after refresh.
              final selected = logs.any((l) => identical(l, _selected)) ? _selected : null;
              final register = ListView(padding: const EdgeInsets.all(12), children: [table]);
              if (selected == null || size.maxWidth < 1050) return register;
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 7, child: register),
                SizedBox(width: 300, child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                  child: SectionCard(title: 'Event details', child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final field in const [
                        ('created_at', 'When'), ('user_name', 'User'),
                        ('role', 'Role'), ('action', 'Action'),
                        ('entity', 'Entity'), ('entity_id', 'Ref'),
                        ('details', 'Details'),
                      ]) Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(field.$2, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                          SelectableText('${selected[field.$1] ?? '—'}'),
                        ]),
                      ),
                    ],
                  )),
                )),
              ]);
            }),
          );
        }
        return ListView(padding: const EdgeInsets.all(20), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _entities)
              ChoiceChip(
                label: Text(e.isEmpty ? tr('All') : tr(e[0].toUpperCase() + e.substring(1))),
                selected: _entity == e,
                onSelected: (_) => setState(() { _entity = e; _selected = null; _future = _load(); }),
              ),
          ]),
          const SizedBox(height: 16),
          table,
        ]);
      },
    );
  }
}
