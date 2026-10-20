/// Stable product key for filtering batches when product names are duplicated.
/// Fall back to the product name for older batch responses without an ID.
String productionBatchProductKey(Map<String, dynamic> batch) {
  final id = batch['product_id']?.toString().trim();
  if (id != null && id.isNotEmpty) return 'id:$id';

  var name = '${batch['product_name'] ?? ''}'.trim();
  if (name.isEmpty) name = '${batch['item_code'] ?? ''}'.trim();
  name = name.toLowerCase();
  return name.isEmpty ? '' : 'name:$name';
}

/// Parses the manufacturing/planned date as a date-only value, avoiding time
/// zone shifts for server strings such as `2026-10-18 08:30:00`.
DateTime? productionBatchPlannedDate(Map<String, dynamic> batch) {
  final raw = batch['planned_date'];
  if (raw == null) return null;
  if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day);

  final value = raw.toString().trim();
  if (value.isEmpty || value == '—') return null;
  final datePart = value.split(RegExp(r'[T ]')).first;
  final parsed = DateTime.tryParse(datePart);
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

/// Combines the production-register search, product, and inclusive date-range
/// filters. Null filter values mean that dimension is not restricted.
bool matchesProductionBatchFilters({
  required Map<String, dynamic> batch,
  String? query,
  String? productKey,
  DateTime? fromDate,
  DateTime? throughDate,
}) {
  if (productKey != null && productionBatchProductKey(batch) != productKey) {
    return false;
  }

  final normalizedQuery = query?.trim().toLowerCase() ?? '';
  if (normalizedQuery.isNotEmpty) {
    final haystack =
        '${batch['code'] ?? ''} ${batch['product_name'] ?? ''} ${batch['item_code'] ?? ''}'
            .toLowerCase();
    if (!haystack.contains(normalizedQuery)) return false;
  }

  if (fromDate != null || throughDate != null) {
    final batchDate = productionBatchPlannedDate(batch);
    if (batchDate == null) return false;

    if (fromDate != null) {
      final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
      if (batchDate.isBefore(start)) return false;
    }
    if (throughDate != null) {
      final end = DateTime(throughDate.year, throughDate.month, throughDate.day);
      if (batchDate.isAfter(end)) return false;
    }
  }

  return true;
}
