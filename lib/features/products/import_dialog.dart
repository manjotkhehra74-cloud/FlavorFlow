import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/company.dart';
import '../../core/download.dart';
import '../../core/i18n.dart';
import '../../core/industry_pack.dart';
import '../../core/item_code.dart';
import '../../core/sheet_parse.dart';
import '../../core/sheet_pick.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// Bulk import of Products (finished goods) or Materials (raw / packing)
/// from Excel / Google Sheets / CSV — fast onboarding of a master list.
///
/// * Web: choose an .xlsx / .csv file, or paste.
/// * Phone: copy the cells in Excel / Sheets and paste into the box
///   (tab-separated text) — no file picker plugin needed.
///
/// Header row is matched by name (any order, extra columns ignored). Each
/// row is POSTed one by one to the existing create endpoint, so the server's
/// validation / duplicate item-code checks apply unchanged and a bad row
/// never blocks the good ones. Item code blank ⇒ server auto-assigns
/// FG / RM / PM numbers.
enum ImportKind { products, materials }

Future<bool?> showImportDialog(BuildContext context, ImportKind kind, {bool rawOnly = false}) {
  return showFastDialog<bool>(context, (_) => _ImportDialog(kind: kind, rawOnly: rawOnly));
}

class _Col {
  final String key; // body key
  final String header; // template header
  final List<String> aliases; // lower-case, no spaces / punctuation
  final bool required;
  const _Col(this.key, this.header, this.aliases, {this.required = false});
}

class _RowResult {
  final int line;
  final String name;
  String status; // pending / ok / error / skipped
  String message;
  _RowResult(this.line, this.name, this.status, this.message);
}

class _ImportDialog extends StatefulWidget {
  final ImportKind kind;
  final bool rawOnly;
  const _ImportDialog({required this.kind, required this.rawOnly});
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final paste = TextEditingController();
  List<List<String>> rows = const [];
  Map<String, int> colIndex = const {};
  List<String> unmatchedHeaders = const [];
  String? parseError;
  String sourceName = '';
  List<_RowResult> results = const [];
  bool running = false;
  bool finished = false;
  int done = 0;

  bool get isProducts => widget.kind == ImportKind.products;

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  List<_Col> get columns {
    final c = CompanyProfile.current;
    if (isProducts) {
      final cb = c.cartonShort, piece = c.pieceLabel, tray = c.trayLabel;
      return [
        const _Col('name', 'Name', ['name', 'product', 'productname', 'item', 'itemname', 'description', 'material', 'materialdescription'], required: true),
        const _Col('itemCode', 'Item Code', ['itemcode', 'code', 'sku', 'materialno', 'materialnumber', 'material', 'partno', 'articleno', 'article']),
        _Col('bottlesPerCb', '$piece per $cb', ['bottlespercb', 'piecespercb', 'piecespercarton', 'unitspercarton', 'packsize', 'perpack', 'percarton', 'percb', _norm('$piece per $cb'), _norm('${piece}s per $cb'), _norm('$piece/$cb')]),
        _Col('weightPerCb', 'Gross weight per $cb (kg)', ['grossweight', 'grossweightpercb', 'weightpercb', 'weightpercarton', 'cartonweight', 'grosskg', 'gross', _norm('gross weight per $cb (kg)')]),
        _Col('weightWithoutCb', 'Net weight per $cb (kg)', ['netweight', 'netweightpercb', 'weightwithoutcb', 'weightwithoutcarton', 'netkg', 'net', _norm('net weight per $cb (kg)')]),
        if (CompanyProfile.usesTrays) _Col('bottlesPerTray', '$piece per $tray', ['bottlespertray', 'piecespertray', 'pertray', _norm('$piece per $tray'), _norm('${piece}s per $tray')]),
        if (CompanyProfile.usesTrays) _Col('trayWeight', '$tray weight (kg)', ['trayweight', 'trayweightkg', _norm('$tray weight (kg)'), _norm('$tray weight')]),
        _Col('minStockCb', 'Min stock ($cb)', ['minstock', 'minstockcb', 'minimumstock', 'reorderlevel', 'reorderpoint', 'safetystock', _norm('min stock ($cb)')]),
      ];
    }
    return [
      const _Col('name', 'Name', ['name', 'material', 'materialname', 'item', 'itemname', 'description', 'materialdescription', 'product'], required: true),
      const _Col('itemCode', 'Item Code', ['itemcode', 'code', 'sku', 'materialno', 'materialnumber', 'partno', 'articleno', 'article']),
      const _Col('category', 'Category', ['category', 'type', 'group', 'materialgroup', 'materialtype']),
      const _Col('unit', 'Unit', ['unit', 'uom', 'units', 'baseunit', 'unitofmeasure']),
      const _Col('stock', 'Opening stock', ['stock', 'openingstock', 'opening', 'qty', 'quantity', 'openingqty', 'currentstock', 'balance']),
      const _Col('minStock', 'Min stock', ['minstock', 'minimumstock', 'reorderlevel', 'reorderpoint', 'safetystock', 'min']),
    ];
  }

