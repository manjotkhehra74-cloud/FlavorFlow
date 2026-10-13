import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/dispatch/destination_field.dart';

void main() {
  group('dispatch destination field', () {
    test('normalizes whitespace and casing for saved/API values', () {
      expect(normalizeDispatchDestination('  North   Star Foods  '), 'NORTH STAR FOODS');
      expect(normalizeDispatchDestination('   '), isEmpty);
    });

    testWidgets('starts blank and accepts a manually typed company name', (tester) async {
      final controller = TextEditingController();
      String? latestValue;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DispatchDestinationField(
            controller: controller,
            suggestions: const ['TEST CUSTOMER LTD'],
            onChanged: (value) => latestValue = value,
          ),
        ),
      ));

      expect(controller.text, isEmpty, reason: 'a new dispatch must not pick a destination for the user');
      expect(find.byHintText('Enter customer, company or destination'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'North Star Foods');
      expect(controller.text, 'North Star Foods');
      expect(latestValue, 'North Star Foods');

      await tester.tap(find.byTooltip('Saved destination suggestions'));
      await tester.pumpAndSettle();
      expect(find.text('TEST CUSTOMER LTD'), findsOneWidget);

      await tester.tap(find.text('TEST CUSTOMER LTD'));
      await tester.pumpAndSettle();
      expect(controller.text, 'TEST CUSTOMER LTD');
      expect(latestValue, 'TEST CUSTOMER LTD');

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  });
}
