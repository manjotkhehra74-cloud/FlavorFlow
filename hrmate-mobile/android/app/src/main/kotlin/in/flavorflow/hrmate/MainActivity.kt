package `in`.flavorflow.hrmate

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity is required by local_auth (fingerprint prompt) —
// with plain FlutterActivity the biometric prompt silently fails.
class MainActivity : FlutterFragmentActivity()
