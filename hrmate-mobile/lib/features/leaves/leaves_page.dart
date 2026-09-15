import 'package:flutter/material.dart';

import '../../ui/app_shell.dart';

/// Leaves — built in Phase 3 (balance, list, apply, approve/reject).
class LeavesPage extends StatelessWidget {
  const LeavesPage({super.key});
  @override
  Widget build(BuildContext context) => const PhasePlaceholder(title: 'Leaves', icon: Icons.event_note_rounded, phase: 3);
}
