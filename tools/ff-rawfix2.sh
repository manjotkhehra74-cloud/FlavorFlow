#!/usr/bin/env bash
# FlavorFlow: recipe corrections per the factory Excel sheet (50-batch page):
#   Soya Sauce 740gm — 300kg batch:
#     Molasses 86  → 105
#     Acetic   1.5 → 3.0
#     Coriander 0.21 → 0.021 (Word doc had a 10× typo)
#   Soya tracking: raw SOYABEAN (1.3 kg/batch) instead of Extract (26 kg/batch)
#     — material renamed to "Soyabean", both soya recipes point to it @1.3.
# Idempotent — safe to run twice.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-RAWFIX2 $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-rawfix2-$TS" 2>/dev/null
echo "DB BACKUP: /opt/flavorflow/backups/erp.db.bak-rawfix2-$TS"

node - <<'JS'
const db = require('/opt/flavorflow/server/db');

/* 1) rename material: Soya Bean Extract → Soyabean (raw, purchased) */
const ext = db.prepare("SELECT id, name FROM packing_materials WHERE LOWER(name) IN ('soya bean extract','soyabean')").all();
if (!ext.length) { console.log('Soya material nahi mili — pehla ff-rawfix chalao'); process.exit(2); }
const soy = ext.find((m) => m.name.toLowerCase() === 'soyabean') || ext[0];
if (soy.name !== 'Soyabean') {
  db.prepare("UPDATE packing_materials SET name = 'Soyabean' WHERE id = ?").run(soy.id);
  console.log('MATERIAL RENAMED: "' + soy.name + '" → "Soyabean" ✓');
} else console.log('MATERIAL: already "Soyabean" — skip');

function setLine(recipeLike, matName, qty) {
  const rec = db.prepare("SELECT id, name FROM recipes WHERE name LIKE ?").get(recipeLike);
  if (!rec) { console.log('RECIPE NOT FOUND: ' + recipeLike); return; }
  const mat = db.prepare("SELECT id FROM packing_materials WHERE LOWER(name) = LOWER(?)").get(matName);
  if (!mat) { console.log('MATERIAL NOT FOUND: ' + matName); return; }
  const line = db.prepare('SELECT id, qty_per_batch FROM recipe_lines WHERE recipe_id = ? AND material_id = ?').get(rec.id, mat.id);
  if (!line) { console.log('LINE MISSING: ' + rec.name + ' / ' + matName + ' — adding'); db.prepare('INSERT INTO recipe_lines (recipe_id, material_id, qty_per_batch) VALUES (?,?,?)').run(rec.id, mat.id, qty); return; }
  if (Math.abs(line.qty_per_batch - qty) < 1e-9) { console.log('OK (already ' + qty + '): ' + rec.name + ' / ' + matName); return; }
  db.prepare('UPDATE recipe_lines SET qty_per_batch = ? WHERE id = ?').run(qty, line.id);
  console.log('UPDATED: ' + rec.name + ' / ' + matName + ': ' + line.qty_per_batch + ' → ' + qty + ' ✓');
}

/* 2) Soya 740gm corrections (Excel sheet ÷ 50) */
setLine('Soya Sauce 740gm%', 'Molasses', 105);
setLine('Soya Sauce 740gm%', 'Acetic Acid', 3.0);
setLine('Soya Sauce 740gm%', 'Coriander Oleoresin', 0.021);
setLine('Soya Sauce 740gm%', 'Soyabean', 1.3);

/* 3) Dark Soya 250gm: raw soyabean 1.3 (was Extract 26) — baki Word figures */
setLine('Dark Soya 250gm%', 'Soyabean', 1.3);

console.log('RAWFIX2 DONE ✓ (koi service restart di lod nahi — data live hai)');
JS
echo ""
echo "App ch Recipe Consumption dubara kholo — preview hun Excel de hisaab naal aayega:"
echo "  50 batches → Molasses 5250, Soyabean 65, Salt 2425, Dhaniya 1.05, Acetic 150 ..."
