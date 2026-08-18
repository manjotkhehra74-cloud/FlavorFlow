import 'package:flutter/material.dart';

/// Web build: ML Kit barcode scanning is Android/iOS-only, so on the website
/// we simply ask the user to type the code (the field stays editable).
Future<String?> scanImpl(BuildContext context, {String title = 'Scan code'}) async {
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content: Text('QR scan sirf phone app vich chalda — web te batch code type kar deo.'),
  ));
  return null;
}
