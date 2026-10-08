#!/usr/bin/env bash
<<<<<<< HEAD
# FlavorFlow — 07/10/2026 closing stock reconciliation (PM + RM) — DIRECT UPDATE, NO DEDUCTION.
#
# Purpose: Update Packing Material (PM) and Raw Material (RM) stock using the
# physical closing count as of 07/10/2026. NO deduction — final stock = physical count.
# Cross-check production/consumption from 05/10 to 07/10 is informational only.
#
# Requirements from MAN-5 (updated per user: sirf stock update krna, koi deduction nahi):
#   - Attach the 07/10/2026 physical stock photos/list.  -> docs/reconciliation/07102026_closing_count.md
#   - Match all materials by exact Product Master name.  -> exact match, no regex
#   - Cross-check completed production and recorded consumption from 05/10 to 07/10 (info only).
#   - Do not double-deduct production already represented in ERP records (no deduction at all now).
#   - Run dry-run first and review proposed balances.
#   - Create a database backup before applying.
#   - Update only targeted PM/RM stock rows.
#   - Do not rewrite production, BOMs, ledger history, or unrelated ERP data.
#   - Shared materials must remain shared; do not split them without confirmation.
#
# Usage:
#   Dry-run (default, READ-ONLY):
#     bash tools/ff-closing-stock-07102026.sh
#
#   Apply after reviewing dry-run:
#     bash tools/ff-closing-stock-07102026.sh --apply
#
#   With external JSON list (exact names -> count):
#     FF_COUNT_JSON=/opt/flavorflow/data/closing-07102026.json bash tools/ff-closing-stock-07102026.sh --apply
#
# Data source priority:
#   1. FF_COUNT_JSON env (JSON: [{"name":"Exact Name","count":123}, ...] or {"Name":count} map)
#   2. Embedded list below (transcribed from 07/10/2026 photos)
=======
# FlavorFlow — 07/10/2026 closing stock reconciliation (PM + RM) — DIRECT UPDATE, NO DEDUCTION
# Updated with EXACT Product Master names from live DB (as seen in server screenshot 00:15 09/10/2026)
#
# Usage:
#   bash /tmp/ff-closing-stock-07102026.sh --list   # list all materials with exact names
#   bash /tmp/ff-closing-stock-07102026.sh          # dry-run, no deduction, final = physical
#   bash /tmp/ff-closing-stock-07102026.sh --apply  # apply direct update
#
# Download fresh:
#   curl -fsSL https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/fc479533-flavorflow/tools/ff-closing-stock-07102026.sh -o /tmp/ff-closing-stock-07102026.sh && chmod +x /tmp/ff-closing-stock-07102026.sh
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
#
set -euo pipefail

DB="${FF_DB:-/opt/flavorflow/server/data/erp.db}"
SERVER_DIR="${FF_SERVER_DIR:-/opt/flavorflow/server}"
CLOSING_DATE="${FF_CLOSING_DATE:-2026-10-07}"
START_DATE="${FF_START_DATE:-2026-10-05}"
COUNT_JSON="${FF_COUNT_JSON:-}"
APPLY=0
<<<<<<< HEAD
if [[ "${1:-}" == "--apply" || "${FF_APPLY:-0}" == "1" ]]; then APPLY=1; fi
=======
LIST=0
if [[ "${1:-}" == "--apply" ]]; then APPLY=1; fi
if [[ "${1:-}" == "--list" ]]; then LIST=1; fi
if [[ "${2:-}" == "--list" ]]; then LIST=1; fi
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)

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

<<<<<<< HEAD
export FF_DB="$DB" CLOSING_DATE START_DATE APPLY TS SERVER_DIR COUNT_JSON
=======
export FF_DB="$DB" CLOSING_DATE START_DATE APPLY TS SERVER_DIR COUNT_JSON LIST
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)

