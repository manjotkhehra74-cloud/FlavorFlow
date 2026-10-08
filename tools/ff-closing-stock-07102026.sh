#!/usr/bin/env bash
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
#
set -euo pipefail

DB="${FF_DB:-/opt/flavorflow/server/data/erp.db}"
SERVER_DIR="${FF_SERVER_DIR:-/opt/flavorflow/server}"
CLOSING_DATE="${FF_CLOSING_DATE:-2026-10-07}"
START_DATE="${FF_START_DATE:-2026-10-05}"
COUNT_JSON="${FF_COUNT_JSON:-}"
APPLY=0
LIST=0
if [[ "${1:-}" == "--apply" ]]; then APPLY=1; fi
if [[ "${1:-}" == "--list" ]]; then LIST=1; fi
if [[ "${2:-}" == "--list" ]]; then LIST=1; fi

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

export FF_DB="$DB" CLOSING_DATE START_DATE APPLY TS SERVER_DIR COUNT_JSON LIST

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
const listMode = process.env.LIST === '1';
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
    rawTargets = [
    { name: 'Shrink Sleeve 740', count: 418903, kind: 'packing' },
    { name: 'Shrink Sleeve White 610', count: 436562, kind: 'packing' },
    { name: 'Shrink Sleeve Brown 610', count: 15265, kind: 'packing' },
    { name: 'Label Soya 1.3', count: 30155, kind: 'packing' },
    { name: 'Label White (180)', count: 158172, kind: 'packing' },
    { name: 'Label Front 4 Ltr', count: 4092, kind: 'packing' },
    { name: 'Label Front 4.7', count: 4200, kind: 'packing' },
    { name: 'Dark S Label (250)', count: 10023, kind: 'packing' },
    { name: 'Hologram (180/220)', count: 171038, kind: 'packing', sharedGroup: 'hologram-180-220' },
    { name: 'Cap Orange (610)', count: 1195479, kind: 'packing' },
    { name: 'Cap Purple (740)', count: 184785, kind: 'packing' },
    { name: 'Red Cap (1.3 / 1 Ltr)', count: 22518, kind: 'packing' },
    { name: 'Red Cap (180/220)', count: 135615, kind: 'packing' },
    { name: 'Plug (180)', count: 422444, kind: 'packing' },
    { name: 'Crown Cork (220)', count: 113050, kind: 'packing' },
    { name: 'Carton CB 180/220', count: 5151, kind: 'packing' },
    { name: 'Carton CB (610/740)', count: 7812, kind: 'packing' },
    { name: 'Carton CB (1.3/1 Ltr)', count: 695, kind: 'packing' },
    { name: 'Jerry Can 4 Ltr', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared' },
    { name: 'Jerry Can 4.7kg', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared' },
    { name: 'Soyabean', count: 446.30, kind: 'raw' },
    { name: 'Potassium Sorbate', count: 277.46, kind: 'raw' },
    { name: 'Citric Acid', count: 623.20, kind: 'raw' },
    { name: 'Ascorbic Acid', count: 30.80, kind: 'raw' },
    { name: 'Sodium Benzoate', count: 1.16, kind: 'raw' },
    { name: 'Garlic Oleoresin', count: 29.49, kind: 'raw' },
    { name: 'Cinnamon Oleoresin', count: 28.48, kind: 'raw' },
    { name: 'Coriander Oleoresin', count: 38.79, kind: 'raw' },
    { name: 'Caramel Colour (E150a)', count: 4757.50, kind: 'raw' },
    { name: 'Black Salt', count: 100, kind: 'raw' },
  ];
}

const deduped = new Map();
for (const t of rawTargets) {
  if (!t.name) continue;
  const key = t.name.trim();
  if (!deduped.has(key)) deduped.set(key, t);
}
let targets = Array.from(deduped.values());

console.log(`\n=== FlavorFlow 07/10/2026 Closing Stock Reconciliation (DIRECT UPDATE, NO DEDUCTION) ===`);
console.log(`Closing Date: ${closingDate} | Window (info only): ${startDate} -> ${closingDate}`);
console.log(`Mode: ${apply ? 'APPLY' : 'DRY-RUN'} — NO DEDUCTION, final = physical`);
console.log(`DB: ${process.env.FF_DB} | Targets: ${targets.length}\n`);

function findExact(name, kind) {
  let candidates = allMaterials.filter(m => m.name === name);
  if (candidates.length === 0) {
    candidates = allMaterials.filter(m => m.name.toLowerCase() === name.toLowerCase());
    if (candidates.length === 1) console.log(`  WARN case-insensitive match for "${name}" -> "${candidates[0].name}"`);
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
const seenIds = new Set();

for (const t of targets) {
  const candidates = findExact(t.name, t.kind);
  if (candidates.length !== 1) {
    if (candidates.length === 0) {
      console.log(`TARGET "${t.name}": NOT FOUND (exact required) — similar:`);
      const similar = allMaterials.filter(m => norm(m.name).includes(norm(t.name).split(' ')[0])).slice(0,5).map(m => `[#${m.id} "${m.name}" (${m.category})]`).join(' ');
      console.log(`  ${similar || '(no similar)'}`);
    } else {
      console.log(`TARGET "${t.name}": AMBIGUOUS ${candidates.map(m => `[#${m.id} "${m.name}"]`).join(' ')}`);
    }
    fatal = true;
    continue;
  }
  const m = candidates[0];
  if (seenIds.has(m.id)) {
    const prev = matched.find(x => x.id === m.id);
    if (prev && Number(prev.desired) !== Number(t.count)) {
      console.log(`DUPLICATE DB ROW #${m.id} "${m.name}" counts differ ${prev.desired} vs ${t.count}`);
      fatal = true;
    }
    continue;
  }
  seenIds.add(m.id);
  matched.push({ label: t.name, desired: Number(t.count), kind: t.kind, sharedGroup: t.sharedGroup || null, ...m });
  console.log(`MATCH "${t.name}" -> #${m.id} "${m.name}" | current=${m.stock} ${m.unit || ''} | 07/10 closing=${t.count} ${m.unit || ''}${t.sharedGroup ? ` | shared=${t.sharedGroup}` : ''}`);
}

if (fatal) {
  console.log('\nSTOPPED: fix exact names. Run with --list to see all exact Product Master names:');
  console.log('  bash /tmp/ff-closing-stock-07102026.sh --list');
  db.close();
  process.exit(2);
}

console.log(`\nCOMPLETED PRODUCTION BETWEEN ${startDate} AND ${closingDate} (INFO ONLY):`);
if (hasTable('batches')) {
  const bc = cols('batches');
  const dateCol = bc.includes('production_date') ? 'production_date' : (bc.includes('planned_date') ? 'planned_date' : null);
  if (dateCol) {
    try {
      const rows = q(`SELECT b.${dateCol} date, b.product_id, COALESCE(b.product_name,'') product_name, COALESCE(b.produced_cb,0) produced_cb FROM batches b WHERE UPPER(COALESCE(b.status,''))='COMPLETED' AND b.${dateCol} > ? AND b.${dateCol} <= ? ORDER BY b.${dateCol}, b.id`, [startDate, closingDate]);
      if (!rows.length) console.log('  none');
      for (const r of rows) console.log(`  ${r.date} | ${r.product_name || ('product #' + r.product_id)} | CB ${r.produced_cb}`);
    } catch (e) { console.log(`  WARN: ${e.message}`); }
  }
}

console.log(`\nRECORDED CONSUMPTION BETWEEN ${startDate} AND ${closingDate} (INFO ONLY, NOT DEDUCTED):`);
if (hasTable('packing_txns')) {
  try {
    const rows = q(`SELECT material_id, SUM(COALESCE(qty,0)) qty FROM packing_txns WHERE txn_type IN ('CONSUMED','RECIPE') AND txn_date > ? AND txn_date <= ? GROUP BY material_id`, [startDate, closingDate]);
    if (!rows.length) console.log('  none');
    for (const r of rows) {
      const mat = allMaterials.find(m => m.id === r.material_id);
      console.log(`  #${r.material_id} ${mat ? mat.name : ''}: -${r.qty} (info only)`);
    }
  } catch (e) { console.log(`  WARN: ${e.message}`); }
}

console.log('\nPROPOSED FINAL BALANCES (DIRECT UPDATE, NO DEDUCTION):');
const finalById = new Map();
const grouped = new Map();
for (const m of matched) if (m.sharedGroup) {
  if (!grouped.has(m.sharedGroup)) grouped.set(m.sharedGroup, []);
  grouped.get(m.sharedGroup).push(m);
}

for (const [group, rows] of grouped) {
  const vals = new Set(rows.map(m => Number(m.desired)));
  if (vals.size !== 1) { console.error(`MISMATCH shared group ${group}: ${Array.from(vals).join(', ')}`); fatal = true; continue; }
  const finalStock = Number(rows[0].desired);
  console.log(`  SHARED ${group}: physical ${rows[0].desired} = FINAL ${finalStock} (NO DEDUCTION)`);
  for (const m of rows) {
    finalById.set(Number(m.id), finalStock);
    console.log(`    #${m.id} "${m.name}": final=${finalStock} (current=${m.stock})`);
  }
}

for (const m of matched) {
  if (m.sharedGroup) continue;
  const finalStock = Number(m.desired);
  finalById.set(Number(m.id), finalStock);
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
try {
  db.exec('BEGIN');
  const upd = db.prepare('UPDATE packing_materials SET stock = ? WHERE id = ?');
  for (const m of matched) {
    const finalStock = finalById.get(Number(m.id));
    upd.run(finalStock, m.id);
    console.log(`UPDATED #${m.id} "${m.name}": ${finalStock} (was ${m.stock})`);
  }
  db.exec('COMMIT');
  console.log(`\nAPPLIED ${matched.length} rows, ${grouped.size} shared pools, NO DEDUCTION. Backup: ${process.env.FF_BACKUP_DIR || '/opt/flavorflow/backups'}/erp.db.bak-closing-07102026-${process.env.TS}`);
} catch (e) {
  try { db.exec('ROLLBACK'); } catch (_) {}
  console.error('APPLY FAILED: ' + e.message);
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
  echo "=== DONE (DIRECT UPDATE, NO DEDUCTION) ==="
elif (( LIST )); then
  echo ""
else
  echo ""
  echo "Dry-run complete. NO DEDUCTION."
fi
