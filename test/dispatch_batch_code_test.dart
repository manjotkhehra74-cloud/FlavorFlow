import 'package:flutter_test/flutter_test.dart';

import '../lib/features/dispatch/batch_code.dart';

void main() {
  group('dispatch batch code resolution', () {
    final soya220Batches = <Map<String, dynamic>>[
      {'id': 21, 'code': 'SOYA220-0918'},
      {'id': 22, 'batch_code': 'SOYA220-0920'},
    ];

    test('normalizes a scanned or typed code and resolves the matching batch', () {
      expect(normalizeDispatchBatchCode('  soya220-0920  '), 'SOYA220-0920');
      expect(dispatchBatchByCode(soya220Batches, ' soya220-0920 ')?['id'], 22);
      expect(dispatchBatchId({'id': '22'}), 22);
    });

    test('does not match an empty or unknown code', () {
      expect(dispatchBatchByCode(soya220Batches, '  '), isNull);
      expect(dispatchBatchByCode(soya220Batches, 'SOYA220-0000'), isNull);
    });
  });
}
