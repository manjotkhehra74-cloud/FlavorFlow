import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Editable company identity printed on every exported PDF (packing slips,
/// stock reports, registers) + configurable industry unit labels that make
/// FlavorFlow universal: a textile unit calls a "Carton" a "Bale", a pharma
/// unit calls "Bottles" "Units", etc. The Super Admin sets everything from
/// the app instead of it being hard-coded for one firm.
///
/// The profile is cached locally (SharedPreferences) and — when the server
/// exposes a /settings/company route — synced so every device sees the same
/// details. Missing server route is never an error.
class CompanyProfile {
  String name;
  String address;
  String taxLine; // e.g. "GSTIN 03AAAAA0000A1Z5 · dispatch@company.in"
  String industry; // key of one of [industries]
  String cartonLabel; // e.g. Carton / Bale / Box / Bag
  String cartonShort; // e.g. CB / Bale / Box
  String trayLabel; // e.g. Tray / Roll / Strip
  String pieceLabel; // e.g. Bottles / Meters / Units / Pieces

  CompanyProfile({
    required this.name,
    required this.address,
    required this.taxLine,
    this.industry = 'food',
    this.cartonLabel = 'Cartons',
    this.cartonShort = 'CB',
    this.trayLabel = 'Trays',
    this.pieceLabel = 'Bottles',
  });

  /// Industry presets: id, label, carton/short/tray/piece unit names.
  /// Choosing one pre-fills the unit labels (still editable afterwards).
  static const industries = [
    ['food', 'Food & Beverage', 'Cartons', 'CB', 'Trays', 'Bottles'],
    ['dairy', 'Dairy', 'Crates', 'Crate', 'Trays', 'Packets'],
    ['oil', 'Edible Oil', 'Cartons', 'CB', 'Trays', 'Tins'],
    ['bakery', 'Bakery & Snacks', 'Cartons', 'CB', 'Trays', 'Packets'],
    ['water', 'Beverages / Water', 'Cases', 'Case', 'Shells', 'Bottles'],
    ['soap', 'Soap & Detergent', 'Cartons', 'CB', 'Trays', 'Bars'],
    ['cosmetics', 'Cosmetics & Personal Care', 'Cartons', 'CB', 'Trays', 'Units'],
    ['paint', 'Paint & Lubricants', 'Cartons', 'CB', 'Trays', 'Tins'],
    ['agro', 'Agro-chemicals & Fertilizer', 'Cartons', 'CB', 'Trays', 'Bottles'],
    ['pharma', 'Pharma / Ayurvedic', 'Boxes', 'Box', 'Strips', 'Units'],
    ['textile', 'Textile / Hosiery', 'Bales', 'Bale', 'Rolls', 'Pieces'],
    ['mill', 'Rice / Flour / Feed Mill', 'Bags', 'Bag', 'Stacks', 'KG'],
    ['footwear', 'Footwear', 'Cartons', 'CB', 'Racks', 'Pairs'],
    ['plastic', 'Plastic & Packaging', 'Cartons', 'CB', 'Trays', 'Pieces'],
    ['hardware', 'Utensils & Hardware', 'Cartons', 'CB', 'Trays', 'Pieces'],
    ['general', 'General Manufacturing', 'Cartons', 'CB', 'Trays', 'Pieces'],
  ];

  /// Per-industry FEATURE PROFILES (researched from how real ERPs are built
  /// for each industry — BatchMaster/Datatex/eresource/ACG/Focus etc.):
  ///   recipes  → process/formula industries (recipe-based raw consumption:
  ///              food, dairy, oil, bakery, beverages, soap, cosmetics, paint,
  ///              agro-chem, pharma). Discrete industries (textile, footwear,
  ///              plastic moulding, hardware, mills) mostly consume per-unit
  ///              BOM, not per-batch recipes.
  ///   lossPct  → monthly packing-material Loss % sheet (bottling/packing
  ///              lines where labels/caps/sleeves wastage matters).
  ///   trays    → whether the secondary "tray/roll/strip" unit is meaningful.
  /// Sections NOT listed here (Products, Inventory, Packing, Raw Material,
  /// Production, Dispatch, Adjustments, Reports, Users, Audit) are the
  /// universal backbone — every industry keeps them.
  static const Map<String, Map<String, bool>> industryFeatures = {
    'food':      {'recipes': true,  'lossPct': true,  'trays': true},
    'dairy':     {'recipes': true,  'lossPct': true,  'trays': true},
    'oil':       {'recipes': true,  'lossPct': true,  'trays': true},
    'bakery':    {'recipes': true,  'lossPct': true,  'trays': true},
    'water':     {'recipes': true,  'lossPct': true,  'trays': true},
    'soap':      {'recipes': true,  'lossPct': true,  'trays': true},
    'cosmetics': {'recipes': true,  'lossPct': true,  'trays': true},
    'paint':     {'recipes': true,  'lossPct': true,  'trays': true},
    'agro':      {'recipes': true,  'lossPct': true,  'trays': true},
    'pharma':    {'recipes': true,  'lossPct': true,  'trays': true},
    'textile':   {'recipes': false, 'lossPct': false, 'trays': true},
    'mill':      {'recipes': false, 'lossPct': false, 'trays': false},
    'footwear':  {'recipes': false, 'lossPct': false, 'trays': true},
    'plastic':   {'recipes': false, 'lossPct': true,  'trays': true},
    'hardware':  {'recipes': false, 'lossPct': false, 'trays': true},
    'general':   {'recipes': true,  'lossPct': true,  'trays': true},
  };

  /// Does the active industry use recipe-based raw material consumption?
  static bool get usesRecipes => industryFeatures[current.industry]?['recipes'] ?? true;

  /// Does the active industry track the monthly Packing Loss % sheet?
  static bool get usesLossPct => industryFeatures[current.industry]?['lossPct'] ?? true;

  /// Does the active industry use the secondary tray/roll/strip unit?
  static bool get usesTrays => industryFeatures[current.industry]?['trays'] ?? true;

  static const _dName = 'FlavorFlow Foods Pvt. Ltd.';  static const _dAddress = 'Industrial Area, Jalandhar, Punjab 144004';
  static const _dTax = 'GSTIN 03AAAAA0000A1Z5 · dispatch@flavorflow.in';

  static CompanyProfile? _cached;

  /// One-time first-run setup (language + industry) completed on this device?
  static Future<bool> setupDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('setup_done') ?? false;
    } catch (_) {
      return true; // never block the app if prefs fail
    }
  }

  static Future<void> markSetupDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('setup_done', true);
    } catch (_) {}
  }

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
      industry: prefs.getString('company_industry') ?? 'food',
      cartonLabel: prefs.getString('unit_carton') ?? 'Cartons',
      cartonShort: prefs.getString('unit_carton_short') ?? 'CB',
      trayLabel: prefs.getString('unit_tray') ?? 'Trays',
      pieceLabel: prefs.getString('unit_piece') ?? 'Bottles',
    );
    if (api != null) {
      try {
        final j = await api.get('/settings/company');
        if (j is Map && (j['name'] ?? '').toString().isNotEmpty) {
          p = CompanyProfile(
            name: j['name'].toString(),
            address: (j['address'] ?? '').toString(),
            taxLine: (j['taxLine'] ?? j['tax_line'] ?? '').toString(),
            industry: (j['industry'] ?? p.industry).toString(),
            cartonLabel: (j['cartonLabel'] ?? p.cartonLabel).toString(),
            cartonShort: (j['cartonShort'] ?? p.cartonShort).toString(),
            trayLabel: (j['trayLabel'] ?? p.trayLabel).toString(),
            pieceLabel: (j['pieceLabel'] ?? p.pieceLabel).toString(),
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
        await api.put('/settings/company', {
          'name': p.name,
          'address': p.address,
          'taxLine': p.taxLine,
          'industry': p.industry,
          'cartonLabel': p.cartonLabel,
          'cartonShort': p.cartonShort,
          'trayLabel': p.trayLabel,
          'pieceLabel': p.pieceLabel,
        });
      } catch (_) {/* server route optional */}
    }
  }

  static Future<void> _persist(SharedPreferences prefs, CompanyProfile p) async {
    await prefs.setString('company_name', p.name);
    await prefs.setString('company_address', p.address);
    await prefs.setString('company_tax', p.taxLine);
    await prefs.setString('company_industry', p.industry);
    await prefs.setString('unit_carton', p.cartonLabel);
    await prefs.setString('unit_carton_short', p.cartonShort);
    await prefs.setString('unit_tray', p.trayLabel);
    await prefs.setString('unit_piece', p.pieceLabel);
  }
}

/// Short helpers for the configurable unit labels — use everywhere instead of
/// hard-coded "Cartons"/"CB"/"Trays"/"Bottles".
class U {
  static String get carton => CompanyProfile.current.cartonLabel; // Cartons / Bales…
  static String get cb => CompanyProfile.current.cartonShort; // CB / Bale…
  static String get tray => CompanyProfile.current.trayLabel; // Trays / Rolls…
  static String get piece => CompanyProfile.current.pieceLabel; // Bottles / Pieces…
  /// lowercase singular-ish tray label for helper texts, e.g. "6/tray"
  static String get trayLc => tray.toLowerCase();
}
