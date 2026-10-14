import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';

import '../core/platform_capabilities.dart';

/// QR/barcode scan that works on EVERY phone (incl. Xiaomi/MIUI where live
/// camera-preview scanners fail with genericError):
/// the system camera app takes the photo, Google ML Kit reads the code from
/// it on-device. No preview surface, no camera lifecycle bugs.
Future<String?> scanImpl(BuildContext context, {String title = 'Scan code'}) async {
  if (!PlatformCapabilities.photoBarcodeScanner) {
    // Windows: a USB keyboard-wedge scanner types into this field, or the user
    // can enter/paste a code. Never call Android/iOS ML Kit on desktop.
    return showDialog<String>(
      context: context,
      builder: (context) => _DesktopCodeDialog(title: title),
    );
  }
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

class _DesktopCodeDialog extends StatefulWidget {
  const _DesktopCodeDialog({required this.title});
  final String title;

  @override
  State<_DesktopCodeDialog> createState() => _DesktopCodeDialogState();
}

class _DesktopCodeDialogState extends State<_DesktopCodeDialog> {
  final _code = TextEditingController();

  void _submit() {
    final value = _code.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: _code,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Batch / item code',
              helperText: 'Use a USB scanner, type or paste the code.',
              helperMaxLines: 2,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Use code')),
        ],
      );
}
