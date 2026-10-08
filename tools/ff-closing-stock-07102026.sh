#!/usr/bin/env bash
# FlavorFlow — 07/10/2026 closing stock reconciliation (PM + RM).
#
# Purpose: Update Packing Material (PM) and Raw Material (RM) stock using the
# physical closing count as of 07/10/2026, cross-checking production and
# consumption from 05/10 to 07/10.
#
# Requirements from MAN-5:
#   - Attach the 07/10/2026 physical stock photos/list.  -> docs/reconciliation/07102026_closing_count.md
#   - Match all materials by exact Product Master name.  -> exact match, no regex
#   - Cross-check completed production and recorded consumption from 05/10 to 07/10.
#   - Do not double-deduct production already represented in ERP records.
#   - Run dry-run first and review proposed balances.
#   - Create a database backup before applying.
#   - Update only targeted PM/RM stock rows.
#   - Do not rewrite production, BOMs, ledger history, or unrelated ERP data.
#   - Shared materials must remain shared; do not split them without confirmation.
#
# Usage:
#   Dry-run (default, READ-ONLY, safe):
#     bash tools/ff-closing-stock-07102026.sh
#     FF_DB=/path/to/erp.db bash tools/ff-closing-stock-07102026.sh
#
#   Apply after reviewing dry-run:
#     bash tools/ff-closing-stock-07102026.sh --apply
#
#   With external JSON list (exact names -> count):
#     FF_COUNT_JSON=/opt/flavorflow/data/closing-07102026.json bash tools/ff-closing-stock-07102026.sh --apply
#
# The script is idempotent and refuses to apply on:
#   - ambiguous or missing exact-name matches
#   - recorded vs expected BOM consumption mismatch (would double-deduct)
#   - negative resulting balances
#   - shared-pool target values that differ
#
# Data source priority for physical counts:
#   1. FF_COUNT_JSON env (JSON file: [{"name":"Exact Product Master Name","count":123}, ...] or {"Name":count} map)
#   2. Embedded list below (transcribed from 07/10/2026 physical count photos/list)
#
set -euo pipefail

DB="${FF_DB:-/opt/flavorflow/server/data/erp.db}"
SERVER_DIR="${FF_SERVER_DIR:-/opt/flavorflow/server}"
CLOSING_DATE="${FF_CLOSING_DATE:-2026-10-07}"
START_DATE="${FF_START_DATE:-2026-10-05}"
COUNT_JSON="${FF_COUNT_JSON:-}"
APPLY=0
if [[ "${1:-}" == "--apply" || "${FF_APPLY:-0}" == "1" ]]; then APPLY=1; fi

[ -f "$DB" ] || { echo "FATAL: database not found: $DB (set FF_DB)"; exit 1; }
command -v node >/dev/null || { echo "FATAL: node is required"; exit 1; }

BACKUP_DIR="${FF_BACKUP_DIR:-/opt/flavorflow/backups}"
TS=$(date +%Y%m%d-%H%M%S)
if (( APPLY )); then
  mkdir -p "$BACKUP_DIR"
  cp -a "$DB" "$BACKUP_DIR/erp.db.bak-closing-07102026-$TS"
  echo "DB BACKUP: $BACKUP_DIR/erp.db.bak-closing-07102026-$TS"
  if systemctl is-active --quiet flavorflow 2>/dev/null; then
    systemctl stop flavorflow || true
    sleep 1
  fi
fi

export FF_DB="$DB" CLOSING_DATE START_DATE APPLY TS SERVER_DIR COUNT_JSON

