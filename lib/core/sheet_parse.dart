import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Tiny spreadsheet reader for bulk import — no heavy `excel` dependency.
///
/// * [parseDelimited]: CSV / TSV / semicolon text (Excel & Google Sheets
///   "copy cells → paste" produces tab-separated text), RFC-4180 quotes, BOM.
/// * [parseXlsx]: first worksheet of an .xlsx (shared strings, inline strings,
///   cached formula values). Dates are not needed for master data, so serial
///   numbers are returned as plain numbers.
///
/// Both return rows of trimmed strings; fully empty rows are dropped.
class SheetParse {
  static List<List<String>> parseDelimited(String text) {
    var t = text;
    if (t.startsWith('\uFEFF')) t = t.substring(1);
    t = t.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (t.trim().isEmpty) return const [];
    final firstLine = t.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final delim = firstLine.contains('\t')
        ? '\t'
        : (firstLine.split(';').length > firstLine.split(',').length ? ';' : ',');
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < t.length; i++) {
      final ch = t[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < t.length && t[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == delim) {
        row.add(cell.toString().trim());
        cell.clear();
      } else if (ch == '\n') {
        row.add(cell.toString().trim());
        cell.clear();
        if (row.any((c) => c.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    row.add(cell.toString().trim());
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
    return rows;
  }

  static List<List<String>> parseXlsx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    String? read(String path) {
      final f = archive.findFile(path);
      if (f == null) return null;
      return utf8.decode(f.content, allowMalformed: true);
    }

    // shared strings
    final shared = <String>[];
    final ss = read('xl/sharedStrings.xml');
    if (ss != null) {
      for (final si in XmlDocument.parse(ss).findAllElements('si')) {
        shared.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }

    // first sheet: workbook.xml → rels → target (fallback sheet1.xml)
    var sheetPath = 'xl/worksheets/sheet1.xml';
    try {
      final wb = read('xl/workbook.xml');
      final rels = read('xl/_rels/workbook.xml.rels');
      if (wb != null && rels != null) {
        final first = XmlDocument.parse(wb).findAllElements('sheet').firstOrNull;
        final rid = first?.attributes.where((a) => a.name.local == 'id').map((a) => a.value).firstOrNull;
        if (rid != null) {
          for (final r in XmlDocument.parse(rels).findAllElements('Relationship')) {
            if (r.getAttribute('Id') == rid) {
              var target = r.getAttribute('Target') ?? '';
              if (target.startsWith('/')) target = target.substring(1);
              if (!target.startsWith('xl/')) target = 'xl/$target';
              if (archive.findFile(target) != null) sheetPath = target;
            }
          }
        }
      }
    } catch (_) {/* keep default */}

    final xml = read(sheetPath);
    if (xml == null) {
      throw const FormatException('No worksheet found in this .xlsx file');
    }
    final rows = <List<String>>[];
    for (final r in XmlDocument.parse(xml).findAllElements('row')) {
      final cells = <int, String>{};
      var auto = 0;
      for (final c in r.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = ref == null ? auto : _colIndex(ref);
        auto = col + 1;
        final type = c.getAttribute('t');
        String v = '';
        if (type == 's') {
          final idx = int.tryParse(c.getElement('v')?.innerText ?? '');
          v = idx != null && idx >= 0 && idx < shared.length ? shared[idx] : '';
        } else if (type == 'inlineStr') {
          v = c.findAllElements('t').map((t) => t.innerText).join();
        } else {
          v = c.getElement('v')?.innerText ?? '';
          if (type == 'b') v = v == '1' ? 'TRUE' : 'FALSE';
          // 12.0 → 12 (Excel stores integers as doubles)
          final n = num.tryParse(v);
          if (n != null && n == n.roundToDouble() && n.abs() < 1e15) v = n.toInt().toString();
        }
        cells[col] = v.trim();
      }
      if (cells.isEmpty) continue;
      final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
      final row = List<String>.generate(width, (i) => cells[i] ?? '');
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
    }
    return rows;
  }

  /// "C12" → 2, "AA3" → 26
  static int _colIndex(String ref) {
    var n = 0;
    for (final ch in ref.codeUnits) {
      if (ch >= 65 && ch <= 90) {
        n = n * 26 + (ch - 64);
      } else if (ch >= 97 && ch <= 122) {
        n = n * 26 + (ch - 96);
      } else {
        break;
      }
    }
    return n == 0 ? 0 : n - 1;
  }

  /// CSV writer for templates / exports.
  static String toCsv(List<List<String>> rows) {
    String esc(String v) => RegExp(r'[",\n\r]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;
    return rows.map((r) => r.map(esc).join(',')).join('\r\n');
  }
}
