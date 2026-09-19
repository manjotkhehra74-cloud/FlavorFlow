import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../ui/widgets.dart';

/// Punch — ships in Phase 3 (live clock ring, punch in/out, history, GPS).
/// The tab is REAL; the body is an honest "coming in Phase 3".
class PunchPage extends StatelessWidget {
  const PunchPage({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<L10n>();
    return Scaffold(
      body: PhaseScreen(
        title: tr('Punch'),
        icon: Icons.fingerprint_rounded,
        phase: 3,
        lines: [tr('Live clock ring, punch in/out, history — real API data.')] + [tr('Your punch summary already works on Home.')],
      ),
    );
  }
}
