import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/subscription.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// FlavorFlow cloud subscription of this company: plan, validity, due
/// invoice with cheque / NEFT instructions, payment history and the
/// available plans. Payment is offline; activation is done by FlavorFlow
/// after the cheque clears (the app just polls the status).
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});
  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthController>();
      auth.subscription.refresh(auth.api);
    });
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    showOk(context, '$what ${tr('copied')}');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return ListenableBuilder(
      listenable: auth.subscription,
      builder: (context, _) {
        final sub = auth.subscription;
        final s = sub.status;
        final scheme = Theme.of(context).colorScheme;
        if (sub.loading && !s.available) return const Center(child: CircularProgressIndicator());
        if (!s.available) {
          return ListView(padding: const EdgeInsets.all(20), children: [
            _back(context),
            const SizedBox(height: 12),
            SectionCard(
              title: tr('Subscription'),
              child: EmptyState(
                sub.blockMessage ?? tr('This server is self-hosted — there is no FlavorFlow cloud subscription to show. For cloud plans see flavorflow.co.in/#pricing.'),
                icon: Icons.cloud_off_outlined,
              ),
            ),
          ]);
        }
        final due = s.dueInvoice;
        final pay = s.payment;
        final tint = s.isBlocked ? AppColors.red : (s.isGrace ? AppColors.orange : (s.isTrial ? AppColors.teal : AppColors.green));
        final stateLabel = s.isDemo ? tr('Demo') : s.isActive ? tr('Active') : s.isTrial ? tr('Free trial') : s.isGrace ? tr('Grace period') : s.state == 'suspended' ? tr('Suspended') : tr('Expired');
        final wide = MediaQuery.sizeOf(context).width > 760;

        return RefreshIndicator(
          onRefresh: () => sub.refresh(auth.api),
          child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(20), children: [
            _back(context),
            const SizedBox(height: 12),
            // ── status header
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: tint.withValues(alpha: 0.35))),
              child: Wrap(spacing: 24, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Icon(s.isBlocked ? Icons.lock_outline_rounded : s.isGrace ? Icons.warning_amber_rounded : Icons.verified_outlined, color: tint, size: 36),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('${s.company} · ${s.code}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  Text('${s.planName} ${s.planCycle.isEmpty ? '' : '· ${s.planCycle == 'yearly' ? tr('yearly') : tr('monthly')}'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    StatusChip(stateLabel.toUpperCase()),
                    const SizedBox(width: 8),
                    if (s.until.isNotEmpty && !s.isDemo)
                      Text(
                        s.isBlocked ? '${tr('ended')} ${fmtDate(s.until)}' : '${tr('valid till')} ${fmtDate(s.isGrace ? s.graceUntil : s.until)}${s.daysLeft != null ? ' · ${s.daysLeft} ${tr('days left')}' : ''}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: tint),
                      ),
                  ]),
                ]),
                if (s.state == 'suspended' && s.suspendNote.isNotEmpty) Text('${tr('Reason')}: ${s.suspendNote}', style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
                if (sub.blockMessage != null && s.isBlocked) SizedBox(width: wide ? 420 : double.infinity, child: Text(sub.blockMessage!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))),
              ]),
            ),
            const SizedBox(height: 16),
            if (s.isTrial && !s.planChosen)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SectionCard(
                  title: tr('After the trial'),
                  child: Text(
                    '${tr('Pick a plan below and WhatsApp us — we send a simple invoice; pay by cheque or NEFT and the plan is activated the same day. No card, no auto-debit.')} ${s.graceDays > 0 ? '${tr('Grace period after expiry')}: ${s.graceDays} ${tr('days')}.' : ''}',
                    style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                ),
              ),
            // ── due invoice + how to pay
            if (due != null)
              SectionCard(
                title: '${tr('Invoice due')} · ${due['no']}',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 24, runSpacing: 10, children: [
                    _kv(context, tr('Amount'), inr(due['amount'], decimals: false), big: true),
                    _kv(context, tr('Plan'), '${_tierName(s, '${due['tier']}')} · ${due['cycle'] == 'yearly' ? tr('yearly') : tr('monthly')}'),
                    _kv(context, tr('Period'), '${fmtDate(due['periodFrom'])} → ${fmtDate(due['periodTo'])}'),
                    _kv(context, tr('Issued'), fmtDate(due['issuedAt'])),
                  ]),
                  if ((due['note'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${due['note']}', style: TextStyle(color: scheme.onSurfaceVariant))),
                  const Divider(height: 26),
                  Text(tr('How to pay (cheque / NEFT)'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _payDetails(context, pay, s),
                  const SizedBox(height: 10),
                  Text(
                    '${pay['note'] ?? tr('WhatsApp a photo of the cheque or the NEFT UTR with your company code — activation within 1 working day of clearance.')}',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (s.whatsapp.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () => _copy('+${s.whatsapp}', 'WhatsApp'),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                        icon: const Icon(Icons.chat_rounded, size: 18),
                        label: Text('WhatsApp +${s.whatsapp}'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _copy(_paymentMessage(s, due), tr('Payment message')),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: Text(tr('Copy payment message')),
                    ),
                  ]),
                ]),
              )
            else if (!s.isDemo)
              SectionCard(
                title: tr('Payment'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.isActive ? tr('No invoice pending. The renewal invoice appears here about 10 days before the paid period ends.') : tr('No invoice yet — choose a plan and message us; the invoice appears here.'), style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5)),
                  const SizedBox(height: 12),
                  _payDetails(context, pay, s),
                  if (s.whatsapp.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _copy('+${s.whatsapp}', 'WhatsApp'),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                      icon: const Icon(Icons.chat_rounded, size: 18),
                      label: Text('WhatsApp +${s.whatsapp}'),
                    ),
                  ],
                ]),
              ),
            const SizedBox(height: 16),
            // ── plans
            SectionCard(
              title: tr('Plans'),
              child: LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth > 900 ? 3 : (c.maxWidth > 560 ? 2 : 1);
                final w = (c.maxWidth - (cols - 1) * 12) / cols;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final p in s.plans)
                    SizedBox(
                      width: w,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: p['tier'] == s.planTier ? AppColors.blue : scheme.outlineVariant, width: p['tier'] == s.planTier ? 2 : 1),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                            if (p['tier'] == s.planTier) StatusChip(s.planChosen ? tr('CURRENT') : tr('TRIAL')),
                          ]),
                          const SizedBox(height: 6),
                          Text('${inr(p['monthly'], decimals: false)} / ${tr('month')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          Text('${inr(p['yearly'], decimals: false)} / ${tr('year')} · ${tr('save')} ${inr((p['monthly'] as num) * 12 - (p['yearly'] as num), decimals: false)}', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700, fontSize: 12.5)),
                          const SizedBox(height: 10),
                          for (final f in ((p['features'] as List?) ?? const []))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Icon(Icons.check_rounded, size: 16, color: AppColors.green),
                                const SizedBox(width: 6),
                                Expanded(child: Text('$f', style: const TextStyle(fontSize: 13))),
                              ]),
                            ),
                        ]),
                      ),
                    ),
                ]);
              }),
            ),
            const SizedBox(height: 16),
            // ── history
            if (s.invoices.isNotEmpty)
              SectionCard(
                title: tr('Invoice history'),
                child: AppDataTable(
                  columns: [tr('Invoice'), tr('Plan'), tr('Period'), tr('Amount'), tr('Status'), tr('Paid on'), tr('Cheque / ref')],
                  moneyColumns: const {3},
                  rows: [
                    for (final i in s.invoices)
                      [
                        Text('${i['no']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        '${_tierName(s, '${i['tier']}')} · ${i['cycle']}',
                        '${fmtDate(i['periodFrom'])} → ${fmtDate(i['periodTo'])}',
                        i['amount'],
                        StatusChip('${i['status']}'.toUpperCase()),
                        (i['paidOn'] ?? '').toString().isEmpty ? '—' : fmtDate(i['paidOn']),
                        [if ((i['mode'] ?? '').toString().isNotEmpty) '${i['mode']}'.toUpperCase(), if ((i['chequeNo'] ?? '').toString().isNotEmpty) '${i['chequeNo']}', if ((i['bank'] ?? '').toString().isNotEmpty) '${i['bank']}'].join(' '),
                      ],
                  ],
                ),
              ),
            const SizedBox(height: 40),
          ]),
        );
      },
    );
  }

  Widget _back(BuildContext context) => Row(children: [
        IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'), icon: const Icon(Icons.arrow_back_rounded)),
        const SizedBox(width: 4),
        Text(tr('FlavorFlow subscription'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      ]);

  String _tierName(SubscriptionStatus s, String tier) {
    for (final p in s.plans) {
      if (p['tier'] == tier) return '${p['name']}';
    }
    return tier;
  }

  Widget _kv(BuildContext context, String k, String v, {bool big = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(k.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.4)),
        const SizedBox(height: 2),
        Text(v, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w600, fontSize: big ? 22 : 13.5)),
      ]);

  Widget _payDetails(BuildContext context, Map<String, dynamic> pay, SubscriptionStatus s) {
    final rows = <List<String>>[
      if ((pay['chequeInFavourOf'] ?? '').toString().isNotEmpty) [tr('Cheque in favour of'), '${pay['chequeInFavourOf']}'],
      if ((pay['bankName'] ?? '').toString().isNotEmpty) [tr('Bank'), '${pay['bankName']}'],
      if ((pay['accountNo'] ?? '').toString().isNotEmpty) [tr('Account no'), '${pay['accountNo']}'],
      if ((pay['ifsc'] ?? '').toString().isNotEmpty) ['IFSC', '${pay['ifsc']}'],
      if ((pay['upiId'] ?? '').toString().isNotEmpty) ['UPI', '${pay['upiId']}'],
      if ((pay['address'] ?? '').toString().isNotEmpty) [tr('Post cheque to'), '${pay['address']}'],
      if ((pay['email'] ?? '').toString().isNotEmpty) [tr('Email'), '${pay['email']}'],
    ];
    if (rows.isEmpty) return Text(tr('Bank details are shared on WhatsApp.'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
    return Column(children: [
      for (final r in rows)
        InkWell(
          onTap: () => _copy(r[1], r[0]),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 150, child: Text(r[0], style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))),
              Expanded(child: Text(r[1], style: const TextStyle(fontWeight: FontWeight.w700))),
              Icon(Icons.copy_rounded, size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ]),
          ),
        ),
    ]);
  }

  String _paymentMessage(SubscriptionStatus s, Map<String, dynamic> due) =>
      'FlavorFlow payment\nCompany: ${s.company} (${s.code})\nInvoice: ${due['no']} — ${inr(due['amount'], decimals: false)}\nPlan: ${_tierName(s, '${due['tier']}')} ${due['cycle']}\nMode: Cheque / NEFT\nCheque no / UTR: ______\nBank: ______\nDate: ${todayYmd()}';
}
