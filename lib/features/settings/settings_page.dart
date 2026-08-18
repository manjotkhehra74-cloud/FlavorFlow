import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_settings.dart';
import '../../core/biometric.dart';
import '../../core/notifier.dart';
import '../../core/i18n.dart';
import '../../state/auth.dart';
import '../../ui/app_shell.dart' show LanguageDialog, CompanyProfileDialog;
import '../../ui/widgets.dart';

/// Settings — one place for every per-user option:
/// language · biometric login · two-factor auth (authenticator app) ·
/// company details (Super Admin) · server address · about.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  bool? _totpEnabled; // null = unknown/server not patched

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final avail = await BiometricAuth.available();
    final enabled = await BiometricAuth.enabled();
    bool? totp;
    try {
      final j = await context.read<AuthController>().api.get('/auth/totp/status');
      totp = (j as Map)['enabled'] == true;
    } catch (_) {/* server route optional until patched */}
    if (!mounted) return;
    setState(() { _bioAvailable = avail; _bioEnabled = enabled; _totpEnabled = totp; });
  }

  Future<void> _toggleBiometrics() async {
    if (_bioEnabled) {
      await BiometricAuth.disable();
      if (mounted) showOk(context, 'Biometric login turned off on this device.');
    } else if (BiometricAuth.hasSession) {
      final saved = await BiometricAuth.enableFromSession();
      if (mounted) {
        saved
            ? showOk(context, 'Biometric login enabled.')
            : showErr(context, 'Verification cancelled.');
      }
    } else {
      showErr(context, 'Sign in with your password once, then enable biometrics.');
    }
    _refresh();
  }

  Future<void> _setup2fa() async {
    final api = context.read<AuthController>().api;
    try {
      final j = await api.post('/auth/totp/setup');
      final m = (j as Map).cast<String, dynamic>();
      if (!mounted) return;
      final done = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TotpSetupDialog(secret: m['secret'] as String, otpauth: m['otpauth'] as String),
      );
      if (done == true && mounted) showOk(context, 'Two-factor authentication is ON.');
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    _refresh();
  }

  Future<void> _disable2fa() async {
    final code = await _askCode(context, 'Enter the 6-digit code from your authenticator app to turn 2FA off.');
    if (code == null || !mounted) return;
    try {
      await context.read<AuthController>().api.post('/auth/totp/disable', {'code': code});
      if (mounted) showOk(context, 'Two-factor authentication turned off.');
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final settings = context.watch<AppSettings>();
    final session = auth.session;
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(20), children: [
      _section('PREFERENCES'),
      _tile(
        icon: Icons.translate_rounded,
        title: '${tr('Language')} · ਭਾਸ਼ਾ · भाषा',
        subtitle: [for (final l in L10n.languages) if (l[0] == L10n.instance.code) l[1]].firstOrNull ?? 'English',
        onTap: () async {
          await showDialog(context: context, builder: (_) => const LanguageDialog());
          setState(() {});
        },
      ),
      _tile(
        icon: Icons.dark_mode_outlined,
        title: 'Dark theme',
        subtitle: settings.darkMode ? 'ON — easier on the eyes at night' : 'OFF — classic light look',
        trailing: Switch(value: settings.darkMode, onChanged: (v) => settings.setDarkMode(v)),
        onTap: () => settings.setDarkMode(!settings.darkMode),
      ),
      _tile(
        icon: Icons.format_size_rounded,
        title: 'Text size',
        subtitle: settings.textScale <= 1.0
            ? 'Normal'
            : settings.textScale <= 1.15
                ? 'Large'
                : 'Extra large (factory floor)',
        trailing: SegmentedButton<double>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: 1.0, label: Text('A', style: TextStyle(fontSize: 12))),
            ButtonSegment(value: 1.15, label: Text('A', style: TextStyle(fontSize: 15))),
            ButtonSegment(value: 1.3, label: Text('A', style: TextStyle(fontSize: 18))),
          ],
          selected: {settings.textScale},
          onSelectionChanged: (v) => settings.setTextScale(v.first),
        ),
      ),
      _tile(
        icon: Icons.alarm_rounded,
        title: 'Daily entry reminder',
        subtitle: settings.dailyReminder
            ? 'ON — roz ${settings.dailyReminderHour > 12 ? settings.dailyReminderHour - 12 : settings.dailyReminderHour} ${settings.dailyReminderHour >= 12 ? 'PM' : 'AM'} vaje yaad karauga (+ month-end Loss% close)'
            : 'OFF — production/dispatch entry da roz da reminder',
        trailing: Switch(
          value: settings.dailyReminder,
          onChanged: (v) async {
            if (v) {
              final hour = await showDialog<int>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text(tr('Reminder time')),
                  children: [
                    for (final h in [9, 12, 17, 18, 20])
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, h),
                        child: Text(h > 12 ? '${h - 12}:00 PM' : h == 12 ? '12:00 PM' : '$h:00 AM'),
                      ),
                  ],
                ),
              );
              if (hour == null) return;
              await settings.setDailyReminder(true, hour);
              await Reminders.enableDaily(hour);
              await Reminders.enableMonthEnd();
              if (context.mounted) showOk(context, 'Reminder set — roz + month-end.');
            } else {
              await settings.setDailyReminder(false, settings.dailyReminderHour);
              await Reminders.disableAll();
              if (context.mounted) showOk(context, 'Reminders off.');
            }
            setState(() {});
          },
        ),
      ),
      _tile(
        icon: Icons.notifications_active_outlined,
        title: 'Notification badge',
        subtitle: settings.showNotifBadge ? 'ON — unread count on the bell icon' : 'OFF — bell stays clean',
        trailing: Switch(value: settings.showNotifBadge, onChanged: (v) => settings.setShowNotifBadge(v)),
        onTap: () => settings.setShowNotifBadge(!settings.showNotifBadge),
      ),

      _section('SECURITY'),
      if (_bioAvailable)
        _tile(
          icon: Icons.fingerprint_rounded,
          title: 'Biometric login',
          subtitle: _bioEnabled ? 'ON — login with fingerprint / face' : 'OFF — tap to enable on this device',
          trailing: Switch(value: _bioEnabled, onChanged: (_) => _toggleBiometrics()),
          onTap: _toggleBiometrics,
        ),
      _tile(
        icon: Icons.verified_user_outlined,
        title: 'Two-factor authentication (2FA)',
        subtitle: _totpEnabled == null
            ? 'Authenticator app (Google/Microsoft) — server update required'
            : _totpEnabled == true
                ? 'ON — authenticator code needed at every login'
                : 'OFF — protect your account with Google/Microsoft Authenticator',
        trailing: _totpEnabled == null
            ? null
            : Switch(value: _totpEnabled!, onChanged: (_) => _totpEnabled! ? _disable2fa() : _setup2fa()),
        onTap: _totpEnabled == null ? null : (_totpEnabled! ? _disable2fa : _setup2fa),
      ),
      _tile(
        icon: Icons.logout_rounded,
        title: 'Auto sign-out',
        subtitle: 'Always ON — closing the app ends the session (security policy)',
      ),

      if (session != null && session.role == 'super_admin') ...[
        _section('COMPANY (SUPER ADMIN)'),
        _tile(
          icon: Icons.business_rounded,
          title: tr('Company details (PDF header)'),
          subtitle: 'Name, address, GSTIN · industry & unit names (view)',
          onTap: () => showDialog(context: context, builder: (_) => const CompanyProfileDialog()),
        ),
      ],

      _section('CONNECTION'),
      _tile(
        icon: Icons.dns_outlined,
        title: 'ERP server',
        subtitle: auth.serverBase ?? 'Automatic',
      ),
      _tile(
        icon: Icons.sync_rounded,
        title: tr('Refresh permissions'),
        subtitle: 'Re-load your role & permissions from the server',
        onTap: () async {
          await auth.refreshSession();
          if (context.mounted) showOk(context, 'Permissions refreshed.');
        },
      ),

      _section('ABOUT'),
      _tile(
        icon: Icons.info_outline_rounded,
        title: 'FlavorFlow ERP',
        subtitle: 'Version 1.1.0 · Universal manufacturing ERP',
      ),
      const SizedBox(height: 8),
      Text('${tr('Role')}: ${session?.roleLabel ?? ''} · ${session?.email ?? ''}',
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
    ]);
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(tr(t), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _tile({required IconData icon, required String title, String? subtitle, Widget? trailing, VoidCallback? onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant)),
      child: ListTile(
        leading: Icon(icon, size: 22, color: scheme.primary),
        title: Text(tr(title), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(tr(subtitle), style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

Future<String?> _askCode(BuildContext context, String message) async {
  final ctl = TextEditingController();
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Authenticator code')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 12),
        TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(counterText: '', hintText: '000000'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text(tr('Confirm'))),
      ],
    ),
  );
  return (v == null || v.length != 6) ? null : v;
}

/// 2FA setup: QR + manual key + code confirmation.
class _TotpSetupDialog extends StatefulWidget {
  final String secret;
  final String otpauth;
  const _TotpSetupDialog({required this.secret, required this.otpauth});
  @override
  State<_TotpSetupDialog> createState() => _TotpSetupDialogState();
}

class _TotpSetupDialogState extends State<_TotpSetupDialog> {
  final code = TextEditingController();
  bool busy = false;

  Future<void> _confirm() async {
    if (code.text.trim().length != 6) return;
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.post('/auth/totp/enable', {'code': code.text.trim()});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(tr('Set up 2FA')),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('1. Open Google / Microsoft Authenticator\n2. Scan this QR (or add the key manually)\n3. Enter the 6-digit code below', style: TextStyle(fontSize: 12.5)),
            const SizedBox(height: 14),
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: scheme.outlineVariant)),
                child: QrImageView(data: widget.otpauth, size: 190),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text('Key: ${widget.secret}', style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Copy key',
                icon: const Icon(Icons.copy_rounded, size: 17),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.secret));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Key copied.')));
                },
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(counterText: '', hintText: '000000', labelText: 'Code from the app'),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _confirm, child: Text(busy ? 'Checking…' : 'Turn on 2FA')),
      ],
    );
  }
}
