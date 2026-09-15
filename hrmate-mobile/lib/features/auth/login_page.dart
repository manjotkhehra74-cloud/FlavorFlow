import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/secure.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// Login — mirrors the webapp: logo, "HRMate", company line, employee code
/// or email + password, fingerprint unlock when a session is stored, and the
/// language selector.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    SecureStore.biometricAvailable().then((v) {
      if (mounted) setState(() => _bioAvailable = v);
    });
    // A locked session (fingerprint unlock on) → prompt right away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthController>();
      if (auth.locked) _unlock();
    });
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthController>();
    final err = await auth.login(_login.text, _password.text);
    if (!mounted) return;
    if (err != null) {
      showErr(context, err);
      return;
    }
    // Offer fingerprint unlock once, right after the first successful login.
    if (_bioAvailable && !(await SecureStore.biometricEnabled())) {
      if (!mounted) return;
      final enable = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('Enable fingerprint unlock')),
          content: Text(tr('Next time, open HRMate with your fingerprint instead of typing the password.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Not now'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Enable'))),
          ],
        ),
      );
      if (enable == true) {
        final ok = await SecureStore.verify(tr('Verify to enable fingerprint unlock'));
        if (ok) await SecureStore.setBiometricEnabled(true);
      }
    }
    // Router redirects to /home via refreshListenable.
  }

  Future<void> _unlock() async {
    final auth = context.read<AuthController>();
    final ok = await auth.unlockWithBiometrics(tr('Unlock HRMate'));
    if (!ok && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final l10n = context.watch<L10n>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: HrBrand.navy,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: HrBrand.blue.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/icon/app_icon.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.badge_rounded, color: Colors.white, size: 44),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(tr('HRMate'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('GD Foods Mfg. (I) Pvt. Ltd. · ${tr('Workforce Portal')}',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 28),
                  HrCard(
                    padding: const EdgeInsets.all(20),
                    child: auth.locked ? _lockedBody(auth) : _formBody(auth),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.language_rounded, size: 18, color: HrBrand.subInk),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: l10n.code,
                        underline: const SizedBox.shrink(),
                        style: const TextStyle(color: HrBrand.ink, fontSize: 14, fontWeight: FontWeight.w600),
                        items: [
                          for (final l in L10n.languages) DropdownMenuItem(value: l[0], child: Text(l[1])),
                        ],
                        onChanged: (v) {
                          if (v != null) l10n.set(v);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formBody(AuthController auth) => Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _login,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: InputDecoration(labelText: tr('Employee code or email'), prefixIcon: const Icon(Icons.person_outline_rounded)),
              validator: (v) => (v == null || v.trim().isEmpty) ? tr('Enter your employee code or email') : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => auth.busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: tr('Password'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? tr('Enter your password') : null,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: auth.busy ? null : _submit,
              child: auth.busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(tr('Sign in')),
            ),
          ],
        ),
      );

  Widget _lockedBody(AuthController auth) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.fingerprint_rounded, size: 64, color: HrBrand.blue),
          const SizedBox(height: 12),
          Text(tr('Unlock HRMate'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 18),
          FilledButton.icon(onPressed: _unlock, icon: const Icon(Icons.fingerprint_rounded), label: Text(tr('Unlock with fingerprint'))),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: auth.discardLocked, child: Text(tr('Sign in'))),
        ],
      );
}
