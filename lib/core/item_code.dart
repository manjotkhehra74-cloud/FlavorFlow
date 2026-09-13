import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'i18n.dart';

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

  /// Input formatters for the code field (upper-case, no spaces, 24 max).
  static List<TextInputFormatter> get formatters => [
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
        LengthLimitingTextInputFormatter(24),
        TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase(), selection: n.selection)),
      ];
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
