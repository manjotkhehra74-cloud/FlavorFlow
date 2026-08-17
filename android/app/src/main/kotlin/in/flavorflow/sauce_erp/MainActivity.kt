package `in`.flavorflow.sauce_erp

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity is required by local_auth (biometric login) —
// with plain FlutterActivity the fingerprint prompt silently fails.
class MainActivity : FlutterFragmentActivity()