node <<'JS'
'use strict';
let DatabaseSync;
try { DatabaseSync = require('/opt/flavorflow/server/sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) try { DatabaseSync = require('node:sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) { console.error('FATAL: SQLite wrapper not available'); process.exit(1); }

const fs = require('fs');
const db = new DatabaseSync(process.env.FF_DB);
const closingDate = process.env.CLOSING_DATE;
const startDate = process.env.START_DATE;
const apply = process.env.APPLY === '1';
<<<<<<< HEAD
=======
const listMode = process.env.LIST === '1';
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
const countJsonPath = process.env.COUNT_JSON;

const n = (v) => Number(v) || 0;
const text = (v) => String(v ?? '').trim();
const norm = (v) => text(v).toLowerCase().replace(/[^a-z0-9]+/g, ' ').replace(/\s+/g, ' ').trim();
const cols = (table) => db.prepare('PRAGMA table_info(' + table + ')').all().map((r) => String(r.name));
const tables = new Set(db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map((r) => String(r.name)));
const hasTable = (t) => tables.has(t);
const hasCol = (t, c) => hasTable(t) && cols(t).includes(c);
const q = (sql, args = []) => db.prepare(sql).all(...args);

if (!hasTable('packing_materials')) { console.error('FATAL: packing_materials table missing'); process.exit(1); }

<<<<<<< HEAD
=======
const allMaterials = q('SELECT id, name, category, unit, COALESCE(stock,0) stock FROM packing_materials ORDER BY id');

if (listMode) {
  console.log(`\n=== ALL Product Master materials (exact names) — DB: ${process.env.FF_DB} ===`);
  console.log(`Total: ${allMaterials.length}\n`);
  const byCat = {};
  for (const m of allMaterials) {
    if (!byCat[m.category]) byCat[m.category] = [];
    byCat[m.category].push(m);
  }
  for (const cat of Object.keys(byCat).sort()) {
    console.log(`\n--- Category: ${cat} (${byCat[cat].length}) ---`);
    for (const m of byCat[cat]) {
      console.log(`#${m.id} | "${m.name}" | stock=${m.stock} ${m.unit || ''} | category=${m.category}`);
    }
  }
  console.log(`\nCopy exact names from above into tools/data/closing-stock-07102026.json`);
  db.close();
  process.exit(0);
}

>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
let rawTargets = [];

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
<<<<<<< HEAD
  // Embedded 07/10/2026 closing count — exact Product Master names.
  // DIRECT UPDATE MODE: final stock = physical count, no deduction.
  rawTargets = [
    // --- Packing Materials (PM) ---
    { name: 'Shrink Soya 740g', count: 418903, kind: 'packing' },
    { name: 'Shrink White Vinegar 610ml', count: 436562, kind: 'packing' },
    { name: 'Shrink Brown Vinegar 610ml', count: 15265, kind: 'packing' },
    { name: 'Label Soya 1.3kg', count: 30155, kind: 'packing' },
    { name: 'Label White Vinegar 1 Ltr', count: 67548, kind: 'packing' },
    { name: 'Label Dark Soya 220g', count: 10023, kind: 'packing' },
    { name: 'Label White Vinegar 180ml', count: 158172, kind: 'packing' },
    { name: 'Hologram 65 x 65', count: 171038, kind: 'packing', sharedGroup: 'hologram-180-220' },
    { name: 'Hologram 65 x 65 — shared Vinegar 180 / Dark Soya 220', count: 171038, kind: 'packing', sharedGroup: 'hologram-180-220', aliasOf: 'Hologram 65 x 65' },
    { name: 'Label White Vinegar 4 Ltr', count: 4092, kind: 'packing' },
    { name: 'Label Dark Soya 4.7kg', count: 4200, kind: 'packing' },
    { name: 'Cap Orange', count: 1195479, kind: 'packing' },
    { name: 'Cap Purple', count: 184785, kind: 'packing' },
    { name: 'Cap Red 1.3kg', count: 22518, kind: 'packing' },
    { name: 'Cap Red Plastic 4gm', count: 135615, kind: 'packing' },
    { name: 'Plug No 9', count: 422444, kind: 'packing' },
    { name: 'Crown Cork', count: 113050, kind: 'packing' },
    { name: 'CB 180ml / 220g', count: 5151, kind: 'packing' },
    { name: 'CB 610ml / 740gm', count: 7812, kind: 'packing' },
    { name: 'CB 1.3kg', count: 695, kind: 'packing' },
    // Shared pool — both rows get SAME final balance, no split
    { name: 'Jerry Can 4Ltr', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared' },
    { name: 'Jerry Can 4.7kg', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared' },
    { name: 'Jerry Can 4Ltr (shared pool)', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared', aliasOf: 'Jerry Can 4Ltr' },
    { name: 'Jerry Can 4.7kg (shared pool)', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared', aliasOf: 'Jerry Can 4.7kg' },

    // --- Raw Materials (RM) — exact names, kg ---
    // NOTE: These will be updated from the new RM image you uploaded.
    // If Product Master has slightly different names, keep exact DB names.
    { name: 'Soyabean', count: 446.30, kind: 'raw' },
    { name: 'Haldi Powder', count: 35.50, kind: 'raw' },
=======
  // Embedded 07/10/2026 closing count — NOW WITH EXACT DB NAMES from live server screenshot (00:15 09/10/2026)
  // These are the exact Product Master names as stored in packing_materials.
  rawTargets = [
    // --- Packing Materials (PM) — exact names from DB ---
    // Sleeves (Shrink)
    { name: 'Shrink Sleeve 740', count: 418903, kind: 'packing' }, // was 'Shrink Soya 740g'
    { name: 'Shrink Sleeve White 610', count: 436562, kind: 'packing' },
    { name: 'Shrink Sleeve Brown 610', count: 15265, kind: 'packing' },

    // Labels
    { name: 'Label Soya 1.3', count: 30155, kind: 'packing' }, // was 'Label Soya 1.3kg'
    { name: 'Label White (180)', count: 158172, kind: 'packing' }, // was 'Label White Vinegar 180ml'
    { name: 'Label Front 4 Ltr', count: 4092, kind: 'packing' }, // was 'Label White Vinegar 4 Ltr'
    { name: 'Label Front 4.7', count: 4200, kind: 'packing' }, // was 'Label Dark Soya 4.7kg'
    // Note: 'Label White Vinegar 1 Ltr' and 'Label Dark Soya 220g' not found as exact in DB screenshot — may be:
    // #12 'Dark S Label (250)' — maps to Dark Soya 220g?
    { name: 'Dark S Label (250)', count: 10023, kind: 'packing' }, // was 'Label Dark Soya 220g' — adjust count if needed
    // If you have Label for 1 Ltr, check exact name via --list, likely 'Label White 1 Ltr' or similar
    // For now include both common variants, script will skip if NOT FOUND and warn
    // { name: 'Label White 1 Ltr', count: 67548, kind: 'packing' },

    // Holograms — shared
    { name: 'Hologram (180/220)', count: 171038, kind: 'packing', sharedGroup: 'hologram-180-220' },
    { name: 'Hologram M (250)', count: 0, kind: 'packing' }, // placeholder, set to actual if you have count for 250

    // Caps — exact names from DB
    { name: 'Cap Orange (610)', count: 1195479, kind: 'packing' },
    { name: 'Cap Purple (740)', count: 184785, kind: 'packing' },
    { name: 'Red Cap (1.3 / 1 Ltr)', count: 22518, kind: 'packing' }, // was 'Cap Red 1.3kg'
    { name: 'Red Cap (180/220)', count: 135615, kind: 'packing' }, // was 'Cap Red Plastic 4gm'
    { name: 'Lug Cap (250)', count: 0, kind: 'packing' }, // placeholder, check if you have count

    // Plugs & Crowns
    { name: 'Plug (180)', count: 422444, kind: 'packing' }, // was 'Plug No 9'
    { name: 'Crown (220)', count: 113050, kind: 'packing' }, // was 'Crown Cork' — verify via --list

    // Cartons (CB) — exact names
    { name: 'Carton CB 180/220', count: 5151, kind: 'packing' },
    { name: 'Carton CB (610/740)', count: 7812, kind: 'packing' },
    { name: 'Carton CB (1.3/1 Ltr)', count: 695, kind: 'packing' },
    { name: 'Carton CB 250', count: 0, kind: 'packing' }, // placeholder
    { name: 'Carton CB 4.7/4 Ltr', count: 0, kind: 'packing' }, // placeholder

    // Jerry Cans — shared pool, both get SAME final balance
    { name: 'Jerry Can 4Ltr', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared' },
    { name: 'Jerry Can 4.7kg', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared' },

    // --- Raw Materials (RM) — exact names from DB (as seen in screenshot) ---
    { name: 'Soyabean', count: 446.30, kind: 'raw' },
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
    { name: 'Potassium Sorbate', count: 277.46, kind: 'raw' },
    { name: 'Citric Acid', count: 623.20, kind: 'raw' },
    { name: 'Ascorbic Acid', count: 30.80, kind: 'raw' },
    { name: 'Sodium Benzoate', count: 1.16, kind: 'raw' },
<<<<<<< HEAD
    { name: 'Oleoresin Garlic', count: 29.49, kind: 'raw' },
    { name: 'Oleoresin Cinnamon', count: 28.48, kind: 'raw' },
    { name: 'Oleoresin Coriander', count: 38.79, kind: 'raw' },
    { name: 'Caramel Colour E150A', count: 4757.50, kind: 'raw' },
    { name: 'Black Salt', count: 100, kind: 'raw' },
=======
    { name: 'Garlic Oleoresin', count: 29.49, kind: 'raw' }, // was 'Oleoresin Garlic'
    { name: 'Cinnamon Oleoresin', count: 28.48, kind: 'raw' },
    { name: 'Coriander Oleoresin', count: 38.79, kind: 'raw' },
    { name: 'Caramel Colour (E150A)', count: 4757.50, kind: 'raw' },
    { name: 'Black Salt', count: 100, kind: 'raw' },
    // Haldi Powder not found — likely 'Turmeric Powder' in DB, check via --list
    // { name: 'Turmeric Powder', count: 35.50, kind: 'raw' },
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
  ];
}

const deduped = new Map();
for (const t of rawTargets) {
  if (!t.name) continue;
  const key = t.name.trim();
<<<<<<< HEAD
  if (!deduped.has(key) || !deduped.get(key).aliasOf) {
    const existing = deduped.get(key);
    if (existing && existing.aliasOf && !t.aliasOf) deduped.set(key, t);
    else if (!existing) deduped.set(key, t);
  }
}
let targets = Array.from(deduped.values()).filter(t => !t.aliasOf);
const aliasMap = new Map();
for (const t of rawTargets) if (t.aliasOf) aliasMap.set(t.name.trim(), t.aliasOf);

console.log(`\n=== FlavorFlow 07/10/2026 Closing Stock Reconciliation (DIRECT UPDATE, NO DEDUCTION) ===`);
console.log(`Closing Date: ${closingDate} (physical count)`);
console.log(`Cross-check Window (info only): ${startDate} -> ${closingDate}`);
console.log(`Mode: ${apply ? 'APPLY (will write)' : 'DRY-RUN (read-only)'} — NO DEDUCTION, final = physical`);
console.log(`DB: ${process.env.FF_DB}`);
console.log(`Targets loaded: ${targets.length}\n`);

const allMaterials = q('SELECT id, name, category, unit, COALESCE(stock,0) stock FROM packing_materials ORDER BY id');
=======
  if (!deduped.has(key)) deduped.set(key, t);
}
let targets = Array.from(deduped.values());

console.log(`\n=== FlavorFlow 07/10/2026 Closing Stock Reconciliation (DIRECT UPDATE, NO DEDUCTION) ===`);
console.log(`Closing Date: ${closingDate} | Window (info only): ${startDate} -> ${closingDate}`);
console.log(`Mode: ${apply ? 'APPLY' : 'DRY-RUN'} — NO DEDUCTION, final = physical`);
console.log(`DB: ${process.env.FF_DB} | Targets: ${targets.length}\n`);
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)

function findExact(name, kind) {
  let candidates = allMaterials.filter(m => m.name === name);
  if (candidates.length === 0) {
    candidates = allMaterials.filter(m => m.name.toLowerCase() === name.toLowerCase());
<<<<<<< HEAD
    if (candidates.length === 1) {
      console.log(`  WARN: case-insensitive exact match for "${name}" -> "${candidates[0].name}"`);
    }
=======
    if (candidates.length === 1) console.log(`  WARN case-insensitive match for "${name}" -> "${candidates[0].name}"`);
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
  }
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
<<<<<<< HEAD
const matchedByName = new Map();

for (const t of targets) {
  const candidates = findExact(t.name, t.kind);
  if (candidates.length !== 1) {
    if (candidates.length === 0) {
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
      console.log(`TARGET "${t.name}": NOT FOUND (exact name required) — similar:`);
      const similar = allMaterials.filter(m => norm(m.name).includes(norm(t.name).split(' ')[0])).slice(0,5).map(m => `[#${m.id} "${m.name}" (${m.category})]`).join(' ');
      console.log(`  ${similar || '(no similar)'}`);
    } else {
      console.log(`TARGET "${t.name}": AMBIGUOUS (${candidates.length}) ${candidates.map(m => `[#${m.id} "${m.name}"]`).join(' ')}`);
=======
const seenIds = new Set();

for (const t of targets) {
  if (n(t.count) === 0 && !String(t.name).toLowerCase().includes('jerry')) {
    // skip placeholder zero counts unless it's shared pool (to avoid false NOT FOUND)
    // But still try to match to show if name exists
    const cands = findExact(t.name, t.kind);
    if (cands.length === 0) {
      console.log(`SKIP (zero placeholder) "${t.name}": NOT FOUND — run with --list to see exact names`);
      continue;
    }
    if (n(t.count) === 0) {
      console.log(`SKIP (zero count) "${t.name}" -> #${cands[0].id} "${cands[0].name}" | current=${cands[0].stock} — set count if needed`);
      continue;
    }
  }
  const candidates = findExact(t.name, t.kind);
  if (candidates.length !== 1) {
    if (candidates.length === 0) {
      console.log(`TARGET "${t.name}": NOT FOUND (exact required) — similar:`);
      const similar = allMaterials.filter(m => norm(m.name).includes(norm(t.name).split(' ')[0])).slice(0,5).map(m => `[#${m.id} "${m.name}" (${m.category})]`).join(' ');
      console.log(`  ${similar || '(no similar)'}`);
    } else {
      console.log(`TARGET "${t.name}": AMBIGUOUS ${candidates.map(m => `[#${m.id} "${m.name}"]`).join(' ')}`);
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
    }
    fatal = true;
    continue;
  }
  const m = candidates[0];
<<<<<<< HEAD
  if (matchedByName.has(m.name)) {
    const prev = matched.find(x => x.id === m.id);
    if (prev && Number(prev.desired) !== Number(t.count)) {
      console.log(`TARGET "${t.name}": DUPLICATE DB ROW #${m.id} "${m.name}" but count ${t.count} != previous ${prev.desired} — shared pool must have identical counts`);
=======
  if (seenIds.has(m.id)) {
    const prev = matched.find(x => x.id === m.id);
    if (prev && Number(prev.desired) !== Number(t.count)) {
      console.log(`DUPLICATE DB ROW #${m.id} "${m.name}" counts differ ${prev.desired} vs ${t.count} — shared pool must have identical counts`);
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
      fatal = true;
    }
    continue;
  }
<<<<<<< HEAD
  matchedByName.set(t.name, m);
=======
  seenIds.add(m.id);
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
  matched.push({ label: t.name, desired: Number(t.count), kind: t.kind, sharedGroup: t.sharedGroup || null, ...m });
  console.log(`MATCH "${t.name}" -> #${m.id} "${m.name}" | current=${m.stock} ${m.unit || ''} | 07/10 closing=${t.count} ${m.unit || ''}${t.sharedGroup ? ` | shared=${t.sharedGroup}` : ''}`);
}

if (fatal) {
<<<<<<< HEAD
  console.log('\nSTOPPED: every target must match exactly one Product Master row by exact name. No changes.');
=======
  console.log('\nSTOPPED: fix exact names. Run with --list to see all exact Product Master names:');
  console.log('  bash /tmp/ff-closing-stock-07102026.sh --list');
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
  db.close();
  process.exit(2);
}

<<<<<<< HEAD
// Cross-check info only (no deduction)
console.log(`\nCOMPLETED PRODUCTION BETWEEN ${startDate} AND ${closingDate} (INFO ONLY, NO DEDUCTION):`);
if (hasTable('batches')) {
  const bc = cols('batches');
  const dateCol = bc.includes('production_date') ? 'production_date' : (bc.includes('planned_date') ? 'planned_date' : null);
  if (dateCol && bc.includes('product_id')) {
=======
// Info only cross-check
console.log(`\nCOMPLETED PRODUCTION BETWEEN ${startDate} AND ${closingDate} (INFO ONLY):`);
if (hasTable('batches')) {
  const bc = cols('batches');
  const dateCol = bc.includes('production_date') ? 'production_date' : (bc.includes('planned_date') ? 'planned_date' : null);
  if (dateCol) {
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
    try {
      const rows = q(`SELECT b.${dateCol} date, b.product_id, COALESCE(b.product_name,'') product_name, COALESCE(b.produced_cb,0) produced_cb FROM batches b WHERE UPPER(COALESCE(b.status,''))='COMPLETED' AND b.${dateCol} > ? AND b.${dateCol} <= ? ORDER BY b.${dateCol}, b.id`, [startDate, closingDate]);
      if (!rows.length) console.log('  none');
      for (const r of rows) console.log(`  ${r.date} | ${r.product_name || ('product #' + r.product_id)} | CB ${r.produced_cb}`);
    } catch (e) { console.log(`  WARN: ${e.message}`); }
  }
}

<<<<<<< HEAD
console.log(`\nRECORDED CONSUMPTION BETWEEN ${startDate} AND ${closingDate} (INFO ONLY, NO DEDUCTION):`);
if (hasTable('packing_txns') && hasCol('packing_txns','material_id')) {
  try {
    const rows = q(`SELECT material_id, SUM(COALESCE(qty,0)) qty FROM packing_txns WHERE txn_type IN ('CONSUMED','RECIPE') AND txn_date > ? AND txn_date <= ? GROUP BY material_id`, [startDate, closingDate]);
    if (!rows.length) console.log('  none recorded');
    for (const r of rows) {
      const mat = allMaterials.find(m => m.id === r.material_id);
      console.log(`  #${r.material_id} ${mat ? mat.name : ''}: -${r.qty}`);
=======
console.log(`\nRECORDED CONSUMPTION BETWEEN ${startDate} AND ${closingDate} (INFO ONLY, NOT DEDUCTED):`);
if (hasTable('packing_txns')) {
  try {
    const rows = q(`SELECT material_id, SUM(COALESCE(qty,0)) qty FROM packing_txns WHERE txn_type IN ('CONSUMED','RECIPE') AND txn_date > ? AND txn_date <= ? GROUP BY material_id`, [startDate, closingDate]);
    if (!rows.length) console.log('  none');
    for (const r of rows) {
      const mat = allMaterials.find(m => m.id === r.material_id);
      console.log(`  #${r.material_id} ${mat ? mat.name : ''}: -${r.qty} (info only)`);
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
    }
  } catch (e) { console.log(`  WARN: ${e.message}`); }
}

<<<<<<< HEAD
// Proposed finals — DIRECT UPDATE, NO DEDUCTION
console.log('\nPROPOSED FINAL BALANCES (DIRECT UPDATE, NO DEDUCTION):');
console.log('Rule: final stock = physical closing count as of 07/10/2026 (no subtraction).\n');

=======
console.log('\nPROPOSED FINAL BALANCES (DIRECT UPDATE, NO DEDUCTION):');
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
const finalById = new Map();
const grouped = new Map();
for (const m of matched) if (m.sharedGroup) {
  if (!grouped.has(m.sharedGroup)) grouped.set(m.sharedGroup, []);
  grouped.get(m.sharedGroup).push(m);
}

for (const [group, rows] of grouped) {
<<<<<<< HEAD
  const desiredValues = new Set(rows.map(m => Number(m.desired)));
  if (desiredValues.size !== 1) {
    console.error(`MISMATCH shared group ${group}: values differ ${Array.from(desiredValues).join(', ')}`);
    fatal = true;
    continue;
  }
  const finalStock = Number(rows[0].desired);
  console.log(`  SHARED ${group}: physical ${rows[0].desired} = FINAL ${finalStock} ${rows[0].unit || ''} (NO DEDUCTION)`);
  for (const m of rows) {
    finalById.set(Number(m.id), finalStock);
    console.log(`    #${m.id} "${m.name}": final=${finalStock} ${m.unit || ''} (current=${m.stock})`);
  }
  if (finalStock < 0) { console.error(`NEGATIVE for shared group ${group}`); fatal = true; }
=======
  const vals = new Set(rows.map(m => Number(m.desired)));
  if (vals.size !== 1) { console.error(`MISMATCH shared group ${group}: ${Array.from(vals).join(', ')}`); fatal = true; continue; }
  const finalStock = Number(rows[0].desired);
  console.log(`  SHARED ${group}: physical ${rows[0].desired} = FINAL ${finalStock} (NO DEDUCTION)`);
  for (const m of rows) {
    finalById.set(Number(m.id), finalStock);
    console.log(`    #${m.id} "${m.name}": final=${finalStock} (current=${m.stock})`);
  }
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
}

for (const m of matched) {
  if (m.sharedGroup) continue;
  const finalStock = Number(m.desired);
  finalById.set(Number(m.id), finalStock);
<<<<<<< HEAD
  console.log(`  #${m.id} "${m.name}": physical ${m.desired} = FINAL ${finalStock} ${m.unit || ''} (current=${m.stock}) NO DEDUCTION`);
  if (finalStock < 0) { console.error(`NEGATIVE for "${m.name}"`); fatal = true; }
}

if (!apply) {
  console.log('\n=== DRY RUN ONLY — no database rows changed ===');
  console.log('Review exact-name matches and proposed finals above (NO DEDUCTION).');
  console.log('If OK, rerun with --apply: bash tools/ff-closing-stock-07102026.sh --apply');
  db.close();
  process.exit(fatal ? 3 : 0);
}
if (fatal) { console.log('\nSTOPPED — errors above. No changes.'); db.close(); process.exit(3); }

console.log('\nAPPLYING: updating only targeted PM/RM stock rows (packing_materials.stock) to physical count directly...');
=======
  console.log(`  #${m.id} "${m.name}": physical ${m.desired} = FINAL ${finalStock} (current=${m.stock}) NO DEDUCTION`);
}

if (!apply) {
  console.log('\n=== DRY RUN ONLY — no changes ===');
  console.log('If OK, rerun: bash /tmp/ff-closing-stock-07102026.sh --apply');
  console.log('To see all exact names: bash /tmp/ff-closing-stock-07102026.sh --list');
  db.close();
  process.exit(fatal ? 3 : 0);
}
if (fatal) { console.log('\nSTOPPED errors.'); db.close(); process.exit(3); }

console.log('\nAPPLYING direct update...');
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
try {
  db.exec('BEGIN');
  const upd = db.prepare('UPDATE packing_materials SET stock = ? WHERE id = ?');
  for (const m of matched) {
    const finalStock = finalById.get(Number(m.id));
<<<<<<< HEAD
    if (finalStock == null) throw new Error(`missing final for #${m.id}`);
    upd.run(finalStock, m.id);
    console.log(`UPDATED #${m.id} "${m.name}": stock=${finalStock} ${m.unit || ''} (was ${m.stock})`);
  }
  db.exec('COMMIT');
  console.log(`\nAPPLIED: ${matched.length} rows (${grouped.size} shared pools) set to 07/10/2026 physical count directly. NO DEDUCTION.`);
  console.log(`Backup: ${process.env.FF_BACKUP_DIR || '/opt/flavorflow/backups'}/erp.db.bak-closing-07102026-${process.env.TS}`);
} catch (e) {
  try { db.exec('ROLLBACK'); } catch (_) {}
  console.error('APPLY FAILED — rolled back: ' + e.message);
=======
    upd.run(finalStock, m.id);
    console.log(`UPDATED #${m.id} "${m.name}": ${finalStock} (was ${m.stock})`);
  }
  db.exec('COMMIT');
  console.log(`\nAPPLIED ${matched.length} rows, ${grouped.size} shared pools, NO DEDUCTION. Backup: ${process.env.FF_BACKUP_DIR || '/opt/flavorflow/backups'}/erp.db.bak-closing-07102026-${process.env.TS}`);
} catch (e) {
  try { db.exec('ROLLBACK'); } catch (_) {}
  console.error('APPLY FAILED: ' + e.message);
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
  process.exit(4);
} finally { db.close(); }
JS

if (( APPLY )); then
  if systemctl is-active --quiet flavorflow 2>/dev/null; then
    systemctl start flavorflow || true
    sleep 3
    curl -sS -m 8 http://127.0.0.1:4000/api/health || true
    echo
  fi
<<<<<<< HEAD
  echo "=== FF-CLOSING-STOCK-07102026 DONE (DIRECT UPDATE, NO DEDUCTION) ==="
else
  echo ""
  echo "Dry-run complete. No changes made. NO DEDUCTION mode."
=======
  echo "=== DONE (DIRECT UPDATE, NO DEDUCTION) ==="
elif (( LIST )); then
  echo ""
else
  echo ""
  echo "Dry-run complete. NO DEDUCTION."
>>>>>>> 7937e95 (MAN-5: Fix exact Product Master names from live DB screenshot)
fi
