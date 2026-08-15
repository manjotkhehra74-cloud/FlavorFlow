import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/company.dart';
import 'core/i18n.dart';
import 'core/theme.dart';
import 'router.dart';
import 'state/auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // One-time language + industry setup: ONLY on a truly fresh install —
  // never for a device that has already completed it or has ever signed in
  // (existing users updating the app must go straight to login/dashboard).
  final prefs = await SharedPreferences.getInstance();
  final alreadyUsed = (prefs.getBool('setup_done') ?? false) || prefs.getString('token') != null;
  if (alreadyUsed && !(prefs.getBool('setup_done') ?? false)) {
    await CompanyProfile.markSetupDone(); // existing install: lock it in
  }
  kNeedsFirstRunSetup = !alreadyUsed;
  final auth = AuthController();
  auth.restore();
  L10n.instance.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: L10n.instance),
      ],
      child: const ErpApp(),
    ),
  );
}

class ErpApp extends StatelessWidget {
  const ErpApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    context.watch<L10n>(); // rebuild the whole app when the language changes
    if (!auth.ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _Splash(),
      );
    }
    return MaterialApp.router(
      title: 'FlavorFlow ERP',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: buildRouter(auth),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 76, height: 76,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
            child: Icon(Icons.factory_rounded, color: scheme.onPrimaryContainer, size: 40),
          ),
          const SizedBox(height: 18),
          Text('FlavorFlow ERP', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onSurface, letterSpacing: -0.3)),
          const SizedBox(height: 14),
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
        ]),
      ),
    );
  }
}
