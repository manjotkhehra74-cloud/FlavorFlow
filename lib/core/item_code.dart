import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'i18n.dart';
import '../ui/scan_page.dart';

/// SAP-style item codes (material numbers) — client helpers.
///
/// The server (tools/ff-saascodes.sh) gives every item a permanent code:
///   FG0000000001  finished goods (products)
///   RM0000000001  raw material
///   PM0000000001  packing material
/// A blank code on create → next number in the series; an admin may type an
/// own code (unique, upper-case, 1-24 of A-Z 0-9 - _ . /). Codes never change
/// on rename / category change. Every list the app reads (`/products`,
/// `/inventory`, `/packing/materials`, `/billing/products`, `/billing/items`)
/// carries `item_code`; an un-patched server simply sends none → the UI hides
/// the code column and pickers fall back to plain names.
class ItemCode {
  ItemCode._();

  static final RegExp _valid = RegExp(r'^[A-Z0-9][A-Z0-9\-_./]{0,23}$');

  /// The code of a server row ('' when the server does not send codes yet).
  static String of(Map<String, dynamic>? row) => (row?['item_code'] ?? row?['code'] ?? '').toString().trim();

  /// True when at least one row carries a code → show the column / prefix.
  static bool anyIn(Iterable<Map<String, dynamic>> rows) => rows.any((r) => of(r).isNotEmpty);

  /// "FG0000000012 · Tomato Ketchup 1kg" (name only when no code).
  /// `compact` → "FG-12 · Tomato Ketchup 1kg" for phone-width dropdowns.
  static String label(Map<String, dynamic> row, {String? name, bool compact = false}) {
    final n = (name ?? row['name'] ?? '').toString();
    final c = of(row);
    return c.isEmpty ? n : '${compact ? short(c) : c} · $n';
  }

  /// Dropdown label: short series code + name.
  static String pick(Map<String, dynamic> row) => label(row, compact: true);

  /// Short form for tight dropdowns: the significant part of a series code
  /// (FG0000000012 → FG-12) or the custom code as typed.
  static String short(String code) {
    final m = RegExp(r'^(FG|RM|PM)0*(\d+)$').firstMatch(code);
    return m == null ? code : '${m.group(1)}-${m.group(2)}';
  }

  /// Normalise what the user typed into a server-valid code ('' when blank).
  static String normalize(String input) => input.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  /// Validation message for a typed code (null = OK / blank = auto).
  static String? validate(String input) {
    final c = normalize(input);
    if (c.isEmpty) return null;
    if (!_valid.hasMatch(c)) return tr('1-24 letters / digits / - _ . / only');
    return null;
  }

  /// Case-insensitive search over name + code (list filters).
  static bool matches(Map<String, dynamic> row, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return (row['name'] ?? '').toString().toLowerCase().contains(q) || of(row).toLowerCase().contains(q) || short(of(row)).toLowerCase().contains(q);
  }

  /// Find the item a scanned payload points at. Accepts the bare code
  /// (`FG0000000012` — what our labels encode), the short form (`FG-12`), a
  /// URL / text that contains the code, or an exact item name.
  static Map<String, dynamic>? resolve(Iterable<Map<String, dynamic>> rows, String payload) {
    final raw = payload.trim();
    if (raw.isEmpty) return null;
    final up = normalize(raw);
    for (final r in rows) {
      final c = of(r);
      if (c.isNotEmpty && (c == up || short(c) == up)) return r;
    }
    // FG-12 / FG12 / fg 12 → FG0000000012
    final m = RegExp(r'^(FG|RM|PM)[-_ ]?0*(\d{1,10})$').firstMatch(up);
    if (m != null) {
      final full = '${m.group(1)}${m.group(2)!.padLeft(10, '0')}';
      for (final r in rows) if (of(r) == full) return r;
    }
    // code embedded in a longer scan (URL, label text)
    for (final r in rows) {
      final c = of(r);
      if (c.length >= 4 && up.contains(c)) return r;
    }
    final lc = raw.toLowerCase();
    for (final r in rows) if ((r['name'] ?? '').toString().toLowerCase() == lc) return r;
    return null;
  }

  /// Camera scan → matching item (or null after a "not found" snackbar).
  /// Phone only — on web the scan page itself explains typing is needed.
  static Future<Map<String, dynamic>?> scanPick(BuildContext context, Iterable<Map<String, dynamic>> rows, {String? title}) async {
    final v = await ScanPage.scan(context, title: title ?? tr('Scan item code'));
    if (v == null) return null;
    final hit = resolve(rows, v);
    if (hit == null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${tr('No item with code')} "${v.length > 40 ? '${v.substring(0, 40)}…' : v}"')));
    }
    return hit;
  }

  /// Input formatters for the code field (upper-case, no spaces, 24 max).
  static List<TextInputFormatter> get formatters => [
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
        LengthLimitingTextInputFormatter(24),
        TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase(), selection: n.selection)),
      ];
}

/// Suffix icon for a picker: opens the camera and returns the matched item.
class ScanPickButton extends StatelessWidget {
  final Iterable<Map<String, dynamic>> rows;
  final void Function(Map<String, dynamic> item) onPicked;
  final String? tooltip;
  const ScanPickButton({super.key, required this.rows, required this.onPicked, this.tooltip});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || rows.isEmpty) return const SizedBox.shrink();
    return IconButton(
      tooltip: tooltip ?? tr('Scan item code'),
      icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
      onPressed: () async {
        final hit = await ItemCode.scanPick(context, rows);
        if (hit != null) onPicked(hit);
      },
    );
  }
}

/// Small monospace chip showing an item code in tables / tiles.
class ItemCodeChip extends StatelessWidget {
  final String code;
  final bool compact;
  const ItemCodeChip(this.code, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (code.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: compact ? 1 : 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(code, style: TextStyle(fontFamily: 'monospace', fontSize: compact ? 10.5 : 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: scheme.onSurfaceVariant)),
    );
  }
}

/// Product / material name cell: bold name with the code underneath.
class ItemNameCell extends StatelessWidget {
  final String name;
  final String code;
  const ItemNameCell({super.key, required this.name, required this.code});

  @override
  Widget build(BuildContext context) {
    if (code.isEmpty) return Text(name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 2),
      Text(code, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
  }
}

/// The "Item code" field used by the product and material forms.
/// Blank = auto (next series number); an existing code is shown and can be
/// replaced by an admin-typed one (must be unique — the server checks).
class ItemCodeField extends StatelessWidget {
  final TextEditingController controller;
  final String seriesPrefix; // FG / RM / PM
  final bool editing;
  const ItemCodeField({super.key, required this.controller, required this.seriesPrefix, required this.editing});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      inputFormatters: ItemCode.formatters,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: tr('Item code'),
        hintText: editing ? '' : '${tr('Auto')} (${seriesPrefix}0000000001…)',
        helperText: editing
            ? tr('Permanent SAP-style code — change only if you use your own coding.')
            : '${tr('Blank = next number in the series')} (${seriesPrefix}0000000001, ${seriesPrefix}0000000002…) · ${tr('or type your own unique code')}',
        helperMaxLines: 2,
        prefixIcon: const Icon(Icons.qr_code_2_rounded, size: 20),
        isDense: true,
      ),
    );
  }
}
