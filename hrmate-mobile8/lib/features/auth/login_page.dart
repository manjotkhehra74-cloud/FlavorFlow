import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';

/// Login — webapp-faithful navy screen (Phase 8). Real API only:
/// `POST /auth/login` with Bearer session storage; the server is the
/// authority (ARCHITECTURE.md §6). No fake states, no dead controls.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _loginCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _showPass = false;
  String? _error;

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _error = null;
    });
    final auth = context.read<AuthController>();
    final err = await auth.login(_loginCtrl.text, _passCtrl.text);
    if (!mounted) return;
    if (err != null) {
      setState(() => _error = err);
    }
    // success: auth.notifyListeners() → router redirect → /home
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final l10n = context.watch<L10n>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: HrBrand.punchGradient,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // --- brand ---
                  Container(
                    width: 84,
                    height: 84,
                    margin: const EdgeInsets.only(bottom: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: HrBrand.shadowPop),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/icon/app_icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.badge_rounded, color: HrBrand.blue, size: 44),
                    ),
                  ),
                  const Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'HR', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
                      TextSpan(text: 'Mate', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: HrBrand.emeraldOnNavy, height: 1)),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr('Workforce Portal') + ' · ' + HrBrand.company,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: HrBrand.slateOnNavy, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 28),
                  // --- form card ---
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(HrBrand.radiusLogin), boxShadow: HrBrand.shadowPop),
                    child: Form(
                      key: _formKey,
                      child: Column(children: [
                        TextField(
                          controller: _loginCtrl,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          style: const TextStyle(fontSize: 14.5, color: HrBrand.ink),
                          decoration: InputDecoration(
                            labelText: tr('Employee code or email'),
                            prefixIcon: const Icon(Icons.badge_outlined, size: 20, color: HrBrand.faint),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? tr('Enter your employee code or email') : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passCtrl,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          obscureText: !_showPass,
                          autocorrect: false,
                          style: const TextStyle(fontSize: 14.5, color: HrBrand.ink),
                          decoration: InputDecoration(
                            labelText: tr('Password'),
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: HrBrand.faint),
                            suffixIcon: IconButton(
                              icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: HrBrand.faint),
                              onPressed: () => setState(() => _showPass = !_showPass),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? tr('Enter your password') : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(color: HrBrand.redContainer, borderRadius: BorderRadius.circular(10)),
                            child: Row(children: [
                              const Icon(Icons.error_outline_rounded, size: 16, color: HrBrand.redText),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: HrBrand.redText))),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: auth.busy ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: HrBrand.navyButton,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                              shadowColor: Colors.black,
                              disabledBackgroundColor: HrBrand.navyLight,
                            ),
                            child: auth.busy
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                : Text(tr('Sign in'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // --- language switch (webapp footer control) ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < L10n.languages.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(L10n.languages[i][1], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            selected: l10n.code == L10n.languages[i][0],
                            selectedColor: HrBrand.blue,
                            labelStyle: TextStyle(color: l10n.code == L10n.languages[i][0] ? Colors.white : HrBrand.slateOnNavy),
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            side: BorderSide.none,
                            onSelected: (_) => l10n.set(L10n.languages[i][0]),
                          ),
                        ),
                    ],
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
