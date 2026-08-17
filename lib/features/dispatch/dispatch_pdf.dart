import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';

/// PDF builder for dispatch challans & truck-loading estimates.
/// Roboto is embedded so all glyphs render correctly.
class DispatchPdf {
  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<void> _loadFonts() async {
    _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf'));
  }

  static final _num = NumberFormat('#,##,##0.##', 'en_IN');
  static String kg(Object? v) => '${_num.format(v is num ? v : num.tryParse('$v') ?? 0)} kg';

  /// Confirmed dispatch challan (from dispatch detail API payload).
  static Future<Uint8List> challan(Map<String, dynamic> d, List<Map<String, dynamic>> items) async {
    await _loadFonts();
    final rows = <List<String>>[
      for (var i = 0; i < items.length; i++)
        [
          '${i + 1}',
          '${items[i]['product_name']}',
          '${items[i]['cartons']}',
          '${items[i]['trays'] ?? 0}',
          '${items[i]['total_bottles']}',
          kg(items[i]['carton_weight']),
          kg(items[i]['tray_weight'] ?? 0),
          kg(items[i]['gross_weight']),
        ],
    ];
    final doc = pw.Document();
    doc.addPage(_page(
      title: 'DISPATCH CHALLAN',
      subtitle: '${d['code']}',
      meta: [
        ['Dispatch Date', _dateWithDay(d['dispatch_date'])],
        ['Truck / Vehicle No.', '${d['truck_number']}'],
        ['Destination', '${d['destination'] ?? '—'}'],
        ['Prepared By', '${d['created_by_name'] ?? '—'}'],
      ],
      remarks: '${d['remarks'] ?? ''}',
      rows: rows,
      totals: [
        'TOTAL', '', '${d['total_cartons']}', '${d['total_trays'] ?? 0}', '${d['total_bottles']}',
        kg(d['carton_weight']), kg(d['tray_weight'] ?? 0), kg(d['gross_weight']),
      ],
      footnote: 'Date & day are recorded automatically at dispatch time.',
    ));
    return doc.save();
  }

  /// Truck Loading Calculator estimate (pre-dispatch loading plan).
  static Future<Uint8List> estimate({
    required List<Map<String, dynamic>> lines,
    required Map<String, dynamic> totals,
    String? truckNumber,
    String? dispatchDate,
    String? destination,
  }) async {
    await _loadFonts();
    final rows = <List<String>>[
      for (var i = 0; i < lines.length; i++)
        [
          '${i + 1}',
          '${lines[i]['productName']}',
          '${lines[i]['cartons']}',
          '${lines[i]['trays'] ?? 0}',
          '${lines[i]['totalBottles']}',
          kg(lines[i]['cartonWeight']),
          kg(lines[i]['trayWeight'] ?? 0),
          kg(lines[i]['grossWeight']),
        ],
    ];
    final doc = pw.Document();
    doc.addPage(_page(
      title: 'TRUCK LOADING PLAN',
      subtitle: 'Pre-dispatch weight estimate',
      meta: [
        ['Truck / Vehicle No.', (truckNumber == null || truckNumber.isEmpty) ? '—' : truckNumber],
        ['Dispatch Date', (dispatchDate == null || dispatchDate.isEmpty) ? '—' : _dateWithDay(dispatchDate)],
        ['Destination', (destination == null || destination.isEmpty) ? '—' : destination],
      ],
      rows: rows,
      totals: [
        'TOTAL', '', '${totals['totalCartons']}', '${totals['totalTrays'] ?? 0}', '${totals['totalBottles']}',
        kg(totals['cartonWeight']), kg(totals['trayWeight'] ?? 0), kg(totals['grossWeight']),
      ],
      footnote: 'Estimate only — actual challan is generated at dispatch.',
    ));
    return doc.save();
  }

  static const _headers = ['#', 'Product', 'Cartons', 'Trays', 'Bottles', 'Carton Wt', 'Tray Wt', 'Gross Wt'];

