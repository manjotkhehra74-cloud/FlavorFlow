import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/i18n.dart';
import 'core/theme.dart';
import 'router.dart';
import 'state/auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthController();
  auth.restore();
  L10n.instance.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider.value(value: L10n.instance),
      ],
      child: const HrMateApp(),
    ),
  );
}

class HrMateApp extends StatefulWidget {
  const HrMateApp({super.key});
  @override
  State<HrMateApp> createState() => _HrMateAppState();
}

class _HrMateAppState extends State<HrMateApp> {
  GoRouter? _router; // built ONCE — rebuilding it would reset navigation

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    context.watch<L10n>(); // rebuild on language change
    // Text scale comes from the phone's accessibility setting, clamped so the
    // layout never breaks. NEVER derive it from a stored preference value
    // (ARCHITECTURE.md §7 — that produced the 1-px text build).
    Widget clamped(BuildContext ctx, Widget child) {
      final scale = MediaQuery.of(ctx).textScaler.scale(1.0).clamp(0.9, 1.3);
      return MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: child,
      );
    }
    if (!auth.ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const SplashScreen(),
      );
    }
    _router ??= buildRouter(auth);
    return MaterialApp.router(
      title: 'HRMate',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: _router,
      builder: (ctx, child) => clamped(ctx, child ?? const SizedBox.shrink()),
    );
  }
}

/// Opaque navy, icon + spinner, NO text (ARCHITECTURE.md §7). Shown only
/// until AuthController.restore() finishes (well under a second).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: HrBrand.navy,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26)),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/icon/app_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.badge_rounded, color: HrBrand.blue, size: 52),
              ),
            ),
            const SizedBox(height: 28),
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
          ]),
        ),
      );
}
