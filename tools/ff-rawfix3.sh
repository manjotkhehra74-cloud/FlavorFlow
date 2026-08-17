#!/usr/bin/env bash
# FlavorFlow: Dark Soya 250gm recipe corrections per the factory Excel
# ("Batch 220" column, 50-batch page ÷ 50):
#   Molasses 106 → 110, Soyabean 1.3 → 4, Acetic Acid 1.9 → 3
# Idempotent — safe to run twice.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-RAWFIX3 $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-rawfix3-$TS" 2>/dev/null
echo "DB BACKUP: /opt/flavorflow/backups/erp.db.bak-rawfix3-$TS"

node - <<'JS'
const db = require('/opt/flavorflow/server/db');

function setLine(recipeLike, matName, qty) {
  const rec = db.prepare("SELECT id, name FROM recipes WHERE name LIKE ?").get(recipeLike);
  if (!rec) { console.log('RECIPE NOT FOUND: ' + recipeLike); return; }
  const mat = db.prepare("SELECT id FROM packing_materials WHERE LOWER(name) = LOWER(?)").get(matName);
  if (!mat) { console.log('MATERIAL NOT FOUND: ' + matName); return; }
  const line = db.prepare('SELECT id, qty_per_batch FROM recipe_lines WHERE recipe_id = ? AND material_id = ?').get(rec.id, mat.id);
  if (!line) { console.log('LINE MISSING — adding: ' + rec.name + ' / ' + matName + ' = ' + qty); db.prepare('INSERT INTO recipe_lines (recipe_id, material_id, qty_per_batch) VALUES (?,?,?)').run(rec.id, mat.id, qty); return; }
  if (Math.abs(line.qty_per_batch - qty) < 1e-9) { console.log('OK (already ' + qty + '): ' + rec.name + ' / ' + matName); return; }
  db.prepare('UPDATE recipe_lines SET qty_per_batch = ? WHERE id = ?').run(qty, line.id);
  console.log('UPDATED: ' + rec.name + ' / ' + matName + ': ' + line.qty_per_batch + ' → ' + qty + ' ✓');
}

setLine('Dark Soya 250gm%', 'Molasses', 110);
setLine('Dark Soya 250gm%', 'Soyabean', 4);
setLine('Dark Soya 250gm%', 'Acetic Acid', 3);

console.log('RAWFIX3 DONE ✓ (koi restart di lod nahi)');
JS
echo ""
echo "Verify: Recipe Consumption → Dark Soya 250gm → 15000 → preview:"
echo "  Molasses 5500 · Soyabean 200 · Salt 2050 · Acetic 150 · Black Salt 500 ..."
