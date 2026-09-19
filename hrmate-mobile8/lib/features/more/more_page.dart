import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// More — ships in Phase 5 (profile, holidays, payslips, settings,
/// language, notifications, about). The tab is REAL; the body is an honest
/// "coming in Phase 5" plus a WORKING sign-out (never a dummy).
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<L10n>();
    final auth = context.watch<AuthController>();
    final user = auth.user;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          // Working sign-out from day one.
          Material(
            color: Colors.transparent,
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tileColor: HrBrand.card,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: HrBrand.redContainer, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.logout_rounded, size: 20, color: HrBrand.redText),
              ),
              title: Text(tr('Sign out'), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: HrBrand.redText)),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: Text(tr('Sign out')),
                    content: Text(user == null ? tr('Are you sure?') : '${tr('See you soon')}, ${user.name}!'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(tr('Cancel'))),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: HrBrand.red, foregroundColor: Colors.white, minimumSize: const Size(0, 40)),
                        onPressed: () => Navigator.of(c).pop(true),
                        child: Text(tr('Sign out')),
                      ),
                    ],
                  ),
                );
                if (ok == true) await auth.logout();
              },
            ),
          ),
          const SizedBox(height: 16),
          PhaseScreen(
            title: tr('More'),
            icon: Icons.grid_view_rounded,
            phase: 5,
            lines: [tr('Profile, holidays, payslips, settings, language, notifications, about.')] +
                [tr('Everything here works — nothing decorative.')],
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(HrBrand.company, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: HrBrand.faint)),
          ),
        ],
      ),
    );
  }
}
