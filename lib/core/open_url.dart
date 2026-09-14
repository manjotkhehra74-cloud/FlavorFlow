import 'package:url_launcher/url_launcher.dart';

/// Open an external https link (HRMate, website) in the browser / matching
/// app — on web this opens a new tab. Returns false when nothing could handle
/// it (caller shows the address instead). Never throws.
Future<bool> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  } catch (_) {
    return false;
  }
}
