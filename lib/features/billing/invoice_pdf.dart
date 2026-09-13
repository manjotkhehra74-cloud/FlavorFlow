import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/company.dart';
import '../../core/i18n.dart';
import '../../core/pdf_fonts.dart';

/// GST tax invoice PDF (A4). Layout follows the usual Indian tax-invoice
/// format: seller block, buyer block, invoice meta, HSN-wise item table,
/// tax split (CGST+SGST or IGST), amount in words, bank details, terms
/// and the authorised-signatory box.
class InvoicePdf {
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

  static final _money = NumberFormat('#,##,##0.00', 'en_IN');
  static final _qty = NumberFormat('#,##,##0.##', 'en_IN');
  static num _n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
  static String m(Object? v) => _money.format(_n(v));
  static String q(Object? v) => _qty.format(_n(v));
  static String d(Object? v) {
    final s = '$v';
    if (s.length < 10) return s;
    return '${s.substring(8, 10)}-${s.substring(5, 7)}-${s.substring(0, 4)}';
  }

  static const _states = {
    '01': 'Jammu & Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh', '05': 'Uttarakhand', '06': 'Haryana',
    '07': 'Delhi', '08': 'Rajasthan', '09': 'Uttar Pradesh', '10': 'Bihar', '11': 'Sikkim', '12': 'Arunachal Pradesh', '13': 'Nagaland',
    '14': 'Manipur', '15': 'Mizoram', '16': 'Tripura', '17': 'Meghalaya', '18': 'Assam', '19': 'West Bengal', '20': 'Jharkhand',
    '21': 'Odisha', '22': 'Chhattisgarh', '23': 'Madhya Pradesh', '24': 'Gujarat', '26': 'Dadra & Nagar Haveli and Daman & Diu',
    '27': 'Maharashtra', '29': 'Karnataka', '30': 'Goa', '31': 'Lakshadweep', '32': 'Kerala', '33': 'Tamil Nadu', '34': 'Puducherry',
    '35': 'Andaman & Nicobar', '36': 'Telangana', '37': 'Andhra Pradesh', '38': 'Ladakh', '97': 'Other Territory',
  };

  /// Indian-system amount in words: "Rupees Thirty Two Thousand Three Hundred Fifty Only".
  static String inWords(num amount) {
    final rupees = amount.floor();
    final paise = ((amount - rupees) * 100).round();
    String r = _words(rupees);
    if (r.isEmpty) r = 'Zero';
    var out = 'Rupees $r';
    if (paise > 0) out += ' and ${_words(paise)} Paise';
    return '$out Only';
  }

  static const _ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
  static const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

  static String _below100(int n) => n < 20 ? _ones[n] : '${_tens[n ~/ 10]}${n % 10 == 0 ? '' : ' ${_ones[n % 10]}'}';

  static String _words(int n) {
    if (n == 0) return '';
    final parts = <String>[];
    if (n >= 10000000) { parts.add('${_words(n ~/ 10000000)} Crore'); n %= 10000000; }
    if (n >= 100000) { parts.add('${_below100(n ~/ 100000)} Lakh'); n %= 100000; }
    if (n >= 1000) { parts.add('${_below100(n ~/ 1000)} Thousand'); n %= 1000; }
    if (n >= 100) { parts.add('${_ones[n ~/ 100]} Hundred'); n %= 100; }
    if (n > 0) parts.add(_below100(n));
    return parts.join(' ');
  }

