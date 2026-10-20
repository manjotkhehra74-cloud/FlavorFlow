import 'package:flutter_test/flutter_test.dart';

import '../lib/features/production/production_batch_filters.dart';

void main() {
  group('production batch filters', () {
    final batch = <String, dynamic>{
      'id': 81,
      'code': 'SOYA-2407-A',
      'product_id': 12,
      'product_name': 'Dark Soya 220 ml',
      'item_code': 'SOY-220',
      'planned_date': '2026-07-24 15:30:00',
    };

    test('uses product ID and falls back to a normalized product name', () {
      expect(productionBatchProductKey(batch), 'id:12');
      expect(
        productionBatchProductKey({'product_name': '  White Vinegar  '}),
        'name:white vinegar',
      );
      expect(
        productionBatchProductKey({'product_name': '', 'item_code': '  VIN-1 '}),
        'name:vin-1',
      );
      expect(productionBatchProductKey({}), isEmpty);
    });

    test('parses the planned date without changing its calendar day', () {
      expect(
        productionBatchPlannedDate(batch),
        DateTime(2026, 7, 24),
      );
      expect(
        productionBatchPlannedDate({'planned_date': '2026-07-24T00:00:00Z'}),
        DateTime(2026, 7, 24),
      );
      expect(productionBatchPlannedDate({'planned_date': 'not a date'}), isNull);
    });

    test('combines search, product, and inclusive planned-date filters', () {
      expect(
        matchesProductionBatchFilters(
          batch: batch,
          query: 'soya-2407',
          productKey: 'id:12',
          fromDate: DateTime(2026, 7, 24),
          throughDate: DateTime(2026, 7, 24),
        ),
        isTrue,
      );
      expect(
        matchesProductionBatchFilters(batch: batch, productKey: 'id:13'),
        isFalse,
      );
      expect(
        matchesProductionBatchFilters(batch: batch, query: 'vinegar'),
        isFalse,
      );
      expect(
        matchesProductionBatchFilters(
          batch: batch,
          fromDate: DateTime(2026, 7, 25),
        ),
        isFalse,
      );
    });

    test('batches without a planned date do not match a date filter', () {
      expect(
        matchesProductionBatchFilters(
          batch: {'code': 'OPENING-1', 'product_name': 'Opening stock'},
          fromDate: DateTime(2026, 7, 1),
        ),
        isFalse,
      );
      expect(
        matchesProductionBatchFilters(
          batch: {'code': 'OPENING-1', 'product_name': 'Opening stock'},
        ),
        isTrue,
      );
    });
  });
}