  static pw.Page _page({
    required String title,
    required String subtitle,
    required List<List<String>> meta,
    required List<List<String>> rows,
    required List<String> totals,
    required String footnote,
    String remarks = '',
  }) {
    const primary = PdfColor.fromInt(0xFF2456C8);
    const headerBg = PdfColor.fromInt(0xFFEFF4FF);
    const greyTxt = PdfColor.fromInt(0xFF64748B);
    const lineCol = PdfColor.fromInt(0xFFD5DBE8);
    final border = pw.TableBorder.all(color: lineCol, width: 0.7);

    pw.TextStyle ts(double size, {bool bold = false, PdfColor? color}) =>
        pw.TextStyle(font: bold ? _bold : _regular, fontSize: size, color: color);

    pw.Widget cell(String text, {bool bold = false, bool right = false, bool header = false, PdfColor? color}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: pw.Text(text,
              textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
              style: ts(header ? 8.6 : 9, bold: bold || header, color: color ?? (header ? primary : null))),
        );

    final widths = {
      0: const pw.FixedColumnWidth(26),
      1: const pw.FlexColumnWidth(2.6),
      2: const pw.FlexColumnWidth(1.0),
      3: const pw.FlexColumnWidth(0.9),
      4: const pw.FlexColumnWidth(1.0),
      5: const pw.FlexColumnWidth(1.25),
      6: const pw.FlexColumnWidth(1.2),
      7: const pw.FlexColumnWidth(1.3),
    };

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
      build: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        // brand row
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('FlavorFlow Foods Pvt. Ltd.', style: ts(15, bold: true)),
            pw.SizedBox(height: 2),
            pw.Text('Industrial Area, Jalandhar, Punjab 144004', style: ts(9, color: greyTxt)),
            pw.Text('GSTIN 03AAAAA0000A1Z5 · dispatch@flavorflow.in', style: ts(9, color: greyTxt)),
          ]),
          pw.Spacer(),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(color: headerBg, borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Text(title, style: ts(12, bold: true, color: primary)),
            ),
            pw.SizedBox(height: 4),
            pw.Text(subtitle, style: ts(11, bold: true)),
          ]),
        ]),
        pw.SizedBox(height: 14),
        pw.Divider(color: lineCol, thickness: 0.8),
        pw.SizedBox(height: 10),

        // meta grid
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in meta)
            pw.Container(
              width: 162,
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: lineCol, width: 0.7), borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(m[0].toUpperCase(), style: ts(7.2, bold: true, color: greyTxt)),
                pw.SizedBox(height: 2.5),
                pw.Text(m[1], style: ts(9.6, bold: true)),
              ]),
            ),
        ]),
        pw.SizedBox(height: 16),

        // items table + totals row
        pw.Table(
          border: border,
          columnWidths: widths,
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: headerBg),
              children: [for (var i = 0; i < _headers.length; i++) cell(_headers[i], header: true, right: i >= 2)],
            ),
            for (final r in rows)
              pw.TableRow(children: [for (var i = 0; i < r.length; i++) cell(r[i], right: i >= 2)]),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: headerBg),
              children: [
                for (var i = 0; i < totals.length; i++)
                  i == 0
                      ? pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6), child: pw.Text('TOTAL', style: ts(9, bold: true, color: primary)))
                      : cell(totals[i], bold: true, right: i >= 2, color: primary),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),

        if (remarks.isNotEmpty)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(9),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: lineCol, width: 0.7), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Text('Remarks: $remarks', style: ts(9)),
          ),
        pw.SizedBox(height: 8),
        pw.Text(footnote, style: ts(9.4, bold: true)),
        pw.SizedBox(height: 6),
        pw.Text('Weights are computed from the Product Master (carton gross weight and tray weight).',
            style: ts(8, color: greyTxt)),
        pw.Spacer(),

        // signature blocks
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Prepared by (Store)', style: ts(9)),
          pw.Text('Transport In-charge', style: ts(9)),
          pw.Text('Received by', style: ts(9)),
        ]),
        pw.SizedBox(height: 4),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Container(width: 150, height: 1, color: const PdfColor.fromInt(0xFF94A3B8)),
          pw.Container(width: 150, height: 1, color: const PdfColor.fromInt(0xFF94A3B8)),
          pw.Container(width: 150, height: 1, color: const PdfColor.fromInt(0xFF94A3B8)),
        ]),
      ]),
    );
  }

  static String _dateWithDay(Object? raw) {
    try {
      final s = '$raw'.split(' ').first;
      return DateFormat('EEEE, dd MMM yyyy').format(DateTime.parse(s));
    } catch (_) {
      return '$raw';
    }
  }
}
