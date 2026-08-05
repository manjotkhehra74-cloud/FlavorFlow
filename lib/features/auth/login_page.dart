import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  String? _error;

  static const _demo = [
    ['Super Admin', 'super.admin@flavorflow.in', 'Super@123', Color(0xFF7C3AED)],
    ['Admin', 'admin@flavorflow.in', 'Admin@123', Color(0xFF2563EB)],
    ['Production Manager', 'pm@flavorflow.in', 'Prod@123', Color(0xFF0891B2)],
    ['Production Supervisor', 'ps@flavorflow.in', 'Super@1234', Color(0xFF0D9488)],
    ['Store Manager', 'sm@flavorflow.in', 'Store@123', Color(0xFFD97706)],
    ['Store Keeper', 'sk@flavorflow.in', 'Keeper@123', Color(0xFF65A30D)],
    ['Dispatch Manager', 'disp@flavorflow.in', 'Dispatch@123', Color(0xFFEA580C)],
    ['Director (Read Only)', 'director@flavorflow.in', 'Director@123', Color(0xFF475569)],
  ];

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    final err = await auth.login(_email.text.trim(), _password.text);
    if (!mounted) return;
    if (err != null) {
      setState(() => _error = err);
    } else {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.of(context).size.width >= 920;
    final auth = context.watch<AuthController>();
    final busy = auth.busy;

    final brandPanel = Container(
      color: Shell.bg,
      child: CustomPaint(
        painter: _DotGridPainter(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(44),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF0A6ED1), Color(0xFF0891B2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: const Text('FF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: 0.4)),
                  ),
                  const SizedBox(width: 12),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('FlavorFlow ERP', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                    Text('SAUCES & VINEGAR SUITE', style: TextStyle(color: Shell.groupLabel, fontSize: 8.5, fontWeight: FontWeight.w600, letterSpacing: 1.8)),
                  ]),
                ]),
                const SizedBox(height: 40),
                const Text('Plant operations,\none system of record.',
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.25)),
                const SizedBox(height: 12),
                Text('Production, stores, packing material and dispatch —\nwith strict role-based access on every screen.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13.5, height: 1.55)),
                const SizedBox(height: 32),
                for (final f in const [
                  'A different dashboard for every role',
                  'Cartons & trays with automatic packing consumption',
                  'Stock adjustments with approval & audit trail',
                  'Truck loading calculator with PDF docket',
                  'Every report exports to PDF and Excel',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(children: [
                      Container(
                        width: 19, height: 19,
                        decoration: BoxDecoration(color: const Color(0xFF0A6ED1).withValues(alpha: 0.30), borderRadius: BorderRadius.circular(5)),
                        child: const Icon(Icons.check_rounded, color: Color(0xFF7FBFF0), size: 13),
                      ),
                      const SizedBox(width: 11),
                      Text(f, style: const TextStyle(color: Color(0xFFC9D6E2), fontSize: 12.8, fontWeight: FontWeight.w500)),
                    ]),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );

    final formPanel = Container(
      color: Colors.white,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!wide) ...[
                Row(children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.center,
                    child: const Text('FF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  const SizedBox(width: 10),
                  Text('FlavorFlow ERP', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                ]),
                const SizedBox(height: 26),
              ],
              Text('Sign in', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: scheme.onSurface, letterSpacing: -0.4)),
              const SizedBox(height: 5),
              Text('Your workspace adapts to your role.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 24),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBEAEA),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFEFC0C0)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C), size: 18),
                    const SizedBox(width: 9),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w500, fontSize: 12.5))),
                  ]),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email_rounded, size: 19)),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 13),
              TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 19),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : _submit,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : const Text('Sign in'),
              ),
              const SizedBox(height: 26),
              Divider(color: scheme.outlineVariant),
              const SizedBox(height: 14),
              Text('DEMO ACCOUNTS — TAP TO FILL',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              Wrap(spacing: 7, runSpacing: 7, children: [
                for (final d in _demo)
                  InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => setState(() {
                      _email.text = d[1] as String;
                      _password.text = d[2] as String;
                      _error = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5.5),
                      decoration: BoxDecoration(
                        color: (d[3] as Color).withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: (d[3] as Color).withValues(alpha: 0.30)),
                      ),
                      child: Text(d[0] as String, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: d[3] as Color)),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              _ServerBar(),
            ]),
          ),
        ),
      ),
    );

    return Scaffold(
      body: wide
          ? Row(children: [Expanded(flex: 11, child: brandPanel), Expanded(flex: 10, child: formPanel)])
          : formPanel,
    );
  }
}

/// Subtle blueprint dot-grid for the brand panel.
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x0FFFFFFF);
    const gap = 26.0;
    for (double x = gap / 2; x < size.width; x += gap) {
      for (double y = gap / 2; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
    // soft glow accent in the corner
    final glow = Paint()
      ..shader = RadialGradient(colors: [const Color(0xFF0A6ED1).withValues(alpha: 0.35), Colors.transparent])
          .createShader(Rect.fromCircle(center: Offset(size.width * 0.85, size.height * 0.12), radius: size.width * 0.5));
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


/// Shows which server the app talks to + lets the user change/test it.
class _ServerBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final base = auth.serverBase;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => showDialog(context: context, builder: (_) => const _ServerDialog()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.dns_outlined, size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(base ?? 'Server not set — tap to set',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 4),
          Icon(Icons.edit_outlined, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }
}

class _ServerDialog extends StatefulWidget {
  const _ServerDialog();
  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  final ctl = TextEditingController();
  bool testing = false;
  String? result;
  bool ok = false;

  @override
  void initState() {
    super.initState();
    ctl.text = context.read<AuthController>().serverBase ?? '';
  }

  Future<void> _test() async {
    setState(() { testing = true; result = null; });
    final err = await ApiClient.testConnection(ctl.text);
    if (mounted) setState(() { testing = false; ok = err == null; result = ok ? 'Connected — server found!' : err; });
  }

  Future<void> _save({bool reset = false}) async {
    final text = reset ? '' : ctl.text.trim();
    if (!reset && text.isEmpty) {
      setState(() { ok = false; result = 'Type the server address first.'; });
      return;
    }
    await context.read<AuthController>().setServerBase(reset ? null : ApiClient.normalizeBase(text));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ERP Server Address'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: ctl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Server address',
              hintText: 'http://192.168.1.10:4000 or https://erp.company.com',
            ),
          ),
          const SizedBox(height: 8),
          Text('Office Wi-Fi: the address shown in the black window on the PC.\nCloud: your https domain. Change only if your IT asks you to.',
              style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4)),
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
              onPressed: testing ? null : _test,
              icon: const Icon(Icons.wifi_find_rounded, size: 16),
              label: Text(testing ? 'Testing…' : 'Test connection'),
            ),
            const SizedBox(width: 10),
            if (result != null)
              Expanded(
                child: Text(result!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ok ? const Color(0xFF047857) : Theme.of(context).colorScheme.error)),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => _save(reset: true), child: const Text('Use automatic')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => _save(), child: const Text('Save')),
      ],
    );
  }
}
