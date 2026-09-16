import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import 'leaves_models.dart';

/// Leaves — Phase 3. Balance per type → (managers) team approvals →
/// my requests with status filter. "Apply" opens a bottom-sheet form that
/// POSTs `leaves`. Server decides balance / overlap / policy; the app only
/// shows what comes back (ARCHITECTURE.md §6).
class LeavesPage extends StatefulWidget {
  const LeavesPage({super.key});
  @override
  State<LeavesPage> createState() => _LeavesPageState();
}

class _LeavesPageState extends State<LeavesPage> {
  Cached<List<LeaveTypeBalance>>? _balances;
  Cached<List<LeaveRequest>>? _mine;
  List<LeaveRequest> _team = const [];
  Object? _error;
  bool _loading = true;
  String _filter = 'all'; // all | pending | approved | rejected
  final Set<String> _acting = {}; // request ids with an approve/reject in flight

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    final api = auth.api;
    Object? err;
    Cached<List<LeaveRequest>>? mine;
    Cached<List<LeaveTypeBalance>>? balances;
    try {
      mine = await cachedFetch('leaves:mine', () => api.get('/leaves'), LeaveRequest.listFromJson);
    } catch (e) {
      err = e;
    }
    try {
      balances = await cachedFetch('leaves/balance', () => api.get('/leaves/balance'), LeaveTypeBalance.listFromJson);
    } catch (_) {}
    var team = _team;
    if (auth.user?.isManager ?? false) {
      try {
        final json = await api.get('/leaves', query: {'scope': 'team', 'status': 'pending'});
        team = LeaveRequest.listFromJson(json);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _mine = mine ?? _mine;
      _balances = balances ?? _balances;
      _team = team;
      _error = mine == null ? err : null;
      _loading = false;
    });
  }

  Future<void> _apply() async {
    final types = _balances?.data ?? const <LeaveTypeBalance>[];
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ApplyLeaveSheet(types: types),
    );
    if (created != true || !mounted) return;
    showOk(context, tr('Leave request submitted'));
    await _load();
  }

  Future<void> _decide(LeaveRequest r, bool approve) async {
    String? note;
    if (!approve) {
      note = await _askReason();
      if (note == null || !mounted) return;
    }
    setState(() => _acting.add(r.id));
    final api = context.read<AuthController>().api;
    try {
      if (approve) {
        await api.post('/leaves/${r.id}/approve');
      } else {
        await api.post('/leaves/${r.id}/reject', {'reason': note ?? ''});
      }
      if (!mounted) return;
      showOk(context, approve ? tr('Leave approved') : tr('Leave rejected'));
      await _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _acting.remove(r.id));
    }
  }

  Future<String?> _askReason() {
    final ctl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Reason for rejection')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: tr('Reason')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: HrBrand.red),
            onPressed: () => Navigator.pop(c, ctl.text.trim()),
            child: Text(tr('Reject')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<L10n>();
    final isManager = context.watch<AuthController>().user?.isManager ?? false;
    final Widget body;
    if (_loading) {
      body = const LoadingView();
    } else if (_mine == null) {
      body = ErrorRetryView(error: _error ?? tr('Something went wrong'), onRetry: _load);
    } else {
      body = _content(context, isManager);
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('Leaves'))),
      body: body,
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              backgroundColor: HrBrand.blue,
              foregroundColor: Colors.white,
              onPressed: _apply,
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('Apply for leave')),
            ),
    );
  }

  Widget _content(BuildContext context, bool isManager) {
    final t = Theme.of(context).textTheme;
    final all = _mine?.data ?? const <LeaveRequest>[];
    final shown = _filter == 'all' ? all : all.where((r) => r.status == _filter).toList();
    final offlineSince = _mine?.staleSince ?? _balances?.staleSince;
    final balances = _balances?.data ?? const <LeaveTypeBalance>[];
    final pendingCount = all.where((r) => r.pending).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          if (offlineSince != null) ...[
            Align(alignment: Alignment.centerLeft, child: OfflineChip(since: offlineSince)),
            const SizedBox(height: 10),
          ],
          // ---- balance per type ----
          Text(tr('Leave balance'), style: t.titleMedium),
          const SizedBox(height: 10),
          if (balances.isEmpty)
            HrCard(child: Text(tr('No leave balance set up yet'), style: t.bodyMedium))
          else
            SizedBox(
              height: 116,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: balances.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _BalanceCard(balance: balances[i]),
              ),
            ),
          if (pendingCount > 0) ...[
            const SizedBox(height: 8),
            Text(tr('%s request(s) awaiting approval').arg(pendingCount), style: t.bodySmall),
          ],
          // ---- manager: team approvals ----
          if (isManager) ...[
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: Text(tr('Team approvals'), style: t.titleMedium)),
              if (_team.isNotEmpty) StatusPill.warning('${_team.length}'),
            ]),
            const SizedBox(height: 10),
            if (_team.isEmpty)
              HrCard(
                child: Row(children: [
                  const Icon(Icons.task_alt_rounded, color: HrBrand.green),
                  const SizedBox(width: 12),
                  Expanded(child: Text(tr('No pending approvals'), style: t.bodyMedium)),
                ]),
              )
            else
              for (final r in _team) ...[
                _LeaveCard(
                  request: r,
                  showEmployee: true,
                  busy: _acting.contains(r.id),
                  onApprove: () => _decide(r, true),
                  onReject: () => _decide(r, false),
                ),
                const SizedBox(height: 10),
              ],
          ],
          // ---- my requests ----
          const SizedBox(height: 20),
          Text(tr('My requests'), style: t.titleMedium),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final f in const ['all', 'pending', 'approved', 'rejected']) ...[
                ChoiceChip(
                  label: Text(tr(_filterLabel(f))),
                  selectedColor: HrBrand.blueContainer,
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
                const SizedBox(width: 8),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            HrCard(
              child: Row(children: [
                const Icon(Icons.event_note_outlined, color: HrBrand.subInk),
                const SizedBox(width: 12),
                Expanded(child: Text(all.isEmpty ? tr('No leave requests yet') : tr('Nothing here'), style: t.bodyMedium)),
              ]),
            )
          else
            for (final r in shown) ...[
              _LeaveCard(request: r, showEmployee: false, busy: false),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  static String _filterLabel(String f) {
    switch (f) {
      case 'pending':
        return 'Pending';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return 'All';
    }
  }
}

StatusPill _statusPill(String status) {
  switch (status) {
    case 'approved':
      return StatusPill.success(tr('Approved'));
    case 'rejected':
      return StatusPill.danger(tr('Rejected'));
    case 'cancelled':
      return StatusPill.info(tr('Cancelled'));
    default:
      return StatusPill.warning(tr('Pending'));
  }
}

class _BalanceCard extends StatelessWidget {
  final LeaveTypeBalance balance;
  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final b = balance;
    final ratio = b.total <= 0 ? 0.0 : (b.available / b.total).clamp(0.0, 1.0).toDouble();
    return HrCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: SizedBox(
        width: 150,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(b.name, style: t.labelLarge?.copyWith(color: HrBrand.subInk), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(Fmt.compact(b.available), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(width: 4),
            Text(tr('of %s').arg(Fmt.compact(b.total)), style: t.bodySmall),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: ratio, minHeight: 6, backgroundColor: HrBrand.blueContainer, color: HrBrand.blue),
          ),
        ]),
      ),
    );
  }
}

