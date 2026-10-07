#!/usr/bin/env bash
# FlavorFlow — 04/10/2026 opening/closing stock reconciliation.
#
# The supplied handwritten values are the closing balances at the end of
# 2026-10-04. The default mode is READ-ONLY. It prints the matched material
# rows, completed production after 04/10, recorded consumption after 04/10,
# and the final balance that would be written.
#
# Apply only after reviewing the dry-run output:
#   bash ff-opening-stock.sh --apply
# or remotely:
#   curl -fsSL RAW_URL | sudo bash -s -- --apply
set -euo pipefail

DB="${FF_DB:-/opt/flavorflow/server/data/erp.db}"
SERVER_DIR="${FF_SERVER_DIR:-/opt/flavorflow/server}"
CLOSING_DATE="${FF_CLOSING_DATE:-2026-10-04}"
APPLY=0
if [[ "${1:-}" == "--apply" || "${FF_APPLY:-0}" == "1" ]]; then APPLY=1; fi

[ -f "$DB" ] || { echo "FATAL: database not found: $DB"; exit 1; }
command -v node >/dev/null || { echo "FATAL: node is required"; exit 1; }

BACKUP_DIR="${FF_BACKUP_DIR:-/opt/flavorflow/backups}"
TS=$(date +%Y%m%d-%H%M%S)
if (( APPLY )); then
  mkdir -p "$BACKUP_DIR"
  cp -a "$DB" "$BACKUP_DIR/erp.db.bak-opening-stock-$TS"
  echo "DB BACKUP: $BACKUP_DIR/erp.db.bak-opening-stock-$TS"
  systemctl stop flavorflow || true
  sleep 1
fi

