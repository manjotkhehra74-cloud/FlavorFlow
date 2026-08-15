import 'dart:typed_data';
import 'package:universal_html/html.dart' as html;

/// Web implementation: trigger a browser download of raw bytes.
Future<void> downloadBytesImpl(String filename, Uint8List bytes, String mimeType) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  (html.AnchorElement(href: url)..setAttribute('download', filename)).click();
  html.Url.revokeObjectUrl(url);
}
