import 'company.dart';

/// INDUSTRY PACKS — what each industry actually stocks, packs, consumes and
/// ships. Every screen reads from here instead of hard-coding the sauce
/// factory's world (bottles / caps / trays / Neemrana).
///
/// Sources (how real units in each industry run their stores):
///   Rice / flour / feed mills — PP-woven & BOPP-laminated bags (5/10/25/
///     50 kg), jute bags, LDPE liners, stitching thread, labels; raw = paddy,
///     wheat, maize, soya DOC; by-products = bran, husk, broken rice.
///   Dairy — pouch film (LDPE/multi-layer), crates, cups & lids, ghee tins/
///     jars; raw = raw milk, cream, SMP, sugar, culture, salt.
///   Edible oil — tins (15 kg), PET bottles, jars, pouches, cartons; raw =
///     seeds (mustard/sunflower/soya), crude oil, bleaching earth, hexane.
///   Bakery & snacks — laminated pouches, BOPP film, trays, cartons, tin
///     boxes; raw = maida/atta, sugar, fat, yeast, salt, flavours.
///   Beverages / water — PET preforms, caps, shrink film, labels, crates;
///     raw = sugar, concentrate, CO2, citric acid, treated water.
///   Soap & detergent — wrappers, laminated pouches, cartons, buckets; raw =
///     noodles/fatty acid, LABSA, soda ash, STPP, perfume, colour, silicate.
///   Cosmetics — bottles, jars, tubes, pumps, mono-cartons, shrink sleeves;
///     raw = base oils, emulsifiers, actives, fragrance, preservatives.
///   Paint & lubricants — tins, drums, buckets, pails, caps, labels; raw =
///     base oil, additives, resin, pigment, solvent.
///   Agro-chem & fertilizer — HDPE bottles, pouches, jerry cans, bags; raw =
///     technical grade actives, urea/DAP/MOP, emulsifiers, fillers.
///   Pharma / Ayurvedic — blister foil, strips, bottles, mono-cartons,
///     shippers, leaflets; raw = APIs/herbs, excipients, capsules, sugar.
///   Textile / hosiery — poly bags, hangers, tags, cartons, bales; raw =
///     yarn, fabric, dyes, chemicals, threads, elastics, buttons.
///   Footwear — shoe boxes, poly bags, tissue, cartons; raw = leather/PU,
///     soles, adhesives, laces, threads, eyelets.
///   Plastic & packaging — cartons, poly bags, stretch film, pallets; raw =
///     granules (PP/HDPE/LDPE/PET), masterbatch, additives, inks.
///   Utensils & hardware — cartons, corrugated sheets, poly bags, bubble
///     wrap, pallets; raw = SS/aluminium sheets & coils, MS rods, brass.
class IndustryPack {
  final String id;
  /// Packing-material CATEGORIES offered in the material form + filters.
  final List<String> packingCategories;
  /// Example material NAMES (hints in forms + quick-add starter list).
  final List<String> packingExamples;
  /// Example raw-material names (hints + quick-add starter list).
  final List<String> rawExamples;
  /// Raw-material stock units offered in the form (first = default).
  final List<String> rawUnits;
  /// Example finished-goods names (product form hint).
  final List<String> productExamples;
  /// Product-master hint replacing the sauce-specific tray note.
  final String productNote;
  /// Where this industry usually dispatches to (dropdown seeds).
  final List<String> destinations;
  /// Consumption hint shown on batch-complete dialog.
  final String consumeNote;
  /// What a production run is called on the floor: 'Batch' (process
  /// industries), 'Lot' (mills / plastic / hardware), 'Job' (textile /
  /// footwear job-work). Drives menu labels, table headers and PDFs.
  final String runNoun;
  /// Finished-goods master title as the trade calls it.
  final String productsTitle;
  /// Stock register title ("Batch-wise Stock" for food, "Lot-wise Stock"
  /// for mills, "Job-wise Stock" for garments).
  String get runStockTitle => '$runNoun-wise Stock';

