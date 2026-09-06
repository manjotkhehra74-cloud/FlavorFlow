import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';

import '../../core/company.dart';
import '../../core/i18n.dart';
import '../../core/pdf_fonts.dart';

/// A grouped block inside a report (e.g. one product's materials in Loss%).
/// Rendered as its OWN table so the heading row always stays attached to its
/// data rows across page breaks (repeat:true re-prints it on continuations).
class PdfSection {
  final String title;
  final List<String> columns; // headers for the value columns (title fills col 0)
  final List<List<dynamic>> rows; // each row: [name, ...values] (1 + columns.length cells)
  const PdfSection({required this.title, required this.columns, required this.rows});
}

/// Generic report PDF — renders any report (title + table) in the company style.
class ReportPdf {
  static pw.Font? _regular;
  static pw.Font? _bold;
  static List<pw.Font> _regFallback = const [];
  static List<pw.Font> _boldFallback = const [];

  static Future<void> _loadFonts() async {
    _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf'));
    _regFallback = await PdfFonts.regularFallback();
    _boldFallback = await PdfFonts.boldFallback();
  }

  static final _num = NumberFormat('#,##,##0.##', 'en_IN');
  static String _fmt(Object? v) {
    if (v == null) return '—';
    if (v is num) return _num.format(v);
    final n = num.tryParse('$v');
    return n != null && '$v'.trim() == n.toString() ? _num.format(n) : '$v';
  }

