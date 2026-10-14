import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flavorflow_erp/core/platform_capabilities.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Windows avoids phone-only native plugins', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(PlatformCapabilities.isWindows, isTrue);
    expect(PlatformCapabilities.cameraCapture, isFalse);
    expect(PlatformCapabilities.photoBarcodeScanner, isFalse);
    expect(PlatformCapabilities.mobileNotifications, isFalse);
    expect(PlatformCapabilities.gpsDispatchStamp, isFalse);
  });

  for (final target in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$target retains mobile capabilities', () {
      debugDefaultTargetPlatformOverride = target;
      expect(PlatformCapabilities.isMobile, isTrue);
      expect(PlatformCapabilities.isWindows, isFalse);
      expect(PlatformCapabilities.photoBarcodeScanner, isTrue);
      expect(PlatformCapabilities.mobileNotifications, isTrue);
    });
  }
}
