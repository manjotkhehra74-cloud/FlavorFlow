import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../core/platform_support.dart';
import '../../ui/widgets.dart';
import '../../ui/windows_widgets.dart';

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
    _tab.addListener(_onTabChanged);
    _focus = int.tryParse(widget.focusId ?? '');
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocus());
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
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
    final tabContent = TabBarView(controller: _tab, children: [
      _PendingList(
        future: _pending,
        focus: _focus,
        cardKeys: _cardKeys,
        onDecided: _reload,
        onRetry: _reload,
      ),
      _HistoryList(future: _history, onRetry: _reload),
    ]);
    if (isWindowsPlatform) {
      return WindowsModuleWorkspace(
        title: 'Stock Adjustments',
        subtitle: 'Review requests and inspect decisions',
        tabs: const [
          WindowsModuleTab('Pending Approval', Icons.pending_actions_outlined),
          WindowsModuleTab('Approval History', Icons.history_rounded),
        ],
        selectedIndex: _tab.index,
        onSelect: (index) => _tab.index = index,
        commandBar: const WindowsCommandStrip(children: [
          Text('Approval decisions are recorded in the audit trail.'),
        ]),
        content: tabContent,
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Row(children: [
          Expanded(
            child: TabBar(
              controller: _tab,
              tabs: [Tab(text: tr('Pending Approval')), Tab(text: tr('Approval History'))],
            ),
          ),
          const SizedBox(width: 16),
          Tooltip(
            message: 'Decisions are recorded in the audit trail',
            child: Icon(Icons.history_edu_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ]),
      ),
      Expanded(child: tabContent),
    ]);
  }
}

class _PendingList extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> future;
  final int? focus;
  final Map<int, GlobalKey> cardKeys;
  final VoidCallback onDecided, onRetry;
  const _PendingList({required this.future, required this.focus, required this.cardKeys, required this.onDecided, required this.onRetry});

  void _inspectWindows(BuildContext context, Map<String, dynamic> a) {
    showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('${a['code'] ?? 'Adjustment'} · Request details'),
      content: SizedBox(width: 560, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, children: [
          for (final field in [
            ('Product', a['product_name']),
            ('Direction', a['adj_type']),
            ('Quantity (${U.cb})', a['qty_cb']),
            ('Reason', a['reason']),
            ('Requested by', a['requested_by_name']),
            ('Requested on', fmtDateTime(a['requested_at'])),
          ]) Padding(padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 130, child: Text(field.$1,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              Expanded(child: SelectableText('${field.$2 ?? '—'}')),
            ]),
          ),
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close')),
        OutlinedButton(onPressed: () {
          Navigator.pop(dialogContext);
          _reject(context, a, onDecided);
        }, child: Text(tr('Reject'))),
        FilledButton(onPressed: () {
          Navigator.pop(dialogContext);
          _approve(context, a, onDecided);
        }, child: Text(tr('Approve'))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: onRetry);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const EmptyState('No pending adjustments — all caught up 🎉', icon: Icons.fact_check_rounded);
        if (isWindowsPlatform) {
          return ListView(padding: const EdgeInsets.all(12), children: [
            SectionCard(
              title: 'Pending approval (${rows.length})',
              padding: EdgeInsets.zero,
              child: AppDataTable(
                columns: ['Code', 'Product', 'Type', U.cb, 'Reason', 'Requested by', 'Requested on', ''],
                onRowTap: (i) => _inspectWindows(context, rows[i]),
                rows: [for (final a in rows) [
                  Text('${a['code']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  a['product_name'] ?? '—',
                  StatusChip('${a['adj_type']}'),
                  qtyInt(a['qty_cb']),
                  a['reason'] ?? '—',
                  a['requested_by_name'] ?? '—',
                  fmtDateTime(a['requested_at']),
                  TextButton(onPressed: () => _inspectWindows(context, a),
                      child: const Text('Review')),
                ]],
              ),
            ),
          ]);
        }
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
                      Text('${qtyInt(a['qty_cb'])} ${U.cb}',
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
                      label: Text(tr('Reject')),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                      onPressed: () => _approve(context, a, onDecided),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(tr('Approve')),
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
  var submitting = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
        ? StatefulBuilder(builder: (dialogCtx, refresh) => Dialog(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(color: const Color(0xFFE2E9EF), padding: const EdgeInsets.all(18),
                  child: Text('Approve ${a['code']}?',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                Padding(padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${a['product_name']} · ${a['adj_type']} · ${qtyInt(a['qty_cb'])} ${U.cb}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      const Text('Approval updates stock immediately and records the decision.'),
                      const SizedBox(height: 14),
                      TextField(controller: remarks, maxLines: 2,
                        decoration: InputDecoration(labelText: tr('Remarks (optional)'))),
                    ])),
                const Divider(height: 1),
                Padding(padding: const EdgeInsets.all(12), child: Row(
                  mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: submitting ? null : () => Navigator.pop(dialogCtx, false),
                      child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                      onPressed: submitting ? null : () async {
                        refresh(() => submitting = true);
                        try {
                          await dialogCtx.read<AuthController>().api.post(
                            '/adjustments/${a['id']}/approve', {'remarks': remarks.text.trim()});
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                        } catch (e) {
                          if (dialogCtx.mounted) {
                            refresh(() => submitting = false);
                            showErr(dialogCtx, e);
                          }
                        }
                      }, child: Text(submitting ? 'Approving…' : tr('Approve'))),
                  ],
                )),
              ]),
            ),
          ))
        : AlertDialog(
      title: Text('Approve ${a['code']}?'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${a['product_name']} — ${a['adj_type']} ${qtyInt(a['qty_cb'])} ${U.cb}. Stock will be updated immediately.'),
        const SizedBox(height: 14),
        TextField(controller: remarks, maxLines: 2, decoration: InputDecoration(labelText: tr('Remarks (optional)'))),
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
          label: Text(tr('Approve')),
        ),
      ],
    ),
  );
  if (ok == true) { onDone(); if (context.mounted) showOk(context, '${a['code']} approved & stock updated.'); }
}

