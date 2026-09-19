import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hrmate/core/api.dart';
import 'package:hrmate/features/auth/login_page.dart';
import 'package:hrmate/core/i18n.dart';
import 'package:hrmate/core/theme.dart';
import 'package:hrmate/router.dart';
import 'package:hrmate/state/auth.dart';
import 'package:hrmate/ui/app_shell.dart';

/// Phase 8 render gate (ARCHITECTURE.md §8): the real router + shell +
/// every tab, with an OFFLINE (throwing) API. The assertion is layout
/// truth — the header, the nav, and the page body must actually exist on
/// screen. No pumpAndSettle anywhere: Home has a 1 s clock ticker and the
/// shimmer repeats, so the tree never "settles" — pump with fixed durations.
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
  Future<dynamic> delete(String path) async => throw ApiException(-1, 'offline test');
}

class _FakeAuth extends AuthController {
  // Static (lazy on first access) so the AuthController super-constructor —
  // which runs before subclass field initializers and calls `api` — never
  // sees an uninitialized value.
  static final ApiClient _shared = _OfflineApi();

  _FakeAuth({HrUser? user}) {
    this.user = user;
    ready = true;
    notifyListeners();
  }

  @override
  ApiClient get api => _shared;
}

HrUser _manager() => HrUser(
      id: 'u1',
      code: 'EMP001',
      name: 'Manjot Khehra',
      email: 'manjot@example.com',
      role: 'manager',
      department: 'Ops',
      avatarUrl: null,
      permissions: const {},
    );

void _sizePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester, AuthController auth) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        // Explicit type: inference from `value` would make this
        // ChangeNotifierProvider<_FakeAuth>, which
        // context.watch<AuthController>() cannot see.
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider.value(value: L10n.instance),
      ],
      child: MaterialApp.router(routerConfig: buildRouter(auth), theme: buildTheme()),
    ),
  );
  await tester.pump(); // commit initial route
  // Let the offline fetches fail + UI settle — fixed durations, NEVER
  // pumpAndSettle (Home's 1 s ticker + repeating shimmer never settle).
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  testWidgets('login screen renders (signed out)', (tester) async {
    _sizePhone(tester);
    await _pump(tester, _FakeAuth());

    expect(find.text('Sign in'), findsWidgets); // button
    expect(find.byType(LoginPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authenticated shell: header + nav + home body (blank-body regression)', (tester) async {
    _sizePhone(tester);
    await _pump(tester, _FakeAuth(user: _manager()));

    // Shell chrome
    expect(find.byType(AppShell), findsOneWidget);
    // Nav — all five tabs (manager sees Team)
    for (final label in ['Home', 'Leaves', 'Punch', 'Team', 'More']) {
      expect(find.text(label), findsWidgets, reason: 'nav label $label');
    }
    // Home body — offline: error card with real retry + announcements block
    expect(find.textContaining('Welcome to HRMate'), findsOneWidget);
    expect(find.text('Announcements'), findsOneWidget);
    expect(find.text('No announcements right now'), findsOneWidget);
    // Offline fetch of attendance/today → the navy slot becomes an error
    // card with a working Retry.
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Retry'), findsWidgets);
    // Header wordmark is rich text — verify via the company subline instead.
    expect(find.text(HrBrand.company), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaves tab renders Phase-2 screen', (tester) async {
    _sizePhone(tester);
    await _pump(tester, _FakeAuth(user: _manager()));
    await tester.tap(find.text('Leaves'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('Coming in Phase 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('punch tab renders Phase-3 screen', (tester) async {
    _sizePhone(tester);
    await _pump(tester, _FakeAuth(user: _manager()));
    await tester.tap(find.text('Punch').last); // nav instance (Home has a 'Punch' tile)
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('Coming in Phase 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('team tab renders Phase-4 screen (manager only)', (tester) async {
    _sizePhone(tester);
    await _pump(tester, _FakeAuth(user: _manager()));
    await tester.tap(find.text('Team'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('Coming in Phase 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('employee (non-manager) has NO team tab, home still renders', (tester) async {
    _sizePhone(tester);
    await _pump(tester, _FakeAuth(user: HrUser(
      id: 'u2', code: 'EMP002', name: 'Ravi Singh', email: 'ravi@example.com',
      role: 'employee', department: 'Ops', avatarUrl: null, permissions: const {},
    )));
    // Nav shows 4 tabs — Team absent.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('More'), findsWidgets);
    // 'Team' should not appear anywhere on home for an employee.
    expect(find.text('Team'), findsNothing);
    expect(find.textContaining('Welcome to HRMate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('more tab renders working sign-out + Phase-5 screen', (tester) async {
    _sizePhone(tester);
    await _pump(tester, _FakeAuth(user: _manager()));
    await tester.tap(find.text('More'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('Sign out'), findsOneWidget); // working control
    expect(find.text('Coming in Phase 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
