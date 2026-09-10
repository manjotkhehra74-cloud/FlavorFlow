import 'package:flutter/foundation.dart';
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
  ///   trays    → whether the secondary "tray/roll/strip" unit is meaningful
  ///              (food/bakery trays, dairy cup trays, beverage shells, pharma
  ///              strips, textile rolls). Off → every tray field/column/row
  ///              disappears app-wide (mills, soap, paint, agro, footwear…).
  /// Sections NOT listed here (Products, Inventory, Packing, Raw Material,
  /// Production, Dispatch, Adjustments, Reports, Users, Audit) are the
  /// universal backbone — every industry keeps them.
  static const Map<String, Map<String, bool>> industryFeatures = {
    'food':      {'recipes': true,  'lossPct': true,  'trays': true},
    'dairy':     {'recipes': true,  'lossPct': true,  'trays': true},
    'oil':       {'recipes': true,  'lossPct': true,  'trays': true},
    'bakery':    {'recipes': true,  'lossPct': true,  'trays': true},
    'water':     {'recipes': true,  'lossPct': true,  'trays': true},
    'soap':      {'recipes': true,  'lossPct': true,  'trays': false},
    'cosmetics': {'recipes': true,  'lossPct': true,  'trays': false},
    'paint':     {'recipes': true,  'lossPct': true,  'trays': false},
    'agro':      {'recipes': true,  'lossPct': true,  'trays': false},
    'pharma':    {'recipes': true,  'lossPct': true,  'trays': true},
    'textile':   {'recipes': false, 'lossPct': false, 'trays': true},
    'mill':      {'recipes': false, 'lossPct': false, 'trays': false},
    'footwear':  {'recipes': false, 'lossPct': false, 'trays': false},
    'plastic':   {'recipes': false, 'lossPct': true,  'trays': false},
    'hardware':  {'recipes': false, 'lossPct': false, 'trays': false},
    'general':   {'recipes': true,  'lossPct': true,  'trays': true},
  };

  /// Does the active industry use recipe-based raw material consumption?
  static bool get usesRecipes => industryFeatures[current.industry]?['recipes'] ?? true;

  /// Does the active industry track the monthly Packing Loss % sheet?
  static bool get usesLossPct => industryFeatures[current.industry]?['lossPct'] ?? true;

  /// Does the active industry use the secondary tray/roll/strip unit?
  static bool get usesTrays => industryFeatures[current.industry]?['trays'] ?? true;

  /// Preset row for an industry id (falls back to 'general').
  static List<String> presetFor(String id) =>
      industries.firstWhere((r) => r[0] == id, orElse: () => industries.last);

  /// Normalise whatever the server/website sent into a preset id:
  /// 'mill' → 'mill'; 'Rice / Flour / Feed Mill' → 'mill'; 'Sauces &
  /// Condiments' → 'food'; unknown text → 'general'.
  static String industryIdFor(String raw) {
    final v = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (v.isEmpty) return current.industry;
    for (final r in industries) {
      if (r[0] == v || r[1].toLowerCase() == v) return r[0];
    }
    const keys = <String, List<String>>{
      'mill': ['rice', 'flour', 'atta', 'feed', 'mill', 'grain', 'dal', 'pulse', 'sheller', 'chakki'],
      'dairy': ['dairy', 'milk', 'ghee', 'paneer', 'curd', 'butter', 'cheese', 'ice cream'],
      'oil': ['oil', 'mustard', 'refinery', 'kachi ghani', 'vanaspati'],
      'bakery': ['bakery', 'biscuit', 'snack', 'namkeen', 'confection', 'chips', 'bread', 'cookie', 'sweet'],
      'water': ['water', 'beverage', 'juice', 'soda', 'drink', 'cold drink'],
      'soap': ['soap', 'detergent', 'washing', 'cleaner', 'phenyl'],
      'cosmetics': ['cosmetic', 'personal care', 'shampoo', 'cream', 'hair', 'herbal care'],
      'paint': ['paint', 'lubricant', 'grease', 'varnish', 'coating', 'thinner'],
      'agro': ['agro', 'fertilizer', 'pesticide', 'seed', 'crop', 'insecticide', 'bio'],
      'pharma': ['pharma', 'ayurved', 'medicine', 'tablet', 'syrup', 'capsule', 'drug', 'nutra'],
      'textile': ['textile', 'hosiery', 'garment', 'yarn', 'fabric', 'knit', 'cloth', 'shawl', 'apparel'],
      'footwear': ['footwear', 'shoe', 'chappal', 'slipper', 'sandal', 'boot'],
      'plastic': ['plastic', 'packaging', 'polymer', 'pouch', 'film', 'mould', 'pvc', 'pipe'],
      'hardware': ['utensil', 'hardware', 'steel', 'fastener', 'tool', 'bolt', 'cycle', 'auto part', 'machine', 'forging', 'casting', 'metal'],
      'food': ['food', 'sauce', 'ketchup', 'pickle', 'spice', 'masala', 'condiment', 'jam', 'vinegar', 'noodle', 'tea', 'coffee', 'flavour', 'flavor', 'honey', 'papad'],
    };
    for (final e in keys.entries) {
      for (final k in e.value) {
        if (v.contains(k)) return e.key;
      }
    }
    return 'general';
  }

  static const _dName = 'FlavorFlow Foods Pvt. Ltd.';  static const _dAddress = 'Industrial Area, Jalandhar, Punjab 144004';
  static const _dTax = 'GSTIN 03AAAAA0000A1Z5 · dispatch@flavorflow.in';

  static CompanyProfile? _cached;

  /// Bumped every time the profile is (re)loaded or saved — UI listens to
  /// this to re-apply industry gating and unit labels immediately.
  static final ValueNotifier<int> rev = ValueNotifier<int>(0);

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
          // Server copy wins. The industry may arrive as a preset id ('mill')
          // OR as the free-text label typed on the website registration form
          // ('Rice / Flour / Feed Mill') — normalise it and, when the server
          // never stored unit labels for that industry, use the preset's.
          final ind = industryIdFor((j['industry'] ?? p.industry).toString());
          final row = presetFor(ind);
          final hasUnits = (j['cartonLabel'] ?? '').toString().isNotEmpty;
          p = CompanyProfile(
            name: j['name'].toString(),
            address: (j['address'] ?? '').toString(),
            taxLine: (j['taxLine'] ?? j['tax_line'] ?? '').toString(),
            industry: ind,
            cartonLabel: hasUnits ? j['cartonLabel'].toString() : row[2],
            cartonShort: hasUnits ? (j['cartonShort'] ?? row[3]).toString() : row[3],
            trayLabel: hasUnits ? (j['trayLabel'] ?? row[4]).toString() : row[4],
            pieceLabel: hasUnits ? (j['pieceLabel'] ?? row[5]).toString() : row[5],
          );
          await _persist(prefs, p);
        } else if (j is Map && (j['industry'] ?? '').toString().isNotEmpty) {
          // SaaS tenant: the gateway seeds ONLY the industry (name etc. come
          // later from the admin) — still enough to pick the right pack.
          final ind = industryIdFor(j['industry'].toString());
          final row = presetFor(ind);
          p = CompanyProfile(
            name: p.name, address: p.address, taxLine: p.taxLine,
            industry: ind, cartonLabel: row[2], cartonShort: row[3], trayLabel: row[4], pieceLabel: row[5],
          );
          await _persist(prefs, p);
        }
      } catch (_) {/* server route optional */}
    }
    _cached = p;
    rev.value++;
    return p;
  }

  /// Save locally and (best-effort) to the server.
  static Future<void> save(CompanyProfile p, [ApiClient? api]) async {
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs, p);
    _cached = p;
    rev.value++;
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

  /// Rewrite text written for the default industry (Cartons / CB / Trays /
  /// Bottles) into the ACTIVE industry's unit names. Server-sent report
  /// titles, descriptions, column headers and dashboard labels all pass
  /// through here, so a rice mill reads "Bags / KG" and a textile unit
  /// "Bales / Rolls / Pieces" without any server change.
  static String ize(String text) {
    if (text.isEmpty) return text;
    var out = text;
    if (cb != 'CB') {
      out = out.replaceAll(RegExp(r'\bCB\b'), cb);
    }
    if (carton != 'Cartons') {
      final lc = carton.toLowerCase();
      final sing = _singular(carton);
      out = out
          .replaceAll('Cartons', carton)
          .replaceAll('cartons', lc)
          .replaceAll('Carton', sing)
          .replaceAll('carton', sing.toLowerCase());
    }
    if (tray != 'Trays') {
      final lc = tray.toLowerCase();
      final sing = _singular(tray);
      out = out
          .replaceAll('Trays', tray)
          .replaceAll('trays', lc)
          .replaceAll('Tray', sing)
          .replaceAll('tray', sing.toLowerCase());
    }
    if (piece != 'Bottles') {
      final lc = piece.toLowerCase();
      final sing = _singular(piece);
      out = out
          .replaceAll('Bottles', piece)
          .replaceAll('bottles', lc)
          .replaceAll('Bottle', sing)
          .replaceAll('bottle', sing.toLowerCase());
    }
    // Industries without a secondary unit: drop dangling ", trays" mentions.
    if (!CompanyProfile.usesTrays) {
      out = out.replaceAll(RegExp(', ?' + RegExp.escape(tray.toLowerCase()) + r'\b'), '')
               .replaceAll(RegExp(' ?& ?' + RegExp.escape(tray.toLowerCase()) + r'\b'), '')
               .replaceAll(RegExp(' ?/ ?' + RegExp.escape(tray.toLowerCase()) + r'\b'), '');
    }
    return out;
  }

  /// Server-built tables (reports, dashboard widgets, batch-stock register)
  /// are written for the default industry and always carry a Trays column.
  /// For industries without a secondary unit the column is dropped from the
  /// headers AND every row, and the remaining headers get the active unit
  /// names — so a rice mill sees "BAGS" and never a "TRAYS" column.
  static (List<String>, List<List<dynamic>>) table(List<String> columns, List<List<dynamic>> rows) {
    var cols = columns;
    var data = rows;
    if (!CompanyProfile.usesTrays) {
      final drop = <int>{
        for (var i = 0; i < cols.length; i++)
          if (_isTrayHeader(cols[i])) i,
      };
      if (drop.isNotEmpty) {
        cols = [for (var i = 0; i < cols.length; i++) if (!drop.contains(i)) cols[i]];
        data = [
          for (final r in rows) [for (var i = 0; i < r.length; i++) if (!drop.contains(i)) r[i]],
        ];
      }
    }
    return ([for (final c in cols) ize(c)], data);
  }

  /// Indexes of tray columns removed by [table] — lets callers re-map
  /// column-based options (money columns etc.) after the drop.
  static List<int> trayColumns(List<String> columns) => [
        for (var i = 0; i < columns.length; i++)
          if (!CompanyProfile.usesTrays && _isTrayHeader(columns[i])) i,
      ];

  /// "Trays", "Trays Left", "Tray Wt", "Total Trays", "Bottles / Tray"…
  /// (whole-word match only — a material column like "Tray Caps" is kept).
  static bool _isTrayHeader(String h) {
    final v = h.trim().toLowerCase();
    if (v == 'trays' || v == 'tray') return true;
    if (v.startsWith('trays ') || v.startsWith('trays(') || v.endsWith(' trays') || v.endsWith(' tray')) return true;
    return v.startsWith('tray ') && (v.contains('wt') || v.contains('weight') || v.contains('left') || v.contains('(nos'));
  }

  static String _singular(String plural) {
    if (plural == 'KG' || plural.toUpperCase() == plural) return plural; // KG, CB…
    if (plural.endsWith('ies')) return '${plural.substring(0, plural.length - 3)}y';
    if (plural.endsWith('xes') || plural.endsWith('ses') || plural.endsWith('ches')) return plural.substring(0, plural.length - 2);
    if (plural.endsWith('s')) return plural.substring(0, plural.length - 1);
    return plural;
  }
}
