import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// Home — Phase 0 shows the signed-in employee (proves the Mobile API login
/// end-to-end). Phase 1 ADDS the today card, quick tiles and announcements
/// below the header; the header itself stays.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    context.watch<L10n>();
    final user = auth.user;
    final now = DateTime.now();
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 0,
            title: Row(children: [
              Avatar(name: user?.name ?? '', url: user?.avatarUrl, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(tr(Fmt.greeting(now)), style: Theme.of(context).textTheme.bodySmall),
                  Text(Fmt.shortName(user?.name ?? ''), style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverList.list(children: [
              Text(Fmt.weekday(now), style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              HrCard(
                child: Row(children: [
                  Avatar(name: user?.name ?? '', url: user?.avatarUrl, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(user?.name ?? '', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        [if ((user?.code ?? '').isNotEmpty) user!.code, if ((user?.department ?? '').isNotEmpty) user!.department].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      StatusPill.info(_roleLabel(user?.role ?? '')),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              // Phase 1 inserts: today card · quick tiles · announcements.
              HrCard(
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(color: HrBrand.blueContainer, shape: BoxShape.circle),
                    child: const Icon(Icons.construction_rounded, color: HrBrand.blue, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(tr('Coming in Phase %s').arg(1), style: Theme.of(context).textTheme.bodyMedium)),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  static String _roleLabel(String role) {
    if (role.isEmpty) return 'Employee';
    return role.split(RegExp(r'[\s_]+')).map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }
}
