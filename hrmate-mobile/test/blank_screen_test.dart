import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hrmate/core/api.dart';
import 'package:hrmate/core/i18n.dart';
import 'package:hrmate/core/theme.dart';
import 'package:hrmate/features/home/home_page.dart';
import 'package:hrmate/features/leaves/leaves_page.dart';
import 'package:hrmate/features/punch/punch_page.dart';
import 'package:hrmate/router.dart';
import 'package:hrmate/state/auth.dart';
import 'package:hrmate/ui/app_shell.dart';

/// Phase 7 regression: after the webapp-style shell redesign (white header +
/// custom bottom nav) the 3.2.0+32 device build rendered a BLANK body on
/// every tab while the nav drew fine. This test pumps the real router +
/// shell with offline (throwing) API data and asserts that the header and
/// the page content actually lay out on screen.
class _OfflineApi extends ApiClient {
  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async =>
      throw ApiException(-1, 'offline test');
  @override
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async =>
      throw ApiException(-1, 'offline test');
  @override
  Future<dynamic> put(String path, [Map<String, dynamic>? body]) async =>
      throw ApiException(-1, 'offline test');
  @override
  Future<dynamic> delete(String path) async =>
      throw ApiException(-1, 'offline test');
}

class _FakeAuth extends AuthController {
  // Static (lazy on first access) so the AuthController super-constructor —
  // which runs before subclass field initializers — never sees an
  // uninitialized value when it calls `api.onUnauthenticated = …`.
  static final ApiClient _shared = _OfflineApi();

  _FakeAuth() {
    ready = true;
    user = HrUser(
      id: 'u1',
      code: 'EMP001',
      name: 'Manjot Khehra',
      email: 'manjot@example.com',
      role: 'manager',
      department: 'Ops',
      avatarUrl: null,
      permissions: const {},
    );
    notifyListeners();
  }

  @override
  ApiClient get api => _shared;
}

void main() {
  testWidgets('P7 shell renders header + home content (blank-body regression)', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final auth = _FakeAuth();
    final router = buildRouter(auth);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          // Explicit type: inference from `value` would make this
          // ChangeNotifierProvider<_FakeAuth>, which the shell's
          // context.watch<AuthController>() cannot see.
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider.value(value: L10n.instance),
        ],
        child: MaterialApp.router(routerConfig: router, theme: buildTheme()),
      ),
    );
    await tester.pump(); // commit the initial /home route
    await tester.pump(const Duration(milliseconds: 60)); // settle _load microtasks

    // ---- TEMPORARY DIAGNOSTIC REPORT (remove once the blank body is fixed)
    // The header renders but the page content does not, with no exception.
    // This dump tells us exactly what the router handed to the shell and
    // which widgets exist, so the next fix is surgical.
    final report = StringBuffer('=== BLANK-SCREEN REPORT ===');
    final shellFinder = find.byType(AppShell);
    report.writeln('AppShell: ${shellFinder.evaluate().length}');
    if (shellFinder.evaluate().isNotEmpty) {
      final child = tester.widget<AppShell>(shellFinder.first).child;
      report.writeln('SHELL CHILD runtimeType: ${child.runtimeType}');
    }
    for (final probe in <(Type, String)>[
      (HomePage, 'HomePage'),
      (Scaffold, 'Scaffold'),
      (ListView, 'ListView'),
      (RefreshIndicator, 'RefreshIndicator'),
      (Stack, 'Stack'),
      (Text, 'Text'),
    ]) {
      report.writeln('${probe.$2}: ${find.byType(probe.$1).evaluate().length}');
    }
    report.writeln("text 'DIAG 33': ${find.textContaining('DIAG 33').evaluate().length}");
    report.writeln('text company subline: ${find.text(HrBrand.company).evaluate().length}');
    report.writeln("text 'Apply for leave': ${find.text('Apply for leave').evaluate().length}");
    report.writeln("text greeting(wave): ${find.textContaining('👋').evaluate().length}");
    report.writeln("text 'Sign in' (login leak): ${find.text('Sign in').evaluate().length}");
    report.writeln("text 'Punch': ${find.text('Punch').evaluate().length}");
    final homeFinder = find.byType(HomePage);
    if (homeFinder.evaluate().isNotEmpty) {
      report.writeln('HomePage rect: ${tester.getRect(homeFinder.first)}');
      report.writeln('--- AppShell element tree (layout dump) ---');
      report.writeln(
        tester.element(shellFinder.first)
            .debugDescribeChildren()
            .map((node) => node.toStringDeep())
            .join('\n'),
      );
    } else {
      report.writeln('HomePage: NOT IN TREE (check SHELL CHILD type above)');
    }
    final shellRect = shellFinder.evaluate().isNotEmpty ? tester.getRect(shellFinder.first) : null;
    report.writeln('AppShell rect: $shellRect');
    debugPrint(report.toString());
    // ---- END DIAGNOSTIC REPORT ----

    // --- header (webapp top bar) ---
    expect(find.text(HrBrand.company), findsOneWidget, reason: 'header company subline must render');
    final headerRect = tester.getRect(find.text(HrBrand.company));
    expect(headerRect.top, greaterThan(0.0), reason: 'header must be inside the screen');
    expect(headerRect.top, lessThan(200.0), reason: 'header must sit at the top, not be pushed off-screen');

    // --- home content (the part that rendered blank on the device) ---
    expect(find.textContaining('Manjot'), findsWidgets, reason: 'greeting and user pill must render');
    expect(find.text('Apply for leave'), findsOneWidget, reason: 'apply-leave button must render');
    final home = find.byType(HomePage).first;
    expect(tester.getSize(home).height, greaterThan(400.0), reason: 'home page must fill the body');
    expect(
      tester.getRect(find.text('Apply for leave')).bottom,
      lessThan(900.0),
      reason: 'home content must be on screen, not below the fold',
    );

    // --- tab switching must not blank the shell ---
    // NOTE: fixed pumps only — pumpAndSettle loops forever on the home
    // page's 1 s clock timer.
    await tester.tap(find.text('Punch').last); // nav label (last in tree order)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(HomePage), findsNothing);
    expect(find.byType(PunchPage), findsOneWidget);

    await tester.tap(find.text('Leaves').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LeavesPage), findsOneWidget);
  });
}
