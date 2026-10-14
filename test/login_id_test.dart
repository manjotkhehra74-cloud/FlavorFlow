import 'package:flutter_test/flutter_test.dart';

import '../lib/core/login_id.dart';

void main() {
  group('FlavorFlow login ID canonicalization', () {
    test('migrates only the exact legacy suffix', () {
      expect(canonicalizeLoginId('operator@flavorflow.in'), 'operator@flavorflow.co.in');
      expect(canonicalizeLoginId(' operator@FLAVORFLOW.IN '), 'operator@flavorflow.co.in');
    });

    test('preserves other identifiers and already-migrated IDs', () {
      expect(canonicalizeLoginId('operator@flavorflow.co.in'), 'operator@flavorflow.co.in');
      expect(canonicalizeLoginId('admin@tops.in'), 'admin@tops.in');
      expect(canonicalizeLoginId('not-a-mailbox-login'), 'not-a-mailbox-login');
    });
  });
}
