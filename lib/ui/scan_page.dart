import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';

/// QR/barcode scan that works on EVERY phone (incl. Xiaomi/MIUI where live
/// camera-preview scanners fail with genericError):
/// the system camera app takes the photo, Google ML Kit reads the code from
/// it on-device. No preview surface, no camera lifecycle bugs.
class ScanPage {
  /// Opens the phone's camera; resolves to the scanned code or null.
  static Future<String?> scan(BuildContext context, {String title = 'Scan code'}) async {
    try {
      final shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 2000,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (shot == null) return null; // user cancelled

      final scanner = BarcodeScanner(formats: [BarcodeFormat.all]);
      try {
        final barcodes = await scanner.processImage(InputImage.fromFile(File(shot.path)));
        for (final b in barcodes) {
          final v = (b.rawValue ?? '').trim();
          if (v.isNotEmpty) return v;
        }
      } finally {
        await scanner.close();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Code nahi mileya — photo saaf te nede ton khicho (code frame ch poora hove).'),
        ));
      }
      return null;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
      }
      return null;
    }
  }
}
