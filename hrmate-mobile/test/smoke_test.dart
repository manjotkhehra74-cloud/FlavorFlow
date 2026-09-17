import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrmate/core/theme.dart';
import 'package:hrmate/main.dart';
import 'package:hrmate/state/push.dart';

void main() {
  testWidgets('theme builds with the HRMate tokens', (tester) async {
    final t = buildTheme();
    expect(t.colorScheme.primary, HrBrand.blue);
    expect(t.scaffoldBackgroundColor, HrBrand.bg);
  });

  test('notification links map to app screens (Phase 6)', () {
    expect(PushController.screenFor('/leaves'), '/leaves');
    expect(PushController.screenFor('/approvals'), '/leaves');
    expect(PushController.screenFor('/attendance'), '/punch');
    expect(PushController.screenFor('/roster'), '/team');
    expect(PushController.screenFor('/wall'), '/home');
    expect(PushController.screenFor(null), '/home');
    expect(PushController.screenFor(''), '/home');
  });

  testWidgets('splash renders without text', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const SplashScreen()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });
}
