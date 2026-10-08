#!/usr/bin/env bash
# FlavorFlow — 07/10/2026 closing stock reconciliation v3 — DIRECT UPDATE, NO DEDUCTION
# Updated from LATEST screenshots uploaded 2026-10-09:
#   - PM screenshot 07/10/2026 Balance (28 items)
#   - RM screenshot (12 items) — Molasses 59338, Soya been 2403.3 etc.
# Previous v2 had 30 rows with old counts (e.g., Shrink 418903 vs new 402615, Hologram 171038 vs 747262)
# This v3 uses NEW counts as final = physical, no deduction.
#
# Usage:
#   bash /tmp/ff-closing-stock-07102026-v3.sh --list   # list all materials exact names
#   bash /tmp/ff-closing-stock-07102026-v3.sh          # dry-run
#   bash /tmp/ff-closing-stock-07102026-v3.sh --apply  # apply direct update
#
# Download fresh:
#   curl -fsSL -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/fc479533-flavorflow/tools/ff-closing-stock-07102026-v3.sh?v=$(date +%s)" -o /tmp/ff-closing-stock-07102026-v3.sh && chmod +x /tmp/ff-closing-stock-07102026-v3.sh
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
  cp -a "$DB" "$BACKUP_DIR/erp.db.bak-closing-07102026-v3-$TS"
  echo "DB BACKUP: $BACKUP_DIR/erp.db.bak-closing-07102026-v3-$TS"
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
const path = require('path');
const db = new DatabaseSync(process.env.FF_DB);
const closingDate = process.env.CLOSING_DATE;
const startDate = process.env.START_DATE;
const apply = process.env.APPLY === '1';
const listMode = process.env.LIST === '1';
let countJsonPath = process.env.COUNT_JSON;

// try default v3 json in repo if no env provided
if (!countJsonPath) {
  const candidates = [
    '/opt/flavorflow/server/tools/data/closing-stock-07102026-v3.json',
    path.join(__dirname, 'data/closing-stock-07102026-v3.json'),
    path.join(process.cwd(), 'tools/data/closing-stock-07102026-v3.json'),
    '/home/manjotkhehra74/FlavorFlow/tools/data/closing-stock-07102026-v3.json'
  ];
  for (const c of candidates) { if (fs.existsSync(c)) { countJsonPath = c; break; } }
}

const n = (v) => Number(v) || 0;
const text = (v) => String(v ?? '').trim();
const norm = (v) => text(v).toLowerCase().replace(/[^a-z0-9]+/g, ' ').replace(/\s+/g, ' ').trim();
const cols = (table) => db.prepare('PRAGMA table_info(' + table + ')').all().map((r) => String(r.name));
const tables = new Set(db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map((r) => String(r.name)));
const hasTable = (t) => tables.has(t);
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
  console.log(`\nCopy exact names from above into tools/data/closing-stock-07102026-v3.json`);
  db.close();
  process.exit(0);
}

let rawTargets = [];

function loadExternal(p) {
  if (!p) return null;
  if (!fs.existsSync(p)) return null;
  const data = JSON.parse(fs.readFileSync(p, 'utf8'));
  const out = [];
  if (Array.isArray(data)) {
    for (const row of data) {
      if (!row.name || row.count == null) continue;
      out.push({ 
        name: String(row.name).trim(), 
        count: Number(row.count), 
        kind: row.kind || null, 
        sharedGroup: row.sharedGroup || null,
        alt_names: row.alt_names || [],
        image_name: row.image_name || ''
      });
    }
  } else if (typeof data === 'object') {
    for (const [k, v] of Object.entries(data)) {
      if (typeof v === 'number') out.push({ name: k.trim(), count: v, kind: null, sharedGroup: null, alt_names: [] });
      else if (v && typeof v === 'object') out.push({ name: k.trim(), count: Number(v.count), kind: v.kind || null, sharedGroup: v.sharedGroup || null, alt_names: v.alt_names || [] });
    }
  }
  return out;
}

