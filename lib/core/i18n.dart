import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight in-app translations (English · ਪੰਜਾਬੀ · हिन्दी).
/// Keys are the English strings themselves — unknown strings fall back to
/// English, so nothing ever breaks when a translation is missing.
/// The choice is per-device (SharedPreferences), ideal for a shared phone
/// on the factory floor.
class L10n extends ChangeNotifier {
  L10n._();
  static final L10n instance = L10n._();

  static const languages = [
    ['en', 'English'],
    ['pa', 'ਪੰਜਾਬੀ'],
    ['hi', 'हिन्दी'],
  ];

  String code = 'en';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      code = prefs.getString('lang') ?? 'en';
      notifyListeners();
    } catch (_) {}
  }

  Future<void> set(String c) async {
    code = c;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lang', c);
    } catch (_) {}
  }

  /// Translate an English source string. Fallback: the string itself.
  String t(String en) {
    if (code == 'en') return en;
    return _tr[code]?[en] ?? en;
  }

  static const Map<String, Map<String, String>> _tr = {
    'pa': {
      // navigation modules
      'Dashboard': 'ਡੈਸ਼ਬੋਰਡ',
      'Product Master': 'ਪ੍ਰੋਡਕਟ ਮਾਸਟਰ',
      'Inventory': 'ਇਨਵੈਂਟਰੀ (ਸਟਾਕ)',
      'Packing Material': 'ਪੈਕਿੰਗ ਸਮੱਗਰੀ',
      'Raw Material': 'ਕੱਚਾ ਮਾਲ',
      'Production': 'ਪ੍ਰੋਡਕਸ਼ਨ',
      'Dispatch': 'ਡਿਸਪੈਚ',
      'Stock Adjustments': 'ਸਟਾਕ ਸੋਧ',
      'Approvals': 'ਮਨਜ਼ੂਰੀਆਂ',
      'Reports': 'ਰਿਪੋਰਟਾਂ',
      'User Management': 'ਯੂਜ਼ਰ ਪ੍ਰਬੰਧਨ',
      'Audit Log': 'ਆਡਿਟ ਲਾਗ',
      'Notifications': 'ਸੂਚਨਾਵਾਂ',
      // navigation groups
      'Overview': 'ਝਲਕ',
      'Operations': 'ਕੰਮਕਾਜ',
      'Stock Control': 'ਸਟਾਕ ਕੰਟਰੋਲ',
      'Insights': 'ਜਾਣਕਾਰੀ',
      'Administration': 'ਪ੍ਰਸ਼ਾਸਨ',
      // login
      'Sign in': 'ਲਾਗਇਨ ਕਰੋ',
      'Email': 'ਈਮੇਲ',
      'Password': 'ਪਾਸਵਰਡ',
      'Your workspace adapts to your role.': 'ਤੁਹਾਡਾ ਵਰਕਸਪੇਸ ਤੁਹਾਡੇ ਰੋਲ ਮੁਤਾਬਕ ਢਲਦਾ ਹੈ।',
      // user menu & common actions
      'Sign out': 'ਲਾਗਆਊਟ',
      'Refresh permissions': 'ਪਰਮਿਸ਼ਨਾਂ ਤਾਜ਼ਾ ਕਰੋ',
      'Company details (PDF header)': 'ਕੰਪਨੀ ਵੇਰਵੇ (PDF ਹੈਡਰ)',
      'Language': 'ਭਾਸ਼ਾ',
      'Cancel': 'ਰੱਦ ਕਰੋ',
      'Save': 'ਸੇਵ ਕਰੋ',
      'Delete': 'ਹਟਾਓ',
      'Edit': 'ਸੋਧੋ',
      'Add Product': 'ਪ੍ਰੋਡਕਟ ਜੋੜੋ',
      'Mark all read': 'ਸਭ ਪੜ੍ਹੀਆਂ ਕਰੋ',
      // common page-level labels
      'Export PDF': 'PDF ਡਾਊਨਲੋਡ',
      'Export Excel': 'Excel ਡਾਊਨਲੋਡ',
      'Status': 'ਸਥਿਤੀ',
      'Product': 'ਪ੍ਰੋਡਕਟ',
      'Date': 'ਤਾਰੀਖ',
      'Day': 'ਦਿਨ',
      'Truck': 'ਟਰੱਕ',
      'Destination': 'ਮੰਜ਼ਿਲ',
      'Remarks': 'ਟਿੱਪਣੀ',
      'Batch code': 'ਬੈਚ ਕੋਡ',
      'Dispatch Entry': 'ਡਿਸਪੈਚ ਐਂਟਰੀ',
      'Truck Loading Calculator': 'ਟਰੱਕ ਲੋਡਿੰਗ ਕੈਲਕੁਲੇਟਰ',
      'Dispatch History': 'ਡਿਸਪੈਚ ਇਤਿਹਾਸ',
      'Confirm & Dispatch': 'ਪੱਕਾ ਕਰੋ ਤੇ ਭੇਜੋ',
      'Add product line': 'ਪ੍ਰੋਡਕਟ ਲਾਈਨ ਜੋੜੋ',
      'Sign out of FlavorFlow?': 'FlavorFlow ਤੋਂ ਲਾਗਆਊਟ ਕਰਨਾ ਹੈ?',
      'No data': 'ਕੋਈ ਡਾਟਾ ਨਹੀਂ',
      'No notifications yet': 'ਹਾਲੇ ਕੋਈ ਸੂਚਨਾ ਨਹੀਂ',
      'Loading Summary': 'ਲੋਡਿੰਗ ਸਾਰ',
      'Choose your industry': 'ਆਪਣੀ ਇੰਡਸਟਰੀ ਚੁਣੋ',
      'Gross loaded weight': 'ਕੁੱਲ ਲੋਡ ਭਾਰ',
    },
    'hi': {
      // navigation modules
      'Dashboard': 'डैशबोर्ड',
      'Product Master': 'प्रोडक्ट मास्टर',
      'Inventory': 'इन्वेंटरी (स्टॉक)',
      'Packing Material': 'पैकिंग सामग्री',
      'Raw Material': 'कच्चा माल',
      'Production': 'प्रोडक्शन',
      'Dispatch': 'डिस्पैच',
      'Stock Adjustments': 'स्टॉक समायोजन',
      'Approvals': 'मंज़ूरियाँ',
      'Reports': 'रिपोर्टें',
      'User Management': 'यूज़र प्रबंधन',
      'Audit Log': 'ऑडिट लॉग',
      'Notifications': 'सूचनाएँ',
      // navigation groups
      'Overview': 'झलक',
      'Operations': 'कामकाज',
      'Stock Control': 'स्टॉक नियंत्रण',
      'Insights': 'जानकारी',
      'Administration': 'प्रशासन',
      // login
      'Sign in': 'साइन इन करें',
      'Email': 'ईमेल',
      'Password': 'पासवर्ड',
      'Your workspace adapts to your role.': 'आपका वर्कस्पेस आपकी भूमिका के अनुसार ढलता है।',
      // user menu & common actions
      'Sign out': 'साइन आउट',
      'Refresh permissions': 'अनुमतियाँ ताज़ा करें',
      'Company details (PDF header)': 'कंपनी विवरण (PDF हेडर)',
      'Language': 'भाषा',
      'Cancel': 'रद्द करें',
      'Save': 'सेव करें',
      'Delete': 'हटाएँ',
      'Edit': 'संपादित करें',
      'Add Product': 'प्रोडक्ट जोड़ें',
      'Mark all read': 'सभी पढ़ी हुई करें',
      // common page-level labels
      'Export PDF': 'PDF डाउनलोड',
      'Export Excel': 'Excel डाउनलोड',
      'Status': 'स्थिति',
      'Product': 'प्रोडक्ट',
      'Date': 'तारीख़',
      'Day': 'दिन',
      'Truck': 'ट्रक',
      'Destination': 'गंतव्य',
      'Remarks': 'टिप्पणी',
      'Batch code': 'बैच कोड',
      'Dispatch Entry': 'डिस्पैच एंट्री',
      'Truck Loading Calculator': 'ट्रक लोडिंग कैलकुलेटर',
      'Dispatch History': 'डिस्पैच इतिहास',
      'Confirm & Dispatch': 'पक्का करें और भेजें',
      'Add product line': 'प्रोडक्ट लाइन जोड़ें',
      'Sign out of FlavorFlow?': 'FlavorFlow से साइन आउट करें?',
      'No data': 'कोई डेटा नहीं',
      'No notifications yet': 'अभी कोई सूचना नहीं',
      'Loading Summary': 'लोडिंग सार',
      'Choose your industry': 'अपनी इंडस्ट्री चुनें',
      'Gross loaded weight': 'कुल लोड वज़न',
    },
  };
}

/// Shorthand: `tr('Dashboard')`
String tr(String en) => L10n.instance.t(en);
