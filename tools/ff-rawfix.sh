#!/usr/bin/env bash
# FlavorFlow: RAW MATERIAL recipes + auto-consumption by total production qty.
#  - Adds raw materials (category "Raw Material") — water intentionally EXCLUDED
#  - Creates recipes: Soya 740gm (300kg), Soya 250gm (300kg),
#    White Vinegar (2700 Ltr), Brown Vinegar (2700 Ltr)
#  - New routes on the packing router:
#      GET  /api/packing/recipes           → recipes with their lines
#      POST /api/packing/recipe-consume    → { recipeId, totalQty, remark }
#        batches = totalQty / batch_size (fractional allowed)
#        every recipe line consumes qty × batches from stock (ledger entries)
# Idempotent — safe to run twice.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-RAWFIX $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-rawfix-$TS" 2>/dev/null
echo "DB BACKUP: /opt/flavorflow/backups/erp.db.bak-rawfix-$TS"

node - <<'JS'
const db = require('/opt/flavorflow/server/db');

/* ---------- 1) tables ---------- */
db.exec(`
CREATE TABLE IF NOT EXISTS recipes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  batch_size REAL NOT NULL,
  batch_unit TEXT NOT NULL DEFAULT 'kg'
);
CREATE TABLE IF NOT EXISTS recipe_lines (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  material_id INTEGER NOT NULL REFERENCES packing_materials(id),
  qty_per_batch REAL NOT NULL
);
`);
console.log('TABLES OK');

/* ---------- 2) raw materials (water excluded) ---------- */
const RAW = [
  ['Molasses', 'kg'],
  ['Soya Bean Extract', 'kg'],
  ['White Salt', 'kg'],
  ['Coriander Oleoresin', 'kg'],
  ['Garlic Oleoresin', 'kg'],
  ['Cinnamon Oleoresin', 'kg'],
  ['Black Salt', 'kg'],
  ['Turmeric Powder', 'kg'],
  ['Potassium Iodate', 'kg'],
  ['Caramel Colour (E150a)', 'kg'],
  ['Caramel Colour (E150c)', 'kg'],
  ['Acetic Acid', 'Ltr'],
];
const now = new Date().toISOString();
const findMat = db.prepare("SELECT id FROM packing_materials WHERE LOWER(name) = LOWER(?)");
// Build the INSERT dynamically so every NOT NULL column without a default
// (e.g. created_at) gets a sensible value — schema-proof.
const cols = db.prepare("PRAGMA table_info(packing_materials)").all();
const matId = {};
function insertMaterial(name, unit) {
  const vals = {};
  for (const c of cols) {
    if (c.pk) continue;
    switch (c.name) {
      case 'name': vals[c.name] = name; break;
      case 'category': vals[c.name] = 'Raw Material'; break;
      case 'unit': vals[c.name] = unit; break;
      case 'stock': vals[c.name] = 0; break;
      case 'min_stock': vals[c.name] = 0; break;
      default:
        if (c.notnull && c.dflt_value === null) {
          vals[c.name] = /INT|REAL|NUM/i.test(c.type || '') ? 0 : now;
        }
    }
  }
  const names = Object.keys(vals);
  db.prepare(`INSERT INTO packing_materials (${names.join(',')}) VALUES (${names.map(() => '?').join(',')})`).run(...names.map((k) => vals[k]));
}
for (const [name, unit] of RAW) {
  let row = findMat.get(name);
  if (!row) { insertMaterial(name, unit); row = findMat.get(name); console.log('RAW ADDED: ' + name); }
  matId[name] = row.id;
}

/* ---------- 3) recipes (from the factory recipe sheet) ---------- */
const RECIPES = [
  ['Soya Sauce 740gm — 300kg batch', 300, 'kg', [
    ['Molasses', 86], ['Soya Bean Extract', 26], ['White Salt', 48.5],
    ['Coriander Oleoresin', 0.21], ['Garlic Oleoresin', 0.021], ['Cinnamon Oleoresin', 0.008],
    ['Turmeric Powder', 0.065], ['Potassium Iodate', 0.27],
    ['Caramel Colour (E150a)', 19.5], ['Caramel Colour (E150c)', 0.1], ['Acetic Acid', 1.5],
  ]],
  ['Dark Soya 250gm — 300kg batch', 300, 'kg', [
    ['Molasses', 106], ['Soya Bean Extract', 26], ['White Salt', 41],
    ['Coriander Oleoresin', 0.025], ['Garlic Oleoresin', 0.025], ['Cinnamon Oleoresin', 0.01],
    ['Black Salt', 10], ['Turmeric Powder', 0.07], ['Potassium Iodate', 0.27],
    ['Caramel Colour (E150a)', 19.5], ['Caramel Colour (E150c)', 0.1], ['Acetic Acid', 1.9],
  ]],
  ['White Vinegar — 2700 Ltr batch', 2700, 'Ltr', [
    ['Acetic Acid', 121.5],
  ]],
  ['Brown Vinegar — 2700 Ltr batch', 2700, 'Ltr', [
    ['Caramel Colour (E150c)', 5.7], ['Acetic Acid', 121.5],
  ]],
];
const findRec = db.prepare('SELECT id FROM recipes WHERE name = ?');
const insRec = db.prepare('INSERT INTO recipes (name, batch_size, batch_unit) VALUES (?,?,?)');
const insLine = db.prepare('INSERT INTO recipe_lines (recipe_id, material_id, qty_per_batch) VALUES (?,?,?)');
for (const [name, size, unit, lines] of RECIPES) {
  if (findRec.get(name)) { console.log('RECIPE EXISTS: ' + name + ' — skip'); continue; }
  const rid = insRec.run(name, size, unit).lastInsertRowid;
  for (const [mat, q] of lines) insLine.run(rid, matId[mat], q);
  console.log('RECIPE ADDED: ' + name + ' (' + lines.length + ' materials)');
}

