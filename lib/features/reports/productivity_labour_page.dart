import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/download.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

const _localLabourKey = 'flavorflow_productivity_local_labour';

const _lineSkuRules = <String, Set<String>>{
  'line 2': {
    'soya sauce 740',
    'soya sauce 1.3',
    'white vinegar 610',
    'brown vinegar 610',
    'vinegar 1.0',
  },
  'line 3': {
    'dark soya 220',
    'white vinegar 180',
    'soya sauce 4.7',
    'white vinegar 4.0',
  },
};

String _skuRuleKey(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String? _lineForSku(String sku) {
  final key = _skuRuleKey(sku).replaceAll(' ', '');
  // Production history sometimes stores the pack size as gm/ml/Ltr instead
  // of the product-master text. Keep those existing records line-assigned.
  if (key.contains('soyasauce740') ||
      key.contains('soyasauce1.3') ||
      key.contains('whitevinegar610') ||
      key.contains('brownvinegar610') ||
      key.contains('vinegar610') ||
      key.contains('vinegar1.0') ||
      key.contains('vinegar1ltr') ||
      key.contains('whitevinegar1ltr')) return 'Line 2';
  if (key.contains('darksoya220') ||
      key.contains('whitevinegar180') ||
      key.contains('vinegar180') ||
      key.contains('soyasauce4.7') ||
      key.contains('whitevinegar4.0') ||
      key.contains('whitevinegar4ltr')) return 'Line 3';
  return null;
}

bool _isUnassignedLine(String line) {
  final key = _skuRuleKey(line);
  return key.isEmpty || key == 'unassigned' || key == 'unknown' || key == 'n/a';
}

bool _skuAllowedForLine(String line, String sku) {
  final allowed = _lineSkuRules[_skuRuleKey(line)];
  if (allowed == null) return true;
  return allowed.contains(_skuRuleKey(sku)) || _skuRuleKey(_lineForSku(sku) ?? '') == _skuRuleKey(line);
}

String _labourSku(Map<String, dynamic> row) {
  for (final value in [row['productId'], row['product_id'], row['sku'], row['product'], row['productName'], row['product_name']]) {
    if (value != null && '$value'.trim().isNotEmpty) return '$value';
  }
  return '';
}

String _labourIdentity(Map<String, dynamic> row) =>
    '${row['date'] ?? ''}|${_skuRuleKey('${row['line'] ?? ''}')}|${_skuRuleKey('${row['shift'] ?? ''}')}|${_skuRuleKey(_labourSku(row))}';

Future<List<Map<String, dynamic>>> _readLocalLabour() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localLabourKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).whereType<Map>().map((r) => r.cast<String, dynamic>()).toList();
  } catch (_) {
    return [];
  }
}

Future<void> _writeLocalLabour(Map<String, dynamic> row) async {
  final prefs = await SharedPreferences.getInstance();
  final rows = await _readLocalLabour();
  final identity = _labourIdentity(row);
  final existingIndex = rows.indexWhere((r) => _labourIdentity(r) == identity);
  final existingId = existingIndex == -1 ? null : rows[existingIndex]['id'];
  final id = '${row['id'] ?? existingId ?? 'local-${DateTime.now().microsecondsSinceEpoch}'}';
  final value = {...row, 'id': id, 'localOnly': true};
  final index = rows.indexWhere((r) => '${r['id']}' == id);
  if (index == -1) {
    rows.add(value);
  } else {
    rows[index] = value;
  }
  await prefs.setString(_localLabourKey, jsonEncode(rows));
}

/// Lets the test build keep manual entries editable when the older server has
/// not received /labour/daily yet. Server rows remain authoritative once the
/// endpoint is available; local rows are only an offline/test fallback.
Future<List<Map<String, dynamic>>> _loadLabourRows(ApiClient api, String query) async {
  List<Map<String, dynamic>> server = [];
  try {
    final json = await api.get('/labour/daily?$query');
    server = ((json as Map)['rows'] as List? ?? const []).cast<Map<String, dynamic>>();
  } catch (_) {}
  final params = Uri.splitQueryString(query);
  final local = (await _readLocalLabour()).where((r) {
    final date = '${r['date'] ?? ''}'.split(RegExp(r'[T ]')).first;
    final shift = '${r['shift'] ?? ''}';
    final line = '${r['line'] ?? ''}';
    final sku = _labourSku(r);
    return (params['from'] == null || date.compareTo(params['from']!) >= 0) &&
        (params['to'] == null || date.compareTo(params['to']!) <= 0) &&
        (params['sku'] == null || sku == params['sku'] || _skuRuleKey(sku) == _skuRuleKey(params['sku']!)) &&
        (params['shift'] == null || shift.toLowerCase() == params['shift']!.toLowerCase()) &&
        (params['line'] == null || line.toLowerCase() == params['line']!.toLowerCase());
  }).toList();
  final byId = <String, Map<String, dynamic>>{for (final r in server) if (r['id'] != null) '${r['id']}': r};
  for (final r in local) {
    final id = r['id'];
    if (id == null) {
      server.add(r);
    } else {
      byId['$id'] = r;
    }
  }
  final result = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final r in [...server, ...local]) {
    final id = r['id'];
    if (id == null) {
      result.add(r);
    } else if (seen.add('$id')) {
      result.add(byId['$id'] ?? r);
    }
  }
  return result;
}

