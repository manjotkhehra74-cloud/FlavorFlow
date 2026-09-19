import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../ui/widgets.dart';

/// Leaves — ships in Phase 2. The tab is REAL (routed, model-ready);
/// the body is an honest "coming in Phase 2" — never fake data.
class LeavesPage extends StatelessWidget {
  const LeavesPage({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<L10n>();
    return Scaffold(
      body: PhaseScreen(
        title: tr('Leaves'),
        icon: Icons.event_note_rounded,
        phase: 2,
        lines: [tr('Balance, leave types, apply + approve — real API data.')] + [tr('Your balance already works on Home.')],
      ),
    );
  }
}
