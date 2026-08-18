import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';

import '../../core/company.dart';
import '../../core/i18n.dart';
import '../../core/pdf_fonts.dart';

/// Stock Report PDF — all finished goods (cartons, trays, bottles, weights).
class StockPdf {
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
  static String n(Object? v) => _num.format(v is num ? v : num.tryParse('$v') ?? 0);

  static Future<Uint8List> build(List<Map<String, dynamic>> items, Map<String, dynamic> summary) async {
    await _loadFonts();
    const primary = PdfColor.fromInt(0xFF0A6ED1);
    const headerBg = PdfColor.fromInt(0xFFEFF5FC);
    const greyTxt = PdfColor.fromInt(0xFF64748B);
    const lineCol = PdfColor.fromInt(0xFFD5DBE8);
    const lowRed = PdfColor.fromInt(0xFFDC2626);

    pw.TextStyle ts(double size, {bool bold = false, PdfColor? color}) =>
        pw.TextStyle(
        font: bold ? _bold : _regular, fontFallback: bold ? _boldFallback : _regFallback, fontSize: size, color: color);

    pw.Widget cell(String text, {bool bold = false, bool right = false, bool header = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5.5),
          child: pw.Text(text,
              textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
              style: ts(header ? 8.6 : 9, bold: bold || header, color: color ?? (header ? primary : null))),
        );

    final headers = ['#', tr('Product'), '${tr(U.carton)} (${U.cb})', tr(U.tray), '${tr('Total')} ${U.piece}', tr('Gross kg'), 'Min (${U.cb})', tr('Status')];
    double sumCb = 0, sumTrays = 0, sumBottles = 0, sumGross = 0;
    final rows = <List<Object>>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      sumCb += (it['qty_cb'] as num).toDouble();
      sumTrays += (it['qty_trays'] as num).toDouble();
      sumBottles += (it['total_bottles'] as num).toDouble();
      sumGross += (it['gross_kg'] as num).toDouble();
      rows.add([
        '${i + 1}',
        '${it['name']}',
        n(it['qty_cb']),
        n(it['qty_trays']),
        n(it['total_bottles']),
        n(it['gross_kg']),
        n(it['min_stock_cb']),
        (it['low'] as num) == 1 ? 'LOW' : 'OK',
      ]);
    }

    pw.Widget metaBox(String label, String value) => pw.Container(
          width: 162,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: lineCol, width: 0.7), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label.toUpperCase(), style: ts(7.2, bold: true, color: greyTxt)),
            pw.SizedBox(height: 2.5),
            pw.Text(value, style: ts(9.6, bold: true)),
          ]),
        );

    final now = DateTime.now();
    final doc = pw.Document();
    // MultiPage: table flows across pages when there are many products
    // (a single Page silently drops overflowing content).
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
      build: (context) => [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(CompanyProfile.current.name, style: ts(15, bold: true)),
            pw.SizedBox(height: 2),
            if (CompanyProfile.current.address.isNotEmpty) pw.Text(CompanyProfile.current.address, style: ts(9, color: greyTxt)),
            if (CompanyProfile.current.taxLine.isNotEmpty) pw.Text(CompanyProfile.current.taxLine, style: ts(9, color: greyTxt)),
          ]),
          pw.Spacer(),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(color: headerBg, borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Text('STOCK REPORT', style: ts(12, bold: true, color: primary)),
            ),
            pw.SizedBox(height: 4),
            pw.Text(DateFormat('EEEE, dd MMM yyyy · hh:mm a').format(now), style: ts(9.5, color: greyTxt)),
          ]),
        ]),
        pw.SizedBox(height: 14),
        pw.Divider(color: lineCol, thickness: 0.8),
        pw.SizedBox(height: 10),
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          metaBox('Total cartons', '${n(summary['total_cb'])} CB'),
          metaBox('Total trays', n(summary['total_trays'])),
          metaBox('Total bottles', n(summary['total_bottles'])),
          metaBox('Low stock items', '${summary['low_count']}'),
        ]),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder.all(color: lineCol, width: 0.7),
          columnWidths: {
            0: const pw.FixedColumnWidth(26),
            1: const pw.FlexColumnWidth(2.6),
            2: const pw.FlexColumnWidth(1.1),
            3: const pw.FlexColumnWidth(0.9),
            4: const pw.FlexColumnWidth(1.1),
            5: const pw.FlexColumnWidth(1.0),
            6: const pw.FlexColumnWidth(0.95),
            7: const pw.FixedColumnWidth(48),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(color: headerBg),
              children: [for (var i = 0; i < headers.length; i++) cell(headers[i], header: true, right: i >= 2 && i <= 6)],
            ),
            for (final r in rows)
              pw.TableRow(children: [
                for (var i = 0; i < r.length; i++)
                  cell('${r[i]}',
                      right: i >= 2 && i <= 6,
                      bold: i == 7,
                      color: i == 7 ? (r[i] == 'LOW' ? lowRed : null) : null),
              ]),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: headerBg),
              children: [
                cell('TOTAL', bold: true, color: primary),
                cell('', color: primary),
                cell(n(sumCb), bold: true, right: true, color: primary),
                cell(n(sumTrays), bold: true, right: true, color: primary),
                cell(n(sumBottles), bold: true, right: true, color: primary),
                cell(n(sumGross), bold: true, right: true, color: primary),
                cell('', color: primary),
                cell('', color: primary),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text('Generated from live inventory — ${U.carton.toLowerCase()} (${U.cb}) and ${U.trayLc} tracked separately.',
            style: ts(8, color: greyTxt)),
      ],
    ));
    return doc.save();
  }
}
