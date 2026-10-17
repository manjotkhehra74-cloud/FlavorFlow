import 'package:flutter/foundation.dart';

/// True for the camera-capable handheld app targets. Desktop platforms and the
/// browser must keep scanner/photo controls out of the operator workflow.
bool get isPhonePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Desktop Flutter targets that need keyboard/mouse-friendly fallbacks.
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Native Windows gets its desktop ERP workspace regardless of logical window
/// width or Windows display scaling. A width breakpoint alone can incorrectly
/// send a small/high-DPI desktop window through the phone-style shell.
bool get isWindowsPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
