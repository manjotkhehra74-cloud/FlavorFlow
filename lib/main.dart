import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_settings.dart';
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
  AppSettings.instance.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: L10n.instance),
        ChangeNotifierProvider.value(value: AppSettings.instance),
      ],
      child: const ErpApp(),
    ),
  );
}

class ErpApp extends StatefulWidget {
  const ErpApp({super.key});
  @override
  State<ErpApp> createState() => _ErpAppState();
}

class _ErpAppState extends State<ErpApp> {
  GoRouter? _router; // built ONCE — rebuilding it would reset navigation
                     // (e.g. the setup screen jumping back to step 1).

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    context.watch<L10n>(); // rebuild screens when the language changes
    final settings = context.watch<AppSettings>();
    Widget scaled(Widget child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(settings.textScale)),
          child: child,
        );
    if (!auth.ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark: settings.darkMode),
        home: const _Splash(),
      );
    }
    _router ??= buildRouter(auth);
    return MaterialApp.router(
      title: 'FlavorFlow ERP',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(dark: settings.darkMode),
      routerConfig: _router,
      builder: (context, child) => scaled(child ?? const SizedBox.shrink()),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF071A3B), Color(0xFF082A54), Color(0xFF07182F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 112,
              height: 112,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: AppBrand.blue.withValues(alpha: 0.38), blurRadius: 32, offset: const Offset(0, 10))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
            ),
            const SizedBox(height: 24),
            const Text('FlavorFlow', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
            const SizedBox(height: 3),
            const Text('ERP', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppBrand.green, letterSpacing: 4)),
            const SizedBox(height: 24),
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppBrand.green)),
          ]),
        ),
      ),
    );
  }
}
