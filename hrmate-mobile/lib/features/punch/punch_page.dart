import 'package:flutter/material.dart';

import '../../ui/app_shell.dart';

/// Punch — built in Phase 2 (geofence + biometric punch in/out).
class PunchPage extends StatelessWidget {
  const PunchPage({super.key});
  @override
  Widget build(BuildContext context) => const PhasePlaceholder(title: 'Punch', icon: Icons.fingerprint_rounded, phase: 2);
}