const external = loadExternal(countJsonPath);
if (external && external.length) {
  console.log(`Loaded ${external.length} targets from ${countJsonPath}`);
  rawTargets = external;
} else {
  // Fallback embedded — from latest screenshots 09/10/2026
  rawTargets = [
    // PM — 07/10/2026 Balance screenshot
    { name: 'Red Cap (180/220)', count: 174245, kind: 'packing', image_name: 'Red Caps 180/220' },
    { name: 'Crown Cork (220)', count: 103064, kind: 'packing', image_name: 'Crown Cork 220' },
    { name: 'Label White (180)', count: 143656, kind: 'packing', image_name: 'Label White vin 180' },
    { name: 'Dark S Label (250)', count: 0, kind: 'packing', image_name: 'Label D Soya 220' },
    { name: 'Hologram (180/220)', count: 747262, kind: 'packing', image_name: 'Hologram 180/220' },
    { name: 'Plug (180)', count: 407847, kind: 'packing', image_name: 'Plug 180' },
    { name: 'Glass Bottles 180/220', count: 81068, kind: 'packing', alt_names: ['Glass Bottle 180/220'], image_name: 'Glass Bottles 180/220' },
    { name: 'Carton CB 180/220', count: 4123, kind: 'packing', image_name: 'CB 180/220' },
    { name: 'Cap Orange (610)', count: 1165805, kind: 'packing', image_name: 'Cap Orange 610' },
    { name: 'Shrink Sleeve White 610', count: 406086, kind: 'packing', image_name: 'Shrink White Vin 610' },
    { name: 'Shrink Sleeve Brown 610', count: 15265, kind: 'packing', image_name: 'Shrink Vin Brown 610' },
    { name: 'Cap Purple (740)', count: 168861, kind: 'packing', image_name: 'Cap Purple 740' },
    { name: 'Shrink Sleeve 740', count: 402615, kind: 'packing', image_name: 'Shrink Soya 740' },
    { name: 'Carton CB (610/740)', count: 5276, kind: 'packing', image_name: 'CB 610/740' },
    { name: 'HDPE Bottles', count: 129556, kind: 'packing', alt_names: ['HDPE Bottle (610/740)', 'HDPE Bottles 610/740'], image_name: 'HDPE Bottles' },
    { name: 'Tray Soya', count: 18819, kind: 'packing', image_name: 'Tray Soya' },
    { name: 'Tray Top', count: 18175, kind: 'packing', image_name: 'Tray Top' },
    { name: 'Red Cap (1.3 / 1 Ltr)', count: 16172, kind: 'packing', image_name: 'Red Cap' },
    { name: 'Label Soya 1.3', count: 30155, kind: 'packing', image_name: 'Label 1.3' },
    { name: 'Label White (1 Ltr)', count: 61103, kind: 'packing', alt_names: ['Label 1 Ltr', 'Label White 1 Ltr'], image_name: 'Label 1 Ltr' },
    { name: 'Bottles 1.3', count: 18808, kind: 'packing', alt_names: ['Bottle 1.3', 'PET Bottle 1.3'], image_name: 'Bottles 1.3' },
    { name: 'Carton CB (1.3/1 Ltr)', count: 165, kind: 'packing', image_name: 'CB 1.3' },
    { name: 'Tray', count: 382, kind: 'packing', image_name: 'Tray' },
    { name: 'Tray Cap', count: 322, kind: 'packing', image_name: 'Tray Cap' },
    { name: 'Jerry Can 4 Ltr', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared', image_name: 'Jerry Can' },
    { name: 'Jerry Can 4.7kg', count: 8016, kind: 'packing', sharedGroup: 'jerry-shared', image_name: 'Jerry Can' },
    { name: 'Label Front 4 Ltr', count: 4092, kind: 'packing', image_name: 'Label vin' },
    { name: 'Label Front 4.7', count: 5623, kind: 'packing', image_name: 'Label Soya' },
    { name: 'Carton CB 4 Ltr', count: 31, kind: 'packing', alt_names: ['CB', 'Carton CB', 'CB 4 Ltr'], image_name: 'CB 31' },

    // RM — from RM screenshot 09/10/2026
    { name: 'Molasses', count: 59338, kind: 'raw', image_name: 'Molasses' },
    { name: 'Soyabean', count: 2403.3, kind: 'raw', image_name: 'Soya been' },
    { name: 'White Salt', count: 26383.5, kind: 'raw', alt_names: ['Salt'], image_name: 'Salt' },
    { name: 'Coriander Oleoresin', count: 36.476, kind: 'raw', image_name: 'Dhaniya ole.' },
    { name: 'Garlic Oleoresin', count: 27.176, kind: 'raw', image_name: 'Garlic ole' },
    { name: 'Cinnamon Oleoresin', count: 27.598, kind: 'raw', image_name: 'Dalchini ole' },
    { name: 'Turmeric Powder', count: 27.895, kind: 'raw', alt_names: ['Haldi', 'Haldi Powder'], image_name: 'Haldi' },
    { name: 'Potassium Sorbate', count: 247.76, kind: 'raw', image_name: 'Pot. Sorbeta' },
    { name: 'Acetic Acid', count: 25598, kind: 'raw', image_name: 'Acetic Acid' },
    { name: 'Caramel Colour (E150a)', count: 12412.5, kind: 'raw', image_name: 'Caramel 150 A' },
    { name: 'Caramel Colour (E150c)', count: 233, kind: 'raw', alt_names: ['Caramel Colour E150c'], image_name: 'Caramel 150 C' },
    { name: 'Black Salt', count: 100, kind: 'raw', image_name: 'Black salt' },
  ];
}

const deduped = new Map();
for (const t of rawTargets) {
  if (!t.name) continue;
  const key = t.name.trim();
  if (!deduped.has(key)) deduped.set(key, t);
}
let targets = Array.from(deduped.values());

console.log(`\n=== FlavorFlow 07/10/2026 Closing Stock Reconciliation v3 (DIRECT UPDATE, NO DEDUCTION) ===`);
console.log(`Closing Date: ${closingDate} | Window (info only): ${startDate} -> ${closingDate}`);
console.log(`Mode: ${apply ? 'APPLY' : 'DRY-RUN'} — NO DEDUCTION, final = physical from LATEST screenshots`);
console.log(`DB: ${process.env.FF_DB} | Targets: ${targets.length}\n`);

function findExact(name, kind, altNames=[]) {
  // 1) exact case-sensitive
  let candidates = allMaterials.filter(m => m.name === name);
  if (candidates.length === 1) return candidates;
  // 2) alt_names exact
  for (const alt of altNames) {
    candidates = allMaterials.filter(m => m.name === alt);
    if (candidates.length === 1) {
      console.log(`  ALT exact match "${name}" -> alt "${alt}" -> "${candidates[0].name}"`);
      return candidates;
    }
  }
  // 3) case-insensitive
  candidates = allMaterials.filter(m => m.name.toLowerCase() === name.toLowerCase());
  if (candidates.length === 1) {
    console.log(`  WARN case-insensitive match for "${name}" -> "${candidates[0].name}"`);
    return candidates;
  }
  for (const alt of altNames) {
    candidates = allMaterials.filter(m => m.name.toLowerCase() === alt.toLowerCase());
    if (candidates.length === 1) {
      console.log(`  ALT case-insensitive "${name}" alt "${alt}" -> "${candidates[0].name}"`);
      return candidates;
    }
  }
  // 4) normalized includes for lenient matching (to help find Tray, CB etc)
  const nName = norm(name);
  candidates = allMaterials.filter(m => norm(m.name) === nName);
  if (candidates.length === 1) {
    console.log(`  NORM exact "${name}" -> "${candidates[0].name}"`);
    return candidates;
  }
  for (const alt of altNames) {
    const nAlt = norm(alt);
    candidates = allMaterials.filter(m => norm(m.name) === nAlt);
    if (candidates.length === 1) {
      console.log(`  ALT NORM "${name}" alt "${alt}" -> "${candidates[0].name}"`);
      return candidates;
    }
  }
  // 5) try contains for short names like "Tray" — but only if kind matches and single
  if (kind) {
    const wantRaw = kind === 'raw';
    let filtered = allMaterials.filter(m => {
      const cat = norm(m.category);
      if (wantRaw) return cat === 'raw material';
      return cat !== 'raw material';
    });
    // exact norm contains
    const contains = filtered.filter(m => norm(m.name).includes(nName) || nName.includes(norm(m.name)));
    if (contains.length === 1) {
      console.log(`  CONTAINS match "${name}" -> "${contains[0].name}"`);
      return contains;
    }
  }
  // 6) category filter if kind specified for previous exact attempts
  if (kind) {
    const wantRaw = kind === 'raw';
    let c = allMaterials.filter(m => m.name === name);
    if (c.length===0) c = allMaterials.filter(m => m.name.toLowerCase() === name.toLowerCase());
    c = c.filter(m => {
      const cat = norm(m.category);
      if (wantRaw) return cat === 'raw material';
      return cat !== 'raw material';
    });
    if (c.length===1) return c;
  }
  return [];
}

const matched = [];
let fatal = false;
const seenIds = new Set();

for (const t of targets) {
  const candidates = findExact(t.name, t.kind, t.alt_names || []);
  if (candidates.length !== 1) {
    if (candidates.length === 0) {
      console.log(`TARGET "${t.name}" (image: "${t.image_name||''}") : NOT FOUND — trying similar:`);
      const similar = allMaterials.filter(m => norm(m.name).includes(norm(t.name).split(' ')[0])).slice(0,8).map(m => `[#${m.id} "${m.name}" (${m.category}) stock=${m.stock}]`).join(' ');
      console.log(`  ${similar || '(no similar)'}`);
      // also try all with same kind
      if (t.kind) {
        const kindMats = allMaterials.filter(m => {
          const cat = norm(m.category);
          return t.kind==='raw' ? cat==='raw material' : cat!=='raw material';
        }).slice(0,5).map(m => `[#${m.id} "${m.name}"]`).join(' ');
        console.log(`  kind=${t.kind} examples: ${kindMats}`);
      }
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
      console.log(`DUPLICATE DB ROW #${m.id} "${m.name}" counts differ ${prev.desired} vs ${t.count} (image ${t.image_name})`);
      fatal = true;
    }
    continue;
  }
  seenIds.add(m.id);
  matched.push({ label: t.name, desired: Number(t.count), kind: t.kind, sharedGroup: t.sharedGroup || null, image_name: t.image_name || '', ...m });
  console.log(`MATCH "${t.name}" (img "${t.image_name||''}") -> #${m.id} "${m.name}" | current=${m.stock} ${m.unit||''} | 07/10 closing=${t.count} ${m.unit||''}${t.sharedGroup?` | shared=${t.sharedGroup}`:''}`);
}

if (fatal) {
  console.log('\nSTOPPED: fix exact names. Run with --list to see all exact Product Master names:');
  console.log('  bash /tmp/ff-closing-stock-07102026-v3.sh --list');
  console.log('  Then update tools/data/closing-stock-07102026-v3.json with exact names');
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

console.log('\nPROPOSED FINAL BALANCES (DIRECT UPDATE, NO DEDUCTION) — v3 from latest screenshots:');
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
    console.log(`    #${m.id} "${m.name}": final=${finalStock} (current=${m.stock}) img=${m.image_name}`);
  }
}

