import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/secure.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// Login — the webapp's login page (Phase 7): navy gradient + ambient
/// glows, white rounded-32 card, logo + "HR" + "Mate", green uppercase
/// company line, dark "#0F172A" submit, green biometric button, language
/// pill top-right.
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF081C33), HrBrand.navyDark, HrBrand.navyLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(children: [
          const NavyGlow(color: HrBrand.emerald, top: -80, right: -80, size: 320),
          const NavyGlow(color: HrBrand.blue, bottom: -80, left: -80, size: 320),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(children: [
                    // ---- language pill (webapp: top-right) ----
                    Align(alignment: Alignment.topRight, child: _LangPill(l10n: l10n)),
                    const SizedBox(height: 26),
                    // ---- white rounded-32 card ----
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(HrBrand.radiusLogin),
                        boxShadow: HrBrand.shadowPop,
                      ),
                      child: Column(children: [
                        Container(
                          width: 64,
                          height: 64,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: HrBrand.shadowGlow),
                          child: Image.asset(
                            'assets/icon/app_icon.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.badge_rounded, color: HrBrand.blue, size: 34),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text.rich(
                          TextSpan(children: const [
                            TextSpan(text: 'HR', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: HrBrand.heading, height: 1)),
                            TextSpan(text: 'Mate', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: HrBrand.blue, height: 1)),
                          ]),
                        ),
                        const SizedBox(height: 5),
                        Text(HrBrand.company.toUpperCase(),
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: HrBrand.emeraldDeep)),
                        const SizedBox(height: 3),
                        Text(tr('Workforce Portal'), style: const TextStyle(fontSize: 12, color: HrBrand.subInk)),
                        const SizedBox(height: 22),
                        auth.locked ? _lockedBody(auth) : _formBody(auth),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
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
            const SizedBox(height: 18),
            // webapp: dark #0F172A "Sign In with Password"
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: HrBrand.navyButton,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                onPressed: auth.busy ? null : _submit,
                child: auth.busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text(tr('Sign in with password')),
              ),
            ),
          ],
        ),
      );

  Widget _lockedBody(AuthController auth) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.fingerprint_rounded, size: 56, color: HrBrand.emeraldDeep),
          const SizedBox(height: 12),
          Text(tr('Unlock HRMate'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 18),
          HrGradientButton(onPressed: _unlock, icon: Icons.fingerprint_rounded, label: tr('Unlock with fingerprint')),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(tr('or with password'), style: const TextStyle(fontSize: 11, color: HrBrand.faint))),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: auth.discardLocked, child: Text(tr('Sign in'))),
        ],
      );
}

/// White/10 language pill on the navy page (webapp top-right).
class _LangPill extends StatelessWidget {
  final L10n l10n;
  const _LangPill({required this.l10n});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(left: 10, right: 6, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.language_rounded, size: 14, color: HrBrand.faint),
          const SizedBox(width: 6),
          DropdownButton<String>(
            value: l10n.code,
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
            dropdownColor: HrBrand.navyMid,
            items: [
              for (final l in L10n.languages) DropdownMenuItem(value: l[0], child: Text(l[1])),
            ],
            onChanged: (v) {
              if (v != null) l10n.set(v);
            },
          ),
        ]),
      );
}
