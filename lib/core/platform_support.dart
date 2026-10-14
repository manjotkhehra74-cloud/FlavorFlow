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
