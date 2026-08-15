import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Native (Android/iOS/desktop) implementation: save the bytes to the app's
/// documents directory and open the file with the platform's default viewer
/// (Excel/PDF apps on Android via open_filex).
Future<void> downloadBytesImpl(String filename, Uint8List bytes, String mimeType) async {
  Directory dir;
  try {
    // Prefer the public Downloads dir when available (desktop platforms).
    dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  } catch (_) {
    dir = await getApplicationDocumentsDirectory();
  }
  final file = File('${dir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  await OpenFilex.open(file.path, type: mimeType);
}
