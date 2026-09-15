import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-app translations (English · ਪੰਜਾਬੀ · हिन्दी) — same approach as the
/// FlavorFlow app: keys are the English strings, unknown keys fall back to
/// English, so a missing translation never breaks a screen.
/// Add the en/pa/hi entries for every new user-visible string in the SAME
/// commit as the screen (ARCHITECTURE.md §6).
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

  String t(String en) => _dict[code]?[en] ?? en;

  static const Map<String, Map<String, String>> _dict = {
    'pa': {
      'HRMate': 'HRMate',
      'Workforce Portal': 'ਵਰਕਫੋਰਸ ਪੋਰਟਲ',
      'Employee code or email': 'ਕਰਮਚਾਰੀ ਕੋਡ ਜਾਂ ਈਮੇਲ',
      'Password': 'ਪਾਸਵਰਡ',
      'Sign in': 'ਸਾਈਨ ਇਨ',
      'Unlock with fingerprint': 'ਫਿੰਗਰਪ੍ਰਿੰਟ ਨਾਲ ਖੋਲ੍ਹੋ',
      'Enter your employee code or email': 'ਆਪਣਾ ਕਰਮਚਾਰੀ ਕੋਡ ਜਾਂ ਈਮੇਲ ਭਰੋ',
      'Enter your password': 'ਆਪਣਾ ਪਾਸਵਰਡ ਭਰੋ',
      'Language': 'ਭਾਸ਼ਾ',
      'Home': 'ਹੋਮ',
      'Leaves': 'ਛੁੱਟੀਆਂ',
      'Punch': 'ਪੰਚ',
      'Team': 'ਟੀਮ',
      'More': 'ਹੋਰ',
      'Good morning': 'ਸ਼ੁਭ ਸਵੇਰ',
      'Good afternoon': 'ਸ਼ੁਭ ਦੁਪਹਿਰ',
      'Good evening': 'ਸ਼ੁਭ ਸ਼ਾਮ',
      'Coming in Phase %s': 'ਫੇਜ਼ %s ਵਿੱਚ ਆ ਰਿਹਾ ਹੈ',
      'Retry': 'ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼',
      'Something went wrong': 'ਕੁਝ ਗਲਤ ਹੋ ਗਿਆ',
      'Nothing here yet': 'ਹਾਲੇ ਇੱਥੇ ਕੁਝ ਨਹੀਂ',
      'Loading…': 'ਲੋਡ ਹੋ ਰਿਹਾ ਹੈ…',
      'Offline · last updated %s': 'ਆਫਲਾਈਨ · ਆਖਰੀ ਅੱਪਡੇਟ %s',
      'Sign out': 'ਸਾਈਨ ਆਊਟ',
      'Sign out of HRMate on this phone?': 'ਇਸ ਫੋਨ ਤੇ HRMate ਤੋਂ ਸਾਈਨ ਆਊਟ ਕਰਨਾ ਹੈ?',
      'Cancel': 'ਰੱਦ ਕਰੋ',
      'Enable fingerprint unlock': 'ਫਿੰਗਰਪ੍ਰਿੰਟ ਅਨਲੌਕ ਚਾਲੂ ਕਰੋ',
      'Next time, open HRMate with your fingerprint instead of typing the password.': 'ਅਗਲੀ ਵਾਰ ਪਾਸਵਰਡ ਦੀ ਥਾਂ ਫਿੰਗਰਪ੍ਰਿੰਟ ਨਾਲ HRMate ਖੋਲ੍ਹੋ।',
      'Not now': 'ਹੁਣੇ ਨਹੀਂ',
      'Enable': 'ਚਾਲੂ ਕਰੋ',
      'Verify to enable fingerprint unlock': 'ਫਿੰਗਰਪ੍ਰਿੰਟ ਅਨਲੌਕ ਚਾਲੂ ਕਰਨ ਲਈ ਪੁਸ਼ਟੀ ਕਰੋ',
      'Unlock HRMate': 'HRMate ਖੋਲ੍ਹੋ',
      'Version': 'ਵਰਜ਼ਨ',
      'Signed in as': 'ਸਾਈਨ ਇਨ ਹੈ',
      'Fingerprint unlock': 'ਫਿੰਗਰਪ੍ਰਿੰਟ ਅਨਲੌਕ',
      'About': 'ਬਾਰੇ',
      'Native app · Phase 1 Home': 'ਨੇਟਿਵ ਐਪ · ਫੇਜ਼ 1 ਹੋਮ',
      'Punch in': 'ਪੰਚ ਇਨ',
      'Punch out': 'ਪੰਚ ਆਊਟ',
      'Leave balance': 'ਛੁੱਟੀ ਬੈਲੇਂਸ',
      '%s pending': '%s ਬਕਾਇਆ',
      'Worked today': 'ਅੱਜ ਕੰਮ',
      'Announcements': 'ਸੂਚਨਾਵਾਂ',
      'No announcements right now': 'ਹਾਲੇ ਕੋਈ ਸੂਚਨਾ ਨਹੀਂ',
      'Today': 'ਅੱਜ',
      'Holiday': 'ਛੁੱਟੀ ਦਾ ਦਿਨ',
      'On leave': 'ਛੁੱਟੀ ਤੇ',
      'Enjoy your day off': 'ਆਪਣੀ ਛੁੱਟੀ ਦਾ ਆਨੰਦ ਲਓ',
      'Punched in': 'ਪੰਚ ਇਨ ਹੋ ਗਿਆ',
      'Since': 'ਤੋਂ',
      'Day complete': 'ਦਿਨ ਪੂਰਾ',
      'Not punched in': 'ਪੰਚ ਇਨ ਨਹੀਂ',
      'Tap Punch to start your day': 'ਦਿਨ ਸ਼ੁਰੂ ਕਰਨ ਲਈ ਪੰਚ ਦਬਾਓ',
      'First in': 'ਪਹਿਲਾ ਇਨ',
      'Last out': 'ਆਖਰੀ ਆਊਟ',
      'Worked': 'ਕੰਮ ਕੀਤਾ',
    },
    'hi': {
      'HRMate': 'HRMate',
      'Workforce Portal': 'वर्कफोर्स पोर्टल',
      'Employee code or email': 'कर्मचारी कोड या ईमेल',
      'Password': 'पासवर्ड',
      'Sign in': 'साइन इन',
      'Unlock with fingerprint': 'फिंगरप्रिंट से खोलें',
      'Enter your employee code or email': 'अपना कर्मचारी कोड या ईमेल भरें',
      'Enter your password': 'अपना पासवर्ड भरें',
      'Language': 'भाषा',
      'Home': 'होम',
      'Leaves': 'छुट्टियाँ',
      'Punch': 'पंच',
      'Team': 'टीम',
      'More': 'और',
      'Good morning': 'सुप्रभात',
      'Good afternoon': 'नमस्कार',
      'Good evening': 'शुभ संध्या',
      'Coming in Phase %s': 'फेज़ %s में आ रहा है',
      'Retry': 'फिर कोशिश करें',
      'Something went wrong': 'कुछ गलत हो गया',
      'Nothing here yet': 'अभी यहाँ कुछ नहीं',
      'Loading…': 'लोड हो रहा है…',
      'Offline · last updated %s': 'ऑफलाइन · आखिरी अपडेट %s',
      'Sign out': 'साइन आउट',
      'Sign out of HRMate on this phone?': 'इस फोन पर HRMate से साइन आउट करें?',
      'Cancel': 'रद्द करें',
      'Enable fingerprint unlock': 'फिंगरप्रिंट अनलॉक चालू करें',
      'Next time, open HRMate with your fingerprint instead of typing the password.': 'अगली बार पासवर्ड की जगह फिंगरप्रिंट से HRMate खोलें।',
      'Not now': 'अभी नहीं',
      'Enable': 'चालू करें',
      'Verify to enable fingerprint unlock': 'फिंगरप्रिंट अनलॉक चालू करने के लिए पुष्टि करें',
      'Unlock HRMate': 'HRMate खोलें',
      'Version': 'वर्ज़न',
      'Signed in as': 'साइन इन है',
      'Fingerprint unlock': 'फिंगरप्रिंट अनलॉक',
      'About': 'के बारे में',
      'Native app · Phase 1 Home': 'नेटिव ऐप · फेज़ 1 होम',
      'Punch in': 'पंच इन',
      'Punch out': 'पंच आउट',
      'Leave balance': 'छुट्टी बैलेंस',
      '%s pending': '%s लंबित',
      'Worked today': 'आज काम',
      'Announcements': 'सूचनाएँ',
      'No announcements right now': 'अभी कोई सूचना नहीं',
      'Today': 'आज',
      'Holiday': 'अवकाश',
      'On leave': 'छुट्टी पर',
      'Enjoy your day off': 'अपनी छुट्टी का आनंद लें',
      'Punched in': 'पंच इन हो गया',
      'Since': 'से',
      'Day complete': 'दिन पूरा',
      'Not punched in': 'पंच इन नहीं',
      'Tap Punch to start your day': 'दिन शुरू करने के लिए पंच दबाएँ',
      'First in': 'पहला इन',
      'Last out': 'आखिरी आउट',
      'Worked': 'काम किया',
    },
  };
}

/// Shorthand used by every screen: `Text(tr('Sign in'))`.
String tr(String en) => L10n.instance.t(en);

/// `tr('Coming in Phase %s').arg('1')`.
extension TrArgs on String {
  String arg(Object v) => replaceFirst('%s', v.toString());
}
