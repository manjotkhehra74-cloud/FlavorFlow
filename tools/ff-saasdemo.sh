#!/usr/bin/env bash
# FlavorFlow SaaS: ONE demo login for EVERY industry —
#   16 demo tenants (ik per industry), sab vich same email/password:
#     Email    demo@flavorflow.co.in
#     Password Demo@1234
#     Company code  demo-<industry>   (demo-mill, demo-dairy, demo-textile, …)
#   Har tenant registry vich apni industry label naal banda hai → gateway
#   COMPANY_INDUSTRY env → core boot-seed (ff-saasindustry) app_settings
#   'company' = {industry:'mill', units Bags/Bag/KG…} → app us industry de
#   units/sections/destinations dikhaundi hai. Purana 'demo' (Food) rehnda hai.
#   Har demo tenant vich us industry da SAMPLE DATA vi seed hunda hai
#   (products, packing + raw materials, trucks, opening stock, ik completed
#   production run, ik dispatch) — tenant di apni API rahin (schema-proof).
#   Nightly reset (3 AM IST) hun SARE demo* tenants fresh + re-seed karda hai.
# Idempotent — dubara chalao ta sirf missing tenants/data add hunde ne.
#   curl -s https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a0858b-flavorflow/tools/ff-saasdemo.sh | sudo bash
set -u
BASE=/opt/flavorflow-saas
echo "=== FF-SAASDEMO $(date) ==="
[ -f "$BASE/data/registry.json" ] || { echo "FATAL: registry nahi — eh SaaS VM nahi?"; exit 1; }
grep -q 'ffIndustrySeed' "$BASE/core/server.js" 2>/dev/null || echo "WARN: core vich industry seed nahi — pehla ff-saasindustry.sh chalao (nahi ta demo tenants sab Food dikhaunge)"

# ---------- 1) registry: demo-<industry> tenants (same admin creds) ----------
node - <<'JS'
const fs = require('fs');
const REG = '/opt/flavorflow-saas/data/registry.json';
const reg = JSON.parse(fs.readFileSync(REG, 'utf8'));
reg.companies = reg.companies || {};
// id → website label (ff-saasindustry LABELS map + app industryIdFor() dono samajhde ne)
const IND = {
  food: 'Food & Beverage', dairy: 'Dairy', oil: 'Edible Oil', bakery: 'Bakery & Snacks',
  water: 'Beverages / Water', soap: 'Soap & Detergent', cosmetics: 'Cosmetics & Personal Care',
  paint: 'Paint & Lubricants', agro: 'Agro-chemicals & Fertilizer', pharma: 'Pharma / Ayurvedic',
  textile: 'Textile / Hosiery', mill: 'Rice / Flour / Feed Mill', footwear: 'Footwear',
  plastic: 'Plastic & Packaging', hardware: 'Utensils & Hardware', general: 'General Manufacturing',
};
const NAMES = {
  food: 'Demo Foods & Sauces', dairy: 'Demo Dairy', oil: 'Demo Oil Mills', bakery: 'Demo Bakery & Snacks',
  water: 'Demo Beverages', soap: 'Demo Soap & Detergents', cosmetics: 'Demo Cosmetics',
  paint: 'Demo Paints & Lubricants', agro: 'Demo Agro Chemicals', pharma: 'Demo Pharma & Ayurveda',
  textile: 'Demo Textiles & Hosiery', mill: 'Demo Rice & Flour Mill', footwear: 'Demo Footwear',
  plastic: 'Demo Plastics & Packaging', hardware: 'Demo Utensils & Hardware', general: 'Demo Manufacturing',
};
const used = new Set(Object.values(reg.companies).map(c => c.port));
let port = 4201; const nextPort = () => { while (used.has(port)) port++; used.add(port); return port; };
let added = 0;
for (const id of Object.keys(IND)) {
  const code = 'demo-' + id;
  if (reg.companies[code]) { if (reg.companies[code].industry !== IND[id]) { reg.companies[code].industry = IND[id]; console.log('demo tenant industry fixed: ' + code); } continue; }
  reg.companies[code] = {
    name: NAMES[id], industry: IND[id], port: nextPort(),
    created: new Date().toISOString(), trialEnds: '2099-12-31',
    adminName: 'Demo User', adminEmail: 'demo@flavorflow.co.in', adminPassword: 'Demo@1234',
    demo: true,
  };
  added++; console.log('demo tenant ✓ ' + code + ' [' + IND[id] + '] @ ' + reg.companies[code].port);
}
if (reg.companies.demo) reg.companies.demo.demo = true;
fs.writeFileSync(REG, JSON.stringify(reg, null, 2));
console.log(added ? added + ' demo tenants added' : 'demo tenants: already ✓');
JS
[ $? -ne 0 ] && { echo "SAASDEMO FAIL (registry)"; exit 1; }

# ---------- 2) seeder: per-industry sample data through the tenant's own API ----------
cat > /usr/local/bin/ff-demo-seed.js <<'SEED'
#!/usr/bin/env node
/** FlavorFlow demo seeder — fills every demo* tenant with industry-true sample data.
 *  Uses the tenant's HTTP API (same calls the app makes) so it can never break the schema.
 *  Idempotent: a tenant that already has products is skipped. */
