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
      'Native app · Phase 2 Punch': 'ਨੇਟਿਵ ਐਪ · ਫੇਜ਼ 2 ਪੰਚ',
      'Confirm punch in': 'ਪੰਚ ਇਨ ਦੀ ਪੁਸ਼ਟੀ ਕਰੋ',
      'Confirm punch out': 'ਪੰਚ ਆਊਟ ਦੀ ਪੁਸ਼ਟੀ ਕਰੋ',
      'You are %s m from the site — move inside the %s m geofence and try again': 'ਤੁਸੀਂ ਸਾਈਟ ਤੋਂ %s ਮੀਟਰ ਦੂਰ ਹੋ — %s ਮੀਟਰ ਦੇ ਘੇਰੇ ਅੰਦਰ ਆ ਕੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ',
      'Punched out': 'ਪੰਚ ਆਊਟ ਹੋ ਗਿਆ',
      'Punch failed': 'ਪੰਚ ਨਹੀਂ ਹੋਇਆ',
      'Done': 'ਠੀਕ ਹੈ',
      'Shift': 'ਸ਼ਿਫਟ',
      'Today\'s punches': 'ਅੱਜ ਦੇ ਪੰਚ',
      'No punches yet today': 'ਅੱਜ ਹਾਲੇ ਕੋਈ ਪੰਚ ਨਹੀਂ',
      'outside geofence': 'ਘੇਰੇ ਤੋਂ ਬਾਹਰ',
      'Getting your location…': 'ਤੁਹਾਡੀ ਲੋਕੇਸ਼ਨ ਲਈ ਜਾ ਰਹੀ ਹੈ…',
      'Stand in the open for a faster GPS fix': 'ਤੇਜ਼ GPS ਲਈ ਖੁੱਲ੍ਹੇ ਵਿੱਚ ਖੜ੍ਹੋ',
      'Location is switched off': 'ਲੋਕੇਸ਼ਨ ਬੰਦ ਹੈ',
      'Turn on Location (GPS) to punch': 'ਪੰਚ ਕਰਨ ਲਈ ਲੋਕੇਸ਼ਨ (GPS) ਚਾਲੂ ਕਰੋ',
      'Open settings': 'ਸੈਟਿੰਗਜ਼ ਖੋਲ੍ਹੋ',
      'Location permission needed': 'ਲੋਕੇਸ਼ਨ ਦੀ ਇਜਾਜ਼ਤ ਚਾਹੀਦੀ ਹੈ',
      'HRMate checks that you are at the site when you punch': 'HRMate ਪੰਚ ਵੇਲੇ ਦੇਖਦਾ ਹੈ ਕਿ ਤੁਸੀਂ ਸਾਈਟ ਤੇ ਹੋ',
      'Allow location': 'ਲੋਕੇਸ਼ਨ ਦੀ ਇਜਾਜ਼ਤ ਦਿਓ',
      'Location permission blocked': 'ਲੋਕੇਸ਼ਨ ਦੀ ਇਜਾਜ਼ਤ ਬਲਾਕ ਹੈ',
      'Allow Location for HRMate in app settings': 'ਐਪ ਸੈਟਿੰਗਜ਼ ਵਿੱਚ HRMate ਲਈ ਲੋਕੇਸ਼ਨ ਦੀ ਇਜਾਜ਼ਤ ਦਿਓ',
      'Open app settings': 'ਐਪ ਸੈਟਿੰਗਜ਼ ਖੋਲ੍ਹੋ',
      'Could not get a GPS fix': 'GPS ਨਹੀਂ ਮਿਲਿਆ',
      'Move near a window or outside and retry': 'ਖਿੜਕੀ ਕੋਲ ਜਾਂ ਬਾਹਰ ਜਾ ਕੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ',
      'Location captured': 'ਲੋਕੇਸ਼ਨ ਮਿਲ ਗਈ',
      'Inside the site geofence': 'ਸਾਈਟ ਦੇ ਘੇਰੇ ਅੰਦਰ',
      'from site': 'ਸਾਈਟ ਤੋਂ',
      'Outside the site geofence': 'ਸਾਈਟ ਦੇ ਘੇਰੇ ਤੋਂ ਬਾਹਰ',
      'allowed': 'ਮਨਜ਼ੂਰ',
      'Refresh location': 'ਲੋਕੇਸ਼ਨ ਤਾਜ਼ਾ ਕਰੋ',
      'Mock location detected': 'ਨਕਲੀ ਲੋਕੇਸ਼ਨ ਮਿਲੀ',
      'Turn off fake-GPS apps to punch': 'ਪੰਚ ਕਰਨ ਲਈ ਨਕਲੀ-GPS ਐਪ ਬੰਦ ਕਰੋ',
      'Location not checked yet': 'ਲੋਕੇਸ਼ਨ ਹਾਲੇ ਚੈੱਕ ਨਹੀਂ ਹੋਈ',
      'Check location': 'ਲੋਕੇਸ਼ਨ ਚੈੱਕ ਕਰੋ',
      'Holiday — no punch needed': 'ਛੁੱਟੀ — ਪੰਚ ਦੀ ਲੋੜ ਨਹੀਂ',
      'Waiting for location': 'ਲੋਕੇਸ਼ਨ ਦੀ ਉਡੀਕ',
      'Confirm with your fingerprint': 'ਆਪਣੇ ਫਿੰਗਰਪ੍ਰਿੰਟ ਨਾਲ ਪੁਸ਼ਟੀ ਕਰੋ',
      'You can try, but the server may reject punches outside the geofence': 'ਕੋਸ਼ਿਸ਼ ਕਰ ਸਕਦੇ ਹੋ, ਪਰ ਘੇਰੇ ਤੋਂ ਬਾਹਰ ਦੇ ਪੰਚ ਸਰਵਰ ਰੱਦ ਕਰ ਸਕਦਾ ਹੈ',
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
      'Native app · Phase 2 Punch': 'नेटिव ऐप · फेज़ 2 पंच',
      'Confirm punch in': 'पंच इन की पुष्टि करें',
      'Confirm punch out': 'पंच आउट की पुष्टि करें',
      'You are %s m from the site — move inside the %s m geofence and try again': 'आप साइट से %s मीटर दूर हैं — %s मीटर के दायरे में आकर फिर कोशिश करें',
      'Punched out': 'पंच आउट हो गया',
      'Punch failed': 'पंच नहीं हुआ',
      'Done': 'ठीक है',
      'Shift': 'शिफ्ट',
      'Today\'s punches': 'आज के पंच',
      'No punches yet today': 'आज अभी कोई पंच नहीं',
      'outside geofence': 'दायरे से बाहर',
      'Getting your location…': 'आपकी लोकेशन ली जा रही है…',
      'Stand in the open for a faster GPS fix': 'तेज़ GPS के लिए खुले में खड़े हों',
      'Location is switched off': 'लोकेशन बंद है',
      'Turn on Location (GPS) to punch': 'पंच करने के लिए लोकेशन (GPS) चालू करें',
      'Open settings': 'सेटिंग्स खोलें',
      'Location permission needed': 'लोकेशन की अनुमति चाहिए',
      'HRMate checks that you are at the site when you punch': 'HRMate पंच के समय देखता है कि आप साइट पर हैं',
      'Allow location': 'लोकेशन की अनुमति दें',
      'Location permission blocked': 'लोकेशन की अनुमति ब्लॉक है',
      'Allow Location for HRMate in app settings': 'ऐप सेटिंग्स में HRMate के लिए लोकेशन की अनुमति दें',
      'Open app settings': 'ऐप सेटिंग्स खोलें',
      'Could not get a GPS fix': 'GPS नहीं मिला',
      'Move near a window or outside and retry': 'खिड़की के पास या बाहर जाकर फिर कोशिश करें',
      'Location captured': 'लोकेशन मिल गई',
      'Inside the site geofence': 'साइट के दायरे के अंदर',
      'from site': 'साइट से',
      'Outside the site geofence': 'साइट के दायरे से बाहर',
      'allowed': 'अनुमत',
      'Refresh location': 'लोकेशन ताज़ा करें',
      'Mock location detected': 'नकली लोकेशन मिली',
      'Turn off fake-GPS apps to punch': 'पंच करने के लिए नकली-GPS ऐप बंद करें',
      'Location not checked yet': 'लोकेशन अभी चेक नहीं हुई',
      'Check location': 'लोकेशन चेक करें',
      'Holiday — no punch needed': 'अवकाश — पंच की ज़रूरत नहीं',
      'Waiting for location': 'लोकेशन की प्रतीक्षा',
      'Confirm with your fingerprint': 'अपने फिंगरप्रिंट से पुष्टि करें',
      'You can try, but the server may reject punches outside the geofence': 'कोशिश कर सकते हैं, पर दायरे से बाहर के पंच सर्वर अस्वीकार कर सकता है',
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
