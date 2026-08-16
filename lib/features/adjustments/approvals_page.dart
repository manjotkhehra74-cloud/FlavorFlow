import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// Pending Approval screen — complete authorization workflow:
/// approve / reject (with mandatory reason), remarks, full decision history
/// (approved by/date · rejected by/date) and audit references.
class ApprovalsPage extends StatefulWidget {
  final String? focusId;
  const ApprovalsPage({super.key, this.focusId});
  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  late Future<List<Map<String, dynamic>>> _pending;
  late Future<List<Map<String, dynamic>>> _history;
  final Map<int, GlobalKey> _cardKeys = {};
  int? _focus;

  @override
  void initState() {
    super.initState();
    _focus = int.tryParse(widget.focusId ?? '');
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocus());
  }

  void _load() {
    final api = context.read<AuthController>().api;
    _pending = api.get('/adjustments/pending').then((j) => ((j as Map)['adjustments'] as List).cast<Map<String, dynamic>>());
    _history = api.get('/adjustments/history').then((j) => ((j as Map)['adjustments'] as List).cast<Map<String, dynamic>>());
  }

  void _reload() => setState(_load);

  void _scrollToFocus() {
    if (_focus == null) return;
    final key = _cardKeys[_focus];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(key!.currentContext!, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Row(children: [
          Expanded(
            child: TabBar(
              controller: _tab,
              tabs: const [Tab(text: 'Pending Approval'), Tab(text: 'Approval History')],
            ),
          ),
          const SizedBox(width: 16),
          Tooltip(
            message: 'Decisions are recorded in the audit trail',
            child: Icon(Icons.history_edu_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ]),
      ),
      Expanded(
        child: TabBarView(controller: _tab, children: [
          _PendingList(
            future: _pending,
            focus: _focus,
            cardKeys: _cardKeys,
            onDecided: _reload,
            onRetry: _reload,
          ),
          _HistoryList(future: _history, onRetry: _reload),
        ]),
      ),
    ]);
  }
}

class _PendingList extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> future;
  final int? focus;
  final Map<int, GlobalKey> cardKeys;
  final VoidCallback onDecided, onRetry;
  const _PendingList({required this.future, required this.focus, required this.cardKeys, required this.onDecided, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: onRetry);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const EmptyState('No pending adjustments — all caught up 🎉', icon: Icons.fact_check_rounded);
        final scheme = Theme.of(context).colorScheme;
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final a = rows[i];
            final id = a['id'] as int;
            final isOut = a['adj_type'] == 'OUT';
            final focused = focus == id;
            final key = cardKeys.putIfAbsent(id, () => GlobalKey());
            return Padding(
              key: key,
              padding: const EdgeInsets.only(bottom: 14),
              child: SectionCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: (isOut ? AppColors.red : AppColors.green).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(isOut ? Icons.north_east_rounded : Icons.south_west_rounded, color: isOut ? AppColors.red : AppColors.green),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(a['code'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          const SizedBox(width: 8),
                          StatusChip(a['adj_type'] as String),
                          if (focused) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(6)),
                              child: Text('from notification', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 3),
                        Text(a['product_name'] as String, style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${qtyInt(a['qty_cb'])} CB',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(fmtAgo(a['requested_at']), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(10)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Reason', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 3),
                      Text(a['reason'] as String, style: const TextStyle(fontSize: 13.5)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.person_outline_rounded, size: 15, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 5),
                        Text('${a['requested_by_name']} · ${fmtDateTime(a['requested_at'])}',
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
                      onPressed: () => _reject(context, a, onDecided),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Reject'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                      onPressed: () => _approve(context, a, onDecided),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approve'),
                    ),
                  ]),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}

Future<void> _approve(BuildContext context, Map<String, dynamic> a, VoidCallback onDone) async {
  final remarks = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text('Approve ${a['code']}?'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${a['product_name']} — ${a['adj_type']} ${qtyInt(a['qty_cb'])} CB. Stock will be updated immediately.'),
        const SizedBox(height: 14),
        TextField(controller: remarks, maxLines: 2, decoration: const InputDecoration(labelText: 'Remarks (optional)')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.green),
          onPressed: () async {
            try {
              await dialogCtx.read<AuthController>().api.post('/adjustments/${a['id']}/approve', {'remarks': remarks.text.trim()});
              if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
            } catch (e) {
              if (dialogCtx.mounted) showErr(dialogCtx, e);
            }
          },
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Approve'),
        ),
      ],
    ),
  );
  if (ok == true) { onDone(); if (context.mounted) showOk(context, '${a['code']} approved & stock updated.'); }
}

Future<void> _reject(BuildContext context, Map<String, dynamic> a, VoidCallback onDone) async {
  final reason = TextEditingController();
  final remarks = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text('Reject ${a['code']}?'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${a['product_name']} — ${a['adj_type']} ${qtyInt(a['qty_cb'])} CB. The stock will NOT change and the requester will be notified.'),
        const SizedBox(height: 14),
        TextField(controller: reason, maxLines: 2, decoration: const InputDecoration(labelText: 'Reason for rejection *')),
        const SizedBox(height: 12),
        TextField(controller: remarks, maxLines: 2, decoration: const InputDecoration(labelText: 'Remarks (optional)')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () async {
            if (reason.text.trim().isEmpty) {
              showErr(dialogCtx, 'A rejection reason is required.');
              return;
            }
            try {
              await dialogCtx.read<AuthController>().api.post('/adjustments/${a['id']}/reject',
                  {'reason': reason.text.trim(), 'remarks': remarks.text.trim()});
              if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
            } catch (e) {
              if (dialogCtx.mounted) showErr(dialogCtx, e);
            }
          },
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Reject'),
        ),
      ],
    ),
  );
  if (ok == true) { onDone(); if (context.mounted) showOk(context, '${a['code']} rejected.'); }
}

class _HistoryList extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> future;
  final VoidCallback onRetry;
  const _HistoryList({required this.future, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: onRetry);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const EmptyState('No decisions recorded yet');
        return ListView(padding: const EdgeInsets.all(20), children: [
          SectionCard(
            title: 'Decision History & Audit Trail',
            child: AppDataTable(
              columns: const ['Code', 'Product', 'Type', 'CB', 'Reason', 'Decision', 'Approved By', 'Approved Date', 'Rejected By', 'Rejected Date', 'Reject Reason', 'Remarks'],
              rows: [
                for (final a in rows)
                  [
                    Text(a['code'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                    a['product_name'],
                    StatusChip(a['adj_type'] as String),
                    qtyInt(a['qty_cb']),
                    a['reason'],
                    StatusChip(a['status'] as String),
                    a['approved_by_name'] ?? '—',
                    fmtDateTime(a['approved_at']),
                    a['rejected_by_name'] ?? '—',
                    fmtDateTime(a['rejected_at']),
                    a['reject_reason'] ?? '—',
                    a['approval_remarks'] ?? '—',
                  ],
              ],
            ),
          ),
        ]);
      },
    );
  }
}