console.log('DATA OK');
JS

# ---------- 4) routes ----------
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/packing.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('/recipe-consume')) { console.log('ROUTES: already present — skip'); process.exit(0); }
const bak = f + '.bak-rawfix-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);

const CODE = `/** ff-rawfix: raw-material recipes + auto consumption by total production qty. */
router.get('/recipes', requirePerm('packing.view'), (req, res) => {
  const recipes = db.prepare('SELECT * FROM recipes ORDER BY id').all();
  for (const r of recipes) {
    r.lines = db.prepare(
      'SELECT l.qty_per_batch, m.id material_id, m.name, m.unit, m.stock FROM recipe_lines l JOIN packing_materials m ON m.id = l.material_id WHERE l.recipe_id = ? ORDER BY l.id'
    ).all(r.id);
  }
  res.json({ recipes });
});

router.post('/recipe-consume', requirePerm('packing.manage'), (req, res) => {
  const recipeId = Number((req.body || {}).recipeId);
  const totalQty = Number((req.body || {}).totalQty);
  const remark = String((req.body || {}).remark || '').trim();
  const recipe = db.prepare('SELECT * FROM recipes WHERE id = ?').get(recipeId);
  if (!recipe) throw bad('Recipe not found.', 404);
  if (!(totalQty > 0)) throw bad('Enter the total production quantity (e.g. 15000).');
  const batches = totalQty / recipe.batch_size;
  const lines = db.prepare(
    'SELECT l.qty_per_batch, m.id material_id, m.name, m.unit, m.stock, m.min_stock FROM recipe_lines l JOIN packing_materials m ON m.id = l.material_id WHERE l.recipe_id = ?'
  ).all(recipeId);
  if (!lines.length) throw bad('Recipe has no materials.');
  const nIso = nowIso();
  const today = dateOnly(nIso);
  const warnings = [];
  const consumed = [];
  const result = tx(db, () => {
    const upd = db.prepare('UPDATE packing_materials SET stock = stock - ? WHERE id = ?');
    const ins = db.prepare(
      "INSERT INTO packing_txns (material_id, txn_type, qty, txn_date, reference, remark, created_by, created_at) VALUES (?, 'CONSUMED', ?, ?, ?, ?, ?, ?)"
    );
    const ref = recipe.name + ' × ' + (Math.round(batches * 100) / 100) + ' batches (' + totalQty + ' ' + recipe.batch_unit + ')';
    for (const l of lines) {
      const q = Math.round(l.qty_per_batch * batches * 1000) / 1000;
      if (q <= 0) continue;
      upd.run(q, l.material_id);
      ins.run(l.material_id, q, today, ref, remark, req.user.id, nIso);
      consumed.push({ name: l.name, qty: q, unit: l.unit });
      const ns = l.stock - q;
      if (ns < 0) warnings.push(l.name + ': stock went negative (' + (Math.round(ns * 100) / 100) + ') — receive stock');
      else if (ns < l.min_stock) warnings.push(l.name + ': below minimum');
      checkPackingLow(db, l.material_id);
    }
    audit(db, req.user, 'CONSUME', 'packing', recipeId, 'Recipe consumption: ' + ref);
    return { batches: Math.round(batches * 100) / 100 };
  });
  res.json({ ok: true, batches: result.batches, consumed, warnings });
});

`;
const anchor = 'module.exports = router;';
src = src.replace(anchor, CODE + anchor);
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED'); process.exit(3); }
JS
RC=$?
if [ $RC -ne 0 ]; then echo "ROUTE PATCH FAIL"; exit 1; fi

systemctl restart flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH FAIL"
echo "RAWFIX VERIFIED ✓ — Raw Material category + 4 recipes + recipe-consume route live"