/// Production productivity + daily labour register.
///
/// Productivity is read from completed production batches. Labour is entered
/// manually per date / shift / line / SKU; it is deliberately not a fixed
/// value on the product master because line manpower changes every day.
class ProductivityLabourPage extends StatefulWidget {
  const ProductivityLabourPage({super.key});

  @override
  State<ProductivityLabourPage> createState() => _ProductivityLabourPageState();
}

class _ProductivityLabourPageState extends State<ProductivityLabourPage> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late DateTime _from;
  late DateTime _to;
  Future<Map<String, dynamic>>? _productivityFuture;
  Future<List<Map<String, dynamic>>>? _labourFuture;
  Future<Map<String, dynamic>>? _analysisFuture;
  final _lineFilter = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  String? _skuFilter;
  String _shiftFilter = 'Combined';
  bool _exporting = false;

  String get _fromYmd => _ymd(_from);
  String get _toYmd => _ymd(_to);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0);
    _loadProducts();
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _lineFilter.dispose();
    super.dispose();
  }

  String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadProducts() async {
    try {
      final json = await context.read<AuthController>().api.get('/products');
      if (!mounted) return;
      setState(() => _products = ((json as Map)['products'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .where((p) => (p['active'] as num? ?? 1) != 0)
          .toList());
    } catch (_) {
      // The report still works when an older server has no product list.
    }
  }

  String _query({bool includeSku = true}) {
    final values = <String, String>{
      'from': _fromYmd,
      'to': _toYmd,
      if (includeSku && _skuFilter != null && _skuFilter!.isNotEmpty) 'sku': _skuFilter!,
      if (_lineFilter.text.trim().isNotEmpty) 'line': _lineFilter.text.trim(),
      if (_shiftFilter != 'Combined') 'shift': _shiftFilter,
    };
    return Uri(queryParameters: values).query;
  }

  Map<String, dynamic> _emptyProductivity() => {
        'columns': const ['SKU', 'LINE', 'MANPOWER', 'PROD. IN KG', 'PROD. IN CB', 'PRODUCTIVITY IN KG/HEAD', 'PRODUCTIVITY IN CB/HEAD'],
        'rows': const [],
        'totals': const {},
      };

  num _n(Object? value) {
    if (value is num) return value;
    return num.tryParse('${value ?? 0}') ?? 0;
  }

  String _dateOnly(Object? value) => value == null ? '' : '$value'.split(RegExp(r'[T ]')).first;

  String _productionDate(Map<String, dynamic> batch) => _dateOnly(
        batch['production_date'] ??
            batch['productionDate'] ??
            batch['manufacturing_date'] ??
            batch['manufacturingDate'] ??
            batch['planned_date'] ??
            batch['plannedDate'] ??
            batch['completed_at'] ??
            batch['completedAt'],
      );

  String _productivityLabel(String source) {
    final key = source.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (key.contains('whitevinegar610') || key.contains('brownvinegar610')) return 'Vinegar 610';
    return source;
  }

  int _columnIndex(List<String> columns, String name, int fallback) {
    final index = columns.indexWhere((c) {
      final normalized = c.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      return normalized == name || (name == 'line' && normalized == 'productionline');
    });
    return index == -1 ? fallback : index;
  }

  Map<String, dynamic> _normaliseProductivity(Map<String, dynamic> source) {
    final raw = source['rows'];
    if (raw is! List || raw.isEmpty) return source;
    final sourceColumns = (source['columns'] as List? ?? const []).map((v) => '$v').toList();
    final skuIndex = _columnIndex(sourceColumns, 'sku', 0);
    final lineIndex = _columnIndex(sourceColumns, 'line', -1);
    final manpowerIndex = _columnIndex(sourceColumns, 'manpower', lineIndex >= 0 ? 2 : 1);
    final kgIndex = _columnIndex(sourceColumns, 'prodinkg', lineIndex >= 0 ? 3 : 2);
    final cbIndex = _columnIndex(sourceColumns, 'prodincb', lineIndex >= 0 ? 4 : 3);
    final grouped = <String, List<dynamic>>{};
    for (final item in raw) {
      if (item is! List || item.isEmpty) continue;
      final row = item.toList();
      final label = _productivityLabel('${skuIndex < row.length ? row[skuIndex] : ''}');
      final reportedLine = lineIndex >= 0 && lineIndex < row.length ? '${row[lineIndex]}' : '';
      final line = _isUnassignedLine(reportedLine) ? (_lineForSku(label) ?? reportedLine) : reportedLine;
      if (lineIndex >= 0 && lineIndex < row.length) row[lineIndex] = line;
      final key = '$label\u0000${line.toLowerCase()}';
      final current = grouped[key];
      if (current == null) {
        if (skuIndex < row.length) row[skuIndex] = label;
        grouped[key] = row;
        continue;
      }
      // Productivity-only merge: keep each production line separate while
      // grouping White/Brown Vinegar 610 only within the same line.
      for (final index in [manpowerIndex, kgIndex, cbIndex]) {
        if (index >= 0 && index < row.length && index < current.length) current[index] = _n(current[index]) + _n(row[index]);
      }
    }
    final rows = <List<dynamic>>[];
    var totalManpower = 0.0, totalKg = 0.0, totalCb = 0.0;
    for (final row in grouped.values) {
      final manpower = _n(manpowerIndex < row.length ? row[manpowerIndex] : 0).toDouble();
      final kg = _n(kgIndex < row.length ? row[kgIndex] : 0).toDouble();
      final cb = _n(cbIndex < row.length ? row[cbIndex] : 0).toDouble();
      final requiredLength = sourceColumns.isEmpty ? (lineIndex >= 0 ? 7 : 6) : sourceColumns.length;
      while (row.length < requiredLength) row.add(0);
      if (manpowerIndex < row.length) row[manpowerIndex] = manpower;
      if (kgIndex < row.length) row[kgIndex] = kg;
      if (cbIndex < row.length) row[cbIndex] = cb;
      final kgPerHeadIndex = _columnIndex(sourceColumns, 'productivityinkghead', lineIndex >= 0 ? 5 : 4);
      final cbPerHeadIndex = _columnIndex(sourceColumns, 'productivityincbhead', lineIndex >= 0 ? 6 : 5);
      while (row.length <= cbPerHeadIndex) row.add(0);
      row[kgPerHeadIndex] = manpower == 0 ? 0 : kg / manpower;
      row[cbPerHeadIndex] = manpower == 0 ? 0 : cb / manpower;
      totalManpower += manpower;
      totalKg += kg;
      totalCb += cb;
      rows.add(row);
    }
    if (lineIndex >= 0) rows.sort((a, b) => '${a[skuIndex]}|${a[lineIndex]}'.compareTo('${b[skuIndex]}|${b[lineIndex]}'));
    final out = Map<String, dynamic>.from(source);
    out['rows'] = rows;
    out['totals'] = {
      'manpower': totalManpower,
      'kg': totalKg,
      'netKg': totalKg,
      'cb': totalCb,
      'producedCb': totalCb,
      'kgPerHead': totalManpower == 0 ? 0 : totalKg / totalManpower,
      'cbPerHead': totalManpower == 0 ? 0 : totalCb / totalManpower,
    };
    return out;
  }

  Future<Map<String, dynamic>> _legacyProductivity() async {
    final api = context.read<AuthController>().api;
    final batchesJson = await api.get('/production/batches?status=COMPLETED');
    final batchList = ((batchesJson as Map)['batches'] as List? ?? const []).cast<Map<String, dynamic>>();
    List<Map<String, dynamic>> productList = [];
    try {
      final productsJson = await api.get('/products');
      productList = ((productsJson as Map)['products'] as List? ?? const []).cast<Map<String, dynamic>>();
    } catch (_) {}
    final products = <String, Map<String, dynamic>>{for (final p in productList) '${p['id']}': p};
    final labour = await _loadLabourRows(api, _query(includeSku: false));

    final seenIds = <String>{};
    final metrics = <String, Map<String, dynamic>>{};
    final labourBySku = <String, double>{};
    final assignmentManpower = <String, double>{};
    String labourKey(String date, String line, String shift, String skuKey) =>
        '${date}|${line.toLowerCase()}|${shift.toLowerCase()}|$skuKey';
    for (final entry in labour) {
      final date = _dateOnly(entry['date']);
      if (date.isNotEmpty && (date.compareTo(_fromYmd) < 0 || date.compareTo(_toYmd) > 0)) continue;
      final entryShift = '${entry['shift'] ?? ''}';
      if (_shiftFilter != 'Combined' && entryShift.toLowerCase() != _shiftFilter.toLowerCase()) continue;
      final line = '${entry['line'] ?? ''}'.trim();
      if (_lineFilter.text.trim().isNotEmpty && line.toLowerCase() != _lineFilter.text.trim().toLowerCase()) continue;
      final worker = _n(entry['manpower'] ?? entry['workerCount'] ?? entry['workers']);
      final hours = _n(entry['actualHours'] ?? entry['hours']);
      final standard = _n(entry['standardShiftHours']);
      final manpower = standard > 0 ? worker * hours / standard : worker;
      final productId = '${entry['productId'] ?? entry['product_id'] ?? ''}';
      final skuName = '${entry['sku'] ?? entry['productName'] ?? entry['product_name'] ?? ''}';
      final skuKeys = <String>{
        if (productId.isNotEmpty) productId,
        if (skuName.trim().isNotEmpty) _skuRuleKey(skuName),
      };
      // SKU is now part of the labour assignment. A line can have several
      // SKU rows in one shift, each carrying its own workers and hours.
      for (final skuKey in skuKeys) {
        labourBySku[labourKey(date, line, entryShift, skuKey)] = manpower.toDouble();
      }
    }

    double skuManpower(String date, String line, String shift, List<String> skuKeys) {
      final prefix = '${date}|${line.toLowerCase()}|';
      for (final skuKey in skuKeys) {
        if (shift.isNotEmpty) {
          final value = labourBySku['$prefix${shift.toLowerCase()}|$skuKey'];
          if (value != null) return value;
        } else {
          final values = labourBySku.entries.where((e) => e.key.startsWith(prefix) && e.key.endsWith('|$skuKey')).map((e) => e.value).toList();
          if (values.isNotEmpty) return values.fold<double>(0, (sum, value) => sum + value);
        }
      }
      return 0;
    }

    String skuAssignmentKey(String date, String line, String shift, List<String> skuKeys) {
      final prefix = '${date}|${line.toLowerCase()}|';
      for (final skuKey in skuKeys) {
        if (shift.isNotEmpty && labourBySku.containsKey('$prefix${shift.toLowerCase()}|$skuKey')) return '$prefix${shift.toLowerCase()}|$skuKey';
        if (shift.isEmpty && labourBySku.keys.any((key) => key.startsWith(prefix) && key.endsWith('|$skuKey'))) return '$prefix|$skuKey';
      }
      return '$prefix${shift.toLowerCase()}|${skuKeys.first}';
    }

    for (final batch in batchList) {
      final status = '${batch['status'] ?? ''}'.toUpperCase();
      if (status != 'COMPLETED') continue;
      final batchId = '${batch['id'] ?? ''}';
      if (batchId.isNotEmpty && !seenIds.add(batchId)) continue;
      // The planned/manufacturing date is the actual production date. A batch
      // may be entered or completed in the system days later; completed_at is
      // only a fallback when legacy data has no production date.
      final date = _productionDate(batch);
      if (date.isEmpty || date.compareTo(_fromYmd) < 0 || date.compareTo(_toYmd) > 0) continue;
      final sourcePid = '${batch['product_id'] ?? batch['productId'] ?? ''}';
      final product = products[sourcePid];
      final source = '${batch['product_name'] ?? batch['productName'] ?? product?['name'] ?? 'Unknown SKU'}';
      if (_skuFilter != null && _skuFilter!.isNotEmpty && sourcePid != _skuFilter) continue;
      var line = '${batch['line'] ?? batch['production_line'] ?? ''}'.trim();
      if (_isUnassignedLine(line)) line = _lineForSku(source) ?? line;
      if (!_skuAllowedForLine(line, source)) continue;
      if (_lineFilter.text.trim().isNotEmpty && line.toLowerCase() != _lineFilter.text.trim().toLowerCase()) continue;
      final lineLabel = line.isEmpty ? 'Unassigned' : line;
      final batchShift = '${batch['shift'] ?? ''}';
      if (_shiftFilter != 'Combined' && batchShift.isNotEmpty && batchShift.toLowerCase() != _shiftFilter.toLowerCase()) continue;
      final label = _productivityLabel(source);
      final cb = _n(batch['produced_cb'] ?? batch['producedCb']).toDouble();
      final net = _n(product?['net_weight_per_cb'] ?? product?['weight_without_cb'] ?? product?['netWeightPerCb'] ?? batch['net_weight_per_cb'] ?? batch['weight_without_cb']).toDouble();
      final metricKey = '$label\u0000${lineLabel.toLowerCase()}';
      final row = metrics.putIfAbsent(metricKey, () => {'sku': label, 'line': lineLabel, 'cb': 0.0, 'kg': 0.0, 'labourCb': <String, double>{}});
      row['cb'] = _n(row['cb']) + cb;
      row['kg'] = _n(row['kg']) + cb * net;
      final runShift = batchShift.isEmpty ? '' : batchShift;
      final skuKeys = <String>{
        if (sourcePid.isNotEmpty) sourcePid,
        _skuRuleKey(source),
      }.where((key) => key.isNotEmpty).toList();
      final labourKey = skuAssignmentKey(date, line, runShift, skuKeys);
      assignmentManpower.putIfAbsent(labourKey, () => skuManpower(date, line, runShift, skuKeys));
      final labourCb = row['labourCb'] as Map<String, double>;
      labourCb[labourKey] = (labourCb[labourKey] ?? 0) + cb;
    }

    final assignmentProductionCb = <String, double>{};
    for (final metric in metrics.values) {
      final labourCb = metric['labourCb'] as Map<String, double>;
      for (final assignment in labourCb.entries) {
        assignmentProductionCb[assignment.key] = (assignmentProductionCb[assignment.key] ?? 0) + assignment.value;
      }
    }

    final rows = <List<dynamic>>[];
    var totalCb = 0.0, totalKg = 0.0;
    for (final entry in metrics.entries) {
      final cb = _n(entry.value['cb']).toDouble();
      final kg = _n(entry.value['kg']).toDouble();
      final labourCb = entry.value['labourCb'] as Map<String, double>;
      // A date/line/shift/SKU assignment is counted once. Multiple completed
      // batches of the same SKU reuse the matching labour row.
      var manpower = 0.0;
      for (final assignment in labourCb.entries) {
        final assignmentCb = assignmentProductionCb[assignment.key] ?? 0;
        if (assignmentCb > 0) manpower += (assignmentManpower[assignment.key] ?? 0) * assignment.value / assignmentCb;
      }
      rows.add([entry.value['sku'], entry.value['line'], manpower, kg, cb, manpower == 0 ? 0 : kg / manpower, manpower == 0 ? 0 : cb / manpower]);
      totalCb += cb;
      totalKg += kg;
    }
    rows.sort((a, b) => '${a[0]}|${a[1]}'.compareTo('${b[0]}|${b[1]}'));
    final totalManpower = assignmentManpower.values.fold<double>(0, (sum, value) => sum + value);
    return {
      'columns': const ['SKU', 'LINE', 'MANPOWER', 'PROD. IN KG', 'PROD. IN CB', 'PRODUCTIVITY IN KG/HEAD', 'PRODUCTIVITY IN CB/HEAD'],
      'rows': rows,
      'totals': {
        'cb': totalCb,
        'producedCb': totalCb,
        'kg': totalKg,
        'netKg': totalKg,
        'manpower': totalManpower,
        'kgPerHead': totalManpower == 0 ? 0 : totalKg / totalManpower,
        'cbPerHead': totalManpower == 0 ? 0 : totalCb / totalManpower,
      },
    };
  }

  Future<Map<String, dynamic>> _loadProductivity() async {
    // Completed batches are the source of truth for the selected production
    // dates. Do this before the aggregate report endpoint so a late-entered
    // batch cannot be pulled into October by its entry/completion timestamp.
    try {
      return await _legacyProductivity();
    } catch (_) {}

    // Keep compatibility with deployments where the completed-batch endpoint
    // is temporarily unavailable.
    try {
      final response = (await context.read<AuthController>().api.get('/reports/productivity?${_query()}') as Map).cast<String, dynamic>();
      return _normaliseProductivity(response);
    } catch (_) {
      return _emptyProductivity();
    }
  }

  void _reload() {
    final api = context.read<AuthController>().api;
    final productivity = _loadProductivity();
    final labour = _loadLabourRows(api, _query());
    final analysis = api.get('/reports/productivity/analysis?${_query()}').then((v) => (v as Map).cast<String, dynamic>()).catchError((_) => <String, dynamic>{'rows': const []});
    void assign() {
      _productivityFuture = productivity;
      _labourFuture = labour;
      _analysisFuture = analysis;
    }
    if (mounted) {
      setState(assign);
    } else {
      assign();
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
    });
    _reload();
  }

  Future<void> _openLabourForm({Map<String, dynamic>? entry}) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => _DailyLabourDialog(entry: entry));
    if (changed == true && mounted) _reload();
  }

  void _currentMonth() {
    final now = DateTime.now();
    setState(() {
      _from = DateTime(now.year, now.month, 1);
      _to = DateTime(now.year, now.month + 1, 0);
    });
    _reload();
  }

  Widget _dateFilters(BuildContext context, {bool includeSku = true}) {
    final scheme = Theme.of(context).colorScheme;
    Widget dateButton(String label, DateTime value, VoidCallback tap) => OutlinedButton.icon(
          onPressed: tap,
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          label: Text('$label: ${fmtDate(_ymd(value))}'),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        dateButton('From', _from, () => _pickDate(start: true)),
        dateButton('To', _to, () => _pickDate(start: false)),
        TextButton.icon(onPressed: _currentMonth, icon: const Icon(Icons.date_range_outlined, size: 17), label: const Text('This month')),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _shiftFilter,
            isDense: true,
            onChanged: (v) { if (v != null) { setState(() => _shiftFilter = v); _reload(); } },
            items: const [
              DropdownMenuItem(value: 'Combined', child: Text('Combined shifts')),
              DropdownMenuItem(value: 'Day', child: Text('Day shift')),
              DropdownMenuItem(value: 'Night', child: Text('Night shift')),
            ],
          ),
        ),
        FilledButton.tonalIcon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
        Text('Actual completed production only', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (includeSku)
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              value: _skuFilter,
              isExpanded: true,
              hint: const Text('All SKUs'),
              decoration: const InputDecoration(labelText: 'SKU / Product', prefixIcon: Icon(Icons.inventory_2_outlined, size: 18)),
              items: [
                for (final p in _products) DropdownMenuItem(value: '${p['id']}', child: Text('${p['name']}')),
              ],
              onChanged: (v) { setState(() => _skuFilter = v); _reload(); },
            ),
          ),
        SizedBox(width: 180, child: TextField(controller: _lineFilter, decoration: const InputDecoration(labelText: 'Production line', prefixIcon: Icon(Icons.precision_manufacturing_outlined, size: 18)), onSubmitted: (_) => _reload())),
        if (_lineFilter.text.isNotEmpty || (includeSku && _skuFilter != null))
          TextButton.icon(onPressed: () { _lineFilter.clear(); setState(() => _skuFilter = null); _reload(); }, icon: const Icon(Icons.clear, size: 17), label: const Text('Clear filters')),
      ]),
    ]);
  }

  Future<void> _export(String kind) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = kind == 'labour' ? '/labour/daily.xlsx' : '/reports/productivity.xlsx';
      final bytes = await context.read<AuthController>().api.getBytes('$path?${_query()}');
      final date = DateTime.now().toIso8601String().substring(0, 10);
      downloadBytes('flavorflow-${kind == 'labour' ? 'daily-labour' : 'productivity'}-$date.xlsx', bytes,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      if (mounted) showOk(context, 'Excel report downloaded.');
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _hero(BuildContext context, Map<String, dynamic> data) {
    final totals = (data['totals'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final scheme = Theme.of(context).colorScheme;
    Widget metric(String label, Object? value, IconData icon, Color color) => Container(
          constraints: const BoxConstraints(minWidth: 145),
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(qty(value), style: TextStyle(color: scheme.onSurface, fontSize: 19, fontWeight: FontWeight.w800)),
            ]),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: AppBrand.gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppBrand.blue.withValues(alpha: .18), blurRadius: 16, offset: const Offset(0, 7))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Productivity & Labour', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('${fmtDate(_fromYmd)} — ${fmtDate(_toYmd)} · net bottle weight only', style: TextStyle(color: Colors.white.withValues(alpha: .86), fontSize: 12.5)),
        const SizedBox(height: 15),
        LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 620;
          final children = [
            metric('Production CB', totals['cb'] ?? totals['producedCb'], Icons.inventory_2_outlined, AppColors.cyan),
            metric('Production KG', totals['kg'] ?? totals['netKg'], Icons.scale_outlined, AppColors.green),
            metric('Manpower', totals['manpower'], Icons.groups_outlined, AppColors.amber),
          ];
          return narrow ? Column(children: [for (var i = 0; i < children.length; i++) Padding(padding: EdgeInsets.only(bottom: i == children.length - 1 ? 0 : 8), child: children[i])]) : Row(children: [for (var i = 0; i < children.length; i++) Expanded(child: Padding(padding: EdgeInsets.only(right: i == children.length - 1 ? 0 : 8), child: children[i]))]);
        }),
      ]),
    );
  }

  Widget _reconciliationBanner(BuildContext context, Map<String, dynamic> data) {
    final warning = data['reconciliationWarning'] ?? data['reconciliation_error'];
    final unresolved = data['reconciliationOk'] == false || warning != null;
    if (!unresolved) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('${warning ?? 'Production reconciliation is not complete. Verify the completed-batch register before accepting totals.'}', style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _productivityTab(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _productivityFuture,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final data = snap.data!;
        final columns = (data['columns'] as List? ?? const ['SKU', 'LINE', 'MANPOWER', 'PROD. IN KG', 'PROD. IN CB', 'PRODUCTIVITY IN KG/HEAD', 'PRODUCTIVITY IN CB/HEAD']).map((v) => '$v').toList();
        final rows = ((data['rows'] as List?) ?? const []).map((r) => (r as List).toList()).toList();
        return ListView(padding: const EdgeInsets.all(18), children: [
          _hero(context, data),
          _reconciliationBanner(context, data),
          const SizedBox(height: 14),
          _dateFilters(context),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: _exporting ? null : () => _export('productivity'), icon: const Icon(Icons.download_outlined, size: 18), label: const Text('Export Excel'))),
          const SizedBox(height: 8),
          SectionCard(
            title: "PRODUCTIVITY ${_from.year == _to.year && _from.month == _to.month ? DateFormatLike.month(_from) : 'PERIOD'}'${_to.year.toString().substring(2)}",
            child: rows.isEmpty ? const EmptyState('No completed production or labour entries for this period.') : AppDataTable(columns: columns.cast<String>(), rows: rows),
          ),
        ]);
      },
    );
  }

  List<Map<String, dynamic>> _analysisSections(Map<String, dynamic> data) {
    final raw = data['sections'];
    if (raw is Map) {
      final result = <Map<String, dynamic>>[];
      for (final entry in [
        ('day', 'Day Shift'),
        ('night', 'Night Shift'),
        ('combined', 'Combined Day & Night'),
      ]) {
        final value = raw[entry.$1];
        if (value is Map) result.add({'title': entry.$2, 'data': value.cast<String, dynamic>()});
      }
      if (result.isNotEmpty) return result;
    }
    // Compatibility fallback for an older flat analysis response.
    return [{'title': 'Combined Day & Night', 'data': data}];
  }

  Widget _analysisMatrix(String title, Map<String, dynamic> data) {
    final rows = ((data['rows'] as List?) ?? const []).map((r) => (r as List).toList()).toList();
    final columns = ((data['columns'] as List?) ?? const ['METRIC']).map((v) => '$v').toList();
    return SectionCard(
      title: title,
      child: rows.isEmpty ? const EmptyState('No labour analysis rows for this section.') : AppDataTable(columns: columns.cast<String>(), rows: rows),
    );
  }

  Widget _analysisTab(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _analysisFuture,
      builder: (context, snap) {
        final data = snap.data ?? const <String, dynamic>{};
        final totals = (data['periodTotals'] as Map?)?.cast<String, dynamic>() ?? (data['totals'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final sections = _analysisSections(data);
        return ListView(padding: const EdgeInsets.all(18), children: [
          _dateFilters(context),
          const SizedBox(height: 12),
          Text('Labour Analysis keeps White Vinegar 610 and Brown Vinegar 610 separate. Only the Productivity summary groups them as Vinegar 610.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Period Totals',
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              _totalChip('CB', totals['cb'] ?? totals['producedCb']),
              _totalChip('Net KG', totals['kg'] ?? totals['netKg']),
              _totalChip('Manpower', totals['manpower']),
              _totalChip('KG / Head', totals['kgPerHead']),
              _totalChip('CB / Head', totals['cbPerHead']),
            ]),
          ),
          for (final section in sections) ...[
            const SizedBox(height: 14),
            _analysisMatrix(section['title'] as String, section['data'] as Map<String, dynamic>),
          ],
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: _exporting ? null : () => _export('productivity'), icon: const Icon(Icons.download_outlined, size: 17), label: const Text('Export Analysis Excel'))),
        ]);
      },
    );
  }

  Widget _totalChip(String label, Object? value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(qty(value), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _labourTab(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _labourFuture,
      builder: (context, snap) {
        final rows = snap.data ?? const <Map<String, dynamic>>[];
        return ListView(padding: const EdgeInsets.all(18), children: [
          _dateFilters(context),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: _exporting ? null : () => _export('labour'), icon: const Icon(Icons.download_outlined, size: 18), label: const Text('Export Labour Excel'))),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Daily Labour Details',
            trailing: FilledButton.icon(onPressed: _openLabourForm, icon: const Icon(Icons.add, size: 17), label: const Text('Add Entry')),
            child: rows.isEmpty
                ? const EmptyState('No daily labour entries yet. Start entering line-wise details tomorrow.')
                : AppDataTable(
                    columns: const ['DATE', 'SHIFT', 'LINE', 'SKU', 'WORKERS', 'HOURS', 'SUPERVISOR', 'REMARKS', ''],
                    rows: [
                      for (final r in rows)
                        [r['date'], r['shift'], r['line'], r['productName'] ?? r['sku'] ?? r['product'], r['workerCount'] ?? r['workers'], r['actualHours'] ?? r['hours'], r['supervisor'], r['remarks'], IconButton(tooltip: 'Edit entry', onPressed: () => _openLabourForm(entry: r), icon: const Icon(Icons.edit_outlined, size: 18))],
                    ],
                  ),
          ),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Material(
        color: Theme.of(context).colorScheme.surface,
        child: TabBar(controller: _tabs, tabs: const [Tab(text: 'Productivity'), Tab(text: 'Daily Labour'), Tab(text: 'Labour Analysis')]),
      ),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          _productivityTab(context),
          _labourTab(context),
          _analysisTab(context),
        ]),
      ),
    ]);
  }
}

