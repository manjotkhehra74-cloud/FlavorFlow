#!/usr/bin/env bash
# FlavorFlow FIX (data-only, no code changes):
#  1) Category typo: "Tray Cap (…)" materials sitting in category "Trays"
#     move to category "Tray Caps".
#  2) MERGE shared 4.7 / 4 Ltr packing materials (jerry cans, cartons, caps —
#     everything EXCEPT Labels): Soya 4.7 & Vinegar 4 Ltr use the same
#     physical material, so both products' BOMs point to ONE stock item.
#     Stocks are summed, BOM lines & ledger history re-pointed, duplicate
#     removed, kept item renamed to "… 4.7/4 Ltr".
# Idempotent — safe to run twice (second run finds nothing to do).
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-PACKFIX $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-packfix-$TS" 2>/dev/null
echo "DB BACKUP: /opt/flavorflow/backups/erp.db.bak-packfix-$TS"

node - <<'JS'
const db = require('/opt/flavorflow/server/db');

/* ---------- 1) category typo: Tray Cap rows must be in "Tray Caps" ---------- */
const fixed = db.prepare("UPDATE packing_materials SET category = 'Tray Caps' WHERE name LIKE 'Tray Cap%' AND category <> 'Tray Caps'").run().changes;
console.log(fixed > 0 ? `CATEGORY FIX: ${fixed} material(s) moved to "Tray Caps" ✓` : 'CATEGORY FIX: already correct — skip');

/* ---------- 2) merge shared 4.7 / 4 Ltr materials (except Labels) ---------- */
// normalize: any "4.7" / "4 Ltr" / "4Ltr" / "4.0" size token becomes "§"
function norm(name) {
  return name.toUpperCase()
    .replace(/4\.7\s*\/\s*4\s*L(TR)?\.?/g, '§') // already merged form
    .replace(/\b4\.7\b/g, '§')
    .replace(/\b4\.0\b/g, '§')
    .replace(/\b4\s*LTR\b/g, '§')
    .replace(/\b4\s*L\b/g, '§')
    .replace(/\s+/g, ' ')
    .trim();
}

const mats = db.prepare("SELECT * FROM packing_materials").all();
const groups = {};
for (const m of mats) {
  if ((m.category || '') === 'Labels') continue;          // labels stay separate
  if (/^label/i.test(m.name)) continue;                    // extra safety
  const key = norm(m.name);
  if (!key.includes('§')) continue;                        // only 4.7/4L-size items
  (groups[key + '|' + m.category + '|' + m.unit] ||= []).push(m);
}

let merged = 0;
for (const [key, list] of Object.entries(groups)) {
  if (list.length < 2) continue;
  list.sort((a, b) => a.id - b.id);
  const keep = list[0];
  const dupes = list.slice(1);
  const totalStock = list.reduce((s, m) => s + (m.stock || 0), 0);
  const maxMin = Math.max(...list.map((m) => m.min_stock || 0));
  const newName = keep.name
    .replace(/4\.7\s*\/\s*4\s*L(tr)?\.?/i, '4.7/4 Ltr')
    .replace(/\b4\.7\b/, '4.7/4 Ltr')
    .replace(/\b4\.0\b/, '4.7/4 Ltr')
    .replace(/\b4\s*Ltr\b/i, '4.7/4 Ltr')
    .replace(/\b4\s*L\b/i, '4.7/4 Ltr');

  db.exec('BEGIN');
  try {
    for (const d of dupes) {
      // re-point BOM lines; if a product already has a BOM line for `keep`, add quantities instead
      for (const row of db.prepare('SELECT * FROM packing_bom WHERE material_id = ?').all(d.id)) {
        const existing = db.prepare('SELECT * FROM packing_bom WHERE product_id = ? AND material_id = ?').get(row.product_id, keep.id);
        if (existing) {
          db.prepare('UPDATE packing_bom SET qty_per_cb = qty_per_cb + ?, qty_per_tray = qty_per_tray + ? WHERE product_id = ? AND material_id = ?')
            .run(row.qty_per_cb, row.qty_per_tray, row.product_id, keep.id);
          db.prepare('DELETE FROM packing_bom WHERE product_id = ? AND material_id = ?').run(row.product_id, d.id);
        } else {
          db.prepare('UPDATE packing_bom SET material_id = ? WHERE product_id = ? AND material_id = ?').run(keep.id, row.product_id, d.id);
        }
      }
      // keep full ledger history under the surviving material
      db.prepare('UPDATE packing_txns SET material_id = ? WHERE material_id = ?').run(keep.id, d.id);
      db.prepare('DELETE FROM packing_materials WHERE id = ?').run(d.id);
    }
    db.prepare('UPDATE packing_materials SET name = ?, stock = ?, min_stock = ? WHERE id = ?').run(newName, totalStock, maxMin, keep.id);
    db.exec('COMMIT');
    merged++;
    console.log(`MERGED: ${list.map((m) => `"${m.name}" (${m.stock})`).join(' + ')} → "${newName}" (stock ${totalStock}) ✓`);
  } catch (e) {
    db.exec('ROLLBACK');
    console.log(`MERGE FAIL for ${key}: ${e.message}`);
  }
}
if (merged === 0) console.log('MERGE: koi 4.7/4Ltr duplicate pair nahi mili (ya pehla hi merged) — skip');
console.log('PACKFIX DONE ✓');
JS

echo ""
echo "NOTE: service restart di LOD NAHI — data changes turant live ne."
echo "App ch check karo: Packing Material → 4.7/4 Ltr items ik-ik vaar dikhnge,"
echo "te dona products (Soya 4.7 / Vin 4 Ltr) di production ikko stock vicho consume karegi."
