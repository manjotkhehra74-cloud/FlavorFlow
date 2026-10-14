import 'package:flutter/foundation.dart';

/// Keep mobile-only plugins out of desktop execution paths. Shared ERP screens,
/// tenant login, reports and server permissions continue to work on all targets.
class PlatformCapabilities {
  static bool get isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get photoBarcodeScanner => isMobile;
  static bool get mobileNotifications => isMobile;
  static bool get cameraCapture => isMobile;
  static bool get gpsDispatchStamp => isMobile;
}