Future<void> _reject(BuildContext context, Map<String, dynamic> a, VoidCallback onDone) async {
  final reason = TextEditingController();
  final remarks = TextEditingController();
  var submitting = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
        ? StatefulBuilder(builder: (dialogCtx, refresh) => Dialog(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(color: const Color(0xFFE2E9EF), padding: const EdgeInsets.all(18),
                  child: Text('Reject ${a['code']}?',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                Padding(padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${a['product_name']} · ${a['adj_type']} · ${qtyInt(a['qty_cb'])} ${U.cb}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      const Text('Rejection does not change stock; the requester is notified.'),
                      const SizedBox(height: 14),
                      TextField(controller: reason, maxLines: 2, autofocus: true,
                        decoration: InputDecoration(labelText: tr('Reason for rejection *')),
                        onChanged: (_) => refresh(() {})),
                      const SizedBox(height: 12),
                      TextField(controller: remarks, maxLines: 2,
                        decoration: InputDecoration(labelText: tr('Remarks (optional)'))),
                    ])),
                const Divider(height: 1),
                Padding(padding: const EdgeInsets.all(12), child: Row(
                  mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: submitting ? null : () => Navigator.pop(dialogCtx, false),
                      child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                      onPressed: submitting || reason.text.trim().isEmpty ? null : () async {
                        refresh(() => submitting = true);
                        try {
                          await dialogCtx.read<AuthController>().api.post(
                            '/adjustments/${a['id']}/reject',
                            {'reason': reason.text.trim(), 'remarks': remarks.text.trim()});
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                        } catch (e) {
                          if (dialogCtx.mounted) {
                            refresh(() => submitting = false);
                            showErr(dialogCtx, e);
                          }
                        }
                      }, child: Text(submitting ? 'Rejecting…' : tr('Reject'))),
                  ],
                )),
              ]),
            ),
          ))
        : AlertDialog(
      title: Text('Reject ${a['code']}?'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${a['product_name']} — ${a['adj_type']} ${qtyInt(a['qty_cb'])} ${U.cb}. The stock will NOT change and the requester will be notified.'),
        const SizedBox(height: 14),
        TextField(controller: reason, maxLines: 2, decoration: InputDecoration(labelText: tr('Reason for rejection *'))),
        const SizedBox(height: 12),
        TextField(controller: remarks, maxLines: 2, decoration: InputDecoration(labelText: tr('Remarks (optional)'))),
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
          label: Text(tr('Reject')),
        ),
      ],
    ),
  );
  if (ok == true) { onDone(); if (context.mounted) showOk(context, '${a['code']} rejected.'); }
}

