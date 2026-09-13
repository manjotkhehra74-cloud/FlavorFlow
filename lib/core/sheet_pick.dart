import 'dart:typed_data';

import 'sheet_pick_native.dart' if (dart.library.html) 'sheet_pick_web.dart' as impl;

/// A spreadsheet file chosen by the user (web only — phones paste instead).
class PickedSheet {
  final String name;
  final Uint8List bytes;
  const PickedSheet(this.name, this.bytes);
  bool get isXlsx => name.toLowerCase().endsWith('.xlsx');
}

/// Whether a native file chooser is available on this platform.
bool get canPickSheet => impl.canPickSheetImpl;

/// Opens the browser's file chooser for .xlsx / .csv / .txt. Resolves null
/// when cancelled or unsupported (Android/iOS builds — use paste there).
Future<PickedSheet?> pickSheet() => impl.pickSheetImpl();
