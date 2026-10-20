/// Canonical domain for FlavorFlow-issued login IDs.
const String _legacyLoginSuffix = '@flavorflow.in';
const String _currentLoginSuffix = '@flavorflow.co.in';

/// Changes only the retired FlavorFlow login suffix. Other identifiers (including
/// customers' own email addresses) are preserved exactly apart from trimming.
String canonicalizeLoginId(String input) {
  final value = input.trim();
  if (value.toLowerCase().endsWith(_legacyLoginSuffix)) {
    return '${value.substring(0, value.length - _legacyLoginSuffix.length)}$_currentLoginSuffix';
  }
  return value;
}
