import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/hrmate.dart';
import '../../core/i18n.dart';
import '../../core/open_url.dart';
import '../../core/theme.dart';

/// Dashboard strip: today's head-count from HRMate (present / absent / on
/// leave / late) — read-only, refreshed with the dashboard. Renders NOTHING
/// when HRMate is not connected on this device or did not answer, so the
/// ERP never looks broken because of the HR server.
class HrPresenceStrip extends StatefulWidget {
  const HrPresenceStrip({super.key});
  @override
  State<HrPresenceStrip> createState() => _HrPresenceStripState();
}

class _HrPresenceStripState extends State<HrPresenceStrip> {
  bool _waiting = false;
  String _askedFor = ''; // base|token the last request was made with

  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void didUpdateWidget(covariant HrPresenceStrip old) {
    super.didUpdateWidget(old);
    _ask(); // dashboard rebuilt (pull-to-refresh) → cached ≤3 min, else refetch
  }

  /// Ask HRMate (cached ≤3 min, deduped while in flight, 45 s back-off after
  /// a failure). Called from initState/didUpdateWidget and again from build
  /// when the connection settings changed — safe: it never calls setState
  /// synchronously, only after the future completes (post-frame).
  void _ask() {
    final hr = HrMate.instance;
    if (!hr.configured) return;
    final key = '${hr.base}|${hr.token}';
    if (_waiting && key == _askedFor) return;
    _askedFor = key;
    _waiting = true;
    hr.summary().whenComplete(() {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _waiting = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final hr = context.watch<HrMate>();
    if (!hr.configured) return const SizedBox.shrink();
    // Connected / key changed from Settings → the cache was cleared → refetch.
    if ('${hr.base}|${hr.token}' != _askedFor) _ask();
    final s = hr.cached();
    if (s == null || !s.hasAny) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _HrCard(summary: s, waiting: _waiting),
    );
  }
}

class _HrCard extends StatelessWidget {
  final HrSummary summary;
  final bool waiting;
  const _HrCard({required this.summary, required this.waiting});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = summary;
    final tint = AppColors.teal;
    final total = s.total;
    final pct = (total != null && total > 0 && s.present != null) ? (s.present! * 100 / total).round() : null;
    final chips = <Widget>[
      if (s.absent != null) _pill(tr('Absent'), s.absent!, AppColors.red),
      if (s.onLeave != null) _pill(tr('On leave'), s.onLeave!, AppColors.amber),
      if (s.lateIn != null && s.lateIn! > 0) _pill(tr('Late'), s.lateIn!, AppColors.orange),
      if (s.halfDay != null && s.halfDay! > 0) _pill(tr('Half day'), s.halfDay!, AppColors.violet),
    ];
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openHrMate(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(17, 14, 12, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.badge_outlined, color: tint, size: 23),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text('${tr('Present today').toUpperCase()} · HRMATE',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.85, color: scheme.onSurfaceVariant)),
                  ),
                  if (waiting) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6)),
                ]),
                const SizedBox(height: 3),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(s.present == null ? '—' : qtyInt(s.present),
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: scheme.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  if (total != null) ...[
                    const SizedBox(width: 4),
                    Text('/ ${qtyInt(total)}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                  ],
                  if (pct != null) ...[
                    const SizedBox(width: 8),
                    Text('$pct%', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: pct >= 90 ? AppColors.green : pct >= 75 ? AppColors.amber : AppColors.red)),
                  ],
                ]),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Wrap(spacing: 6, runSpacing: 4, children: chips),
                ],
                if (s.departments.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    [for (final d in s.departments) '${d.name} ${qtyInt(d.present)}${d.total != null ? '/${qtyInt(d.total)}' : ''}'].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${fmtDateWithDay(s.date)} · ${tr('Updated')} ${fmtAgo(ymdHms(s.fetchedAt))}',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ]),
            ),
            Icon(Icons.open_in_new_rounded, size: 18, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }

  Widget _pill(String label, int n, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withValues(alpha: 0.35))),
        child: Text('$label $n', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
      );
}

/// Detail row for a production batch: "38 / 45 present · 2 on leave" for
/// the batch's planned date (+ approximate labour cost per carton when a
/// daily wage is set). Renders nothing while unknown / HRMate off.
class HrBatchPresence extends StatefulWidget {
  final String date; // planned_date YYYY-MM-DD
  final num? plannedQty; // planned cartons → labour cost per carton (when wage set)
  const HrBatchPresence({super.key, required this.date, this.plannedQty});
  @override
  State<HrBatchPresence> createState() => _HrBatchPresenceState();
}

class _HrBatchPresenceState extends State<HrBatchPresence> {
  @override
  void initState() {
    super.initState();
    // Fetch (cached ≤3 min, deduped); a success notifies HrMate → rebuild.
    HrMate.instance.summary(date: widget.date);
  }

  @override
  void didUpdateWidget(covariant HrBatchPresence old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) HrMate.instance.summary(date: widget.date);
  }

  @override
  Widget build(BuildContext context) {
    final hr = context.watch<HrMate>();
    if (!hr.configured) return const SizedBox.shrink();
    final s = hr.cached(widget.date);
    if (s == null || s.present == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    // Shop-floor head-count when HRMate breaks the day down by department
    // (office staff must not inflate the labour cost); else the whole plant.
    final prod = s.production;
    final present = prod?.present ?? s.present!;
    final total = prod?.total ?? s.total;
    final onLeave = prod?.onLeave ?? s.onLeave;
    final absent = prod?.absent ?? s.absent;
    final parts = <String>[
      '${qtyInt(present)}${total != null ? ' / ${qtyInt(total)}' : ''} ${tr('present')}',
      if ((onLeave ?? 0) > 0) '${qtyInt(onLeave)} ${tr('on leave')}',
      if ((absent ?? 0) > 0) '${qtyInt(absent)} ${tr('absent')}',
    ];
    final qty = widget.plannedQty;
    String? cost;
    if (hr.wage > 0 && qty != null && qty > 0 && present > 0) {
      cost = '${inr(hr.wage * present / qty)} / ${U.cb}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 150, child: Text('${tr('Workers')} (${prod?.name ?? 'HRMate'})', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(parts.join(' · '), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            if (prod != null && s.present != null && s.present != present)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${tr('All staff')}: ${qtyInt(s.present)}${s.total != null ? ' / ${qtyInt(s.total)}' : ''} ${tr('present')} · HRMate',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ),
            if (cost != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('≈ ${tr('Labour cost')} $cost (${tr('daily wage')} ${inr(hr.wage, decimals: false)} × ${qtyInt(present)} ÷ ${qtyInt(qty)} ${U.cb})',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// DateTime → 'YYYY-MM-DD HH:MM:SS' (the format [fmtAgo] understands).
String ymdHms(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${ymd(d)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

/// Open HRMate (configured address, else hr.flavorflow.co.in) in the browser
/// or the HRMate app. Falls back to a snackbar with the address.
Future<void> openHrMate(BuildContext context) async {
  final hr = HrMate.instance;
  final url = hr.configured ? hr.base : HrMate.defaultBase;
  final ok = await openExternalUrl(url);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('HRMate: $url'),
        action: SnackBarAction(label: tr('Settings'), onPressed: () => context.push('/settings')),
      ));
  }
}
