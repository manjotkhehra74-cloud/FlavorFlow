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

  // ---- Indic visual reordering for the naive PDF renderer -----------------
  // The pdf package draws codepoints in logical order without complex text
  // shaping, so pre-base matras (ਿ ि ি ে ெ ...) appear AFTER their consonant
  // (e.g. ਰਿਪੋਰਟ → ਰਪਿਰਟ). shape() moves them to visual position and splits
  // two-part vowels so the output reads correctly.

  static const _prebase = {
    0x0A3F, // Gurmukhi ਿ
    0x093F, // Devanagari ि
    0x09BF, 0x09C7, 0x09C8, // Bengali ি ে ৈ
    0x0ABF, // Gujarati િ
    0x0BC6, 0x0BC7, 0x0BC8, // Tamil ெ ே ை
  };
  static const _halant = {0x0A4D, 0x094D, 0x09CD, 0x0ACD, 0x0BCD};
  static const _nukta = {0x0A3C, 0x093C, 0x09BC, 0x0ABC};
  static const _twoPart = {
    0x09CB: [0x09C7, 0x09BE], // Bengali ো
    0x09CC: [0x09C7, 0x09D7], // Bengali ৌ
    0x0BCA: [0x0BC6, 0x0BBE], // Tamil ொ
    0x0BCB: [0x0BC7, 0x0BBE], // Tamil ோ
    0x0BCC: [0x0BC6, 0x0BD7], // Tamil ௌ
  };

  /// Reorders Indic pre-base matras into visual order for PDF rendering.
  /// Latin/other text passes through unchanged.
  static String shape(String s) {
    var indic = false;
    for (final r in s.runes) {
      if (r >= 0x0900 && r <= 0x0DFF) {
        indic = true;
        break;
      }
    }
    if (!indic) return s;
    final cs = <int>[];
    for (final r in s.runes) {
      final t = _twoPart[r];
      if (t != null) {
        cs.addAll(t);
      } else {
        cs.add(r);
      }
    }
    for (var i = 0; i < cs.length; i++) {
      if (_prebase.contains(cs[i]) && i > 0) {
        var j = i - 1;
        if (j > 0 && _nukta.contains(cs[j])) j--;
        while (j - 1 >= 0 && _halant.contains(cs[j - 1])) {
          j -= 2;
          if (j > 0 && _nukta.contains(cs[j])) j--;
        }
        if (j < 0) j = 0;
        final m = cs.removeAt(i);
        cs.insert(j, m);
      }
    }
    return String.fromCharCodes(cs);
  }
}
