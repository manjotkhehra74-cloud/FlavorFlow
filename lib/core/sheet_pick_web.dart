import 'dart:async';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

import 'sheet_pick.dart';

const bool canPickSheetImpl = true;

/// Web: <input type=file> → bytes. Cancelling the browser dialog fires no
/// change event, so the future is also resolved (null) a moment after window
/// focus returns with no file selected.
Future<PickedSheet?> pickSheetImpl() async {
  final input = html.FileUploadInputElement()..accept = '.csv,.tsv,.txt,.xlsx';
  final done = Completer<PickedSheet?>();
  void finish(PickedSheet? v) {
    if (!done.isCompleted) done.complete(v);
  }

  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      finish(null);
      return;
    }
    final f = files.first;
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      final r = reader.result;
      if (r is Uint8List) {
        finish(PickedSheet(f.name, r));
      } else if (r is ByteBuffer) {
        finish(PickedSheet(f.name, r.asUint8List()));
      } else {
        finish(null);
      }
    });
    reader.onError.listen((_) => finish(null));
    reader.readAsArrayBuffer(f);
  });
  input.click();
  html.window.onFocus.first.then((_) {
    Future.delayed(const Duration(seconds: 3), () {
      final files = input.files;
      if (files == null || files.isEmpty) finish(null);
    });
  });
  return done.future;
}