class _LeaveCard extends StatelessWidget {
  final LeaveRequest request;
  final bool showEmployee;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  const _LeaveCard({required this.request, required this.showEmployee, required this.busy, this.onApprove, this.onReject});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = request;
    final days = r.halfDay ? tr('Half day') : tr('%s day(s)').arg(Fmt.compact(r.days));
    return HrCard(
      onTap: () => _showDetail(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: HrBrand.blueContainer, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(r.code, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: HrBrand.blueDeep)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(showEmployee ? (r.employeeName ?? r.employeeCode ?? r.typeName) : r.typeName, style: t.titleMedium),
              const SizedBox(height: 2),
              Text(showEmployee ? '${r.typeName} · ${r.dateLabel} · $days' : '${r.dateLabel} · $days', style: t.bodySmall),
            ]),
          ),
          const SizedBox(width: 8),
          _statusPill(r.status),
        ]),
        if (r.reason.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(r.reason, style: t.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        if (onApprove != null && r.pending) ...[
          const SizedBox(height: 12),
          if (busy)
            const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2)))
          else
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), foregroundColor: HrBrand.red),
                  onPressed: onReject,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(tr('Reject')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44), backgroundColor: HrBrand.green),
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(tr('Approve')),
                ),
              ),
            ]),
        ],
      ]),
    );
  }

  void _showDetail(BuildContext context) {
    final r = request;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) {
        final t = Theme.of(c).textTheme;
        Widget row(String label, String value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 110, child: Text(label, style: t.bodySmall)),
                Expanded(child: Text(value, style: t.bodyMedium)),
              ]),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(r.typeName, style: t.titleLarge)),
              _statusPill(r.status),
            ]),
            const SizedBox(height: 12),
            if (r.employeeName != null) row(tr('Employee'), '${r.employeeName}${r.employeeCode == null ? '' : ' · ${r.employeeCode}'}'),
            row(tr('Dates'), r.dateLabel),
            row(tr('Days'), r.halfDay ? tr('Half day') : Fmt.compact(r.days)),
            if (r.reason.isNotEmpty) row(tr('Reason'), r.reason),
            if (r.appliedAt != null) row(tr('Applied'), '${Fmt.date(r.appliedAt)} · ${Fmt.time(r.appliedAt)}'),
            if (r.decidedBy != null && r.decidedBy!.isNotEmpty) row(tr('Decided by'), r.decidedBy!),
            if (r.decidedAt != null) row(tr('Decided on'), Fmt.date(r.decidedAt)),
            if (r.decisionNote != null && r.decisionNote!.isNotEmpty) row(tr('Note'), r.decisionNote!),
          ]),
        );
      },
    );
  }
}