const http = require('http');
const reg = JSON.parse(require('fs').readFileSync('/opt/flavorflow-saas/data/registry.json', 'utf8'));
const EMAIL = 'demo@flavorflow.co.in', PASS = 'Demo@1234';
const ONLY = process.argv[2] || '';
const RAW = 'Raw Material';
// P: [name, piecesPerPack, grossKg, netKg, minStock, openingStock, piecesPerTray?, trayKg?]
// PM: [name, category, unit, stock, min]   RM: [name, unit, stock, min]   TR: [truckNo, destination]
const D = {
  food: {
    P: [['Tomato Ketchup 500gm', 24, 14.2, 13.4, 50, 320], ['Soya Sauce 200gm', 48, 13.1, 12.3, 50, 210], ['Mixed Pickle 1kg', 12, 13.0, 12.4, 30, 96], ['Green Chilli Sauce 680gm', 12, 9.6, 9.0, 30, 150, 6, 4.5]],
    PM: [['PET Bottle 500ml', 'Bottles', 'pcs', 12000, 3000], ['Cap Green 28mm', 'Caps', 'pcs', 15000, 4000], ['Front Label 500gm', 'Labels', 'pcs', 20000, 5000], ['Shrink Sleeve 200gm', 'Sleeves', 'pcs', 8000, 2000], ['Carton 24 × 500gm', 'Cartons', 'pcs', 900, 200], ['Tray 6 × 680gm', 'Trays', 'pcs', 600, 150]],
    RM: [['Sugar', 'kg', 2400, 500], ['Salt', 'kg', 900, 200], ['Tomato Paste', 'kg', 1800, 400], ['Acetic Acid', 'Ltr', 300, 80], ['Spices Mix', 'kg', 150, 40]],
    TR: [['PB10AB1234', 'DEPOT'], ['HR55CD5678', 'DISTRIBUTOR']] },
  dairy: {
    P: [['Toned Milk 500ml Pouch', 20, 10.8, 10.2, 40, 260], ['Curd 400gm Cup', 24, 10.4, 9.8, 30, 140, 6, 2.6], ['Desi Ghee 1 Ltr', 12, 11.6, 11.0, 20, 84], ['Paneer 200gm', 30, 6.5, 6.1, 20, 120]],
    PM: [['Milk Pouch Film 500ml', 'Pouch Film', 'kg', 420, 100], ['Curd Cup 400gm', 'Cups & Lids', 'pcs', 9000, 2000], ['Cup Lid 400gm', 'Cups & Lids', 'pcs', 9000, 2000], ['Ghee Jar 1 Ltr', 'Ghee Tins / Jars', 'pcs', 1500, 300], ['Crate 20 Ltr', 'Crates', 'pcs', 400, 100], ['Paneer Vacuum Pouch 200gm', 'Pouch Film', 'pcs', 6000, 1500]],
    RM: [['Raw Milk', 'Ltr', 5200, 1500], ['Cream', 'kg', 260, 60], ['Skimmed Milk Powder', 'kg', 400, 100], ['Culture', 'g', 900, 200], ['Salt', 'kg', 120, 30]],
    TR: [['PB08MK4521', 'CHILLING CENTRE'], ['PB65DR7788', 'RETAIL ROUTE']] },
  oil: {
    P: [['Kachi Ghani Mustard Oil 1 Ltr', 12, 11.9, 11.2, 40, 380], ['Refined Sunflower Oil 5 Ltr Jar', 4, 19.2, 18.6, 30, 160], ['Mustard Oil 15kg Tin', 1, 15.6, 15.0, 30, 210], ['Mustard Oil 500ml Pouch', 24, 11.6, 11.1, 30, 140]],
    PM: [['Tin 15kg', 'Tins', 'pcs', 1200, 300], ['PET Bottle 1 Ltr', 'PET Bottles', 'pcs', 14000, 3000], ['Jar 5 Ltr', 'Jars', 'pcs', 2400, 500], ['Pouch 500ml', 'Pouches', 'pcs', 10000, 2500], ['Cap 1 Ltr', 'Caps', 'pcs', 15000, 3000], ['Carton 12 × 1 Ltr', 'Cartons', 'pcs', 1100, 250]],
    RM: [['Mustard Seed', 'Quintal', 420, 100], ['Sunflower Seed', 'Quintal', 180, 50], ['Crude Oil', 'kg', 6000, 1500], ['Bleaching Earth', 'kg', 400, 100], ['Antioxidant (TBHQ)', 'kg', 25, 5]],
    TR: [['PB13OL2211', 'DEPOT'], ['RJ14TN9090', 'MANDI']] },
  bakery: {
    P: [['Glucose Biscuit 100gm', 60, 6.8, 6.2, 60, 420], ['Aloo Bhujia 200gm', 24, 5.4, 4.9, 40, 260], ['Rusk 300gm', 20, 6.6, 6.1, 30, 150], ['Cream Roll 6 pcs', 12, 3.9, 3.5, 20, 90, 6, 1.8]],
    PM: [['Laminated Pouch 200gm', 'Laminated Pouches', 'pcs', 20000, 5000], ['BOPP Wrapper 100gm', 'BOPP Film', 'kg', 380, 100], ['Plastic Tray 6-cavity', 'Trays', 'pcs', 6000, 1500], ['Cookie Tin 400gm', 'Tin Boxes', 'pcs', 1200, 300], ['Carton 60 × 100gm', 'Cartons', 'pcs', 900, 200], ['BOPP Tape', 'Tape & Strapping', 'Roll', 240, 60]],
    RM: [['Maida', 'kg', 4800, 1000], ['Sugar', 'kg', 2200, 500], ['Vegetable Fat / Palm Oil', 'kg', 1600, 400], ['Yeast', 'kg', 60, 15], ['Besan', 'kg', 900, 200]],
    TR: [['PB11BK3344', 'DEPOT'], ['CH01SN1122', 'SUPER STOCKIST']] },
  water: {
    P: [['Packaged Drinking Water 1 Ltr', 12, 12.6, 12.0, 100, 640], ['Soda 750ml', 24, 20.4, 19.2, 60, 300, 12, 9.8], ['Jar 20 Ltr', 1, 20.9, 20.0, 40, 220], ['Orange Drink 250ml', 24, 6.9, 6.3, 60, 280]],
    PM: [['PET Preform 19.5gm', 'PET Preforms / Bottles', 'pcs', 60000, 15000], ['Cap 29/25 Blue', 'Caps', 'pcs', 70000, 15000], ['Label 1 Ltr', 'Labels', 'pcs', 60000, 15000], ['Shrink Film 12-pack', 'Shrink Film', 'kg', 360, 90], ['Jar 20 Ltr', 'Jars (20 Ltr)', 'pcs', 800, 200], ['Crate 24 × 300ml', 'Crates', 'pcs', 600, 150]],
    RM: [['Sugar', 'kg', 3000, 800], ['Concentrate / Flavour', 'Ltr', 240, 60], ['CO2', 'kg', 900, 200], ['Citric Acid', 'kg', 180, 40], ['Mineral Mix', 'kg', 60, 15]],
    TR: [['PB02WT5566', 'DISTRIBUTOR'], ['PB02WT5567', 'RETAIL ROUTE']] },
  soap: {
    P: [['Bath Soap 125gm', 48, 6.6, 6.0, 60, 520], ['Detergent Powder 1kg', 12, 12.5, 12.0, 60, 340], ['Dish Wash Liquid 500ml', 24, 13.2, 12.6, 30, 180], ['Detergent Cake 250gm', 40, 10.6, 10.0, 40, 260]],
    PM: [['Wrapper 125gm', 'Wrappers', 'pcs', 40000, 10000], ['Detergent Pouch 1kg', 'Laminated Pouches', 'pcs', 12000, 3000], ['Liquid Bottle 500ml', 'Bottles', 'pcs', 8000, 2000], ['Flip Cap 500ml', 'Caps', 'pcs', 8000, 2000], ['Carton 48 × 125gm', 'Cartons', 'pcs', 1200, 300], ['Bucket 4kg', 'Buckets', 'pcs', 900, 200]],
    RM: [['Soap Noodles', 'kg', 8000, 2000], ['LABSA', 'kg', 3200, 800], ['Soda Ash', 'kg', 4500, 1000], ['STPP', 'kg', 1200, 300], ['Perfume', 'kg', 90, 20]],
    TR: [['PB29SP7711', 'DEPOT'], ['HR26DT4433', 'SUPER STOCKIST']] },
  cosmetics: {
    P: [['Herbal Shampoo 200ml', 48, 11.4, 10.8, 40, 300], ['Face Cream 50gm', 96, 7.2, 6.6, 40, 240], ['Hair Oil 100ml', 72, 8.4, 7.8, 40, 260], ['Body Lotion 400ml', 24, 11.0, 10.4, 20, 120]],
    PM: [['HDPE Bottle 200ml', 'Bottles', 'pcs', 12000, 3000], ['Acrylic Jar 50gm', 'Jars', 'pcs', 9000, 2000], ['Lami Tube 100gm', 'Tubes', 'pcs', 7000, 1500], ['Flip-top Cap 24mm', 'Pumps & Caps', 'pcs', 14000, 3000], ['Mono Carton 200ml', 'Mono Cartons', 'pcs', 12000, 3000], ['Shipper 48 × 200ml', 'Shippers', 'pcs', 500, 120]],
    RM: [['Coconut Oil', 'kg', 900, 200], ['Glycerine', 'kg', 400, 100], ['Emulsifying Wax', 'kg', 260, 60], ['Fragrance', 'kg', 45, 10], ['SLES', 'kg', 700, 150]],
    TR: [['PB10CS8899', 'DEPOT'], ['DL01EC2020', 'E-COMMERCE WAREHOUSE']] },
  paint: {
    P: [['Emulsion White 4 Ltr', 4, 23.4, 22.6, 30, 160], ['Engine Oil 20W-40 1 Ltr', 12, 11.6, 11.0, 40, 300], ['Enamel Black 1 Ltr', 12, 14.8, 14.1, 30, 140], ['Gear Oil 20 Ltr Bucket', 1, 18.6, 18.0, 20, 90]],
    PM: [['Tin 1 Ltr', 'Tins', 'pcs', 9000, 2000], ['Tin 4 Ltr', 'Tins', 'pcs', 3000, 700], ['Bucket 20 Ltr', 'Buckets / Pails', 'pcs', 700, 150], ['Lid 1 Ltr', 'Caps & Lids', 'pcs', 9000, 2000], ['Label Emulsion 4 Ltr', 'Labels', 'pcs', 4000, 1000], ['Carton 12 × 1 Ltr', 'Cartons', 'pcs', 900, 200]],
    RM: [['Base Oil SN-500', 'Ltr', 6000, 1500], ['Additive Package', 'kg', 400, 100], ['Acrylic Resin', 'kg', 1800, 400], ['Titanium Dioxide', 'kg', 1200, 300], ['Solvent (MTO)', 'Ltr', 900, 200]],
    TR: [['PB08PT6655', 'DEALER'], ['HR38LB1199', 'DEPOT']] },
  agro: {
    P: [['Insecticide 250ml', 40, 12.4, 11.8, 30, 220], ['NPK 19:19:19 1kg', 25, 26.0, 25.2, 40, 300], ['Bio-Fertilizer 5 Ltr', 4, 21.6, 21.0, 20, 90], ['Micronutrient Mix 50kg', 1, 50.4, 50.0, 40, 180]],
    PM: [['HDPE Bottle 250ml', 'HDPE Bottles', 'pcs', 12000, 3000], ['Pouch 1kg', 'Pouches', 'pcs', 9000, 2000], ['Jerry Can 5 Ltr', 'Jerry Cans', 'pcs', 1200, 300], ['PP Bag 50kg', 'Bags', 'pcs', 3000, 700], ['Cap 28mm', 'Caps', 'pcs', 12000, 3000], ['Leaflet', 'Labels & Leaflets', 'pcs', 15000, 4000]],
    RM: [['Technical Grade Active', 'kg', 600, 150], ['Urea', 'MT', 40, 10], ['DAP', 'MT', 25, 6], ['Emulsifier', 'kg', 300, 80], ['Zinc Sulphate', 'kg', 900, 200]],
    TR: [['PB19AG2233', 'DEALER'], ['PB19AG2234', 'MANDI']] },
  pharma: {
    P: [['Paracetamol 500mg 10×10', 100, 4.8, 4.4, 60, 420, 10, 0.05], ['Cough Syrup 100ml', 60, 9.6, 9.0, 40, 260], ['Chyawanprash 500gm', 24, 14.2, 13.6, 20, 120], ['Ashwagandha Capsules 60s', 48, 3.6, 3.2, 30, 200]],
    PM: [['Alu Foil 100mm', 'Blister Foil (Alu / PVC)', 'kg', 260, 60], ['PVC Film 250 mic', 'Blister Foil (Alu / PVC)', 'kg', 400, 100], ['Amber Bottle 100ml', 'Bottles', 'pcs', 12000, 3000], ['CRC Cap 25mm', 'Caps & Droppers', 'pcs', 12000, 3000], ['Mono Carton 10 × 10', 'Mono Cartons', 'pcs', 20000, 5000], ['Shipper 100 boxes', 'Shippers', 'pcs', 600, 150]],
    RM: [['Paracetamol API', 'kg', 400, 100], ['Ashwagandha Powder', 'kg', 300, 80], ['Lactose', 'kg', 600, 150], ['Magnesium Stearate', 'kg', 60, 15], ['Empty Capsules Size 0', 'pcs', 500000, 100000]],
    TR: [['PB10PH4455', 'C&F AGENT'], ['CH01ST9911', 'STOCKIST']] },
  textile: {
    P: [['Men T-Shirt L', 60, 14.5, 13.8, 20, 140], ['Ladies Cardigan M', 40, 18.2, 17.4, 20, 90], ['Socks 3-pack', 120, 12.0, 11.4, 30, 160], ['Thermal Set XL', 30, 15.6, 15.0, 20, 110]],
    PM: [['Poly Bag 12×16', 'Poly Bags', 'pcs', 30000, 8000], ['Hanger', 'Hangers', 'pcs', 9000, 2000], ['Hang Tag', 'Tags & Labels', 'pcs', 30000, 8000], ['Wash Care Label', 'Tags & Labels', 'pcs', 30000, 8000], ['Carton 60 pcs', 'Cartons', 'pcs', 800, 200], ['PP Strap', 'Strapping', 'Roll', 60, 15]],
    RM: [['Cotton Yarn 30s', 'kg', 3200, 800], ['Polyester Yarn', 'kg', 1800, 400], ['Fabric (Single Jersey)', 'kg', 2400, 600], ['Sewing Thread', 'Cone', 900, 200], ['Elastic', 'Meter', 6000, 1500]],
    TR: [['PB10TX1212', 'WHOLESALER'], ['PB10TX1213', 'BRAND WAREHOUSE']] },
  mill: {
    P: [['Basmati Rice 25kg', 25, 25.3, 25.0, 100, 1200], ['Sella Rice 50kg', 50, 50.5, 50.0, 100, 860], ['Chakki Atta 10kg', 10, 10.15, 10.0, 80, 640], ['Cattle Feed 50kg', 50, 50.4, 50.0, 60, 420]],
    PM: [['PP Woven Bag 50kg', 'PP Woven Bags', 'pcs', 12000, 3000], ['BOPP Bag 25kg (branded)', 'BOPP Laminated Bags', 'pcs', 9000, 2000], ['Non-Woven Bag 10kg', 'Non-Woven Bags', 'pcs', 7000, 1500], ['Jute Bag 50kg', 'Jute Bags', 'pcs', 3000, 700], ['LDPE Liner 25kg', 'LDPE Liners / Pouches', 'pcs', 6000, 1500], ['Stitching Thread', 'Stitching Thread', 'Cone', 400, 100]],
    RM: [['Paddy (PR-126)', 'Quintal', 2400, 500], ['Paddy (Basmati 1121)', 'Quintal', 1800, 400], ['Wheat', 'Quintal', 1600, 400], ['Maize', 'Quintal', 600, 150], ['Soya DOC', 'Quintal', 300, 80]],
    TR: [['PB03RM1001', 'MANDI'], ['PB03RM1002', 'FCI GODOWN']] },
  footwear: {
    P: [['Sports Shoe Size 8', 12, 11.4, 10.8, 20, 140], ['Ladies Sandal Size 6', 24, 9.6, 9.0, 20, 120], ['School Shoe Size 4', 24, 12.2, 11.6, 30, 200], ['Slipper Size 9', 48, 13.0, 12.4, 30, 260]],
    PM: [['Shoe Box Size 8', 'Shoe Boxes', 'pcs', 6000, 1500], ['Poly Bag', 'Poly Bags', 'pcs', 20000, 5000], ['Tissue Paper', 'Tissue Paper', 'Ream', 120, 30], ['Size Sticker', 'Tags & Labels', 'pcs', 20000, 5000], ['Master Carton 12 pairs', 'Cartons', 'pcs', 900, 200], ['Silica Gel 1gm', 'Silica Gel', 'pcs', 15000, 4000]],
    RM: [['Leather (sq ft)', 'sq ft', 9000, 2000], ['PU Sheet', 'Meter', 1800, 400], ['EVA Sole', 'Pair', 12000, 3000], ['Adhesive', 'Ltr', 400, 100], ['Laces', 'Pair', 15000, 4000]],
    TR: [['PB10FW3030', 'WHOLESALER'], ['UP32SH4141', 'SHOWROOM']] },
  plastic: {
    P: [['Carry Bag 16×20', 2000, 9.2, 8.6, 30, 220], ['HDPE Bottle 1 Ltr', 200, 8.4, 7.8, 30, 180], ['Disposable Glass 200ml', 1000, 6.6, 6.0, 40, 300], ['PVC Pipe 4 inch', 10, 32.0, 31.4, 20, 90]],
    PM: [['Carton 500 pcs', 'Cartons', 'pcs', 1500, 400], ['Poly Bag 24×36', 'Poly Bags', 'pcs', 12000, 3000], ['Stretch Film 23 mic', 'Stretch Film', 'kg', 300, 80], ['Wooden Pallet', 'Pallets', 'pcs', 120, 30], ['PP Strap 12mm', 'Strapping', 'Roll', 80, 20], ['Label', 'Labels', 'pcs', 20000, 5000]],
    RM: [['PP Granules', 'kg', 12000, 3000], ['HDPE Granules', 'kg', 9000, 2000], ['LDPE Granules', 'kg', 6000, 1500], ['Masterbatch White', 'kg', 600, 150], ['Printing Ink', 'Ltr', 200, 50]],
    TR: [['PB10PL5050', 'CUSTOMER FACTORY'], ['HR29PK6161', 'DEALER']] },
  hardware: {
    P: [['SS Pressure Cooker 5 Ltr', 4, 10.8, 10.2, 20, 120], ['Aluminium Kadai 3 Ltr', 6, 6.6, 6.0, 20, 140], ['Door Hinge 4 inch', 200, 24.0, 23.4, 30, 160], ['Hex Bolt M12', 500, 26.0, 25.4, 30, 180]],
    PM: [['Carton 24 pcs', 'Cartons', 'pcs', 1200, 300], ['Corrugated Sheet', 'Corrugated Sheets', 'pcs', 5000, 1200], ['Poly Bag', 'Poly Bags', 'pcs', 15000, 4000], ['Bubble Wrap Roll', 'Bubble Wrap', 'Roll', 90, 20], ['Wooden Pallet', 'Pallets', 'pcs', 80, 20], ['Steel Strap', 'Strapping', 'Roll', 60, 15]],
    RM: [['SS Sheet 202', 'kg', 6000, 1500], ['SS Coil 304', 'kg', 4000, 1000], ['Aluminium Circle', 'kg', 3000, 800], ['MS Rod 12mm', 'kg', 5000, 1200], ['Polish Compound', 'kg', 200, 50]],
    TR: [['PB10HW7070', 'DEALER'], ['PB10HW7071', 'WHOLESALER']] },
  general: {
    P: [['Product A 500gm', 24, 12.6, 12.0, 40, 240], ['Product B 1kg', 12, 12.5, 12.0, 40, 180], ['Product C 250gm', 48, 12.6, 12.0, 30, 200, 12, 3.2], ['Product D 5kg', 4, 20.6, 20.0, 20, 90]],
    PM: [['Carton 24 pcs', 'Cartons', 'pcs', 1000, 250], ['Poly Bag', 'Poly Bags', 'pcs', 15000, 4000], ['Pouch 500gm', 'Pouches', 'pcs', 12000, 3000], ['Label', 'Labels', 'pcs', 20000, 5000], ['Tape Roll', 'Strapping / Tape', 'Roll', 200, 50], ['Tray 12 pcs', 'Trays', 'pcs', 800, 200]],
    RM: [['Raw Material A', 'kg', 3000, 800], ['Raw Material B', 'kg', 2000, 500], ['Chemical', 'Ltr', 400, 100], ['Additive', 'kg', 150, 40]],
    TR: [['PB10GM9090', 'DEPOT'], ['PB10GM9091', 'DISTRIBUTOR']] },
};
const LABELS = {
  'food & beverage': 'food', 'dairy': 'dairy', 'edible oil': 'oil', 'bakery & snacks': 'bakery', 'beverages / water': 'water',
  'soap & detergent': 'soap', 'cosmetics & personal care': 'cosmetics', 'paint & lubricants': 'paint', 'agro-chemicals & fertilizer': 'agro',
  'pharma / ayurvedic': 'pharma', 'textile / hosiery': 'textile', 'rice / flour / feed mill': 'mill', 'footwear': 'footwear',
  'plastic & packaging': 'plastic', 'utensils & hardware': 'hardware', 'general manufacturing': 'general',
};
const indId = (c, code) => { const m = code.match(/^demo-([a-z]+)$/); if (m && D[m[1]]) return m[1]; const v = String(c.industry || '').trim().toLowerCase().replace(/\s+/g, ' '); return D[v] ? v : (LABELS[v] || 'food'); };