  /// [payload] = GET /billing/invoices/:id → {invoice, items, payments, settings, company}
  static Future<Uint8List> build(Map<String, dynamic> payload, {bool original = true}) async {
    await _loadFonts();
    final inv = (payload['invoice'] as Map).cast<String, dynamic>();
    final items = (payload['items'] as List).cast<Map<String, dynamic>>();
    final payments = ((payload['payments'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final s = ((payload['settings'] as Map?) ?? const {}).cast<String, dynamic>();
    final co = ((payload['company'] as Map?) ?? const {}).cast<String, dynamic>();
    final profile = CompanyProfile.current;

    final sellerName = (s['legalName'] ?? '').toString().isNotEmpty ? s['legalName'].toString() : (co['name'] ?? profile.name).toString();
    final sellerAddr = (s['address'] ?? '').toString().isNotEmpty ? s['address'].toString() : (co['address'] ?? profile.address).toString();
    final sellerGstin = (s['gstin'] ?? '').toString();
    final sellerState = (s['stateCode'] ?? '').toString().isNotEmpty ? s['stateCode'].toString() : (sellerGstin.length >= 2 ? sellerGstin.substring(0, 2) : '');
    final contact = [if ((s['phone'] ?? '').toString().isNotEmpty) 'Ph: ${s['phone']}', if ((s['email'] ?? '').toString().isNotEmpty) '${s['email']}'].join('  ·  ');
    final intra = inv['supply_type'] != 'inter';
    final cancelled = inv['status'] == 'CANCELLED';
    final paid = _n(inv['paid_amount']);
    final balance = _n(inv['total']) - paid;
    final pos = (inv['place_of_supply'] ?? '').toString();
    final hasDisc = items.any((it) => _n(it['discount_amt']) > 0);
    final hasBatch = items.any((it) => (it['batch_code'] ?? '').toString().isNotEmpty);

    const primary = PdfColor.fromInt(0xFF1E3A8A);
    const headerBg = PdfColor.fromInt(0xFFEEF2FF);
    const greyTxt = PdfColor.fromInt(0xFF64748B);
    const lineCol = PdfColor.fromInt(0xFFCBD5E1);
    const red = PdfColor.fromInt(0xFFDC2626);
    final border = pw.TableBorder.all(color: lineCol, width: 0.6);

    pw.TextStyle ts(double size, {bool bold = false, PdfColor? color}) =>
        pw.TextStyle(font: bold ? _bold : _regular, fontFallback: bold ? _boldFallback : _regFallback, fontSize: size, color: color);
    pw.Widget t(String text, double size, {bool bold = false, PdfColor? color, pw.TextAlign? align}) =>
        pw.Text(PdfFonts.shape(text), style: ts(size, bold: bold, color: color), textAlign: align);
    pw.Widget cell(String text, {bool bold = false, bool right = false, bool header = false, PdfColor? color, double size = 8.6}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4.5),
          child: pw.Text(PdfFonts.shape(text), textAlign: right ? pw.TextAlign.right : pw.TextAlign.left, style: ts(header ? 8 : size, bold: bold || header, color: color ?? (header ? primary : null))),
        );
    pw.Widget kv(String k, String v, {bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2.5),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 78, child: t(k, 8, color: greyTxt)),
            pw.Expanded(child: t(v, 8.6, bold: bold)),
          ]),
        );