  static Future<Uint8List> build({
    required String title,
    required String desc,
    required List<String> columns,
    required List<List<dynamic>> rows,
    List<PdfSection> sections = const [],
  }) async {
    title = tr(title);
    desc = tr(desc);
    columns = [for (final c in columns) tr(c)];

    // Auto-detect legacy "▶ Heading" rows (e.g. server-built batch-stock rows)
    // and lift them into proper sections so a heading is never stranded at the
    // bottom of a page away from its data, and pages pack fully.
    if (sections.isEmpty) {
      final firstHead = rows.indexWhere((r) => r.isNotEmpty && '${r[0]}'.trimLeft().startsWith('▶'));
      if (firstHead != -1) {
        bool blank(List<dynamic> r) => r.every((c) => '${c ?? ''}'.trim().isEmpty);
        final main = [for (final r in rows.sublist(0, firstHead)) if (!blank(r)) r];
        final auto = <PdfSection>[];
        String? curTitle;
        List<String>? curCols;
        var curRows = <List<dynamic>>[];
        void flush() {
          if (curTitle != null) auto.add(PdfSection(title: curTitle!, columns: curCols!, rows: curRows));
          curRows = <List<dynamic>>[];
        }
        for (final r in rows.sublist(firstHead)) {
          if (blank(r)) continue;
          if ('${r[0]}'.trimLeft().startsWith('▶')) {
            flush();
            curTitle = '${r[0]}'.trimLeft().replaceFirst('▶', '').trim();
            final rest = [for (var c = 1; c < r.length; c++) '${r[c] ?? ''}'.trim()];
            curCols = rest.any((s) => s.isNotEmpty) ? rest : [for (var c = 1; c < columns.length; c++) columns[c]];
          } else if (curTitle != null) {
            curRows.add(r);
          }
        }
        flush();
        rows = main;
        sections = auto;
      }
    }

    await _loadFonts();
    const primary = PdfColor.fromInt(0xFF0A6ED1);
    const headerBg = PdfColor.fromInt(0xFFEFF5FC);
    const greyTxt = PdfColor.fromInt(0xFF64748B);
    const lineCol = PdfColor.fromInt(0xFFD5DBE8);

    pw.TextStyle ts(double size, {bool bold = false, PdfColor? color}) => pw.TextStyle(
        font: bold ? _bold : _regular, fontFallback: bold ? _boldFallback : _regFallback, fontSize: size, color: color);

    final landscape = columns.length > 6;
    final numericCols = <int>{};
    for (var c = 0; c < columns.length; c++) {
      if (rows.any((r) => c < r.length && r[c] is num)) numericCols.add(c);
    }

    pw.Widget cell(String text, {bool bold = false, bool right = false, bool header = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(PdfFonts.shape(text),
              textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
              style: ts(header ? 8.4 : 8.8, bold: bold || header, color: header ? primary : null)),
        );

    final now = DateTime.now();
    final doc = pw.Document();
    // MultiPage: long reports (30–200+ rows) flow across pages automatically —
    // a single Page silently drops content that overflows (blank-table bug).
    doc.addPage(pw.MultiPage(
      pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(34, 28, 34, 28),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(children: [
          pw.Text(PdfFonts.shape(tr('Exported from FlavorFlow ERP — quantities and weights only.')), style: ts(7.8, color: greyTxt)),
          pw.Spacer(),
          pw.Text(PdfFonts.shape('Page ${context.pageNumber} of ${context.pagesCount}'), style: ts(7.8, color: greyTxt)),
        ]),
      ),
      build: (context) => [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(PdfFonts.shape(CompanyProfile.current.name), style: ts(14, bold: true)),
            pw.SizedBox(height: 2),
            if (CompanyProfile.current.address.isNotEmpty) pw.Text(PdfFonts.shape(CompanyProfile.current.address), style: ts(8.6, color: greyTxt)),
            if (CompanyProfile.current.taxLine.isNotEmpty) pw.Text(PdfFonts.shape(CompanyProfile.current.taxLine), style: ts(8.6, color: greyTxt)),
          ]),
          pw.Spacer(),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(color: headerBg, borderRadius: pw.BorderRadius.circular(5)),
              child: pw.Text(PdfFonts.shape(title.toUpperCase()), style: ts(11, bold: true, color: primary)),
            ),
            pw.SizedBox(height: 4),
            pw.Text(PdfFonts.shape(DateFormat('EEEE, dd MMM yyyy · hh:mm a').format(now)), style: ts(8.8, color: greyTxt)),
          ]),
        ]),
        pw.SizedBox(height: 6),
        pw.Text(PdfFonts.shape(desc), style: ts(9, color: greyTxt)),
        pw.SizedBox(height: 8),
        pw.Divider(color: lineCol, thickness: 0.8),
        pw.SizedBox(height: 6),
        pw.Text(PdfFonts.shape('${rows.length} ${tr('records')}'), style: ts(8.6, bold: true, color: greyTxt)),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: lineCol, width: 0.7),
          columnWidths: {
            for (var c = 0; c < columns.length; c++)
              c: c == 0 ? const pw.FlexColumnWidth(2.2) : const pw.FlexColumnWidth(1.4),
          },
          // Repeat the header row at the top of every page.
          tableWidth: pw.TableWidth.max,
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(color: headerBg),
              children: [for (var c = 0; c < columns.length; c++) cell(columns[c].toUpperCase(), header: true, right: numericCols.contains(c))],
            ),
            for (final r in rows)
              pw.TableRow(children: [
                for (var c = 0; c < r.length; c++) cell(_fmt(r[c]), right: numericCols.contains(c)),
              ]),
          ],
        ),
        // ---- grouped sections (e.g. Loss% per-product blocks) ----
        // Each section renders as its own small tables so MultiPage can pack
        // pages fully (no half-empty pages), while the heading + column labels
        // + first data row form ONE widget — a heading can never be left
        // orphaned at the bottom of a page without its data.
        ..._sectionWidgets(sections, cell, ts, headerBg, lineCol, primary),
      ],
    ));
    return doc.save();
  }

  static List<pw.Widget> _sectionWidgets(
    List<PdfSection> sections,
    pw.Widget Function(String, {bool bold, bool right, bool header}) cell,
    pw.TextStyle Function(double, {bool bold, PdfColor? color}) ts,
    PdfColor headerBg,
    PdfColor lineCol,
    PdfColor primary,
  ) {
    if (sections.isEmpty) return const [];

    pw.Table block(List<pw.TableRow> trs, int valueCols) => pw.Table(
          border: pw.TableBorder.all(color: lineCol, width: 0.7),
          tableWidth: pw.TableWidth.max,
          columnWidths: {
            for (var c = 0; c <= valueCols; c++)
              c: c == 0 ? const pw.FlexColumnWidth(2.2) : const pw.FlexColumnWidth(1.4),
          },
          children: trs,
        );

    pw.TableRow dataRow(List<dynamic> r, int valueCols) => pw.TableRow(children: [
          for (var c = 0; c <= valueCols; c++) cell(c < r.length ? _fmt(r[c]) : '', right: c > 0),
        ]);

    final out = <pw.Widget>[];
    for (final s in sections) {
      final vc = s.columns.length;
      out.add(pw.SizedBox(height: 10));
      // heading row + column labels + first data row = one unbreakable block
      out.add(block([
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerBg),
          children: [
            cell(s.title, bold: true),
            for (final c in s.columns) cell(tr(c).toUpperCase(), header: true, right: true),
          ],
        ),
        if (s.rows.isNotEmpty) dataRow(s.rows.first, vc),
      ], vc));
      // remaining rows flow one-by-one → pages fill completely
      for (final r in s.rows.skip(1)) {
        out.add(block([dataRow(r, vc)], vc));
      }
    }
    return out;
  }
}
