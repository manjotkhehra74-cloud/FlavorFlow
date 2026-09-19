import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// Team — ships in Phase 4. Non-managers never see the tab (router + shell),
/// so this body only runs for managers; honest "coming in Phase 4".
class TeamPage extends StatelessWidget {
  const TeamPage({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<L10n>();
    context.watch<AuthController>();
    return Scaffold(
      body: PhaseScreen(
        title: tr('Team'),
        icon: Icons.groups_rounded,
        phase: 4,
        lines: [tr('Who is in, on leave, late — real team data.')] + [tr('Team count already works on Home.')],
      ),
    );
  }
}