export FF_DB="$DB" CLOSING_DATE APPLY TS SERVER_DIR
node <<'JS'
'use strict';
let DatabaseSync;
try { DatabaseSync = require('/opt/flavorflow/server/sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) try { DatabaseSync = require('node:sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) { console.error('FATAL: SQLite wrapper not available'); process.exit(1); }

const db = new DatabaseSync(process.env.FF_DB);
const closingDate = process.env.CLOSING_DATE;
const apply = process.env.APPLY === '1';
const n = (v) => Number(v) || 0;
const text = (v) => String(v ?? '').trim();
const norm = (v) => text(v).toLowerCase().replace(/[^a-z0-9]+/g, ' ').replace(/\s+/g, ' ').trim();
const cols = (table) => db.prepare('PRAGMA table_info(' + table + ')').all().map((r) => String(r.name));
const tables = new Set(db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map((r) => String(r.name)));
const hasTable = (t) => tables.has(t);
const hasCol = (t, c) => hasTable(t) && cols(t).includes(c);
const q = (sql, args = []) => db.prepare(sql).all(...args);
const one = (sql, args = []) => db.prepare(sql).get(...args);

if (!hasTable('packing_materials')) { console.error('FATAL: packing_materials table missing'); process.exit(1); }
const materialCols = cols('packing_materials');
if (!materialCols.includes('id') || !materialCols.includes('name') || !materialCols.includes('stock')) {
  console.error('FATAL: packing_materials must contain id, name, stock'); process.exit(1);
}

const targets = [
  // Packing materials. The matcher is deliberately narrow and refuses an
  // ambiguous match instead of changing the wrong material.
  ['Shrink Soya 740g', /shrink .*soya .*740/, 418903, 'packing'],
  ['Shrink White Vinegar 610ml', /shrink .*white vinegar .*610/, 436562, 'packing'],
  ['Shrink Brown Vinegar 610ml', /shrink .*brown vinegar .*610/, 15265, 'packing'],
  ['Label Soya 1.3kg', /label .*soya .*1 3/, 30155, 'packing'],
  ['Label White Vinegar 1 Ltr', /label .*white vinegar .*1 l/, 67548, 'packing'],
  ['Label Dark Soya 220g', /label .*dark soya .*220/, 10023, 'packing'],
  ['Label White Vinegar 180ml', /label .*white vinegar .*180/, 158172, 'packing'],
  ['Hologram 65 x 65 — shared Vinegar 180 / Dark Soya 220', /hologram .*65 .*65/, 171038, 'packing'],
  ['Label White Vinegar 4 Ltr', /label .*white vinegar .*4 l/, 4092, 'packing'],
  ['Label Dark Soya 4.7kg', /label .*dark soya .*4 7/, 4200, 'packing'],
  ['Cap Orange', /cap orange/, 1195479, 'packing'],
  ['Cap Purple', /cap purple/, 184785, 'packing'],
  ['Cap Red 1.3kg', /cap red .*1 3/, 22518, 'packing'],
  ['Cap Red Plastic 4gm', /cap red plastic .*4/, 135615, 'packing'],
  ['Plug No 9', /plug .*9/, 422444, 'packing'],
  ['CB 180ml / 220g', /cb .*180 .*220/, 5151, 'packing'],
  ['CB 610ml / 740gm', /cb .*610 .*740/, 7812, 'packing'],
  ['CB 1.3kg', /cb .*1 3/, 695, 'packing'],
  ['Crown Cork', /crown cork/, 113050, 'packing'],
  ['Jerry Can 4Ltr / 4.7kg', /jerry can .*4/, 8016, 'packing'],

  // Raw materials. These quantities were confirmed as kg by the user.
  ['Soyabean', /soya bean|soyabean/, 446.30, 'raw'],
  ['Haldi Powder', /haldi powder|turmeric powder/, 35.50, 'raw'],
  ['Potassium Sorbate', /potassium sorbate|potasium sorbate/, 277.46, 'raw'],
  ['Citric Acid', /citric acid/, 623.20, 'raw'],
  ['Ascorbic Acid', /ascorbic acid/, 30.80, 'raw'],
  ['Sodium Benzoate', /sodium benzoate/, 1.16, 'raw'],
  ['Oleoresin Garlic', /oleoresin garlic/, 29.49, 'raw'],
  ['Oleoresin Cinnamon', /oleoresin cinnamon/, 28.48, 'raw'],
  ['Oleoresin Coriander', /oleoresin coriander/, 38.79, 'raw'],
  ['Caramel Colour E150A', /caramel colour e 150 a|caramel colour e150a/, 4757.50, 'raw'],
  ['Black Salt', /black salt/, 100, 'raw'],
];

const all = q('SELECT id, name, category, unit, COALESCE(stock, 0) stock FROM packing_materials ORDER BY id');
const matched = [];
let fatal = false;
for (const [label, matcher, desired, kind] of targets) {
  const candidates = all.filter((m) => {
    const category = norm(m.category);
    if (kind === 'raw' && category !== 'raw material') return false;
    if (kind === 'packing' && category === 'raw material') return false;
    return matcher.test(norm(m.name));
  });
  if (candidates.length !== 1) {
    console.log(`TARGET ${label}: ${candidates.length === 0 ? 'NOT FOUND' : 'AMBIGUOUS'} ${candidates.map((m) => `[#${m.id} ${m.name} (${m.category})]`).join(' ')}`);
    fatal = true;
    continue;
  }
  const m = candidates[0];
  matched.push({ label, desired: Number(desired), kind, ...m });
  console.log(`MATCH ${label} -> #${m.id} ${m.name} | current=${m.stock} ${m.unit || ''} | 04/10 closing=${desired} ${m.unit || ''}`);
}
if (fatal) {
  console.log('STOPPED: every target must match exactly one material. No database rows changed.');
  db.close(); process.exit(2);
}

// Show production completed after the handwritten closing date. This is
// informational and also helps verify the consumption figures before apply.
if (hasTable('batches')) {
  const bc = cols('batches');
  if (bc.includes('planned_date') && bc.includes('product_id') && bc.includes('produced_cb')) {
    console.log(`\nCOMPLETED PRODUCTION AFTER ${closingDate}:`);
    const dateCol = bc.includes('production_date') ? 'production_date' : 'planned_date';
    const nameCol = bc.includes('product_name') ? 'product_name' : null;
    const rows = q(`SELECT b.${dateCol} date, b.product_id product_id, ${nameCol ? `b.${nameCol}` : 'NULL'} product_name, COALESCE(b.produced_cb,0) produced_cb${bc.includes('produced_trays') ? ', COALESCE(b.produced_trays,0) produced_trays' : ''} FROM batches b WHERE UPPER(COALESCE(b.status,''))='COMPLETED' AND b.${dateCol} > ? ORDER BY b.${dateCol}, b.id`, [closingDate]);
    if (!rows.length) console.log('  none');
    for (const r of rows) console.log(`  ${r.date} | ${r.product_name || ('product #' + r.product_id)} | CB ${r.produced_cb}${r.produced_trays != null ? ' | trays ' + r.produced_trays : ''}`);
  }
}

// Calculate the expected packing-BOM consumption after 04/10. This is used
// only when the server has not already recorded the same consumption.
const expected = new Map();
if (hasTable('batches') && hasTable('packing_bom') && hasCol('batches', 'planned_date') && hasCol('batches', 'product_id') && hasCol('batches', 'produced_cb')) {
  const trayExpr = hasCol('batches', 'produced_trays') ? 'COALESCE(b.produced_trays,0)' : '0';
  const expectedRows = q(`SELECT pb.material_id material_id,
      SUM(COALESCE(b.produced_cb,0) * COALESCE(pb.qty_per_cb,0) + ${trayExpr} * COALESCE(pb.qty_per_tray,0)) qty
    FROM batches b JOIN packing_bom pb ON pb.product_id = b.product_id
    WHERE UPPER(COALESCE(b.status,''))='COMPLETED' AND b.planned_date > ?
    GROUP BY pb.material_id`, [closingDate]);
  for (const r of expectedRows) expected.set(Number(r.material_id), n(r.qty));
}
console.log(`\nEXPECTED PACKING-BOM CONSUMPTION AFTER ${closingDate}:`);
if (!expected.size) console.log('  none calculated');
for (const m of matched) if (expected.has(Number(m.id))) console.log(`  #${m.id} ${m.name}: -${expected.get(Number(m.id))} ${m.unit || ''}`);

// Existing consumption after 04/10 is the authoritative deduction when it
// exists. If expected BOM usage and recorded usage both exist, they must agree;
// otherwise the script stops instead of silently double-deducting.
const recorded = new Map();
if (hasTable('packing_txns') && hasCol('packing_txns', 'material_id') && hasCol('packing_txns', 'qty') && hasCol('packing_txns', 'txn_date')) {
  const rows = q("SELECT material_id, SUM(COALESCE(qty,0)) qty FROM packing_txns WHERE txn_type='CONSUMED' AND txn_date > ? GROUP BY material_id", [closingDate]);
  for (const r of rows) recorded.set(Number(r.material_id), n(r.qty));
}
console.log(`\nRECORDED CONSUMPTION AFTER ${closingDate}:`);
if (!recorded.size) console.log('  none recorded in packing_txns');
for (const m of matched) if (recorded.has(Number(m.id))) console.log(`  #${m.id} ${m.name}: -${recorded.get(Number(m.id))} ${m.unit || ''}`);

console.log('\nPROPOSED FINAL BALANCES:');
for (const m of matched) {
  const rec = recorded.get(Number(m.id)) || 0;
  const exp = expected.get(Number(m.id)) || 0;
  if (rec > 0 && exp > 0 && Math.abs(rec - exp) > 0.001) {
    console.error(`MISMATCH ${m.name}: recorded=${rec}, expected BOM=${exp}; refusing to apply until reviewed`);
    fatal = true;
  }
  const deduction = rec > 0 ? rec : exp;
  const finalStock = Number(m.desired) - deduction;
  console.log(`  #${m.id} ${m.name}: ${m.desired} - ${deduction} = ${finalStock} ${m.unit || ''}`);
  if (finalStock < 0) { console.error(`NEGATIVE RESULT for ${m.name}; refusing to apply`); fatal = true; }
}

if (!apply) {
  console.log('\nDRY RUN ONLY — no database rows changed. Review the matches and proposed balances, then rerun with --apply.');
  db.close(); process.exit(fatal ? 3 : 0);
}
if (fatal) { console.log('STOPPED — no database rows changed.'); db.close(); process.exit(3); }

try {
  db.exec('BEGIN');
  const update = db.prepare('UPDATE packing_materials SET stock = ? WHERE id = ?');
  for (const m of matched) {
    const rec = recorded.get(Number(m.id)) || 0;
    const exp = expected.get(Number(m.id)) || 0;
    const deduction = rec > 0 ? rec : exp;
    const finalStock = Number(m.desired) - deduction;
    update.run(finalStock, m.id);
    console.log(`UPDATED #${m.id} ${m.name}: stock=${finalStock} ${m.unit || ''}`);
  }
  db.exec('COMMIT');
  console.log(`APPLIED: ${matched.length} materials. Backup was created by the shell wrapper before the write.`);
} catch (e) {
  try { db.exec('ROLLBACK'); } catch (_) {}
  console.error('APPLY FAILED — transaction rolled back: ' + e.message);
  process.exit(4);
} finally { db.close(); }
JS

if (( APPLY )); then
  systemctl start flavorflow || true
  sleep 3
  curl -sS -m 8 http://127.0.0.1:4000/api/health || true
  echo
fi
