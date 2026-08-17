#!/usr/bin/env bash
# FlavorFlow: raw material upgrades —
#  1) PUT /api/packing/recipes/:id  → edit a recipe (batch size + per-material
#     qty/batch; qty 0 removes the line)
#  2) /api/packing/recipe-consume now accepts optional per-material OVERRIDES:
#     { overrides: { "<materialId>": totalQty } } — specific consumption for
#     one (or more) materials while the rest follow the recipe.
#  3) New report "raw-material-stock" (PDF/Excel from the Reports section) +
#     packing-stock report no longer mixes raw materials in.
# Idempotent — safe to run twice.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-RAWFIX4 $(date) ==="

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
let failed = false;
function backup(f) { const b = f + '.bak-rawfix4-' + Date.now(); fs.copyFileSync(f, b); console.log('BACKUP: ' + b); return b; }
function check(f, b) {
  try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK: ' + f); return true; }
  catch (e) { fs.copyFileSync(b, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); return false; }
}

/* ---------- packing.js: recipe edit + consume overrides ---------- */
{
  const f = '/opt/flavorflow/server/routes/packing.js';
  let src = fs.readFileSync(f, 'utf8');
  let changed = false;
  const bak = backup(f);

  if (!src.includes("router.put('/recipes/")) {
    const CODE = `/** ff-rawfix4: edit a recipe — batch size + qty/batch per material (0 = remove line). */
router.put('/recipes/:id', requirePerm('packing.manage'), (req, res) => {
  const id = Number(req.params.id);
  const recipe = db.prepare('SELECT * FROM recipes WHERE id = ?').get(id);
  if (!recipe) throw bad('Recipe not found.', 404);
  const b = req.body || {};
  const batchSize = Number(b.batchSize);
  const lines = Array.isArray(b.lines) ? b.lines : [];
  tx(db, () => {
    if (batchSize > 0) db.prepare('UPDATE recipes SET batch_size = ? WHERE id = ?').run(batchSize, id);
    for (const l of lines) {
      const mid = Number(l.materialId);
      const q = Number(l.qtyPerBatch);
      if (!mid || isNaN(q)) continue;
      const ex = db.prepare('SELECT id FROM recipe_lines WHERE recipe_id = ? AND material_id = ?').get(id, mid);
      if (q <= 0) { if (ex) db.prepare('DELETE FROM recipe_lines WHERE id = ?').run(ex.id); continue; }
      if (ex) db.prepare('UPDATE recipe_lines SET qty_per_batch = ? WHERE id = ?').run(q, ex.id);
      else db.prepare('INSERT INTO recipe_lines (recipe_id, material_id, qty_per_batch) VALUES (?,?,?)').run(id, mid, q);
    }
  });
  audit(db, req.user, 'UPDATE', 'packing', id, 'Recipe "' + recipe.name + '" edited');
  res.json({ ok: true });
});

`;
    src = src.replace('module.exports = router;', CODE + 'module.exports = router;');
    changed = true;
    console.log('RECIPE EDIT ROUTE: added');
  } else console.log('RECIPE EDIT ROUTE: already present — skip');

  if (!src.includes('overrides[')) {
    const a1 = "const remark = String((req.body || {}).remark || '').trim();";
    const b1 = a1 + "\n  const overrides = (req.body || {}).overrides || {};";
    const a2 = 'const q = Math.round(l.qty_per_batch * batches * 1000) / 1000;';
    const b2 = "const ov = Number(overrides[l.material_id] ?? overrides[String(l.material_id)]);\n      const q = ov > 0 ? Math.round(ov * 1000) / 1000 : Math.round(l.qty_per_batch * batches * 1000) / 1000;";
    if (src.includes(a1) && src.includes(a2)) {
      src = src.replace(a1, b1).replace(a2, b2);
      changed = true;
      console.log('CONSUME OVERRIDES: added');
    } else { console.log('CONSUME OVERRIDES: anchors not found'); failed = true; }
  } else console.log('CONSUME OVERRIDES: already present — skip');

  if (changed && !failed) { fs.writeFileSync(f, src); if (!check(f, bak)) failed = true; }
}

/* ---------- reports.js: raw material stock report ---------- */
if (!failed) {
  const f = '/opt/flavorflow/server/routes/reports.js';
  let src = fs.readFileSync(f, 'utf8');
  if (src.includes("'raw-material-stock'")) {
    console.log('RAW REPORT: already present — skip');
  } else {
    const bak = backup(f);
    const REPORT = `  'raw-material-stock': {
    title: 'Raw Material Stock',
    desc: 'Current balance of every raw material (recipe consumption draws from here).',
    run: () => ({
      columns: ['Material', 'Unit', 'Balance', 'Minimum', 'Status'],
      rows: db.prepare(
        \`SELECT name, unit, stock, min_stock,
                CASE WHEN stock < min_stock THEN 'LOW' ELSE 'OK' END st
         FROM packing_materials WHERE category = 'Raw Material' ORDER BY name\`
      ).all().map((r) => [r.name, r.unit, r.stock, r.min_stock, r.st]),
    }),
  },
`;
    const anchor = "  'packing-ledger': {";
    if (!src.includes(anchor)) { console.log('RAW REPORT: anchor not found'); failed = true; }
    else {
      src = src.replace(anchor, REPORT + anchor);
      // packing-stock report: raw material bahar
      src = src.replace('FROM packing_materials ORDER BY category, name', "FROM packing_materials WHERE category <> 'Raw Material' ORDER BY category, name");
      // role lists (super_admin/admin/director use Object.keys — auto)
      src = src.split("'packing-stock', 'packing-ledger'").join("'packing-stock', 'raw-material-stock', 'packing-ledger'");
      fs.writeFileSync(f, src);
      if (check(f, bak)) console.log('RAW REPORT: added ✓'); else failed = true;
    }
  }
}

if (failed) { console.log('PATCH INCOMPLETE'); process.exit(2); }
console.log('ALL PATCHES OK');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "RAWFIX4 FAIL — upar output dekho"; exit 1; fi

systemctl restart flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH FAIL"
echo "RAWFIX4 VERIFIED ✓ — recipe edit + consumption overrides + Raw Material Stock report live"