  List<String> get templateHeaders => [for (final c in columns) c.header];

  List<List<String>> get templateSample {
    if (isProducts) {
      final sample = IndustryPack.current.productExamples.take(3).toList();
      if (sample.isEmpty) sample.add('Sample product 1 kg');
      return [
        for (final p in sample)
          [p, '', '12', '13.5', '12.9', if (CompanyProfile.usesTrays) '6', if (CompanyProfile.usesTrays) '0.3', '50'],
      ];
    }
    final pack = IndustryPack.current;
    if (widget.rawOnly) {
      final unit = pack.rawUnits.firstOrNull ?? 'kg';
      final ex = pack.rawExamples.take(2).toList();
      if (ex.isEmpty) ex.add('Sample raw material');
      return [for (final e in ex) [e, '', IndustryPack.rawCategory, unit, '0', '100']];
    }
    final cat = pack.packingCategories.firstOrNull ?? 'Cartons';
    final ex = pack.packingExamples.take(2).toList();
    if (ex.isEmpty) ex.add('Sample $cat');
    return [for (final e in ex) [e, '', cat, 'pcs', '0', '100']];
  }

  void _downloadTemplate() {
    final csv = SheetParse.toCsv([templateHeaders, ...templateSample]);
    final bytes = utf8.encode('\uFEFF$csv');
    downloadBytes(isProducts ? 'flavorflow-products-template.csv' : 'flavorflow-materials-template.csv', Uint8List.fromList(bytes), 'text/csv');
  }

  void _load(List<List<String>> parsed, String name) {
    parseError = null;
    results = const [];
    finished = false;
    done = 0;
    sourceName = name;
    if (parsed.isEmpty) {
      rows = const [];
      colIndex = const {};
      parseError = tr('Nothing to import — the sheet is empty.');
      setState(() {});
      return;
    }
    // header detection: a row where ≥1 cell matches a known column alias
    final header = parsed.first;
    final idx = <String, int>{};
    final unmatched = <String>[];
    for (var i = 0; i < header.length; i++) {
      final h = _norm(header[i]);
      if (h.isEmpty) continue;
      _Col? hit;
      for (final c in columns) {
        if (idx.containsKey(c.key)) continue;
        if (_norm(c.header) == h || c.aliases.contains(h)) {
          hit = c;
          break;
        }
      }
      if (hit != null) {
        idx[hit.key] = i;
      } else {
        unmatched.add(header[i]);
      }
    }
    if (!idx.containsKey('name')) {
      // no header row → positional (template order)
      idx.clear();
      unmatched.clear();
      for (var i = 0; i < columns.length; i++) {
        idx[columns[i].key] = i;
      }
      rows = parsed;
    } else {
      rows = parsed.sublist(1);
    }
    colIndex = idx;
    unmatchedHeaders = unmatched;
    if (rows.isEmpty) parseError = tr('Only a header row found — add the items below it.');
    setState(() {});
  }

  String _cell(List<String> r, String key) {
    final i = colIndex[key];
    if (i == null || i >= r.length) return '';
    return r[i];
  }

