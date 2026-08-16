import 'dart:typed_data';

import 'download_native.dart' if (dart.library.html) 'download_web.dart' as impl;

/// Cross-platform "download" of raw bytes.
/// - Web: triggers a browser download.
/// - Android/iOS/desktop: saves the file and opens it with the default app
///   (Excel viewer, PDF reader, …) via open_filex.
void downloadBytes(String filename, Uint8List bytes, String mimeType) {
  impl.downloadBytesImpl(filename, bytes, mimeType);
}