function call(port, method, path, body, token) {
  return new Promise((resolve) => {
    const data = body ? JSON.stringify(body) : null;
    const req = http.request({ host: '127.0.0.1', port, method, path: '/api' + path, timeout: 15000,
      headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}), ...(data ? { 'content-length': Buffer.byteLength(data) } : {}) } },
      (res) => { let s = ''; res.on('data', (d) => s += d); res.on('end', () => { let j = null; try { j = JSON.parse(s); } catch (_) { j = { raw: s.slice(0, 120) }; } resolve({ status: res.statusCode, json: j }); }); });
    req.on('error', (e) => resolve({ status: 0, json: { error: e.message } }));
    req.on('timeout', () => { req.destroy(); resolve({ status: 0, json: { error: 'timeout' } }); });
    if (data) req.write(data);
    req.end();
  });
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const today = new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10); // IST date

async function seedTenant(code, c) {
  const port = c.port, ind = indId(c, code), d = D[ind];
  const log = (m) => console.log('[seed ' + code + '] ' + m);
  // wait for the tenant process (fresh DB → seeding admin) up to ~90s
  let up = false;
  for (let i = 0; i < 45; i++) { const h = await call(port, 'GET', '/health'); if (h.status === 200) { up = true; break; } await sleep(2000); }
  if (!up) { log('SKIP — tenant not up on ' + port); return 'down'; }
  const lg = await call(port, 'POST', '/auth/login', { email: EMAIL, password: PASS });
  const token = lg.json && lg.json.token;
  if (!token) { log('SKIP — demo login failed (' + JSON.stringify(lg.json).slice(0, 100) + ')'); return 'nologin'; }
  const list = await call(port, 'GET', '/products', null, token);
  const existing = (list.json && list.json.products) || [];
  if (existing.length) { log('already has ' + existing.length + ' products ✓'); return 'ok'; }
  const stat = { products: 0, materials: 0, trucks: 0, receipts: 0, batch: '-', dispatch: '-', errors: [] };
  const err = (what, r) => stat.errors.push(what + ' → ' + (r.status || 0) + ' ' + JSON.stringify(r.json).slice(0, 90));
  for (const p of d.P) {
    const r = await call(port, 'POST', '/products', { name: p[0], weightPerCb: p[2], weightWithoutCb: p[3], bottlesPerCb: p[1], bottlesPerTray: p[6] || 0, trayWeight: p[7] || 0, minStockCb: p[4] }, token);
    r.status < 300 ? stat.products++ : err('product ' + p[0], r);
  }
  for (const m of d.PM) {
    const r = await call(port, 'POST', '/packing/materials', { name: m[0], category: m[1], unit: m[2], stock: m[3], minStock: m[4] }, token);
    r.status < 300 ? stat.materials++ : err('material ' + m[0], r);
  }
  for (const m of d.RM) {
    const r = await call(port, 'POST', '/packing/materials', { name: m[0], category: RAW, unit: m[1], stock: m[2], minStock: m[3] }, token);
    r.status < 300 ? stat.materials++ : err('raw ' + m[0], r);
  }
  for (const t of d.TR) {
    const r = await call(port, 'POST', '/dispatch/trucks', { number: t[0], destination: t[1] }, token);
    r.status < 300 ? stat.trucks++ : err('truck ' + t[0], r);
  }
  const after = await call(port, 'GET', '/products', null, token);
  const prods = (after.json && after.json.products) || [];
  const idOf = (name) => { const p = prods.find((x) => x.name === name); return p ? p.id : null; };
  for (const p of d.P) {
    const pid = idOf(p[0]); if (!pid) continue;
    const r = await call(port, 'POST', '/inventory/receipt', { productId: pid, qtyCb: p[5], qtyTrays: 0, note: 'Opening stock (demo)' }, token);
    r.status < 300 ? stat.receipts++ : err('receipt ' + p[0], r);
  }
  // one completed production run for the first product (Production + run-wise stock + reports get data)
  const p0 = d.P[0], pid0 = idOf(p0[0]);
  let did = 0; // dispatch id → sample invoice below
  if (pid0) {
    const qty = ind === 'mill' ? 200 : 100;
    const cr = await call(port, 'POST', '/production/batches', { productId: pid0, plannedCb: qty, plannedDate: today, remarks: 'Demo run' }, token);
    let bid = cr.json && (cr.json.id || (cr.json.batch && cr.json.batch.id));
    if (!bid && cr.status < 300) {
      const bl = await call(port, 'GET', '/production/batches', null, token);
      const arr = ((bl.json && bl.json.batches) || []).filter((b) => b.status === 'PLANNED').sort((a, b) => b.id - a.id);
      if (arr.length) bid = arr[0].id;
    }
    if (bid) {
      const st = await call(port, 'POST', '/production/batches/' + bid + '/start', {}, token);
      const cp = await call(port, 'POST', '/production/batches/' + bid + '/complete', { producedCb: qty, producedTrays: 0, consumePacking: false }, token);
      stat.batch = (st.status < 300 && cp.status < 300) ? 'ok' : 'fail'; if (stat.batch === 'fail') err('batch complete', cp.status < 300 ? st : cp);
    } else err('batch create', cr);
    const dr = await call(port, 'POST', '/dispatch', { dispatchDate: today, destination: d.TR[0][1], truckNumber: d.TR[0][0], remarks: 'Demo dispatch', items: [{ productId: pid0, cartons: 20, trays: 0 }] }, token);
    stat.dispatch = dr.status < 300 ? 'ok' : 'fail'; if (dr.status >= 300) err('dispatch', dr);
    did = (dr.json && dr.json.id) || 0;
  }
  // billing sample — GST setup, one customer invoice made from the dispatch (half paid by cheque)
  // and one supplier bill for raw material (stock IN, part paid). Skipped quietly when the
  // billing module is not mounted on this core (older VM).
  stat.billing = 'n/a';
  const bset = await call(port, 'GET', '/billing/settings', null, token);
  if (bset.status === 200) {
    stat.billing = 'ok';
    const berr = (what, r) => { stat.billing = 'partial'; err(what, r); };
    const gst = ['paint', 'agro', 'plastic', 'hardware', 'general'].includes(ind) ? 18 : 5;
    const RATE_PER_KG = { water: 18, dairy: 60, mill: 50, oil: 130, food: 110, bakery: 90, soap: 110, cosmetics: 250, paint: 200, agro: 180, pharma: 300, textile: 350, footwear: 250, plastic: 140, hardware: 160, general: 110 };
    await call(port, 'PUT', '/billing/settings', { gstin: '03DEMOF0000A1Z5', legalName: c.name || ('Demo ' + ind), address: 'Focal Point, Ludhiana, Punjab 141010', bankName: 'Demo Bank', accountNo: '000011112222', ifsc: 'DEMO0000001', defaultGstRate: gst, creditDays: 30 }, token);
    for (const p of d.P) { const pid = idOf(p[0]); if (pid) await call(port, 'PUT', '/billing/products/' + pid + '/rates', { gstRate: gst, saleRate: Math.max(10, Math.round(p[2] * (RATE_PER_KG[ind] || 110) / 10) * 10), ratePer: 'pack' }, token); }
    const cust = await call(port, 'POST', '/billing/parties', { name: 'Sample Distributor (Demo)', gstin: '03DEMOC0001A1Z5', address: 'Miller Ganj, Ludhiana, Punjab', creditDays: 30, isCustomer: true }, token);
    const sup = await call(port, 'POST', '/billing/parties', { name: 'Sample Supplier (Demo)', gstin: '06DEMOS0001A1Z5', address: 'Industrial Area, Ambala, Haryana', creditDays: 15, isSupplier: true, isCustomer: false }, token);
    const custId = cust.json && cust.json.id, supId = sup.json && sup.json.id;
    if (!custId) berr('customer party', cust);
    if (!supId) berr('supplier party', sup);
    if (custId && did) {
      const fd = await call(port, 'GET', '/billing/from-dispatch/' + did, null, token);
      const lines = (fd.json && fd.json.lines) || [];
      const inv = await call(port, 'POST', '/billing/invoices', { partyId: custId, invoiceDate: today, dispatchId: did, items: lines }, token);
      if (inv.status < 300 && inv.json && inv.json.id) {
        const pay = await call(port, 'POST', '/billing/invoices/' + inv.json.id + '/payments', { amount: Math.round(inv.json.total / 2), mode: 'cheque', refNo: '004521', bank: 'Demo Bank', paidOn: today, note: 'Part payment (demo)' }, token);
        if (pay.status >= 300) berr('invoice payment', pay);
      } else berr('invoice', inv);
    }
    if (supId) {
      const it = await call(port, 'GET', '/billing/items', null, token);
      const mats = ((it.json && it.json.materials) || []).filter((m) => m.category === RAW).slice(0, 2);
      const items = mats.map((m) => ({ itemType: 'material', itemId: m.id, description: m.name, qty: Math.max(1, Math.round(m.min_stock || 10)), unit: m.unit, rate: m.unit === 'kg' ? 48 : m.unit === 'Ltr' ? 95 : 120, gstRate: gst }));
      if (items.length) {
        const pur = await call(port, 'POST', '/billing/purchases', { billNo: 'SS/2026/1187', billDate: today, receivedDate: today, partyId: supId, addStock: true, remarks: 'Demo supplier bill', items }, token);
        if (pur.status < 300 && pur.json && pur.json.id) {
          const pay = await call(port, 'POST', '/billing/purchases/' + pur.json.id + '/payments', { amount: Math.round(pur.json.total * 0.4), mode: 'cheque', refNo: '117733', bank: 'Demo Bank', paidOn: today, note: 'Advance (demo)' }, token);
          if (pay.status >= 300) berr('purchase payment', pay);
        } else berr('purchase', pur);
      }
    }
  }
  log('[' + ind + '] products ' + stat.products + '/' + d.P.length + ', materials ' + stat.materials + '/' + (d.PM.length + d.RM.length) + ', trucks ' + stat.trucks + ', receipts ' + stat.receipts + ', run ' + stat.batch + ', dispatch ' + stat.dispatch + ', billing ' + stat.billing + (stat.errors.length ? ' | ERR: ' + stat.errors.join('; ') : ' ✓'));
  return stat.errors.length ? 'partial' : 'ok';
}

