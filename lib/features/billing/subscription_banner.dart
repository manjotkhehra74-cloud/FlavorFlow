import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';

/// Dashboard strip for the FlavorFlow cloud subscription: trial ending,
/// invoice due (pay by cheque), grace period, or blocked. Hidden for demo
/// tenants, self-hosted servers and healthy paid companies.
class SubscriptionBanner extends StatelessWidget {
  const SubscriptionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return ListenableBuilder(
      listenable: auth.subscription,
      builder: (context, _) {
        final s = auth.subscription.status;
        if (!s.needsAttention) return const SizedBox.shrink();
        final due = s.dueInvoice;
        String title;
        String body;
        Color tint;
        IconData icon;
        if (s.isBlocked) {
          tint = AppColors.red; icon = Icons.lock_outline_rounded;
          title = s.state == 'suspended' ? tr('Subscription suspended') : tr('Subscription ended');
          body = auth.subscription.blockMessage ?? tr('Pay by cheque / NEFT to continue — tap for bank details.');
        } else if (s.isGrace) {
          tint = AppColors.orange; icon = Icons.warning_amber_rounded;
          title = '${tr('Subscription ended')} ${fmtDate(s.until)} · ${tr('grace till')} ${fmtDate(s.graceUntil)}';
          body = due != null ? '${tr('Invoice')} ${due['no']} · ${inr(due['amount'], decimals: false)} ${tr('due — pay by cheque / NEFT to keep access.')}' : tr('Pay by cheque / NEFT to keep access — tap for details.');
        } else if (due != null) {
          tint = AppColors.amber; icon = Icons.receipt_long_rounded;
          title = '${tr('Invoice due')} · ${due['no']} · ${inr(due['amount'], decimals: false)}';
          body = '${tr('Period')} ${fmtDate(due['periodFrom'])} → ${fmtDate(due['periodTo'])} · ${tr('pay by cheque / NEFT and WhatsApp the receipt — tap for bank details.')}';
        } else {
          tint = AppColors.teal; icon = Icons.timelapse_rounded;
          title = '${tr('Free trial ends in')} ${s.daysLeft} ${tr('days')} (${fmtDate(s.until)})';
          body = tr('Choose a plan — Basic / Pro / Enterprise, monthly or yearly. Pay by cheque or NEFT; no card needed.');
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Material(
            color: tint.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push('/subscription'),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: tint.withValues(alpha: 0.35))),
                child: Row(children: [
                  Icon(icon, color: tint, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: tint)),
                      const SizedBox(height: 2),
                      Text(body, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant), maxLines: 3, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, color: tint),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