    final headers = ['#', tr('Description'), 'HSN', if (hasBatch) tr('Batch'), tr('Qty'), tr('Rate'), if (hasDisc) tr('Disc'), tr('Taxable'), 'GST %', tr('Amount')];
    final firstRight = hasBatch ? 4 : 3;
    final widths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(20),
      1: const pw.FlexColumnWidth(3.0),
      2: const pw.FixedColumnWidth(42),
      for (var i = 3; i < headers.length; i++) i: const pw.FlexColumnWidth(1.0),
    };

    String unitOf(Map<String, dynamic> it) {
      final u = (it['unit'] ?? '').toString();
      if (u.isNotEmpty) return u;
      return it['rate_per'] == 'piece' ? profile.pieceLabel : profile.cartonShort;
    }

    // Rate-wise tax summary (HSN summary as GST rules expect).
    final byHsn = <String, Map<String, num>>{};
    for (final it in items) {
      final key = '${it['hsn_code'] ?? ''}|${_n(it['gst_rate'])}';
      final e = byHsn.putIfAbsent(key, () => {'rate': _n(it['gst_rate']), 'taxable': 0, 'cgst': 0, 'sgst': 0, 'igst': 0});
      e['taxable'] = e['taxable']! + _n(it['taxable']);
      e['cgst'] = e['cgst']! + _n(it['cgst']);
      e['sgst'] = e['sgst']! + _n(it['sgst']);
      e['igst'] = e['igst']! + _n(it['igst']);
    }

    final doc = pw.Document(title: '${inv['number']}', author: sellerName);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 26),
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          t('${inv['number']}  ·  ${tr('This is a computer generated invoice')}', 7.5, color: greyTxt),
          t('${tr('Page')} ${ctx.pageNumber}/${ctx.pagesCount}', 7.5, color: greyTxt),
        ]),
      ),
      build: (ctx) => [
        // ── Title strip
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
          decoration: const pw.BoxDecoration(color: headerBg),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            t(sellerGstin.isEmpty ? tr('INVOICE') : tr('TAX INVOICE'), 12, bold: true, color: primary),
            t(cancelled ? tr('CANCELLED') : (original ? tr('Original for Recipient') : tr('Duplicate for Supplier')), 8.5, bold: true, color: cancelled ? red : greyTxt),
          ]),
        ),
        pw.SizedBox(height: 8),
        // ── Seller + invoice meta
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            flex: 3,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              t(sellerName, 14, bold: true),
              if (sellerAddr.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: t(sellerAddr, 8.6, color: greyTxt)),
              if (contact.isNotEmpty) t(contact, 8.4, color: greyTxt),
              pw.SizedBox(height: 3),
              if (sellerGstin.isNotEmpty) t('GSTIN: $sellerGstin', 9, bold: true),
              if (sellerState.isNotEmpty) t('${tr('State')}: ${_states[sellerState] ?? sellerState} ($sellerState)', 8.4, color: greyTxt),
            ]),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            flex: 2,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: lineCol, width: 0.6), borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                kv(tr('Invoice No'), '${inv['number']}', bold: true),
                kv(tr('Date'), d(inv['invoice_date'])),
                if ((inv['due_date'] ?? '').toString().isNotEmpty && inv['due_date'] != inv['invoice_date']) kv(tr('Due date'), d(inv['due_date'])),
                if ((inv['dispatch_code'] ?? '').toString().isNotEmpty) kv(tr('Dispatch'), '${inv['dispatch_code']}'),
                if (pos.isNotEmpty) kv(tr('Place of supply'), '${_states[pos] ?? pos} ($pos)'),
                kv(tr('Supply'), intra ? tr('Intra-state') : tr('Inter-state')),
              ]),
            ),
          ),
        ]),
        pw.SizedBox(height: 8),
        // ── Buyer
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: lineCol, width: 0.6), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            t(tr('BILL TO').toUpperCase(), 7.5, bold: true, color: primary),
            pw.SizedBox(height: 2),
            t('${inv['party_name']}', 11, bold: true),
            if ((inv['party_address'] ?? '').toString().isNotEmpty) t('${inv['party_address']}', 8.6, color: greyTxt),
            pw.SizedBox(height: 2),
            if ((inv['party_gstin'] ?? '').toString().isNotEmpty) t('GSTIN: ${inv['party_gstin']}', 8.8, bold: true) else t(tr('Unregistered (B2C)'), 8.4, color: greyTxt),
          ]),
        ),
        pw.SizedBox(height: 10),
        // ── Items
        pw.Table(
          border: border,
          columnWidths: widths,
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: headerBg), children: [for (var i = 0; i < headers.length; i++) cell(headers[i], header: true, right: i >= firstRight)]),
            for (var i = 0; i < items.length; i++)
              pw.TableRow(children: [
                cell('${i + 1}'),
                cell('${items[i]['description']}${(items[i]['item_code'] ?? '').toString().isNotEmpty ? '\n${tr('Code')}: ${items[i]['item_code']}' : ''}${items[i]['rate_per'] == 'piece' && _n(items[i]['pieces_per_pack']) > 1 ? '\n${q(items[i]['qty'])} ${profile.cartonShort} × ${q(items[i]['pieces_per_pack'])} ${profile.pieceLabel.toLowerCase()}' : ''}'),
                cell('${items[i]['hsn_code'] ?? ''}'),
                if (hasBatch) cell('${items[i]['batch_code'] ?? ''}'),
                cell(items[i]['rate_per'] == 'piece' ? '${q(_n(items[i]['qty']) * (_n(items[i]['pieces_per_pack']) <= 0 ? 1 : _n(items[i]['pieces_per_pack'])))} ${unitOf(items[i])}' : '${q(items[i]['qty'])} ${unitOf(items[i])}', right: true),
                cell(m(items[i]['rate']), right: true),
                if (hasDisc) cell(_n(items[i]['discount_pct']) > 0 ? '${q(items[i]['discount_pct'])}%' : '—', right: true),
                cell(m(items[i]['taxable']), right: true),
                cell('${q(items[i]['gst_rate'])}%', right: true),
                cell(m(items[i]['total']), right: true, bold: true),
              ]),
          ],
        ),
        pw.SizedBox(height: 8),
        // ── Tax summary + totals
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            flex: 3,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Table(
                border: border,
                columnWidths: const {0: pw.FlexColumnWidth(1.4), 1: pw.FlexColumnWidth(1.0), 2: pw.FlexColumnWidth(1.3), 3: pw.FlexColumnWidth(1.3), 4: pw.FlexColumnWidth(1.3)},
                children: [
                  pw.TableRow(decoration: const pw.BoxDecoration(color: headerBg), children: [
                    cell('HSN', header: true), cell('GST %', header: true, right: true), cell(tr('Taxable'), header: true, right: true),
                    if (intra) ...[cell('CGST', header: true, right: true), cell('SGST', header: true, right: true)] else ...[cell('IGST', header: true, right: true), cell('', header: true)],
                  ]),
                  for (final e in byHsn.entries)
                    pw.TableRow(children: [
                      cell(e.key.split('|').first, size: 8), cell('${q(e.value['rate'])}%', right: true, size: 8), cell(m(e.value['taxable']), right: true, size: 8),
                      if (intra) ...[cell(m(e.value['cgst']), right: true, size: 8), cell(m(e.value['sgst']), right: true, size: 8)] else ...[cell(m(e.value['igst']), right: true, size: 8), cell('', size: 8)],
                    ]),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(7),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: lineCol, width: 0.6), borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  t(tr('Amount in words').toUpperCase(), 7, bold: true, color: greyTxt),
                  pw.SizedBox(height: 1.5),
                  t(inWords(_n(inv['total'])), 8.8, bold: true),
                ]),
              ),
            ]),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            flex: 2,
            child: pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: lineCol, width: 0.6), borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(children: [
                _tot(t, tr('Sub total'), m(inv['subtotal'])),
                if (_n(inv['discount']) > 0) _tot(t, tr('Discount'), '- ${m(inv['discount'])}'),
                if (_n(inv['discount']) > 0) _tot(t, tr('Taxable value'), m(inv['taxable'])),
                if (intra) ...[_tot(t, 'CGST', m(inv['cgst'])), _tot(t, 'SGST', m(inv['sgst']))] else _tot(t, 'IGST', m(inv['igst'])),
                if (_n(inv['round_off']) != 0) _tot(t, tr('Round off'), m(inv['round_off'])),
                pw.Divider(color: lineCol, thickness: 0.6, height: 8),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [t(tr('GRAND TOTAL'), 9.5, bold: true, color: primary), t('₹ ${m(inv['total'])}', 12, bold: true, color: primary)]),
                if (paid > 0) ...[
                  pw.SizedBox(height: 3),
                  _tot(t, tr('Received'), m(paid)),
                  _tot(t, tr('Balance due'), m(balance), bold: true),
                ],
              ]),
            ),
          ),
        ]),
        pw.SizedBox(height: 10),
        // ── Bank + terms + signature
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            flex: 3,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              if ((s['bankName'] ?? '').toString().isNotEmpty || (s['accountNo'] ?? '').toString().isNotEmpty || (s['upiId'] ?? '').toString().isNotEmpty) ...[
                t(tr('Bank details').toUpperCase(), 7.5, bold: true, color: primary),
                pw.SizedBox(height: 2),
                if ((s['bankName'] ?? '').toString().isNotEmpty) kv(tr('Bank'), '${s['bankName']}'),
                if ((s['accountNo'] ?? '').toString().isNotEmpty) kv(tr('A/c No'), '${s['accountNo']}', bold: true),
                if ((s['ifsc'] ?? '').toString().isNotEmpty) kv('IFSC', '${s['ifsc']}'),
                if ((s['upiId'] ?? '').toString().isNotEmpty) kv('UPI', '${s['upiId']}'),
                pw.SizedBox(height: 6),
              ],
              if (payments.isNotEmpty) ...[
                t(tr('Payments received').toUpperCase(), 7.5, bold: true, color: primary),
                pw.SizedBox(height: 2),
                for (final p in payments) t('${d(p['paid_on'])}  ·  ${(p['mode'] ?? '').toString().toUpperCase()}${(p['ref_no'] ?? '').toString().isEmpty ? '' : ' ${p['ref_no']}'}${(p['bank'] ?? '').toString().isEmpty ? '' : ' (${p['bank']})'}  ·  ₹ ${m(p['amount'])}', 8),
                pw.SizedBox(height: 6),
              ],
              if ((s['terms'] ?? '').toString().isNotEmpty) ...[
                t(tr('Terms & conditions').toUpperCase(), 7.5, bold: true, color: primary),
                pw.SizedBox(height: 2),
                t('${s['terms']}', 7.8, color: greyTxt),
              ],
              if ((inv['remarks'] ?? '').toString().isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 5), child: t('${tr('Remarks')}: ${inv['remarks']}', 8)),
            ]),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            flex: 2,
            child: pw.Container(
              height: 78,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: lineCol, width: 0.6), borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                t('${tr('For')} $sellerName', 8.6, bold: true),
                t(tr('Authorised Signatory'), 8, color: greyTxt),
              ]),
            ),
          ),
        ]),
      ],
    ));
    return doc.save();
  }

  static pw.Widget _tot(pw.Widget Function(String, double, {bool bold, PdfColor? color, pw.TextAlign? align}) t, String k, String v, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [t(k, 8.4, bold: bold), t(v, 8.8, bold: true)]),
      );
}
