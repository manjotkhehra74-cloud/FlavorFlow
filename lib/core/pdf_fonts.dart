import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

import 'i18n.dart';

/// Loads the script font for the currently selected app language so PDFs
/// can render Punjabi/Hindi/Gujarati/Marathi/Bengali/Tamil/Telugu text.
/// Used as `fontFallback` — Latin text keeps rendering with Roboto.
class PdfFonts {
  static final Map<String, pw.Font> _cache = {};

  static String? _assetBase() {
    switch (L10n.instance.code) {
      case 'pa':
        return 'noto-gurmukhi';
      case 'hi':
      case 'mr':
        return 'noto-devanagari';
      case 'gu':
        return 'noto-gujarati';
      case 'bn':
        return 'noto-bengali';
      case 'ta':
        return 'noto-tamil';
      case 'te':
        return 'noto-telugu';
      default:
        return null; // English — Roboto already covers it.
    }
  }

  static Future<pw.Font?> _load(String asset) async {
    if (_cache.containsKey(asset)) return _cache[asset];
    try {
      final f = pw.Font.ttf(await rootBundle.load('assets/fonts/$asset.ttf'));
      _cache[asset] = f;
      return f;
    } catch (_) {
      return null;
    }
  }

  /// Fallback fonts for regular text in the current language.
  static Future<List<pw.Font>> regularFallback() async {
    final base = _assetBase();
    if (base == null) return const [];
    final f = await _load('$base-regular');
    return f == null ? const [] : [f];
  }

  /// Fallback fonts for bold text in the current language.
  static Future<List<pw.Font>> boldFallback() async {
    final base = _assetBase();
    if (base == null) return const [];
    final f = await _load('$base-bold') ?? await _load('$base-regular');
    return f == null ? const [] : [f];
  }
}
