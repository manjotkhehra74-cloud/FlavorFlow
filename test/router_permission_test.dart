import 'package:flutter_test/flutter_test.dart';

import '../lib/router.dart';

void main() {
  group('route permission compatibility', () {
    test('personal settings and notifications stay available to signed-in users', () {
      bool denyAll(String _) => false;

      expect(hasRoutePermission('/settings', denyAll), isTrue);
      expect(hasRoutePermission('/notifications', denyAll), isTrue);
    });

    test('Stock Ledger accepts either its explicit permission or inventory view', () {
      expect(hasRoutePermission('/stock', (permission) => permission == 'stock.view'), isTrue);
      expect(hasRoutePermission('/stock', (permission) => permission == 'inventory.view'), isTrue);
      expect(hasRoutePermission('/stock', (permission) => permission == 'reports.view'), isFalse);
    });

    test('unrelated module routes still require their declared permission', () {
      expect(hasRoutePermission('/reports', (permission) => permission == 'reports.view'), isTrue);
      expect(hasRoutePermission('/reports', (permission) => permission == 'inventory.view'), isFalse);
    });
  });
}
