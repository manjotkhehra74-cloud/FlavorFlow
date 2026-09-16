import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/secure.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// More — Phase 0 ships the parts every build needs for verification:
/// signed-in identity, language, fingerprint unlock toggle, About (version)
/// and Sign out. Phase 5 ADDS profile, holidays, calendar, payslips tiles
/// above these rows.
class MorePage extends StatefulWidget {
  const MorePage({super.key});
  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    () async {
      final a = await SecureStore.biometricAvailable();
      final e = await SecureStore.biometricEnabled();
      String v = '';
      try {
        final info = await PackageInfo.fromPlatform();
        v = '${info.version} (${info.buildNumber})';
      } catch (_) {}
      if (mounted) setState(() { _bioAvailable = a; _bioEnabled = e; _version = v; });
    }();
  }

  Future<void> _toggleBio(bool on) async {
    if (on) {
      final ok = await SecureStore.verify(tr('Verify to enable fingerprint unlock'));
      if (!ok) return;
    }
    await SecureStore.setBiometricEnabled(on);
    if (mounted) setState(() => _bioEnabled = on);
  }

  Future<void> _signOut() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Sign out')),
        content: Text(tr('Sign out of HRMate on this phone?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Sign out'))),
        ],
      ),
    );
    if (yes == true && mounted) await context.read<AuthController>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final l10n = context.watch<L10n>();
    final user = auth.user;
    return Scaffold(
      appBar: AppBar(title: Text(tr('More'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          HrCard(
            child: Row(children: [
              Avatar(name: user?.name ?? '', url: user?.avatarUrl, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Signed in as'), style: Theme.of(context).textTheme.bodySmall),
                  Text(user?.name ?? '', style: Theme.of(context).textTheme.titleMedium),
                  Text(user?.email ?? '', style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          // Phase 5 inserts its tiles grid here.
          HrCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.language_rounded, color: HrBrand.blue),
                title: Text(tr('Language')),
                trailing: DropdownButton<String>(
                  value: l10n.code,
                  underline: const SizedBox.shrink(),
                  items: [for (final l in L10n.languages) DropdownMenuItem(value: l[0], child: Text(l[1]))],
                  onChanged: (v) { if (v != null) l10n.set(v); },
                ),
              ),
              if (_bioAvailable) ...[
                const Divider(),
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint_rounded, color: HrBrand.blue),
                  title: Text(tr('Fingerprint unlock')),
                  value: _bioEnabled,
                  onChanged: _toggleBio,
                ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded, color: HrBrand.blue),
                title: Text(tr('About')),
                subtitle: Text(tr('Native app · Phase 4 Team')),
                trailing: Text(_version.isEmpty ? '' : '${tr('Version')} $_version', style: Theme.of(context).textTheme.bodySmall),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded, color: HrBrand.red),
            label: Text(tr('Sign out'), style: const TextStyle(color: HrBrand.red)),
          ),
        ],
      ),
    );
  }
}
