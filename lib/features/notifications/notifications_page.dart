import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/unread.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// All notifications. Tapping a notification marks it read AND opens the
/// exact related screen via its server-provided deep link — no manual searching.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final json = await context.read<AuthController>().api.get('/notifications');
    return ((json as Map)['notifications'] as List).cast<Map<String, dynamic>>();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _open(Map<String, dynamic> n) async {
    final api = context.read<AuthController>().api;
    try {
      if (n['is_read'] == 0) Unread.dec(); // instant badge update
      await api.post('/notifications/${n['id']}/read');
    } catch (_) {/* non-blocking */}
    final route = n['route'] as String? ?? '/notifications';
    if (!mounted) return;
    context.go(route);
  }

  Future<void> _readAll() async {
    final api = context.read<AuthController>().api;
    Unread.clear(); // optimistic: badge 0 INSTANTLY, server sync follows
    try {
      await api.post('/notifications/read-all');
    } catch (_) {
      // Fallback for servers without the bulk route (or where /:id/read
      // shadows it): mark every unread notification individually.
      try {
        final items = await _future;
        final unread = items.where((n) => n['is_read'] == 0).toList();
        for (final n in unread) {
          await api.post('/notifications/${n['id']}/read');
        }
      } catch (e) {
        if (mounted) showErr(context, e);
        return;
      }
    }
    Unread.clear();
    if (mounted) {
      _reload();
      showOk(context, 'All notifications marked as read.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        final unread = items.where((n) => n['is_read'] == 0).length;
        return ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            Expanded(
              child: Text('$unread unread · tap any notification to jump straight to the related screen',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
            if (unread > 0)
              TextButton.icon(onPressed: _readAll, icon: const Icon(Icons.done_all_rounded, size: 18), label: Text(tr('Mark all read'))),
          ]),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const EmptyState('No notifications yet', icon: Icons.notifications_none_rounded)
          else
            for (final n in items) ...[
              _NotifTile(n: n, unread: n['is_read'] == 0, onTap: () => _open(n)),
              const SizedBox(height: 8),
            ],
        ]);
      },
    );
  }
}

class _NotifTile extends StatelessWidget {
  final Map<String, dynamic> n;
  final bool unread;
  final VoidCallback onTap;
  const _NotifTile({required this.n, required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = notifColor(n['type'] as String);
    return Card(
      color: unread ? scheme.primaryContainer.withValues(alpha: 0.28) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(11)),
              child: Icon(notifIcon(n['type'] as String), color: color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(n['title'] as String, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600, fontSize: 14)),
                  ),
                  Text(fmtAgo(n['created_at']), style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ]),
                const SizedBox(height: 3),
                Text(n['body'] as String, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 7),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: Text(notifLabel(n['type'] as String), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.open_in_new_rounded, size: 13, color: scheme.primary),
                  const SizedBox(width: 4),
                  Text('Opens ${routeName(n['route'] as String? ?? '')}', style: TextStyle(fontSize: 11.5, color: scheme.primary, fontWeight: FontWeight.w600)),
                ]),
              ]),
            ),
            if (unread)
              Container(width: 9, height: 9, margin: const EdgeInsets.only(top: 5, left: 8), decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle)),
          ]),
        ),
      ),
    );
  }

  static String routeName(String route) {
    if (route.startsWith('/inventory')) return 'Inventory';
    if (route.startsWith('/approvals')) return 'Approvals';
    if (route.startsWith('/production/batches/')) return 'Production details';
    if (route.startsWith('/production')) return 'Production';
    if (route.startsWith('/dispatch/')) return 'Dispatch details';
    if (route.startsWith('/dispatch')) return 'Dispatch';
    if (route.startsWith('/adjustments')) return 'Stock adjustments';
    return 'screen';
  }
}