  const IndustryPack({
    required this.id,
    required this.packingCategories,
    required this.packingExamples,
    required this.rawExamples,
    required this.rawUnits,
    required this.productExamples,
    required this.productNote,
    required this.destinations,
    required this.consumeNote,
    this.runNoun = 'Batch',
    this.productsTitle = 'Finished Goods Master',
  });

  /// Pack for the ACTIVE company industry.
  static IndustryPack get current => forIndustry(CompanyProfile.current.industry);

  static IndustryPack forIndustry(String id) => _packs[id] ?? _packs['general']!;

  /// "Raw Material" is the fixed category name the server uses to split the
  /// raw screen from the packing screen — never rename it.
  static const rawCategory = 'Raw Material';

  static const Map<String, IndustryPack> _packs = {
    'food': IndustryPack(
      id: 'food',
      packingCategories: ['Bottles', 'Jars', 'Pouches', 'Caps', 'Labels', 'Holograms', 'Plugs', 'Sleeves', 'Cartons', 'Trays', 'Tray Caps', 'Tape & Strapping', 'Other'],
      packingExamples: ['PET Bottle 500ml', 'Cap Green 28mm', 'Front Label 200gm', 'Shrink Sleeve 1 Ltr', 'Carton 12 × 500ml', 'Tray 6 × 740gm'],
      rawExamples: ['Sugar', 'Salt', 'Tomato Paste', 'Acetic Acid', 'Spices Mix', 'Preservative (Sodium Benzoate)'],
      rawUnits: ['kg', 'Ltr', 'g', 'pcs'],
      productExamples: ['Tomato Ketchup 500gm', 'Soya Sauce 200gm', 'Mixed Pickle 1kg'],
      productNote: 'Enter pieces per carton and the gross carton weight. Use the tray fields only for products that ship in trays.',
      destinations: ['DEPOT', 'DISTRIBUTOR', 'C&F AGENT'],
      consumeNote: 'Bottles, caps, labels, cartons & trays are consumed automatically as per BOM',
      runNoun: 'Batch',
      productsTitle: 'Finished Goods Master',
    ),
    'dairy': IndustryPack(
      id: 'dairy',
      packingCategories: ['Pouch Film', 'Cups & Lids', 'Ghee Tins / Jars', 'Caps', 'Labels', 'Crates', 'Cartons', 'Ice Packs', 'Tape & Strapping', 'Other'],
      packingExamples: ['Milk Pouch Film 500ml', 'Curd Cup 400gm', 'Cup Lid 400gm', 'Ghee Tin 15kg', 'Paneer Vacuum Pouch 200gm', 'Crate 20 Ltr'],
      rawExamples: ['Raw Milk', 'Cream', 'Skimmed Milk Powder', 'Sugar', 'Culture', 'Salt', 'Citric Acid'],
      rawUnits: ['Ltr', 'kg', 'g', 'pcs'],
      productExamples: ['Toned Milk 500ml Pouch', 'Curd 400gm Cup', 'Desi Ghee 1 Ltr', 'Paneer 200gm'],
      productNote: 'Enter packets per crate and crate weight. Use tray fields for cup / tub products packed in trays.',
      destinations: ['CHILLING CENTRE', 'DISTRIBUTOR', 'RETAIL ROUTE', 'PARLOUR'],
      consumeNote: 'Pouch film, cups, lids, tins & crates are consumed automatically as per BOM',
      runNoun: 'Batch',
      productsTitle: 'Products Master (SKU)',
    ),
    'oil': IndustryPack(
      id: 'oil',
      packingCategories: ['Tins', 'PET Bottles', 'Jars', 'Pouches', 'Caps', 'Labels', 'Cartons', 'Tape & Strapping', 'Other'],
      packingExamples: ['Tin 15kg', 'PET Bottle 1 Ltr', 'Jar 5 Ltr', 'Pouch 1 Ltr', 'Cap 1 Ltr', 'Label 1 Ltr', 'Carton 12 × 1 Ltr'],
      rawExamples: ['Mustard Seed', 'Sunflower Seed', 'Soybean', 'Crude Oil', 'Bleaching Earth', 'Caustic Soda', 'Hexane', 'Antioxidant (TBHQ)'],
      rawUnits: ['kg', 'Ltr', 'Quintal', 'MT'],
      productExamples: ['Kachi Ghani Mustard Oil 1 Ltr', 'Refined Sunflower Oil 5 Ltr Jar', 'Mustard Oil 15kg Tin'],
      productNote: 'Enter bottles / pouches / tins per carton and gross carton weight (e.g. 12 × 1 Ltr, 10 × 1 Ltr pouch). Loose tins / jars: 1 tin = 1 carton.',
      destinations: ['DEPOT', 'DISTRIBUTOR', 'MANDI', 'C&F AGENT'],
      consumeNote: 'Tins, bottles, caps, labels & cartons are consumed automatically as per BOM',
      runNoun: 'Batch',
      productsTitle: 'Finished Goods Master',
    ),
    'bakery': IndustryPack(
      id: 'bakery',
      packingCategories: ['Laminated Pouches', 'BOPP Film', 'Trays', 'Tin Boxes', 'Labels', 'Cartons', 'Tape & Strapping', 'Other'],
      packingExamples: ['Laminated Pouch 200gm', 'BOPP Wrapper 50gm', 'Plastic Tray 6-cavity', 'Cookie Tin 400gm', 'Carton 24 × 200gm'],
      rawExamples: ['Maida', 'Atta', 'Sugar', 'Vegetable Fat / Palm Oil', 'Yeast', 'Salt', 'Milk Powder', 'Essence / Flavour', 'Besan', 'Peanut'],
      rawUnits: ['kg', 'Ltr', 'g', 'pcs'],
      productExamples: ['Glucose Biscuit 100gm', 'Aloo Bhujia 200gm', 'Rusk 300gm', 'Cream Roll 6 pcs'],
      productNote: 'Enter packets per carton and gross carton weight. Use tray fields for products packed on trays inside the carton.',
      destinations: ['DEPOT', 'DISTRIBUTOR', 'SUPER STOCKIST', 'RETAIL ROUTE'],
      consumeNote: 'Pouches, wrappers, trays & cartons are consumed automatically as per BOM',
      runNoun: 'Batch',
      productsTitle: 'Finished Goods Master',
    ),
    'water': IndustryPack(
      id: 'water',
      packingCategories: ['PET Preforms / Bottles', 'Caps', 'Labels', 'Shrink Film', 'Crates', 'Jars (20 Ltr)', 'Handles', 'Cartons', 'Other'],
      packingExamples: ['PET Preform 19.5gm', 'Cap 29/25 Blue', 'Label 1 Ltr', 'Shrink Film 12-pack', 'Jar 20 Ltr', 'Crate 24 × 300ml'],
      rawExamples: ['Sugar', 'Concentrate / Flavour', 'CO2', 'Citric Acid', 'Preservative', 'Treated Water', 'Mineral Mix'],
      rawUnits: ['kg', 'Ltr', 'g', 'pcs'],
      productExamples: ['Packaged Drinking Water 1 Ltr', 'Soda 750ml', 'Jar 20 Ltr', 'Orange Drink 250ml'],
      productNote: 'Enter bottles per case / shrink pack and gross case weight. Use the crate fields for glass bottles that move in 24-bottle crates.',
      destinations: ['DISTRIBUTOR', 'RETAIL ROUTE', 'DEPOT', 'INSTITUTION'],
      consumeNote: 'Preforms, caps, labels, shrink film & crates are consumed automatically as per BOM',
      runNoun: 'Batch',
      productsTitle: 'SKU Master',
    ),
    'soap': IndustryPack(
      id: 'soap',
      packingCategories: ['Wrappers', 'Laminated Pouches', 'Bottles', 'Caps', 'Labels', 'Buckets', 'Cartons', 'Tape & Strapping', 'Other'],
      packingExamples: ['Wrapper 125gm', 'Detergent Pouch 1kg', 'Liquid Bottle 500ml', 'Bucket 4kg', 'Carton 48 × 125gm'],
      rawExamples: ['Soap Noodles', 'LABSA', 'Soda Ash', 'STPP', 'Caustic Soda', 'Sodium Silicate', 'Perfume', 'Colour', 'Salt', 'Glycerine'],
      rawUnits: ['kg', 'Ltr', 'g', 'pcs'],
      productExamples: ['Bath Soap 125gm', 'Detergent Powder 1kg', 'Dish Wash Liquid 500ml', 'Detergent Cake 250gm'],
      productNote: 'Enter pieces per carton and the gross carton weight (e.g. 48 × 125gm).',
      destinations: ['DEPOT', 'DISTRIBUTOR', 'SUPER STOCKIST'],
      consumeNote: 'Wrappers, pouches, bottles & cartons are consumed automatically as per BOM',
      runNoun: 'Batch',
      productsTitle: 'Finished Goods Master',
    ),
    'cosmetics': IndustryPack(
      id: 'cosmetics',
      packingCategories: ['Bottles', 'Jars', 'Tubes', 'Pumps & Caps', 'Labels', 'Shrink Sleeves', 'Mono Cartons', 'Shippers', 'Other'],
      packingExamples: ['HDPE Bottle 200ml', 'Acrylic Jar 50gm', 'Lami Tube 100gm', 'Flip-top Cap 24mm', 'Mono Carton 100ml', 'Shipper 48 × 100ml'],
      rawExamples: ['Coconut Oil', 'Glycerine', 'Emulsifying Wax', 'Cetyl Alcohol', 'Fragrance', 'Preservative (Phenoxyethanol)', 'Aloe Vera Extract', 'SLES'],
      rawUnits: ['kg', 'Ltr', 'g', 'ml'],
      productExamples: ['Herbal Shampoo 200ml', 'Face Cream 50gm', 'Hair Oil 100ml', 'Body Lotion 400ml'],
      productNote: 'Enter units per shipper carton and the gross shipper weight (mono carton is part of the BOM, not a unit).',
      destinations: ['DEPOT', 'DISTRIBUTOR', 'E-COMMERCE WAREHOUSE', 'C&F AGENT'],
      consumeNote: 'Bottles, tubes, caps, mono cartons & shippers are consumed automatically as per BOM',
      runNoun: 'Batch',
      productsTitle: 'SKU Master',
    ),
    'paint': IndustryPack(
      id: 'paint',
      packingCategories: ['Tins', 'Drums', 'Buckets / Pails', 'Bottles', 'Caps & Lids', 'Labels', 'Cartons', 'Other'],
      packingExamples: ['Tin 1 Ltr', 'Tin 4 Ltr', 'Bucket 20 Ltr', 'Drum 210 Ltr', 'Lid 1 Ltr', 'Label Emulsion 4 Ltr', 'Carton 12 × 1 Ltr'],
      rawExamples: ['Base Oil SN-500', 'Additive Package', 'Acrylic Resin', 'Titanium Dioxide', 'Pigment', 'Solvent (MTO)', 'Thickener', 'Calcium Carbonate'],
      rawUnits: ['kg', 'Ltr', 'Drum', 'MT'],
      productExamples: ['Emulsion White 4 Ltr', 'Engine Oil 20W-40 1 Ltr', 'Enamel Black 1 Ltr', 'Gear Oil 20 Ltr Bucket'],
      productNote: 'Enter tins per carton and the gross carton weight. Loose buckets / drums: 1 pack = 1 carton.',
      destinations: ['DEPOT', 'DEALER', 'DISTRIBUTOR', 'PROJECT SITE'],
      consumeNote: 'Tins, lids, labels & cartons are consumed automatically as per BOM',
      runNoun: 'Batch',
      productsTitle: 'Finished Goods Master',
    ),
    'agro': IndustryPack(
      id: 'agro',
      packingCategories: ['HDPE Bottles', 'Pouches', 'Jerry Cans', 'Bags', 'Caps', 'Labels & Leaflets', 'Cartons', 'Other'],
      packingExamples: ['HDPE Bottle 250ml', 'Pouch 100gm', 'Jerry Can 5 Ltr', 'PP Bag 50kg', 'Cap 28mm', 'Leaflet', 'Carton 40 × 250ml'],
      rawExamples: ['Technical Grade Active', 'Urea', 'DAP', 'MOP', 'Emulsifier', 'Solvent', 'Filler (Kaolin)', 'Zinc Sulphate', 'Humic Acid'],
      rawUnits: ['kg', 'Ltr', 'MT', 'g'],
      productExamples: ['Insecticide 250ml', 'NPK 19:19:19 1kg', 'Bio-Fertilizer 5 Ltr', 'Micronutrient Mix 50kg'],
      productNote: 'Enter bottles / pouches per carton and the gross carton weight. Bag products: 1 bag = 1 carton.',
      destinations: ['DEPOT', 'DEALER', 'DISTRIBUTOR', 'MANDI'],
      consumeNote: 'Bottles, pouches, caps, leaflets & cartons are consumed automatically as per BOM',
      runNoun: 'Batch',
      productsTitle: 'Finished Goods Master',
    ),
    'pharma': IndustryPack(
      id: 'pharma',
      packingCategories: ['Blister Foil (Alu / PVC)', 'Strips', 'Bottles', 'Caps & Droppers', 'Labels & Leaflets', 'Mono Cartons', 'Shippers', 'Other'],
      packingExamples: ['Alu Foil 100mm', 'PVC Film 250 mic', 'Amber Bottle 100ml', 'CRC Cap 25mm', 'Leaflet', 'Mono Carton 10 × 10', 'Shipper 100 boxes'],
      rawExamples: ['Paracetamol API', 'Ashwagandha Powder', 'Lactose', 'Starch', 'Magnesium Stearate', 'Sugar', 'Empty Capsules Size 0', 'Sorbitol'],
      rawUnits: ['kg', 'g', 'Ltr', 'pcs'],
      productExamples: ['Paracetamol 500mg 10×10', 'Cough Syrup 100ml', 'Chyawanprash 500gm', 'Ashwagandha Capsules 60s'],
      productNote: 'Enter boxes per shipper and gross shipper weight. Use strip fields for strips per box.',
      destinations: ['DEPOT', 'C&F AGENT', 'STOCKIST', 'HOSPITAL SUPPLY'],
      consumeNote: 'Foil, bottles, caps, leaflets, mono cartons & shippers are consumed automatically as per BOM',
      runNoun: 'Batch',
      productsTitle: 'Product Master (SKU)',
    ),
    'textile': IndustryPack(
      id: 'textile',
      packingCategories: ['Poly Bags', 'Hangers', 'Tags & Labels', 'Cartons', 'Bale Cloth / Hessian', 'Strapping', 'Tissue / Board', 'Other'],
      packingExamples: ['Poly Bag 12×16', 'Hanger', 'Hang Tag', 'Wash Care Label', 'Carton 60 pcs', 'Bale Cloth', 'PP Strap'],
      rawExamples: ['Cotton Yarn 30s', 'Polyester Yarn', 'Fabric (Single Jersey)', 'Dyes', 'Sewing Thread', 'Elastic', 'Buttons', 'Zippers', 'Interlining'],
      rawUnits: ['kg', 'Meter', 'pcs', 'Cone', 'Roll'],
      productExamples: ['Men T-Shirt L', 'Ladies Cardigan M', 'Socks 3-pack', 'Thermal Set XL'],
      productNote: 'Enter pieces per bale / carton and gross weight. Use the dozen fields for hosiery packed and sold per dozen (e.g. 12 per dozen, 5 dozen per carton).',
      destinations: ['WHOLESALER', 'BRAND WAREHOUSE', 'EXPORT CHA', 'SHOWROOM'],
      consumeNote: 'Poly bags, hangers, tags & cartons are consumed automatically as per BOM',
      runNoun: 'Lot',
      productsTitle: 'Style / Article Master',
    ),
    'mill': IndustryPack(
      id: 'mill',
      packingCategories: ['PP Woven Bags', 'BOPP Laminated Bags', 'Jute Bags', 'Non-Woven Bags', 'LDPE Liners / Pouches', 'Stitching Thread', 'Labels / Tags', 'Other'],
      packingExamples: ['PP Woven Bag 50kg', 'BOPP Bag 25kg (branded)', 'BOPP Bag 10kg', 'Non-Woven Bag 5kg', 'Jute Bag 50kg', 'LDPE Liner 25kg', 'Stitching Thread', 'Tag'],
      rawExamples: ['Paddy (PR-126)', 'Paddy (Basmati 1121)', 'Wheat', 'Maize', 'Soya DOC', 'Bran', 'Husk', 'Broken Rice', 'Molasses', 'Mineral Mix'],
      rawUnits: ['Quintal', 'kg', 'MT', 'Bag'],
      productExamples: ['Basmati Rice 25kg', 'Sella Rice 50kg', 'Chakki Atta 10kg', 'Cattle Feed 50kg', 'Rice Bran 40kg'],
      productNote: 'Enter KG per bag (e.g. 25 or 50) and the gross bag weight including the bag. Stock and dispatch are counted in bags.',
      destinations: ['MANDI', 'FCI GODOWN', 'EXPORT CHA', 'DISTRIBUTOR', 'WHOLESALER'],
      consumeNote: 'Bags, liners, thread & tags are consumed automatically as per BOM',
      runNoun: 'Lot',
      productsTitle: 'Grade & Pack Master',
    ),
    'footwear': IndustryPack(
      id: 'footwear',
      packingCategories: ['Shoe Boxes', 'Poly Bags', 'Tissue Paper', 'Tags & Labels', 'Cartons', 'Silica Gel', 'Strapping', 'Other'],
      packingExamples: ['Shoe Box Size 8', 'Poly Bag', 'Tissue Paper', 'Size Sticker', 'Dozen Bag (12 pairs)', 'Master Carton 12 pairs', 'Silica Gel 1gm'],
      rawExamples: ['Leather (sq ft)', 'PU Sheet', 'EVA Sole', 'PVC Sole', 'Adhesive', 'Laces', 'Thread', 'Eyelets', 'Insole Board', 'Buckles'],
      rawUnits: ['pcs', 'Pair', 'sq ft', 'kg', 'Meter', 'Ltr'],
      productExamples: ['Sports Shoe Size 8', 'Ladies Sandal Size 6', 'School Shoe Size 4', 'Slipper Size 9'],
      productNote: 'Enter pairs per master carton and the gross carton weight (e.g. 12 or 24 pairs). Use the dozen fields for chappal / hawai lines packed per dozen.',
      destinations: ['WHOLESALER', 'SHOWROOM', 'DISTRIBUTOR', 'BRAND WAREHOUSE'],
      consumeNote: 'Shoe boxes, poly bags, tissue & cartons are consumed automatically as per BOM',
      runNoun: 'Lot',
      productsTitle: 'Article Master',
    ),
    'plastic': IndustryPack(
      id: 'plastic',
      packingCategories: ['Cartons', 'Inner Pack / Sleeve Bags', 'Poly Bags', 'Stretch Film', 'Pallets', 'Strapping', 'Labels', 'Bubble Wrap', 'Other'],
      packingExamples: ['Carton 500 pcs', 'Sleeve Bag 100 pcs', 'Poly Bag 24×36', 'Stretch Film 23 mic', 'Wooden Pallet', 'PP Strap 12mm', 'Label'],
      rawExamples: ['PP Granules', 'HDPE Granules', 'LDPE Granules', 'PET Resin', 'Masterbatch White', 'Masterbatch Black', 'Calcium Filler', 'Printing Ink', 'Solvent'],
      rawUnits: ['kg', 'MT', 'Bag', 'Ltr'],
      productExamples: ['Carry Bag 16×20', 'HDPE Bottle 1 Ltr', 'Disposable Glass 200ml', 'PVC Pipe 4 inch'],
      productNote: 'Enter pieces per carton / bundle and the gross weight. Use the pack fields for sleeve / inner packs (e.g. 100 glasses per pack, 10 packs per carton). Weight per piece drives the loading calculator.',
      destinations: ['CUSTOMER FACTORY', 'DEALER', 'WHOLESALER', 'DEPOT'],
      consumeNote: 'Cartons, poly bags, film & labels are consumed automatically as per BOM',
      runNoun: 'Lot',
      productsTitle: 'Item Master',
    ),
    'hardware': IndustryPack(
      id: 'hardware',
      packingCategories: ['Cartons', 'Inner Boxes', 'Corrugated Sheets', 'Poly Bags', 'Bubble Wrap', 'Pallets', 'Strapping', 'Labels', 'Other'],
      packingExamples: ['Carton 24 pcs', 'Inner Box 100 pcs', 'Corrugated Sheet', 'Poly Bag', 'Bubble Wrap Roll', 'Wooden Pallet', 'Steel Strap', 'Label'],
      rawExamples: ['SS Sheet 202', 'SS Coil 304', 'Aluminium Circle', 'MS Rod 12mm', 'Brass Rod', 'Zinc Plating Chemical', 'Polish Compound', 'Nuts & Bolts'],
      rawUnits: ['kg', 'MT', 'pcs', 'Sheet', 'Coil'],
      productExamples: ['SS Pressure Cooker 5 Ltr', 'Aluminium Kadai 3 Ltr', 'Door Hinge 4 inch', 'Hex Bolt M12'],
      productNote: 'Enter pieces per carton and the gross carton weight. Use the inner-box fields for small items (e.g. 100 bolts per inner box, 10 boxes per carton). Heavy items: 1 piece = 1 carton is fine.',
      destinations: ['DEALER', 'WHOLESALER', 'DISTRIBUTOR', 'EXPORT CHA'],
      consumeNote: 'Cartons, sheets, poly bags & labels are consumed automatically as per BOM',
      runNoun: 'Lot',
      productsTitle: 'Item Master',
    ),
    'general': IndustryPack(
      id: 'general',
      packingCategories: ['Cartons', 'Poly Bags', 'Pouches', 'Bottles', 'Caps', 'Labels', 'Trays', 'Strapping / Tape', 'Other'],
      packingExamples: ['Carton 12 pcs', 'Poly Bag', 'Label', 'Pouch 500gm', 'Tape Roll'],
      rawExamples: ['Raw Material A', 'Raw Material B', 'Chemical', 'Additive'],
      rawUnits: ['kg', 'Ltr', 'pcs', 'Meter', 'g'],
      productExamples: ['Product 500gm', 'Product 1kg'],
      productNote: 'Enter pieces per carton and gross carton weight. Use tray fields only for tray-packed products.',
      destinations: ['DEPOT', 'DISTRIBUTOR', 'DEALER', 'WHOLESALER'],
      consumeNote: 'Packing material is consumed automatically as per BOM',
      runNoun: 'Batch',
      productsTitle: 'Finished Goods Master',
    ),
  };

  /// Example text for "e.g. …" hints (first two examples joined).
  static String eg(List<String> items, [int n = 2]) => 'e.g. ${items.take(n).join(' / ')}';

  /// Rewrite production-run wording ("Batch", "batches", "Batch Code"…)
  /// into the active industry's noun (Lot / Job). Unit words are handled
  /// by [U.ize]; call both on server-sent text.
  static String noun(String text) {
    final n = current.runNoun;
    if (n == 'Batch' || text.isEmpty) return text;
    final lc = n.toLowerCase();
    return text
        .replaceAll(RegExp(r'\bBatches\b'), '${n}s')
        .replaceAll(RegExp(r'\bbatches\b'), '${lc}s')
        .replaceAll(RegExp(r'\bBatch\b'), n)
        .replaceAll(RegExp(r'\bbatch\b'), lc);
  }
}
