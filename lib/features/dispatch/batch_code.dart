/// Normalize a batch label before comparing it with the available batch list.
///
/// Operators may scan a code with surrounding whitespace or mixed casing; the
/// dispatch API should receive the same canonical value as the selected batch.
String normalizeDispatchBatchCode(Object? value) =>
    (value?.toString() ?? '').trim().toUpperCase();

/// Read a batch ID from both integer and string-backed API responses.
int? dispatchBatchId(Map<String, dynamic>? batch) {
  final rawId = batch?['id'];
  if (rawId is int) return rawId;
  if (rawId is num) return rawId.toInt();
  return int.tryParse('${rawId ?? ''}');
}

/// Resolve a typed or scanned batch code to its product-scoped batch option.
///
/// The dispatch batch endpoint uses `code`; older production responses may use
/// `batch_code` or `batchCode`. The caller passes only the selected product's
/// batches, so a code on another product can never be selected accidentally.
Map<String, dynamic>? dispatchBatchByCode(
  Iterable<Map<String, dynamic>> batches,
  Object? rawCode,
) {
  final code = normalizeDispatchBatchCode(rawCode);
  if (code.isEmpty) return null;

  for (final batch in batches) {
    final batchCode = normalizeDispatchBatchCode(
      batch['code'] ?? batch['batch_code'] ?? batch['batchCode'],
    );
    if (batchCode == code) return batch;
  }
  return null;
}
