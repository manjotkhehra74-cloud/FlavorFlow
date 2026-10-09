import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_settings.dart';
import '../../core/biometric.dart';
import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/notifier.dart';
import '../../core/offline_queue.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
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
  bool _totpBusy = false; // blocks duplicate setup/disable requests per account
  bool? _notifOn; // phone notification permission (null = still checking)

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
    final notif = await PhoneNotifier.notificationsAllowed();
    if (!mounted) return;
    setState(() { _bioAvailable = avail; _bioEnabled = enabled; _totpEnabled = totp; _notifOn = notif; });
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
    if (_totpBusy) return;
    setState(() => _totpBusy = true);
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
    } finally {
      if (mounted) setState(() => _totpBusy = false);
    }
    _refresh();
  }

  Future<void> _disable2fa() async {
    if (_totpBusy) return;
    setState(() => _totpBusy = true);
    try {
      final code = await _askCode(context, 'Enter the 6-digit code from your authenticator app to turn 2FA off.');
      if (code == null || !mounted) return;
      await context.read<AuthController>().api.post('/auth/totp/disable', {'code': code});
      if (mounted) showOk(context, 'Two-factor authentication turned off.');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _totpBusy = false);
    }
    _refresh();
  }

  /// 12-hour label for the reminder time, e.g. 5:30 PM.
  String _clock(int h, int m) {
    final suffix = h >= 12 ? 'PM' : 'AM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '$hour12:${m.toString().padLeft(2, '0')} $suffix';
  }

  Future<void> _toggleReminder(AppSettings settings, bool on) async {
    if (!on) {
      await settings.setDailyReminder(false, settings.dailyReminderHour, minute: settings.dailyReminderMinute);
      await Reminders.disableAll();
      if (mounted) showOk(context, 'Reminders off.');
      return;
    }
    await _changeReminderTime(settings);
  }

  /// Hour + minute picker (MAN-10), then save and re-schedule the daily alarm.
  Future<void> _changeReminderTime(AppSettings settings) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.dailyReminderHour, minute: settings.dailyReminderMinute),
      helpText: 'Reminder time',
    );
    if (picked == null) return;
    await settings.setDailyReminder(true, picked.hour, minute: picked.minute);
    await Reminders.enableDaily(picked.hour, picked.minute); // same id → replaces the old alarm
    await Reminders.enableMonthEnd();
    final allowed = await PhoneNotifier.notificationsAllowed();
    if (!mounted) return;
    if (!allowed) await _notificationGuidance();
    if (!mounted) return;
    setState(() => _notifOn = allowed);
    showOk(context, 'Reminder set — roz ${_clock(picked.hour, picked.minute)} + month-end.');
  }

  /// MAN-12: explain what to do when the phone blocks notifications.
  Future<void> _notificationGuidance() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notifications are off'),
        content: const Text('FlavorFlow cannot show alerts or reminders until notifications are allowed. Open phone settings → Notifications → FlavorFlow and turn them on.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  /// Ask for the notification permission; if the phone blocks it for good, open its settings.
  Future<void> _enableNotifications() async {
    final st = await Permission.notification.request();
    if (st.isPermanentlyDenied) await openAppSettings();
    await _refresh();
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
        subtitle: switch (settings.darkPref) {
          DarkPref.off => 'OFF — classic light look',
          DarkPref.on => 'ON — easier on the eyes at night',
          DarkPref.system => 'System — follows the phone setting',
          DarkPref.auto =>
            'Auto — dark ${settings.autoDarkStart > 12 ? settings.autoDarkStart - 12 : settings.autoDarkStart} PM to ${settings.autoDarkEnd} AM (by time)',
        },
        onTap: () async {
          final picked = await showDialog<DarkPref>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: Text(tr('Dark theme')),
              children: [
                for (final (mode, label, icon) in [
                  (DarkPref.off, tr('Off — always light'), Icons.light_mode_outlined),
                  (DarkPref.on, tr('On — always dark'), Icons.dark_mode_outlined),
                  (DarkPref.system, tr('System — follow phone setting'), Icons.smartphone_rounded),
                  (DarkPref.auto, tr('Auto — dark by time (evening to morning)'), Icons.schedule_rounded),
                ])
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, mode),
                    child: Row(children: [
                      Icon(icon, size: 20, color: settings.darkPref == mode ? Theme.of(ctx).colorScheme.primary : null),
                      const SizedBox(width: 12),
                      Expanded(child: Text(label, style: TextStyle(fontWeight: settings.darkPref == mode ? FontWeight.w700 : FontWeight.w400))),
                      if (settings.darkPref == mode) Icon(Icons.check_rounded, size: 18, color: Theme.of(ctx).colorScheme.primary),
                    ]),
                  ),
              ],
            ),
          );
          if (picked == null) return;
          if (picked == DarkPref.auto) {
            // choose the evening hour for switching to dark
            final start = await showDialog<int>(
              // ignore: use_build_context_synchronously
              context: context,
              builder: (ctx) => SimpleDialog(
                title: Text(tr('Dark from (evening)')),
                children: [
                  for (final h in [17, 18, 19, 20, 21])
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, h),
                      child: Text('${h - 12}:00 PM'),
                    ),
                ],
              ),
            );
            await settings.setDarkPref(DarkPref.auto, start: start ?? settings.autoDarkStart);
          } else {
            await settings.setDarkPref(picked);
          }
          setState(() {});
        },
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
            ? 'ON — roz ${_clock(settings.dailyReminderHour, settings.dailyReminderMinute)} vaje yaad karauga (+ month-end ${CompanyProfile.usesLossPct ? 'Loss% close' : 'stock closing'}) · tap karke time badlo'
            : 'OFF — production/dispatch entry da roz da reminder',
        onTap: settings.dailyReminder ? () => _changeReminderTime(settings) : null,
        trailing: Switch(
          value: settings.dailyReminder,
          onChanged: (v) => _toggleReminder(settings, v),
        ),
      ),
      _tile(
        icon: Icons.notifications_active_outlined,
        title: 'Notification badge',
        subtitle: settings.showNotifBadge ? 'ON — unread count on the bell icon' : 'OFF — bell stays clean',
        trailing: Switch(value: settings.showNotifBadge, onChanged: (v) => settings.setShowNotifBadge(v)),
        onTap: () => settings.setShowNotifBadge(!settings.showNotifBadge),
      ),

      _tile(
        icon: Icons.notifications_none_rounded,
        title: 'Phone notifications',
        subtitle: _notifOn == null
            ? 'Checking…'
            : _notifOn!
                ? 'ON — alerts & reminders show on this phone'
                : 'OFF — tap to allow (needed for alerts & reminders)',
        onTap: _notifOn == false ? _enableNotifications : null,
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
        trailing: _totpBusy
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.2))
            : _totpEnabled == null
                ? null
                : Switch(value: _totpEnabled!, onChanged: (_) => _totpEnabled! ? _disable2fa() : _setup2fa()),
        onTap: (_totpEnabled == null || _totpBusy) ? null : (_totpEnabled! ? _disable2fa : _setup2fa),
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
          subtitle: 'Name, address, GSTIN · industry (units, categories, destinations)',
          onTap: () => showDialog(context: context, builder: (_) => const CompanyProfileDialog()),
        ),
        _tile(
          icon: Icons.receipt_long_outlined,
          title: tr('Billing setup (GST invoices)'),
          subtitle: 'GSTIN, invoice prefix, bank details, terms · printed on every tax invoice',
          onTap: () => context.push('/billing?tab=settings'),
        ),
      ],

      if (auth.subscription.status.available) ...[
        _section('SUBSCRIPTION'),
        _tile(
          icon: Icons.workspace_premium_outlined,
          title: tr('FlavorFlow subscription'),
          subtitle: '${auth.subscription.status.planName}${auth.subscription.status.planCycle.isEmpty ? '' : ' · ${auth.subscription.status.planCycle}'} · ${auth.subscription.status.state}${auth.subscription.status.until.isEmpty ? '' : ' · till ${auth.subscription.status.until}'} — plans, invoice, pay by cheque',
          onTap: () => context.push('/subscription'),
        ),
      ],

      _section('CONNECTION'),
      ListenableBuilder(
        listenable: OfflineQueue.instance,
        builder: (context, _) {
          final q = OfflineQueue.instance;
          final String sub;
          if (!q.online) {
            sub = 'Offline — ${q.pendingCount} waiting on this phone';
          } else if (q.failed.isNotEmpty) {
            sub = '${q.failed.length} need review · ${q.pendingCount} waiting';
          } else if (q.pendingCount > 0) {
            sub = '${q.pendingCount} waiting to sync';
          } else {
            sub = 'Online · nothing waiting';
          }
          return _tile(
            icon: Icons.cloud_sync_outlined,
            title: 'Offline entries (sync)',
            subtitle: sub,
            onTap: () => context.push('/sync'),
          );
        },
      ),
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
        subtitle: 'Version 1.2.0 · Universal manufacturing ERP',
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