class _HistoryList extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> future;
  final VoidCallback onRetry;
  const _HistoryList({required this.future, required this.onRetry});
  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  Map<String, dynamic>? _selected;

  void _inspectWindows(BuildContext context, Map<String, dynamic> a) {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text('${a['code'] ?? 'Adjustment'} · Decision history'),
      content: SizedBox(width: 600, child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final field in [
              ('Product', a['product_name']),
              ('Type', a['adj_type']),
              ('Quantity (${U.cb})', a['qty_cb']),
              ('Reason', a['reason']),
              ('Decision', a['status']),
              ('Approved by', a['approved_by_name']),
              ('Approved on', fmtDateTime(a['approved_at'])),
              ('Rejected by', a['rejected_by_name']),
              ('Rejected on', fmtDateTime(a['rejected_at'])),
              ('Reject reason', a['reject_reason']),
              ('Remarks', a['approval_remarks']),
            ]) Padding(padding: const EdgeInsets.only(bottom: 9),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 145, child: Text(field.$1,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
                Expanded(child: SelectableText('${field.$2 ?? '—'}')),
              ]),
            ),
          ],
        ),
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx),
        child: const Text('Close'))],
    ));
  }

  Widget _decisionDetails(Map<String, dynamic> a) {
    final fields = <(String, String)>[
      ('Code', '${a['code'] ?? '—'}'),
      ('Product / SKU', '${a['product_name'] ?? '—'}'),
      ('IN / OUT', '${a['adj_type'] ?? '—'}'),
      ('Qty (company pack unit)', a['qty_cb'] == null ? '—' : '${a['qty_cb']}'),
      ('Requested By', '${a['requested_by_name'] ?? a['requested_by'] ?? '—'}'),
      ('Requested on', fmtDateTime(a['requested_at'])),
      ('Reason', '${a['reason'] ?? '—'}'),
      ('Decision', '${a['status'] ?? '—'}'),
      ('Decision By', '${a['approved_by_name'] ?? a['rejected_by_name'] ?? '—'}'),
      ('Decision Date', fmtDateTime(a['approved_at'] ?? a['rejected_at'])),
      ('Approved', fmtDateTime(a['approved_at'])),
      ('Rejected', fmtDateTime(a['rejected_at'])),
      ('Reject Reason', '${a['reject_reason'] ?? '—'}'),
      ('Full Reason', '${a['reason'] ?? ''}\n${a['approval_remarks'] ?? ''}'.trim()),
    ];
    return SectionCard(
      title: 'Decision Details',
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final f in fields)
          Padding(padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.$1, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              const SizedBox(height: 2),
              SelectableText(f.$2.isEmpty ? '—' : f.$2, style: const TextStyle(fontSize: 12.5)),
            ])),
        const Divider(height: 16),
        Text('Approval Remarks.', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: widget.future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: widget.onRetry);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const EmptyState('No decisions recorded yet');
        // Approve inspector: first row selected by default on Windows, mirrors concept's blue selection.
        final selected = (_selected != null && rows.any((r) => identical(r, _selected))) ? _selected : (isWindowsPlatform && rows.isNotEmpty ? rows.first : null);
        final table = SectionCard(
          title: 'Approval History',
          padding: EdgeInsets.zero,
          child: AppDataTable(
            columns: ['Code', 'Product / SKU', 'IN / OUT', 'Qty (company pack unit)', 'Requested By', 'Requested on', 'Reason'],
            onRowTap: isWindowsPlatform ? (i) => setState(() => _selected = rows[i]) : (i) => _inspectWindows(context, rows[i]),
            rows: [
              for (final a in rows)
                [
                  Text(a['code'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                  a['product_name'] ?? '—',
                  StatusChip(a['adj_type'] as String? ?? '—'),
                  a['qty_cb'] == null ? '—' : qtyInt(a['qty_cb']),
                  a['requested_by_name'] ?? a['requested_by'] ?? '—',
                  fmtDateTime(a['requested_at']),
                  SizedBox(width: 180, child: Text('${a['reason'] ?? '—'}', maxLines: 2, overflow: TextOverflow.ellipsis)),
                ],
            ],
          ),
        );
        if (isWindowsPlatform) {
          return LayoutBuilder(builder: (context, bounds) {
            final inspector = selected == null ? const SizedBox.shrink() : _decisionDetails(selected);
            if (bounds.maxWidth < 900) {
              return ListView(padding: const EdgeInsets.all(12), children: [table, const SizedBox(height: 12), inspector]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 7, child: ListView(padding: const EdgeInsets.all(12), children: [table])),
              SizedBox(width: 320, child: Padding(padding: const EdgeInsets.fromLTRB(0, 12, 12, 12), child: inspector)),
            ]);
          });
        }
        // Mobile keeps the expanded flat table with all decision columns for small screens.
        return ListView(padding: const EdgeInsets.all(20), children: [
          SectionCard(
            title: 'Decision History & Audit Trail',
            child: AppDataTable(
              columns: ['Code', 'Product', 'Type', U.cb, 'Reason', 'Decision', 'Approved By', 'Approved Date', 'Rejected By', 'Rejected Date', 'Reject Reason', 'Remarks'],
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