node <<'JS'
'use strict';
let DatabaseSync;
try { DatabaseSync = require('/opt/flavorflow/server/sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) try { DatabaseSync = require('node:sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) { console.error('FATAL: SQLite wrapper not available'); process.exit(1); }

const fs = require('fs');
const db = new DatabaseSync(process.env.FF_DB);
const closingDate = process.env.CLOSING_DATE; // 2026-10-07
const startDate = process.env.START_DATE;     // 2026-10-05
const apply = process.env.APPLY === '1';
const countJsonPath = process.env.COUNT_JSON;

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
  console.error('FATAL: packing_materials must contain id, name, stock');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Load physical counts: exact Product Master name -> desired count as of 07/10
// Priority: external JSON file if provided, else embedded list.
// The embedded list is transcribed from the 07/10/2026 physical stock
// photos/list attached to MAN-5 (docs/reconciliation/07102026_closing_count.md).
// Update this list only from the photos — do not guess.
// ---------------------------------------------------------------------------

let rawTargets = [];

// Helper: parse external JSON if supplied
function loadExternal() {
  if (!countJsonPath) return null;
  if (!fs.existsSync(countJsonPath)) {
    console.error(`FATAL: FF_COUNT_JSON not found: ${countJsonPath}`);
    process.exit(1);
  }
  const data = JSON.parse(fs.readFileSync(countJsonPath, 'utf8'));
  const out = [];
  if (Array.isArray(data)) {
    for (const row of data) {
      if (!row.name || row.count == null) continue;
      out.push({ name: String(row.name).trim(), count: Number(row.count), kind: row.kind || null, sharedGroup: row.sharedGroup || null });
    }
  } else if (typeof data === 'object') {
    // map form: {"Exact Name": 123, ...} or {"Exact Name": {"count":123,"kind":"packing"}}
    for (const [k, v] of Object.entries(data)) {
      if (typeof v === 'number') out.push({ name: k.trim(), count: v, kind: null, sharedGroup: null });
      else if (v && typeof v === 'object') out.push({ name: k.trim(), count: Number(v.count), kind: v.kind || null, sharedGroup: v.sharedGroup || null });
    }
  }
  return out;
}

const external = loadExternal();
if (external && external.length) {
  console.log(`Loaded ${external.length} targets from ${countJsonPath}`);
  rawTargets = external;
} else {
  // Embedded 07/10/2026 closing count — exact Product Master names.
  // These values were transcribed from the physical stock photos attached to MAN-5.
  // NOTE: If the screenshot shows different numbers, update ONLY the count values,
  // keeping the exact names unchanged. Shared pool (Jerry Can) must keep identical counts.
  rawTargets = [
    // --- Packing Materials (PM) - exact Product Master names ---
    // Labels & Shrink
    { name: 'Shrink Soya 740g', count: 418903, kind: 'packing' },
    { name: 'Shrink White Vinegar 610ml', count: 436562, kind: 'packing' },
    { name: 'Shrink Brown Vinegar 610ml', count: 15265, kind: 'packing' },
    { name: 'Label Soya 1.3kg', count: 30155, kind: 'packing' },
    { name: 'Label White Vinegar 1 Ltr', count: 67548, kind: 'packing' },
    { name: 'Label Dark Soya 220g', count: 10023, kind: 'packing' },
    { name: 'Label White Vinegar 180ml', count: 158172, kind: 'packing' },
    { name: 'Hologram 65 x 65', count: 171038, kind: 'packing', sharedGroup: 'hologram-180-220' }, // shared Vinegar 180 / Dark Soya 220
    // If Product Master stores it as "Hologram 65 x 65 — shared Vinegar 180 / Dark Soya 220", exact match will use that full name.
    // We list both variants to guarantee exact match; deduplication below handles it.
    { name: 'Hologram 65 x 65 — shared Vinegar 180 / Dark Soya 220', count: 171038, kind: 'packing', sharedGroup: 'hologram-180-220', aliasOf: 'Hologram 65 x 65' },

    { name: 'Label White Vinegar 4 Ltr', count: 4092, kind: 'packing' },
    { name: 'Label Dark Soya 4.7kg', count: 4200, kind: 'packing' },

    // Caps & Plugs
    { name: 'Cap Orange', count: 1195479, kind: 'packing' },
    { name: 'Cap Purple', count: 184785, kind: 'packing' },
    { name: 'Cap Red 1.3kg', count: 22518, kind: 'packing' },
    { name: 'Cap Red Plastic 4gm', count: 135615, kind: 'packing' },
    { name: 'Plug No 9', count: 422444, kind: 'packing' },
    { name: 'Crown Cork', count: 113050, kind: 'packing' },

    // Cartons (CB)
    { name: 'CB 180ml / 220g', count: 5151, kind: 'packing' },
    { name: 'CB 610ml / 740gm', count: 7812, kind: 'packing' },
    { name: 'CB 1.3kg', count: 695, kind: 'packing' },

    // Jerry Can — shared physical pool, represented by two Product Master rows.
    // Both rows must receive the SAME final balance; we never split the count.
    { name: 'Jerry Can 4Ltr', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared' },
    { name: 'Jerry Can 4.7kg', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared' },
    // Full exact names if stored with "(shared pool)" suffix:
    { name: 'Jerry Can 4Ltr (shared pool)', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared', aliasOf: 'Jerry Can 4Ltr' },
    { name: 'Jerry Can 4.7kg (shared pool)', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared', aliasOf: 'Jerry Can 4.7kg' },

    // --- Raw Materials (RM) — exact Product Master names, kg ---
    { name: 'Soyabean', count: 446.30, kind: 'raw' },
    { name: 'Haldi Powder', count: 35.50, kind: 'raw' },
    { name: 'Potassium Sorbate', count: 277.46, kind: 'raw' },
    { name: 'Citric Acid', count: 623.20, kind: 'raw' },
    { name: 'Ascorbic Acid', count: 30.80, kind: 'raw' },
    { name: 'Sodium Benzoate', count: 1.16, kind: 'raw' },
    { name: 'Oleoresin Garlic', count: 29.49, kind: 'raw' },
    { name: 'Oleoresin Cinnamon', count: 28.48, kind: 'raw' },
    { name: 'Oleoresin Coriander', count: 38.79, kind: 'raw' },
    { name: 'Caramel Colour E150A', count: 4757.50, kind: 'raw' },
    { name: 'Black Salt', count: 100, kind: 'raw' },
  ];
}

// Deduplicate by exact name, prefer non-alias, and keep sharedGroup
const deduped = new Map();
for (const t of rawTargets) {
  if (!t.name) continue;
  const key = t.name.trim();
  if (!deduped.has(key) || !deduped.get(key).aliasOf) {
    // if existing is alias and new is not alias, replace; otherwise keep first
    const existing = deduped.get(key);
    if (existing && existing.aliasOf && !t.aliasOf) deduped.set(key, t);
    else if (!existing) deduped.set(key, t);
  }
}
let targets = Array.from(deduped.values()).filter(t => !t.aliasOf); // remove alias entries unless they are the only match

// If external JSON not used, we may have included alias duplicates that should be resolved
// to actual DB names later; keep alias mapping for fallback.
const aliasMap = new Map();
for (const t of rawTargets) {
  if (t.aliasOf) aliasMap.set(t.name.trim(), t.aliasOf);
}

console.log(`\n=== FlavorFlow 07/10/2026 Closing Stock Reconciliation ===`);
console.log(`Closing Date: ${closingDate} (physical count)`);
console.log(`Cross-check Window: ${startDate} -> ${closingDate} (production & consumption)`);
console.log(`Mode: ${apply ? 'APPLY (will write)' : 'DRY-RUN (read-only)'}`);
console.log(`DB: ${process.env.FF_DB}`);
console.log(`Targets loaded: ${targets.length}\n`);

// ---------------------------------------------------------------------------
// Exact Product Master name matching
// ---------------------------------------------------------------------------
const allMaterials = q('SELECT id, name, category, unit, COALESCE(stock,0) stock FROM packing_materials ORDER BY id');

function findExact(name, kind) {
  // 1) exact case-sensitive
  let candidates = allMaterials.filter(m => m.name === name);
  // 2) exact case-insensitive but preserve case (if Product Master has different case)
  if (candidates.length === 0) {
    candidates = allMaterials.filter(m => m.name.toLowerCase() === name.toLowerCase());
    if (candidates.length === 1) {
      console.log(`  WARN: case-insensitive exact match for "${name}" -> "${candidates[0].name}" (consider correcting master to exact case)`);
    }
  }
  // 3) category filter if kind specified
  if (kind) {
    const wantRaw = kind === 'raw';
    candidates = candidates.filter(m => {
      const cat = norm(m.category);
      if (wantRaw) return cat === 'raw material';
      return cat !== 'raw material';
    });
  }
  return candidates;
}

const matched = [];
let fatal = false;
const matchedByName = new Map();

for (const t of targets) {
  const candidates = findExact(t.name, t.kind);
  if (candidates.length !== 1) {
    if (candidates.length === 0) {
      // Try alias fallback for shared pools where DB might store short name
      const aliasTarget = aliasMap.has(t.name) ? aliasMap.get(t.name) : null;
      if (aliasTarget) {
        const alt = findExact(aliasTarget, t.kind);
        if (alt.length === 1) {
          console.log(`MATCH (alias) "${t.name}" -> "${alt[0].name}" via alias "${aliasTarget}"`);
          matched.push({ label: t.name, desired: Number(t.count), kind: t.kind, sharedGroup: t.sharedGroup || null, ...alt[0] });
          matchedByName.set(t.name, alt[0]);
          continue;
        }
      }
      console.log(`TARGET "${t.name}": NOT FOUND (exact Product Master name required) — available names containing similar words:`);
      const similar = allMaterials.filter(m => norm(m.name).includes(norm(t.name).split(' ')[0]) ).slice(0,5).map(m => `[#${m.id} "${m.name}" (${m.category})]`).join(' ');
      console.log(`  ${similar || '(no similar)'}`);
    } else {
      console.log(`TARGET "${t.name}": AMBIGUOUS (${candidates.length} matches) ${candidates.map(m => `[#${m.id} "${m.name}" (${m.category})]`).join(' ')}`);
    }
    fatal = true;
    continue;
  }
  const m = candidates[0];
  if (matchedByName.has(m.name)) {
    // duplicate target mapping to same DB row (e.g., both short and long Jerry Can names)
    // keep the first, ensure counts match
    const prev = matched.find(x => x.id === m.id);
    if (prev && Number(prev.desired) !== Number(t.count)) {
      console.log(`TARGET "${t.name}": DUPLICATE DB ROW #${m.id} "${m.name}" but count ${t.count} != previous ${prev.desired} — shared pool must have identical counts`);
      fatal = true;
    }
    continue;
  }
  matchedByName.set(t.name, m);
  matched.push({ label: t.name, desired: Number(t.count), kind: t.kind, sharedGroup: t.sharedGroup || null, ...m });
  console.log(`MATCH "${t.name}" -> #${m.id} "${m.name}" | current=${m.stock} ${m.unit || ''} | 07/10 closing=${t.count} ${m.unit || ''}${t.sharedGroup ? ` | shared=${t.sharedGroup}` : ''}`);
}

if (fatal) {
  console.log('\nSTOPPED: every target must match exactly one Product Master row by exact name. No database rows changed.');
  console.log('Fix: update Product Master names to match the list, or update the list to exact DB names.');
  db.close();
  process.exit(2);
}

// ---------------------------------------------------------------------------
// Production cross-check: completed production from 05/10 to 07/10
// ---------------------------------------------------------------------------
console.log(`\nCOMPLETED PRODUCTION BETWEEN ${startDate} AND ${closingDate}:`);
let prodRows = [];
if (hasTable('batches')) {
  const bc = cols('batches');
  const hasPlanned = bc.includes('planned_date');
  const hasProdDate = bc.includes('production_date');
  const dateCol = hasProdDate ? 'production_date' : (hasPlanned ? 'planned_date' : null);
  if (dateCol && bc.includes('product_id') && bc.includes('produced_cb')) {
    const nameCol = bc.includes('product_name') ? 'product_name' : null;
    try {
      prodRows = q(`SELECT b.${dateCol} date, b.product_id product_id, ${nameCol ? `b.${nameCol}` : 'NULL'} product_name, COALESCE(b.produced_cb,0) produced_cb${bc.includes('produced_trays') ? ', COALESCE(b.produced_trays,0) produced_trays' : ''} FROM batches b WHERE UPPER(COALESCE(b.status,''))='COMPLETED' AND b.${dateCol} > ? AND b.${dateCol} <= ? ORDER BY b.${dateCol}, b.id`, [startDate, closingDate]);
    } catch (e) {
      console.log(`  WARN: could not query batches: ${e.message}`);
    }
    if (!prodRows.length) console.log('  none');
    for (const r of prodRows) console.log(`  ${r.date} | ${r.product_name || ('product #' + r.product_id)} | CB ${r.produced_cb}${r.produced_trays != null ? ' | trays ' + r.produced_trays : ''}`);
  } else {
    console.log('  batches table missing required columns — skipping');
  }
} else {
  console.log('  batches table not found — skipping');
}

// ---------------------------------------------------------------------------
// Expected BOM consumption from 05/10 to 07/10 (packing)
// ---------------------------------------------------------------------------
const expected = new Map();
if (hasTable('batches') && hasTable('packing_bom') && hasCol('batches','product_id') && hasCol('batches','produced_cb')) {
  const dateCol = hasCol('batches','production_date') ? 'production_date' : (hasCol('batches','planned_date') ? 'planned_date' : null);
  if (dateCol) {
    const trayExpr = hasCol('batches','produced_trays') ? 'COALESCE(b.produced_trays,0)' : '0';
    try {
      const expectedRows = q(`SELECT pb.material_id material_id,
          SUM(COALESCE(b.produced_cb,0) * COALESCE(pb.qty_per_cb,0) + ${trayExpr} * COALESCE(pb.qty_per_tray,0)) qty
        FROM batches b JOIN packing_bom pb ON pb.product_id = b.product_id
        WHERE UPPER(COALESCE(b.status,''))='COMPLETED' AND b.${dateCol} > ? AND b.${dateCol} <= ?
        GROUP BY pb.material_id`, [startDate, closingDate]);
      for (const r of expectedRows) expected.set(Number(r.material_id), n(r.qty));
    } catch (e) {
      console.log(`  WARN: could not calculate expected BOM consumption: ${e.message}`);
    }
  }
}
console.log(`\nEXPECTED PACKING-BOM CONSUMPTION BETWEEN ${startDate} AND ${closingDate}:`);
if (!expected.size) console.log('  none calculated');
for (const m of matched) if (expected.has(Number(m.id))) console.log(`  #${m.id} "${m.name}": -${expected.get(Number(m.id))} ${m.unit || ''}`);

// ---------------------------------------------------------------------------
// Recorded consumption from 05/10 to 07/10 (authoritative if exists)
// ---------------------------------------------------------------------------
const recorded = new Map();
if (hasTable('packing_txns') && hasCol('packing_txns','material_id') && hasCol('packing_txns','qty') && hasCol('packing_txns','txn_date')) {
  try {
    const rows = q(`SELECT material_id, SUM(COALESCE(qty,0)) qty FROM packing_txns WHERE txn_type='CONSUMED' AND txn_date > ? AND txn_date <= ? GROUP BY material_id`, [startDate, closingDate]);
    for (const r of rows) recorded.set(Number(r.material_id), n(r.qty));
  } catch (e) {
    console.log(`  WARN: could not query packing_txns: ${e.message}`);
  }
}
console.log(`\nRECORDED CONSUMPTION BETWEEN ${startDate} AND ${closingDate}:`);
if (!recorded.size) console.log('  none recorded in packing_txns');
for (const m of matched) if (recorded.has(Number(m.id))) console.log(`  #${m.id} "${m.name}": -${recorded.get(Number(m.id))} ${m.unit || ''}`);

// Also check recipe consumption for raw materials in same window
const recordedRawRecipe = new Map();
if (hasTable('packing_txns')) {
  try {
    const rows = q(`SELECT material_id, SUM(COALESCE(qty,0)) qty FROM packing_txns WHERE txn_type IN ('CONSUMED','RECIPE') AND txn_date > ? AND txn_date <= ? GROUP BY material_id`, [startDate, closingDate]);
    for (const r of rows) {
      if (!recorded.has(Number(r.material_id))) recordedRawRecipe.set(Number(r.material_id), n(r.qty));
    }
  } catch (_) {}
}
if (recordedRawRecipe.size) {
  console.log(`\nRECORDED RAW/RECIPE CONSUMPTION (additional) BETWEEN ${startDate} AND ${closingDate}:`);
  for (const m of matched) if (recordedRawRecipe.has(Number(m.id))) console.log(`  #${m.id} "${m.name}": -${recordedRawRecipe.get(Number(m.id))} ${m.unit || ''}`);
  for (const [k,v] of recordedRawRecipe) recorded.set(k, (recorded.get(k)||0)+v);
}

// ---------------------------------------------------------------------------
// Proposed final balances — avoid double-deduction
// ---------------------------------------------------------------------------
console.log('\nPROPOSED FINAL BALANCES (physical count - deduction):');
console.log('Rule: if recorded consumption exists for the window, it is authoritative (already deducted in ERP).');
console.log('      Expected BOM consumption is used only when recorded is absent.');
console.log('      If both exist and differ >0.001, we STOP to avoid double-deduction.\n');

const finalById = new Map();
const grouped = new Map();
for (const m of matched) {
  if (m.sharedGroup) {
    if (!grouped.has(m.sharedGroup)) grouped.set(m.sharedGroup, []);
    grouped.get(m.sharedGroup).push(m);
  }
}

let hasMismatch = false;

// Shared pools first
for (const [group, rows] of grouped) {
  const desiredValues = new Set(rows.map(m => Number(m.desired)));
  if (desiredValues.size !== 1) {
    console.error(`MISMATCH shared group ${group}: target values differ ${Array.from(desiredValues).join(', ')}; refusing to apply`);
    fatal = true;
    continue;
  }
  const rec = rows.reduce((sum, m) => sum + (recorded.get(Number(m.id)) || 0), 0);
  const exp = rows.reduce((sum, m) => sum + (expected.get(Number(m.id)) || 0), 0);
  if (rec > 0 && exp > 0 && Math.abs(rec - exp) > 0.001) {
    console.error(`MISMATCH shared group ${group}: recorded=${rec}, expected BOM=${exp}; refusing to apply until reviewed (would double-deduct)`);
    hasMismatch = true;
    fatal = true;
  }
  const deduction = rec > 0 ? rec : exp;
  const finalStock = Number(rows[0].desired) - deduction;
  console.log(`  SHARED ${group}: physical ${rows[0].desired} - deduction ${deduction} = FINAL ${finalStock} ${rows[0].unit || ''}`);
  for (const m of rows) {
    finalById.set(Number(m.id), finalStock);
    console.log(`    #${m.id} "${m.name}": shared final=${finalStock} ${m.unit || ''} (current=${m.stock})`);
  }
  if (finalStock < 0) { console.error(`NEGATIVE RESULT for shared group ${group}: ${finalStock}; refusing to apply`); fatal = true; }
}

for (const m of matched) {
  if (m.sharedGroup) continue;
  const rec = recorded.get(Number(m.id)) || 0;
  const exp = expected.get(Number(m.id)) || 0;
  if (rec > 0 && exp > 0 && Math.abs(rec - exp) > 0.001) {
    console.error(`MISMATCH "${m.name}": recorded=${rec}, expected BOM=${exp}; refusing to apply until reviewed (would double-deduct)`);
    hasMismatch = true;
    fatal = true;
  }
  const deduction = rec > 0 ? rec : exp;
  const finalStock = Number(m.desired) - deduction;
  finalById.set(Number(m.id), finalStock);
  console.log(`  #${m.id} "${m.name}": physical ${m.desired} - deduction ${deduction} = FINAL ${finalStock} ${m.unit || ''} (current=${m.stock})`);
  if (finalStock < 0) { console.error(`NEGATIVE RESULT for "${m.name}": ${finalStock}; refusing to apply`); fatal = true; }
}

if (hasMismatch) {
  console.log('\nSTOPPED: recorded vs expected consumption mismatch detected. This prevents double-deduction.');
  console.log('Action: review production and packing_txns between 05/10 and 07/10. If recorded already includes BOM consumption, keep recorded as authoritative.');
}

if (!apply) {
  console.log('\n=== DRY RUN ONLY — no database rows changed ===');
  console.log('Review the exact-name matches and proposed final balances above.');
  console.log('If OK, rerun with --apply:');
  console.log('  bash tools/ff-closing-stock-07102026.sh --apply');
  console.log('\nAttachments: docs/reconciliation/07102026_closing_count.md contains the physical stock photos/list.');
  db.close();
  process.exit(fatal ? 3 : 0);
}
if (fatal) {
  console.log('\nSTOPPED — no database rows changed due to errors above.');
  db.close();
  process.exit(3);
}

// ---------------------------------------------------------------------------
// Apply: only update packing_materials.stock for targeted rows
// ---------------------------------------------------------------------------
console.log('\nAPPLYING: updating only targeted PM/RM stock rows (packing_materials.stock)...');
try {
  db.exec('BEGIN');
  const update = db.prepare('UPDATE packing_materials SET stock = ? WHERE id = ?');
  for (const m of matched) {
    const finalStock = finalById.get(Number(m.id));
    if (finalStock == null) throw new Error(`missing proposed balance for #${m.id} "${m.name}"`);
    update.run(finalStock, m.id);
    console.log(`UPDATED #${m.id} "${m.name}": stock=${finalStock} ${m.unit || ''} (was ${m.stock})`);
  }
  db.exec('COMMIT');
  console.log(`\nAPPLIED: ${matched.length} Product Master rows (${grouped.size} shared pools) updated to 07/10/2026 closing.`);
  console.log(`Backup: ${process.env.FF_BACKUP_DIR || '/opt/flavorflow/backups'}/erp.db.bak-closing-07102026-${process.env.TS}`);
  console.log('Note: production, BOMs, ledger history untouched — only stock column updated. Stock journal triggers will log SET_STOCK entries.');
} catch (e) {
  try { db.exec('ROLLBACK'); } catch (_) {}
  console.error('APPLY FAILED — transaction rolled back: ' + e.message);
  process.exit(4);
} finally {
  db.close();
}
JS

if (( APPLY )); then
  if systemctl is-active --quiet flavorflow 2>/dev/null; then
    systemctl start flavorflow || true
    sleep 3
    curl -sS -m 8 http://127.0.0.1:4000/api/health || true
    echo
  fi
  echo "=== FF-CLOSING-STOCK-07102026 DONE ==="
else
  echo ""
  echo "Dry-run complete. No changes made."
fi
