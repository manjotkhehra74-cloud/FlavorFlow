import 'package:flutter_test/flutter_test.dart';

import '../lib/features/drums/drum_opening_balances.dart';

void main() {
  group('PDF drum opening balances', () {
    test('keeps the duplicate Pear Pulp page from being counted twice', () {
      final pearPulp = drumOpeningBalances.where((balance) => balance.productName == 'Pear Pulp').toList();

      expect(pearPulp, hasLength(1));
      expect(pearPulp.single.availableDrums, 6);
      expect(pearPulp.single.balanceKg, 1270);
    });

    test('uses the final report balance for Carrot Paste', () {
      final carrotPaste = drumOpeningBalances.singleWhere((balance) => balance.productName == 'Carrot Paste Salt Mix (10%)');

      expect(carrotPaste.availableDrums, 4086);
      expect(carrotPaste.balanceKg, 903267);
    });

    test('combines the two distinct Red Chilli sheets by product name', () {
      final redChilli = drumOpeningBalances.where((balance) => drumProductBalanceKey(balance.productName) == 'red chilli puree salted');

      expect(redChilli, hasLength(2));
      expect(redChilli.fold<int>(0, (sum, balance) => sum + balance.availableDrums), 128);
      expect(redChilli.fold<double>(0, (sum, balance) => sum + balance.balanceKg), 28190);
    });

    test('contains the unique product balances from the report snapshot', () {
      final productNames = drumOpeningBalances.map((balance) => drumProductBalanceKey(balance.productName)).toSet();
      final drumTotal = drumOpeningBalances.fold<int>(0, (sum, balance) => sum + balance.availableDrums);
      final kgTotal = drumOpeningBalances.fold<double>(0, (sum, balance) => sum + balance.balanceKg);

      expect(productNames, hasLength(11));
      expect(drumTotal, 20279);
      expect(kgTotal, closeTo(4471159.5, 0.01));
      expect(drumOpeningBalanceSnapshotLabel, '22 Oct 2026');
    });
  });
}
