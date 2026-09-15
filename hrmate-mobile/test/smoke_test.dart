import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrmate/core/theme.dart';
import 'package:hrmate/main.dart';

void main() {
  testWidgets('theme builds with the HRMate tokens', (tester) async {
    final t = buildTheme();
    expect(t.colorScheme.primary, HrBrand.blue);
    expect(t.scaffoldBackgroundColor, HrBrand.bg);
  });

  testWidgets('splash renders without text', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const SplashScreen()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });
}
