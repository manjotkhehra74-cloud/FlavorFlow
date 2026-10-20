import 'package:flutter/material.dart';

import 'scan_page_native.dart' if (dart.library.html) 'scan_page_web.dart' as impl;

/// Cross-platform QR/barcode scan entry point.
/// - Android/iOS: system camera photo + Google ML Kit (works on Xiaomi/MIUI).
/// - Web/desktop: manual entry is used instead; desktop USB scanners act as a keyboard.
class ScanPage {
  /// Opens the scanner; resolves to the scanned code or null.
  static Future<String?> scan(BuildContext context, {String title = 'Scan code'}) =>
      impl.scanImpl(context, title: title);
}
