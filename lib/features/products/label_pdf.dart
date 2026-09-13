import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/company.dart';
import '../../core/i18n.dart';
import '../../core/item_code.dart';
import '../../core/pdf_fonts.dart';

/// Item-code label sheets (SAP material-number labels) for shelves, bins,
/// cartons and sample boards.
///
/// Every label carries a QR code whose payload is the bare item code
/// (e.g. `FG0000000012`) — the app's scan button reads that payload and picks
/// the item — plus a Code-128 barcode of the same value for hand scanners,
/// the item name, the code in text, pack info and the company name.
///
/// Sheet: A4, 3 columns × 8 rows = 24 labels (≈ 63.5 × 33.9 mm — the common
/// "24-up" self-adhesive sheet); `copies` repeats each item.
class LabelPdf {
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

  /// [items]: rows with `name`, `item_code` and optionally `bottles_per_cb`,
  /// `unit`, `category`. Items without a code are skipped (nothing to encode).
  static Future<Uint8List> sheet(List<Map<String, dynamic>> items, {int copies = 1, bool big = false}) async {
    await _loadFonts();
    final company = CompanyProfile.current;
    final labels = <Map<String, dynamic>>[
      for (final it in items)
        if (ItemCode.of(it).isNotEmpty)
          for (var c = 0; c < copies.clamp(1, 48); c++) it,
    ];

    pw.TextStyle ts(double size, {bool bold = false, PdfColor? color}) =>
        pw.TextStyle(font: bold ? _bold : _regular, fontFallback: bold ? _boldFallback : _regFallback, fontSize: size, color: color);
    const grey = PdfColor.fromInt(0xFF64748B);
    const line = PdfColor.fromInt(0xFFCBD5E1);

    // 24-up (3×8) or 8-up (2×4) big labels
    final cols = big ? 2 : 3, rows = big ? 4 : 8;
    final perPage = cols * rows;

    String subline(Map<String, dynamic> it) {
      final parts = <String>[];
      final ppc = it['bottles_per_cb'];
      if (ppc is num && ppc > 0) parts.add('${ppc.toInt()} ${company.pieceLabel.toLowerCase()} / ${company.cartonShort}');
      final unit = (it['unit'] ?? '').toString();
      if (unit.isNotEmpty) parts.add(unit);
      final cat = (it['category'] ?? '').toString();
      if (cat.isNotEmpty) parts.add(tr(cat));
      return parts.join(' · ');
    }

    pw.Widget label(Map<String, dynamic> it) {
      final code = ItemCode.of(it);
      final name = (it['name'] ?? '').toString();
      final qrSize = big ? 62.0 : 44.0;
      return pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: line, width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
        padding: pw.EdgeInsets.all(big ? 8 : 5),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: code, width: qrSize, height: qrSize, drawText: false),
          pw.SizedBox(width: big ? 8 : 5),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.center, children: [
              pw.Text(PdfFonts.shape(name), style: ts(big ? 10.5 : 7.8, bold: true), maxLines: 2, overflow: pw.TextOverflow.clip),
              pw.SizedBox(height: 2),
              pw.Text(code, style: ts(big ? 10 : 7.6, bold: true, color: PdfColors.blueGrey800)),
              if (subline(it).isNotEmpty) pw.Text(PdfFonts.shape(subline(it)), style: ts(big ? 7.4 : 5.8, color: grey), maxLines: 1, overflow: pw.TextOverflow.clip),
              pw.SizedBox(height: 3),
              // Code-128 for hand scanners (same payload as the QR)
              pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: code, width: big ? 150 : 96, height: big ? 20 : 13, drawText: false),
              pw.SizedBox(height: 2),
              pw.Text(PdfFonts.shape(company.name), style: ts(big ? 6.4 : 5.2, color: grey), maxLines: 1, overflow: pw.TextOverflow.clip),
            ]),
          ),
        ]),
      );
    }

    final doc = pw.Document(title: tr('Item code labels'), author: company.name);
    if (labels.isEmpty) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Center(child: pw.Text(PdfFonts.shape(tr('No item codes yet — the server assigns FG / RM / PM codes automatically; reopen the list and try again.')), style: ts(11))),
      ));
      return doc.save();
    }
    for (var start = 0; start < labels.length; start += perPage) {
      final page = labels.sublist(start, (start + perPage).clamp(0, labels.length));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(20, 24, 20, 24),
        build: (_) => pw.GridView(
          crossAxisCount: cols,
          childAspectRatio: big ? 0.5 : 0.53,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          children: [for (final it in page) label(it)],
        ),
      ));
    }
    return doc.save();
  }
}