/// Apply form — bottom sheet. Validates only what the server would reject
/// anyway (type, dates, reason); balance/overlap/policy errors come back as
/// VALIDATION / CONFLICT and are shown verbatim.
class _ApplyLeaveSheet extends StatefulWidget {
  final List<LeaveTypeBalance> types;
  const _ApplyLeaveSheet({required this.types});
  @override
  State<_ApplyLeaveSheet> createState() => _ApplyLeaveSheetState();
}

class _ApplyLeaveSheetState extends State<_ApplyLeaveSheet> {
  String? _type;
  DateTime? _from;
  DateTime? _to;
  bool _halfDay = false;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.types.length == 1) _type = widget.types.first.type;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  double get _days {
    final f = _from, t = _to;
    if (f == null || t == null) return 0;
    if (_halfDay) return 0.5;
    return t.difference(f).inDays + 1.0;
  }

  Future<void> _pick(bool from) async {
    final now = DateTime.now();
    final initial = (from ? _from : _to) ?? (from ? now : (_from ?? now));
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (d == null || !mounted) return;
    setState(() {
      if (from) {
        _from = DateTime(d.year, d.month, d.day);
        if (_to == null || _to!.isBefore(_from!)) _to = _from;
      } else {
        _to = DateTime(d.year, d.month, d.day);
        if (_from == null || _from!.isAfter(_to!)) _from = _to;
      }
      if (_from != _to) _halfDay = false;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final type = _type, from = _from, to = _to;
    String? problem;
    if (type == null && widget.types.isNotEmpty) {
      problem = tr('Select a leave type');
    } else if (from == null || to == null) {
      problem = tr('Select dates');
    } else if (_reason.text.trim().isEmpty) {
      problem = tr('Please enter a reason');
    }
    if (problem != null || from == null || to == null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<AuthController>().api;
    try {
      await api.post('/leaves', {
        'type': type ?? '',
        'from': Fmt.iso(from),
        'to': Fmt.iso(to),
        'halfDay': _halfDay,
        'reason': _reason.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final selected = widget.types.where((b) => b.type == _type).toList();
    final sameDay = _from != null && _to != null && _from == _to;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Apply for leave'), style: t.titleLarge),
          const SizedBox(height: 16),
          if (widget.types.isNotEmpty) ...[
            Text(tr('Leave type'), style: t.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in widget.types)
                ChoiceChip(
                  label: Text('${b.code} · ${Fmt.compact(b.available)}'),
                  selectedColor: HrBrand.blueContainer,
                  selected: _type == b.type,
                  onSelected: (_) => setState(() {
                    _type = b.type;
                    _error = null;
                  }),
                ),
            ]),
            if (selected.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('${selected.first.name} · ${tr('%s available').arg(Fmt.compact(selected.first.available))}', style: t.bodySmall),
            ],
            const SizedBox(height: 16),
          ],
          Row(children: [
            Expanded(child: _DateField(label: tr('From'), value: _from, onTap: () => _pick(true))),
            const SizedBox(width: 10),
            Expanded(child: _DateField(label: tr('To'), value: _to, onTap: () => _pick(false))),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Half day'), style: t.bodyMedium),
            subtitle: sameDay ? null : Text(tr('Only for a single day'), style: t.bodySmall),
            value: _halfDay,
            onChanged: sameDay ? (v) => setState(() => _halfDay = v) : null,
          ),
          TextField(
            controller: _reason,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Reason'), alignLabelWithHint: true),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(_error!, style: t.bodySmall?.copyWith(color: HrBrand.red)),
            const SizedBox(height: 8),
          ],
          Row(children: [
            Expanded(child: Text(_days > 0 ? tr('%s day(s)').arg(Fmt.compact(_days)) : '', style: t.titleMedium)),
            SizedBox(
              width: 160,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(tr('Submit')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  const _DateField({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(HrBrand.radiusInput),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18)),
        child: Text(value == null ? tr('Select') : Fmt.date(value), style: t.bodyLarge),
      ),
    );
  }
}
