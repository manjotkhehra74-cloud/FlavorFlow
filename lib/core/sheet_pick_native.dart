import 'sheet_pick.dart';

/// Android / iOS / desktop: no file chooser without an extra plugin — the
/// import dialog offers paste-from-Excel/Sheets instead.
const bool canPickSheetImpl = false;

Future<PickedSheet?> pickSheetImpl() async => null;