for (const m of matched) {
  if (m.sharedGroup) continue;
  const finalStock = Number(m.desired);
  finalById.set(Number(m.id), finalStock);
  console.log(`  #${m.id} "${m.name}": physical ${m.desired} = FINAL ${finalStock} (current=${m.stock}) img=${m.image_name} NO DEDUCTION`);
}

if (!apply) {
  console.log('\n=== DRY RUN ONLY — no changes ===');
  console.log('If OK, rerun: bash /tmp/ff-closing-stock-07102026-v3.sh --apply');
  console.log('To see all exact names: bash /tmp/ff-closing-stock-07102026-v3.sh --list');
  db.close();
  process.exit(fatal ? 3 : 0);
}
if (fatal) { console.log('\nSTOPPED errors.'); db.close(); process.exit(3); }

console.log('\nAPPLYING direct update v3...');
try {
  db.exec('BEGIN');
  const upd = db.prepare('UPDATE packing_materials SET stock = ? WHERE id = ?');
  for (const m of matched) {
    const finalStock = finalById.get(Number(m.id));
    upd.run(finalStock, m.id);
    console.log(`UPDATED #${m.id} "${m.name}": ${finalStock} (was ${m.stock}) img=${m.image_name}`);
  }
  db.exec('COMMIT');
  console.log(`\nAPPLIED ${matched.length} rows, ${grouped.size} shared pools, NO DEDUCTION. Backup: ${process.env.FF_BACKUP_DIR || '/opt/flavorflow/backups'}/erp.db.bak-closing-07102026-v3-${process.env.TS}`);
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
  echo "=== DONE v3 (DIRECT UPDATE, NO DEDUCTION) ==="
elif (( LIST )); then
  echo ""
else
  echo ""
  echo "Dry-run complete v3. NO DEDUCTION."
fi
