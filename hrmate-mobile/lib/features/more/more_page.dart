import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/secure.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import 'calendar_page.dart';
import 'holidays_page.dart';
import 'payslips_page.dart';
import 'profile_page.dart';

/// More — Phase 0: identity, language, fingerprint unlock, About, Sign out.
/// Phase 5 adds the tiles grid (Profile · My attendance · Holidays · Payslips)
/// between the identity card and the settings rows. Payslips hides itself when
/// the server has no payslips module (404 on `GET payslips`).
class MorePage extends StatefulWidget {
  const MorePage({super.key});
  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  String _version = '';
  bool _payslips = true; // false once the server says 404 (module absent)

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
      _probePayslips();
    }();
  }

  Future<void> _probePayslips() async {
    if (!mounted) return;
    final api = context.read<AuthController>().api;
    try {
      await api.get('/payslips');
    } on ApiException catch (e) {
      if (e.status == 404 && mounted) setState(() => _payslips = false);
    } catch (_) {}
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

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
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.9,
            children: [
              _Tile(icon: Icons.person_outline_rounded, label: tr('Profile'), onTap: () => _push(const ProfilePage())),
              _Tile(icon: Icons.calendar_month_rounded, label: tr('My attendance'), onTap: () => _push(const CalendarPage())),
              _Tile(icon: Icons.celebration_outlined, label: tr('Holidays'), onTap: () => _push(const HolidaysPage())),
              if (_payslips) _Tile(icon: Icons.receipt_long_outlined, label: tr('Payslips'), onTap: () => _push(const PayslipsPage())),
            ],
          ),
          const SizedBox(height: 16),
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
                subtitle: Text(tr('Native app · Phase 5 Release')),
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

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => HrCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(color: HrBrand.blueContainer, shape: BoxShape.circle),
            child: Icon(icon, color: HrBrand.blue, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      );
}
