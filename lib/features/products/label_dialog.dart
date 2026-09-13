import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/item_code.dart';
import '../../ui/widgets.dart';
import 'label_pdf.dart';

/// "Print labels" — QR + barcode label sheet for the listed items.
/// Lets the user pick copies per item and the sheet size, then shares the PDF.
Future<void> showLabelDialog(BuildContext context, List<Map<String, dynamic>> items, {String? title}) {
  return showFastDialog<void>(context, (_) => _LabelDialog(items: items, title: title));
}

class _LabelDialog extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final String? title;
  const _LabelDialog({required this.items, this.title});
  @override
  State<_LabelDialog> createState() => _LabelDialogState();
}

class _LabelDialogState extends State<_LabelDialog> {
  int copies = 1;
  bool big = false;
  bool busy = false;

  List<Map<String, dynamic>> get coded => widget.items.where((it) => ItemCode.of(it).isNotEmpty).toList();

  Future<void> _go() async {
    setState(() => busy = true);
    try {
      final bytes = await LabelPdf.sheet(coded, copies: copies, big: big);
      await Printing.sharePdf(bytes: bytes, filename: 'flavorflow-item-labels-${todayYmd()}.pdf');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    final n = coded.length;
    final perPage = big ? 8 : 24;
    final pages = n == 0 ? 0 : ((n * copies) / perPage).ceil();
    return AlertDialog(
      title: Text(widget.title ?? tr('Print item-code labels')),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            n == 0
                ? tr('No item codes yet — the server assigns FG / RM / PM codes automatically; reopen the list and try again.')
                : '$n ${tr('items with a code')} · ${tr('QR + barcode of the item code, name, pack info and company name on each label')}',
            style: TextStyle(fontSize: 12.5, color: sub),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: copies,
                decoration: InputDecoration(labelText: tr('Copies per item'), isDense: true),
                items: [for (final c in const [1, 2, 3, 4, 6, 8, 12, 24]) DropdownMenuItem(value: c, child: Text('$c'))],
                onChanged: (v) => setState(() => copies = v ?? 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<bool>(
                initialValue: big,
                decoration: InputDecoration(labelText: tr('Label size'), isDense: true),
                items: [
                  DropdownMenuItem(value: false, child: Text('${tr('Small')} · 24 / A4')),
                  DropdownMenuItem(value: true, child: Text('${tr('Big')} · 8 / A4')),
                ],
                onChanged: (v) => setState(() => big = v ?? false),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text('${tr('Sheets')}: $pages × A4 · ${tr('Stick on shelves, bins or cartons; scan with the app to pick the item')}', style: TextStyle(fontSize: 12, color: sub)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton.icon(
          onPressed: busy || n == 0 ? null : _go,
          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
          label: Text(busy ? tr('Building…') : tr('Make PDF')),
        ),
      ],
    );
  }
}
