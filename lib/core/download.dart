import 'dart:typed_data';
import 'package:universal_html/html.dart' as html;

/// Trigger a browser download of raw bytes (the app runs as web).
void downloadBytes(String filename, Uint8List bytes, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  (html.AnchorElement(href: url)..setAttribute('download', filename)).click();
  html.Url.revokeObjectUrl(url);
}