(async () => {
  const codes = Object.keys(reg.companies || {}).filter((k) => (ONLY ? k === ONLY : (k === 'demo' || k.startsWith('demo-'))));
  const out = {};
  for (const code of codes) { try { out[code] = await seedTenant(code, reg.companies[code]); } catch (e) { out[code] = 'error'; console.log('[seed ' + code + '] ERROR ' + e.message); } }
  const bad = Object.entries(out).filter(([, v]) => v !== 'ok');
  console.log('SEED SUMMARY: ' + codes.length + ' demo tenants, ' + (codes.length - bad.length) + ' ok' + (bad.length ? ', issues: ' + bad.map(([k, v]) => k + '=' + v).join(' ') : ''));
})();
SEED
chmod +x /usr/local/bin/ff-demo-seed.js
node --check /usr/local/bin/ff-demo-seed.js || { echo "SAASDEMO FAIL (seeder syntax)"; exit 1; }
echo "seeder installed ✓ (/usr/local/bin/ff-demo-seed.js)"

# ---------- 3) nightly reset covers demo + demo-* (DB delete → respawn → fresh admin → re-seed) ----------
cat > /usr/local/bin/ff-demo-reset.sh <<'SH'
#!/bin/bash
# FlavorFlow: reset every demo tenant (demo, demo-*) — DB wipe + re-arm admin password → fresh seed on respawn
node - <<'JS'
const fs = require('fs');
const REG = '/opt/flavorflow-saas/data/registry.json';
const reg = JSON.parse(fs.readFileSync(REG, 'utf8'));
for (const [code, c] of Object.entries(reg.companies || {})) {
  if (!(c.demo || code === 'demo' || code.startsWith('demo-'))) continue;
  c.adminEmail = c.adminEmail || 'demo@flavorflow.co.in';
  c.adminName = c.adminName || 'Demo User';
  c.adminPassword = 'Demo@1234';          // seed re-arm (gateway wipes it 10s after boot)
  fs.rmSync('/opt/flavorflow-saas/data/tenant-' + code, { recursive: true, force: true });
  console.log('reset ' + code);
}
fs.writeFileSync(REG, JSON.stringify(reg, null, 2));
JS
systemctl restart flavorflow-saas
sleep 15
/usr/local/bin/ff-demo-seed.js
SH
chmod +x /usr/local/bin/ff-demo-reset.sh
cat > /etc/systemd/system/ff-demo-reset.service <<'UNIT'
[Unit]
Description=FlavorFlow demo tenants nightly reset + re-seed
[Service]
Type=oneshot
ExecStart=/usr/local/bin/ff-demo-reset.sh
UNIT
cat > /etc/systemd/system/ff-demo-reset.timer <<'UNIT'
[Unit]
Description=Nightly FlavorFlow demo reset (3 AM IST)
[Timer]
OnCalendar=*-*-* 21:30:00 UTC
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now ff-demo-reset.timer >/dev/null 2>&1
echo "nightly reset (demo + demo-*) + re-seed ✓"

