import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Editable company identity printed on every exported PDF (packing slips,
/// stock reports, registers). FlavorFlow is a universal manufacturing ERP —
/// the Super Admin sets the company name / address / GSTIN from the app
/// instead of them being hard-coded for one firm.
///
/// The profile is cached locally (SharedPreferences) and — when the server
/// exposes a /settings/company route — synced so every device sees the same
/// details. Missing server route is never an error.
class CompanyProfile {
  String name;
  String address;
  String taxLine; // e.g. "GSTIN 03AAAAA0000A1Z5 · dispatch@company.in"

  CompanyProfile({required this.name, required this.address, required this.taxLine});

  static const _dName = 'FlavorFlow Foods Pvt. Ltd.';
  static const _dAddress = 'Industrial Area, Jalandhar, Punjab 144004';
  static const _dTax = 'GSTIN 03AAAAA0000A1Z5 · dispatch@flavorflow.in';

  static CompanyProfile? _cached;

  /// Last loaded profile (defaults until [load] runs).
  static CompanyProfile get current =>
      _cached ?? CompanyProfile(name: _dName, address: _dAddress, taxLine: _dTax);

  /// Load from local cache, then (best-effort) prefer the server copy.
  static Future<CompanyProfile> load([ApiClient? api]) async {
    final prefs = await SharedPreferences.getInstance();
    var p = CompanyProfile(
      name: prefs.getString('company_name') ?? _dName,
      address: prefs.getString('company_address') ?? _dAddress,
      taxLine: prefs.getString('company_tax') ?? _dTax,
    );
    if (api != null) {
      try {
        final j = await api.get('/settings/company');
        if (j is Map && (j['name'] ?? '').toString().isNotEmpty) {
          p = CompanyProfile(
            name: j['name'].toString(),
            address: (j['address'] ?? '').toString(),
            taxLine: (j['taxLine'] ?? j['tax_line'] ?? '').toString(),
          );
          await _persist(prefs, p);
        }
      } catch (_) {/* server route optional */}
    }
    _cached = p;
    return p;
  }

  /// Save locally and (best-effort) to the server.
  static Future<void> save(CompanyProfile p, [ApiClient? api]) async {
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs, p);
    _cached = p;
    if (api != null) {
      try {
        await api.put('/settings/company', {'name': p.name, 'address': p.address, 'taxLine': p.taxLine});
      } catch (_) {/* server route optional */}
    }
  }

  static Future<void> _persist(SharedPreferences prefs, CompanyProfile p) async {
    await prefs.setString('company_name', p.name);
    await prefs.setString('company_address', p.address);
    await prefs.setString('company_tax', p.taxLine);
  }
}
