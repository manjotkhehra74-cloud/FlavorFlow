import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/permissions.dart';

/// Full-screen QR/barcode scanner — returns the scanned text via
/// Navigator.pop. Used for batch codes on dispatch (no typing).
class ScanPage extends StatefulWidget {
  final String title;
  const ScanPage({super.key, this.title = 'Scan code'});

  /// Open the scanner; resolves to the scanned string or null (cancelled).
  /// Camera permission is verified first — the "unexpected error" screen was
  /// the camera starting without permission on some devices.
  static Future<String?> scan(BuildContext context, {String title = 'Scan code'}) async {
    final ok = await AppPermissions.ensureCamera();
    if (!ok || !context.mounted) return null;
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ScanPage(title: title)),
    );
  }

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _ctl = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _done = false; // pop only once

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && v.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _ctl.toggleTorch(),
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _ctl,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 42),
              const SizedBox(height: 10),
              const Text('Camera nahi khul reha — permission check karo',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13.5)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await AppPermissions.ensureCamera();
                  await _ctl.stop();
                  await _ctl.start();
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ]),
          ),
        ),
        // simple viewfinder frame
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          left: 0, right: 0, bottom: 28,
          child: Text('Place the QR / barcode inside the frame',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5)),
        ),
      ]),
    );
  }
}