# ---------- 4) spawn the new tenants now (gateway reads registry on start), verify industry, seed ----------
systemctl restart flavorflow-saas
sleep 12
curl -s -m 8 http://127.0.0.1:4100/api/saas/health && echo ""
node - <<'JS'
const cp = require('child_process');
const reg = require('/opt/flavorflow-saas/data/registry.json');
let ok = 0, bad = 0;
for (const [code, c] of Object.entries(reg.companies || {})) {
  if (!code.startsWith('demo')) continue;
  let out = '';
  try { out = cp.execSync('curl -s -m 6 http://127.0.0.1:' + c.port + '/api/settings/company').toString().trim(); } catch (e) { out = 'ERR'; }
  const ind = (out.match(/"industry":"([^"]*)"/) || [])[1] || '';
  const good = /"industry"/.test(out);
  good ? ok++ : bad++;
  console.log((good ? 'OK   ' : 'FAIL ') + code.padEnd(16) + ' [' + (c.industry || '-') + '] -> ' + (ind || out.slice(0, 80)));
}
console.log('demo tenants: ' + ok + ' ok, ' + bad + ' fail' + (bad ? '  (FAIL = /api/settings/company route nahi / tenant haale boot ho reha — 20s baad dubara: curl -s http://127.0.0.1:<port>/api/settings/company)' : ''));
JS
/usr/local/bin/ff-demo-seed.js
echo ""
echo "SAASDEMO DONE ✓  — app login: Company code demo-<industry> (demo-mill, demo-dairy, demo-textile, demo-pharma, …)"
echo "                   Email demo@flavorflow.co.in   Password Demo@1234   (nightly reset + re-seed 3 AM IST)"