  num _num(String s) => num.tryParse(s.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;

  Map<String, dynamic> _body(List<String> r) {
    final code = ItemCode.normalize(_cell(r, 'itemCode'));
    if (isProducts) {
      return {
        'name': _cell(r, 'name'),
        'weightPerCb': _num(_cell(r, 'weightPerCb')),
        'weightWithoutCb': _num(_cell(r, 'weightWithoutCb')),
        'bottlesPerCb': _num(_cell(r, 'bottlesPerCb')).toInt(),
        'bottlesPerTray': CompanyProfile.usesTrays ? _num(_cell(r, 'bottlesPerTray')).toInt() : 0,
        'trayWeight': CompanyProfile.usesTrays ? _num(_cell(r, 'trayWeight')) : 0,
        'minStockCb': _num(_cell(r, 'minStockCb')).toInt(),
        'itemCode': code,
      };
    }
    final pack = IndustryPack.current;
    var category = _cell(r, 'category');
    // Raw-material screen: everything imported there is raw material
    if (widget.rawOnly) category = IndustryPack.rawCategory;
    if (category.isEmpty) category = pack.packingCategories.firstOrNull ?? 'Other';
    // tolerant category match against the industry list (case-insensitive)
    final known = [IndustryPack.rawCategory, ...pack.packingCategories];
    final m = known.where((k) => _norm(k) == _norm(category)).firstOrNull;
    if (m != null) category = m;
    if (const {'raw', 'rawmaterials', 'rm', 'rawmat'}.contains(_norm(category))) category = IndustryPack.rawCategory;
    var unit = _cell(r, 'unit');
    if (unit.isEmpty) unit = category == IndustryPack.rawCategory ? (pack.rawUnits.firstOrNull ?? 'kg') : 'pcs';
    return {
      'name': _cell(r, 'name'),
      'category': category,
      'unit': unit,
      'stock': _num(_cell(r, 'stock')),
      'minStock': _num(_cell(r, 'minStock')),
      'itemCode': code,
    };
  }

  Future<void> _run() async {
    final api = context.read<AuthController>().api;
    final path = isProducts ? '/products' : '/packing/materials';
    results = [for (var i = 0; i < rows.length; i++) _RowResult(i + 2, _cell(rows[i], 'name'), 'pending', '')];
    setState(() {
      running = true;
      done = 0;
    });
    // duplicate names / codes inside the sheet itself
    final seenNames = <String>{}, seenCodes = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final res = results[i];
      final body = _body(rows[i]);
      final name = (body['name'] as String).trim();
      final code = body['itemCode'] as String;
      if (name.isEmpty) {
        res
          ..status = 'skipped'
          ..message = tr('Name is empty');
      } else if (!seenNames.add(name.toLowerCase())) {
        res
          ..status = 'skipped'
          ..message = tr('Duplicate name in the sheet');
      } else if (code.isNotEmpty && ItemCode.validate(code) != null) {
        res
          ..status = 'error'
          ..message = ItemCode.validate(code)!;
      } else if (code.isNotEmpty && !seenCodes.add(code)) {
        res
          ..status = 'skipped'
          ..message = tr('Duplicate item code in the sheet');
      } else {
        try {
          await api.post(path, body);
          res
            ..status = 'ok'
            ..message = code.isEmpty ? tr('Created (code auto)') : '${tr('Created')} · $code';
        } on ApiException catch (e) {
          res
            ..status = 'error'
            ..message = e.message;
        } catch (e) {
          res
            ..status = 'error'
            ..message = '$e';
        }
      }
      done = i + 1;
      if (mounted) setState(() {});
    }
    if (mounted) {
      setState(() {
        running = false;
        finished = true;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final f = await pickSheet();
      if (f == null) return;
      final parsed = f.isXlsx ? SheetParse.parseXlsx(f.bytes) : SheetParse.parseDelimited(utf8.decode(f.bytes, allowMalformed: true));
      _load(parsed, f.name);
    } catch (e) {
      setState(() => parseError = '${tr('Could not read the file')}: $e');
    }
  }

  @override
  void dispose() {
    paste.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    final title = isProducts
        ? tr('Import products from Excel / CSV')
        : (widget.rawOnly ? tr('Import raw materials from Excel / CSV') : tr('Import materials from Excel / CSV'));
    final okCount = results.where((r) => r.status == 'ok').length;
    final errCount = results.where((r) => r.status == 'error').length;
    final skipCount = results.where((r) => r.status == 'skipped').length;
    final wide = MediaQuery.sizeOf(context).width > 700;

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: wide ? 640 : double.maxFinite,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // step 1 — columns / template
            Text('${tr('Columns')}: ${templateHeaders.join(' · ')}', style: sub),
            const SizedBox(height: 4),
            Text(tr('First row = headers (any order, extra columns ignored). Item Code blank = auto FG / RM / PM number. Existing names are not updated — only new items are created.'), style: sub),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: running ? null : _downloadTemplate, icon: const Icon(Icons.download_rounded, size: 18), label: Text(tr('Download template (CSV)'))),
              if (canPickSheet)
                OutlinedButton.icon(onPressed: running ? null : _pickFile, icon: const Icon(Icons.upload_file_rounded, size: 18), label: Text(tr('Choose .xlsx / .csv file'))),
            ]),
            const SizedBox(height: 12),
            // step 2 — paste
            TextField(
              controller: paste,
              enabled: !running,
              minLines: 4,
              maxLines: 8,
              style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: tr('Or paste cells copied from Excel / Google Sheets'),
                hintText: '${templateHeaders.take(3).join('\t')}\n${templateSample.first.take(3).join('\t')}',
                alignLabelWithHint: true,
                helperText: kIsWeb ? null : tr('Phone: open the sheet, select the cells, copy, and paste here.'),
              ),
              onChanged: (v) {
                if (v.trim().isEmpty) {
                  setState(() {
                    rows = const [];
                    results = const [];
                    parseError = null;
                    finished = false;
                  });
                } else {
                  _load(SheetParse.parseDelimited(v), tr('pasted text'));
                }
              },
            ),
            const SizedBox(height: 10),
            if (parseError != null) Text(parseError!, style: TextStyle(color: scheme.error, fontSize: 12.5)),
            // step 3 — preview
            if (rows.isNotEmpty && results.isEmpty) ...[
              Text('${rows.length} ${tr('rows from')} $sourceName · ${tr('matched columns')}: ${colIndex.keys.map((k) => columns.firstWhere((c) => c.key == k).header).join(', ')}',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: scheme.primary)),
              if (unmatchedHeaders.isNotEmpty) Text('${tr('Ignored columns')}: ${unmatchedHeaders.join(', ')}', style: sub),
              const SizedBox(height: 6),
              _preview(scheme),
            ],
            // step 4 — results
            if (results.isNotEmpty) ...[
              if (running) LinearProgressIndicator(value: rows.isEmpty ? null : done / rows.length),
              const SizedBox(height: 6),
              Text(
                running
                    ? '${tr('Importing')} $done / ${rows.length}…'
                    : '${tr('Done')}: $okCount ${tr('created')} · $errCount ${tr('errors')} · $skipCount ${tr('skipped')}',
                style: TextStyle(fontWeight: FontWeight.w700, color: errCount > 0 ? scheme.error : scheme.primary),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (_, i) {
                    final r = results[i];
                    final color = switch (r.status) {
                      'ok' => Colors.green.shade700,
                      'error' => scheme.error,
                      'skipped' => scheme.onSurfaceVariant,
                      _ => scheme.outline,
                    };
                    final icon = switch (r.status) {
                      'ok' => Icons.check_circle_rounded,
                      'error' => Icons.error_rounded,
                      'skipped' => Icons.remove_circle_outline_rounded,
                      _ => Icons.hourglass_empty_rounded,
                    };
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(icon, size: 15, color: color),
                        const SizedBox(width: 6),
                        SizedBox(width: 34, child: Text('#${r.line}', style: TextStyle(fontSize: 11.5, color: scheme.outline))),
                        Expanded(child: Text(r.name.isEmpty ? '—' : r.name, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Flexible(child: Text(r.message, style: TextStyle(fontSize: 11.5, color: color), overflow: TextOverflow.ellipsis, maxLines: 2)),
                      ]),
                    );
                  },
                ),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: running ? null : () => Navigator.pop(context, okCount > 0), child: Text(finished ? tr('Close') : tr('Cancel'))),
        if (!finished)
          FilledButton.icon(
            onPressed: running || rows.isEmpty || parseError != null ? null : _run,
            icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
            label: Text(running ? tr('Importing…') : '${tr('Import')} ${rows.isEmpty ? '' : rows.length} ${isProducts ? tr('products') : tr('materials')}'),
          ),
      ],
    );
  }

  Widget _preview(ColorScheme scheme) {
    final keys = colIndex.keys.toList();
    final show = rows.take(5).toList();
    return Container(
      decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(8)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 32,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 32,
          columnSpacing: 18,
          columns: [for (final k in keys) DataColumn(label: Text(columns.firstWhere((c) => c.key == k).header, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))],
          rows: [
            for (final r in show)
              DataRow(cells: [for (final k in keys) DataCell(Text(_cell(r, k), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))]),
            if (rows.length > show.length)
              DataRow(cells: [
                for (var i = 0; i < keys.length; i++) DataCell(Text(i == 0 ? '… +${rows.length - show.length} ${tr('more')}' : '', style: TextStyle(fontSize: 12, color: scheme.outline))),
              ]),
          ],
        ),
      ),
    );
  }
}