class _DailyLabourDialog extends StatefulWidget {
  final Map<String, dynamic>? entry;
  const _DailyLabourDialog({this.entry});
  @override
  State<_DailyLabourDialog> createState() => _DailyLabourDialogState();
}

class _DailyLabourDialogState extends State<_DailyLabourDialog> {
  final line = TextEditingController();
  final workers = TextEditingController();
  final hours = TextEditingController();
  final supervisor = TextEditingController();
  final remarks = TextEditingController();
  DateTime date = DateTime.now();
  String shift = 'Day';
  String? product;
  List<Map<String, dynamic>> products = [];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    if (e != null) {
      date = DateTime.tryParse('${e['date']}'.split(RegExp(r'[T ]')).first) ?? date;
      shift = '${e['shift'] ?? 'Day'}';
      line.text = '${e['line'] ?? ''}';
      workers.text = '${e['workerCount'] ?? e['workers'] ?? ''}';
      hours.text = '${e['actualHours'] ?? e['hours'] ?? ''}';
      supervisor.text = '${e['supervisor'] ?? ''}';
      remarks.text = '${e['remarks'] ?? ''}';
      final rawProduct = e['productId'] ?? e['product_id'] ?? e['sku'] ?? e['product'] ?? e['productName'] ?? e['product_name'];
      if (rawProduct != null) product = '$rawProduct';
    }
    context.read<AuthController>().api.get('/products').then((json) {
      if (!mounted) return;
      final loaded = ((json as Map)['products'] as List? ?? const []).cast<Map<String, dynamic>>().where((p) => (p['active'] as num? ?? 1) != 0).toList();
      setState(() {
        products = loaded;
        if (product != null && !loaded.any((p) => '${p['id']}' == product)) {
          final match = loaded.where((p) => _skuRuleKey('${p['name']}') == _skuRuleKey(product!)).toList();
          if (match.isNotEmpty) product = '${match.first['id']}';
        }
        final selected = loaded.where((p) => '${p['id']}' == product).toList();
        final inferred = selected.isEmpty ? null : _lineForSku('${selected.first['name']}');
        if (_isUnassignedLine(line.text) && inferred != null) line.text = inferred;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [line, workers, hours, supervisor, remarks]) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final w = double.tryParse(workers.text.trim());
    final h = double.tryParse(hours.text.trim());
    final selected = products.where((p) => '${p['id']}' == product).toList();
    final selectedName = selected.isEmpty ? '' : '${selected.first['name']}';
    if (line.text.trim().isEmpty || product == null || selectedName.isEmpty || w == null || h == null || w <= 0 || h <= 0) {
      showErr(context, 'SKU, line, workers and actual hours are required.');
      return;
    }
    final inferredLine = _lineForSku(selectedName);
    if (inferredLine != null && _skuRuleKey(line.text) != _skuRuleKey(inferredLine)) {
      showErr(context, '$selectedName belongs to $inferredLine.');
      return;
    }
    setState(() => busy = true);
    try {
      final body = <String, dynamic>{
        'date': _ymd(date),
        'shift': shift,
        'line': line.text.trim(),
        'productId': int.tryParse(product!) ?? product,
        'sku': selectedName,
        'productName': selectedName,
        'workerCount': w,
        'workers': w,
        'actualHours': h,
        'hours': h,
        'supervisor': supervisor.text.trim(),
        'remarks': remarks.text.trim(),
      };
      final id = widget.entry?['id'];
      final localBody = {...body};
      if (widget.entry?['localOnly'] == true) {
        await _writeLocalLabour({...localBody, 'id': id});
      } else {
        try {
          if (id == null) {
            await context.read<AuthController>().api.post('/labour/daily', body);
          } else {
            await context.read<AuthController>().api.put('/labour/daily/$id', body);
          }
        } catch (_) {
          // Older test servers can still be used; persist an editable local row.
          await _writeLocalLabour({...localBody, if (id != null) 'id': id});
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.entry == null ? 'Daily Labour Entry' : 'Edit Daily Labour Entry'),
      content: SizedBox(
        width: 470,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () async { final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) setState(() => date = d); }, icon: const Icon(Icons.calendar_today, size: 17), label: Text(fmtDate(_ymd(date))))),
            const SizedBox(width: 10),
            Expanded(child: DropdownButtonFormField<String>(value: shift, decoration: const InputDecoration(labelText: 'Shift'), items: const [DropdownMenuItem(value: 'Day', child: Text('Day')), DropdownMenuItem(value: 'Night', child: Text('Night'))], onChanged: (v) => setState(() => shift = v ?? 'Day'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: line, decoration: const InputDecoration(labelText: 'Production line *', hintText: 'e.g. Line 1')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: products.any((p) => '${p['id']}' == product) ? product : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'SKU / Product *'),
            items: [for (final p in products) DropdownMenuItem(value: '${p['id']}', child: Text('${p['name']}'))],
            onChanged: (v) {
              final selected = products.where((p) => '${p['id']}' == v).toList();
              final inferred = selected.isEmpty ? null : _lineForSku('${selected.first['name']}');
              setState(() {
                product = v;
                if (_isUnassignedLine(line.text) && inferred != null) line.text = inferred;
              });
            },
          ),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: TextField(controller: workers, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Workers *'))), const SizedBox(width: 10), Expanded(child: TextField(controller: hours, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Actual hours *')))]),
          const SizedBox(height: 10),
          TextField(controller: supervisor, decoration: const InputDecoration(labelText: 'Supervisor')),
          const SizedBox(height: 10),
          TextField(controller: remarks, decoration: const InputDecoration(labelText: 'Remarks (optional)')),
        ])),
      ),
      actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : widget.entry == null ? 'Save Entry' : 'Update Entry'))],
    );
  }
}

class DateFormatLike {
  static String month(DateTime d) {
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return names[d.month - 1].toUpperCase();
  }
}
