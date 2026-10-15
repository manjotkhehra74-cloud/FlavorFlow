import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/offline_queue.dart';
import '../../core/platform_support.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../../ui/windows_widgets.dart';

/// Offline entries kept on this device (MAN-13): what is waiting to sync, what
/// the server did not accept (needs review), and what already synced.
/// Opened from the status banner or from Settings → Offline entries.
class SyncPage extends StatelessWidget {
  const SyncPage({super.key});

  String _stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _count(String label, int n, Color c) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$n', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
          Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _header(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Future<void> _confirmDiscard(BuildContext context, QueuedEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this entry?'),
        content: Text('${e.label}${e.summary.isEmpty ? '' : ' · ${e.summary}'} will be removed from this device and will NOT be saved on the server.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok == true) await OfflineQueue.instance.discard(e);
  }

  Widget _entryTile(BuildContext context, QueuedEntry e) {
    final scheme = Theme.of(context).colorScheme;
    final q = OfflineQueue.instance;
    final color = switch (e.state) {
      SyncState.pending => AppColors.blue,
      SyncState.failed => AppColors.red,
      SyncState.synced => AppColors.green,
    };
    final icon = switch (e.state) {
      SyncState.pending => Icons.schedule_rounded,
      SyncState.failed => Icons.error_outline_rounded,
      SyncState.synced => Icons.check_circle_outline_rounded,
    };
    final parts = <String>[
      if (e.summary.isNotEmpty) e.summary,
      _stamp(e.syncedAt ?? e.createdAt),
      if (e.state == SyncState.pending && e.attempts > 0) 'try ${e.attempts}',
      if (e.serverRef != null) 'server: ${e.serverRef}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(e.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
            if (e.state == SyncState.failed) ...[
              TextButton(onPressed: () => q.retry(e), child: const Text('Retry')),
              IconButton(
                tooltip: 'Discard',
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                onPressed: () => _confirmDiscard(context, e),
              ),
            ],
          ]),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(parts.join(' · '), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
          if (e.lastError != null && e.state != SyncState.synced) ...[
            const SizedBox(height: 4),
            Text(
              e.lastError!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: e.state == SyncState.failed ? AppColors.red : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OfflineQueue.instance,
      builder: (context, _) {
        final q = OfflineQueue.instance;
        final scheme = Theme.of(context).colorScheme;
        final pending = q.pending;
        final failed = q.failed;
        final synced = q.synced.take(10).toList();
        if (isWindowsPlatform) {
          Widget register(String title, List<QueuedEntry> entries) => SectionCard(
                title: '$title (${entries.length})',
                padding: EdgeInsets.zero,
                child: entries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('No entries in this section.', style: TextStyle(color: scheme.onSurfaceVariant)),
                      )
                    : AppDataTable(
                        columns: const ['Entry', 'Details', 'Created / synced', 'Attempts', 'Server reference', ''],
                        rows: [
                          for (final e in entries)
                            [
                              Text(e.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                              SizedBox(width: 180, child: Text(e.summary.isEmpty ? '—' : e.summary, maxLines: 2, overflow: TextOverflow.ellipsis)),
                              _stamp(e.syncedAt ?? e.createdAt),
                              e.attempts,
                              e.serverRef ?? '—',
                              e.state == SyncState.failed
                                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                                      TextButton(onPressed: () => q.retry(e), child: Text(tr('Retry'))),
                                      IconButton(tooltip: tr('Discard'), icon: const Icon(Icons.delete_outline_rounded, size: 18), onPressed: () => _confirmDiscard(context, e)),
                                    ])
                                  : Text(e.state == SyncState.pending ? tr('Waiting') : tr('Synced')),
                            ],
                        ],
                      ),
              );

          return WindowsDocumentWorkspace(
            title: 'Offline Entries',
            subtitle: q.online ? 'Connected · ${pending.length} waiting · ${failed.length} needs review' : 'Offline · entries are saved locally on this device',
            icon: Icons.cloud_sync_outlined,
            commandBar: WindowsCommandStrip(children: [
              Icon(q.online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, size: 17, color: q.online ? AppColors.green : AppColors.amber),
              Text(q.online ? tr('Online') : tr('Offline'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              FilledButton.icon(onPressed: () => q.syncNow(), icon: const Icon(Icons.sync_rounded, size: 16), label: Text(tr('Sync now'))),
            ]),
            content: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1160;
              return ListView(padding: const EdgeInsets.all(14), children: [
                Row(children: [
                  Expanded(child: KpiCard(label: 'Waiting', value: '${pending.length}', icon: Icons.schedule_rounded, tint: AppColors.blue)),
                  const SizedBox(width: 9),
                  Expanded(child: KpiCard(label: 'Needs review', value: '${failed.length}', icon: Icons.error_outline_rounded, tint: AppColors.red)),
                  const SizedBox(width: 9),
                  Expanded(child: KpiCard(label: 'Synced', value: '${q.synced.length}', icon: Icons.check_circle_outline_rounded, tint: AppColors.green)),
                ]),
                const SizedBox(height: 12),
                if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: register('Waiting to sync', pending)),
                    const SizedBox(width: 12),
                    Expanded(child: register('Needs review', failed)),
                  ])
                else ...[
                  register('Waiting to sync', pending),
                  const SizedBox(height: 10),
                  register('Needs review', failed),
                ],
                const SizedBox(height: 10),
                register('Synced (latest 10)', synced),
                const SizedBox(height: 8),
                Text(
                  'Entries remain on this device until accepted. Each entry is sent once; the server ignores a repeat. Review rejected entries before retrying or discarding them.',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ]);
            }),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: scheme.outlineVariant)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(q.online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: q.online ? AppColors.green : AppColors.amber),
                    const SizedBox(width: 8),
                    Text(q.online ? 'Online' : 'Offline', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Entries are saved on this device and sent automatically when the server is reachable. Each entry is sent once — the server ignores a repeat.',
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    _count('Waiting', pending.length, AppColors.blue),
                    _count('Needs review', failed.length, AppColors.red),
                    _count('Synced', q.synced.length, AppColors.green),
                  ]),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => q.syncNow(),
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('Sync now'),
                  ),
                ]),
              ),
            ),
            if (pending.isNotEmpty) ...[
              _header(context, 'WAITING TO SYNC'),
              for (final e in pending) _entryTile(context, e),
            ],
            if (failed.isNotEmpty) ...[
              _header(context, 'NEEDS REVIEW — the server did not accept these'),
              for (final e in failed) _entryTile(context, e),
            ],
            if (synced.isNotEmpty) ...[
              _header(context, 'SYNCED (LATEST)'),
              for (final e in synced) _entryTile(context, e),
            ],
            if (q.entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(child: Text('No offline entries on this device.', style: TextStyle(color: scheme.onSurfaceVariant))),
              ),
          ],
        );
      },
    );
  }
}
