#!/usr/bin/env bash
# FlavorFlow — 07/10/2026 closing stock reconciliation v4 — DIRECT UPDATE, NO DEDUCTION
# Built from LIVE --list output 09/10/2026 09:33 (49 materials exact names)
# Transcribed from latest screenshots:
#   PM 07/10/2026 Balance (28 counts) + RM 12 counts = 40 physical, 41 DB rows (Jerry shared)
# Previous v2 had wrong counts (e.g., Hologram 171038 vs 747262, Shrink 418903 vs 402615)
# This v4 uses EXACT names from live DB --list, so MATCH 100% guaranteed.
#
# Usage:
#   bash /tmp/ff-closing-stock-07102026-v4.sh --list
#   bash /tmp/ff-closing-stock-07102026-v4.sh          # dry-run
#   bash /tmp/ff-closing-stock-07102026-v4.sh --apply  # apply
#
set -euo pipefail

DB="${FF_DB:-/opt/flavorflow/server/data/erp.db}"
CLOSING_DATE="${FF_CLOSING_DATE:-2026-10-07}"
START_DATE="${FF_START_DATE:-2026-10-05}"
COUNT_JSON="${FF_COUNT_JSON:-}"
APPLY=0
LIST=0
if [[ "${1:-}" == "--apply" ]]; then APPLY=1; fi
if [[ "${1:-}" == "--list" ]]; then LIST=1; fi
if [[ "${2:-}" == "--list" ]]; then LIST=1; fi

[ -f "$DB" ] || { echo "FATAL: database not found: $DB"; exit 1; }
command -v node >/dev/null || { echo "FATAL: node required"; exit 1; }

BACKUP_DIR="${FF_BACKUP_DIR:-/opt/flavorflow/backups}"
TS=$(date +%Y%m%d-%H%M%S)
if (( APPLY )); then
  mkdir -p "$BACKUP_DIR"
  cp -a "$DB" "$BACKUP_DIR/erp.db.bak-closing-07102026-v4-$TS"
  echo "BACKUP: $BACKUP_DIR/erp.db.bak-closing-07102026-v4-$TS"
  if systemctl is-active --quiet flavorflow 2>/dev/null; then systemctl stop flavorflow || true; sleep 1; fi
fi

export FF_DB="$DB" CLOSING_DATE START_DATE APPLY TS COUNT_JSON LIST

node <<'JS'
'use strict';
let DatabaseSync;
try { DatabaseSync = require('/opt/flavorflow/server/sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) try { DatabaseSync = require('node:sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) { console.error('FATAL: SQLite wrapper missing'); process.exit(1); }
const fs = require('fs');
const db = new DatabaseSync(process.env.FF_DB);
const closingDate = process.env.CLOSING_DATE;
const startDate = process.env.START_DATE;
const apply = process.env.APPLY === '1';
const listMode = process.env.LIST === '1';
const countJsonPath = process.env.COUNT_JSON;

const cols = (table) => db.prepare('PRAGMA table_info(' + table + ')').all().map(r=>String(r.name));
const tables = new Set(db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(r=>String(r.name)));
const hasTable = t=>tables.has(t);
const q = (sql,args=[])=>db.prepare(sql).all(...args);
const norm = v=>String(v??'').trim().toLowerCase().replace(/[^a-z0-9]+/g,' ').replace(/\s+/g,' ').trim();

const allMaterials = q('SELECT id, name, category, unit, COALESCE(stock,0) stock FROM packing_materials ORDER BY id');

if (listMode) {
  console.log(`\n=== ALL Product Master materials — DB: ${process.env.FF_DB} ===\nTotal: ${allMaterials.length}\n`);
  const byCat={}; for(const m of allMaterials){ if(!byCat[m.category]) byCat[m.category]=[]; byCat[m.category].push(m); }
  for(const cat of Object.keys(byCat).sort()){
    console.log(`\n--- Category: ${cat} (${byCat[cat].length}) ---`);
    for(const m of byCat[cat]) console.log(`#${m.id} | "${m.name}" | stock=${m.stock} ${m.unit||''} | category=${m.category}`);
  }
  db.close(); process.exit(0);
}

let rawTargets=[];
function loadExternal(p){
  if(!p) return null;
  if(!fs.existsSync(p)) return null;
  const data=JSON.parse(fs.readFileSync(p,'utf8'));
  const out=[];
  for(const row of data){ if(!row.name||row.count==null) continue; out.push({name:String(row.name).trim(),count:Number(row.count),kind:row.kind||null,sharedGroup:row.sharedGroup||null}); }
  return out;
}
let external = loadExternal(countJsonPath);
if (!external) {
  // try default paths
  const tryPaths=['/opt/flavorflow/server/tools/data/closing-stock-07102026-v4.json','tools/data/closing-stock-07102026-v4.json','/home/user/FlavorFlow/tools/data/closing-stock-07102026-v4.json'];
  for(const p of tryPaths){ if(fs.existsSync(p)){ external=loadExternal(p); if(external){ console.log(`Loaded ${external.length} from ${p}`); break; } } }
}
if (external && external.length) rawTargets=external;
else {
  // embedded exact names from live --list 09:33
  rawTargets=[
    {name:'Red Cap (180/220)',count:174245,kind:'packing'},
    {name:'Crown Cork (220)',count:103064,kind:'packing'},
    {name:'Label White (180)',count:143656,kind:'packing'},
    {name:'Dark S Label (220)',count:0,kind:'packing'},
    {name:'Hologram (180/220)',count:747262,kind:'packing'},
    {name:'Plug (180)',count:407847,kind:'packing'},
    {name:'Glass Bottles 180/220',count:81068,kind:'packing'},
    {name:'Carton CB 180/220',count:4123,kind:'packing'},
    {name:'Cap Orange (610)',count:1165805,kind:'packing'},
    {name:'Shrink Sleeve White 610',count:406086,kind:'packing'},
    {name:'Shrink Sleeve Brown 610',count:15265,kind:'packing'},
    {name:'Cap Purple (740)',count:168861,kind:'packing'},
    {name:'Shrink Sleeve 740',count:402615,kind:'packing'},
    {name:'Carton CB (610/740)',count:5276,kind:'packing'},
    {name:'HDPE Bottle (610/740)',count:129556,kind:'packing'},
    {name:'Tray (740/610)',count:18819,kind:'packing'},
    {name:'Tray Cap (740/610)',count:18175,kind:'packing'},
    {name:'Red Cap (1.3 / 1 Ltr)',count:16172,kind:'packing'},
    {name:'Label Soya 1.3',count:30155,kind:'packing'},
    {name:'Label Vinegar 1 Ltr',count:61103,kind:'packing'},
    {name:'HDPE Bottle (1.3/1 Ltr)',count:18808,kind:'packing'},
    {name:'Carton CB (1.3/1 Ltr)',count:165,kind:'packing'},
    {name:'Tray (1.3/1 Ltr)',count:382,kind:'packing'},
    {name:'Tray Cap (1.3/1 Ltr)',count:322,kind:'packing'},
    {name:'Jerry Can 4 Ltr',count:8016,kind:'packing',sharedGroup:'jerry-shared'},
    {name:'Jerry Can 4.7kg',count:8016,kind:'packing',sharedGroup:'jerry-shared'},
    {name:'Label Front 4 Ltr',count:4092,kind:'packing'},
    {name:'Label Front 4.7',count:5623,kind:'packing'},
    {name:'Carton CB 4.7/4 Ltr',count:31,kind:'packing'},
    {name:'Molasses',count:59338,kind:'raw'},
    {name:'Soyabean',count:2403.3,kind:'raw'},
    {name:'White Salt',count:26383.5,kind:'raw'},
    {name:'Coriander Oleoresin',count:36.476,kind:'raw'},
    {name:'Garlic Oleoresin',count:27.176,kind:'raw'},
    {name:'Cinnamon Oleoresin',count:27.598,kind:'raw'},
    {name:'Turmeric Powder',count:27.895,kind:'raw'},
    {name:'Potassium Sorbate',count:247.76,kind:'raw'},
    {name:'Acetic Acid',count:25598,kind:'raw'},
    {name:'Caramel Colour (E150a)',count:12412.5,kind:'raw'},
    {name:'Caramel Colour (E150c)',count:233,kind:'raw'},
    {name:'Black Salt',count:100,kind:'raw'},
  ];
}

const deduped=new Map();
for(const t of rawTargets){ const k=t.name.trim(); if(!deduped.has(k)) deduped.set(k,t); }
let targets=Array.from(deduped.values());

console.log(`\n=== FlavorFlow 07/10/2026 v4 (DIRECT UPDATE, NO DEDUCTION) ===`);
console.log(`Closing: ${closingDate} | Mode: ${apply?'APPLY':'DRY-RUN'} | DB: ${process.env.FF_DB} | Targets: ${targets.length}\n`);

function findExact(name,kind){
  let c=allMaterials.filter(m=>m.name===name);
  if(c.length===0) c=allMaterials.filter(m=>m.name.toLowerCase()===name.toLowerCase());
  if(kind){
    const wantRaw=kind==='raw';
    c=c.filter(m=>{ const cat=norm(m.category); return wantRaw?cat==='raw material':cat!=='raw material'; });
  }
  return c;
}

const matched=[];
let fatal=false;
const seen=new Set();
for(const t of targets){
  const cands=findExact(t.name,t.kind);
  if(cands.length!==1){
    if(cands.length===0){
      console.log(`TARGET "${t.name}": NOT FOUND`);
      const sim=allMaterials.filter(m=>norm(m.name).includes(norm(t.name).split(' ')[0])).slice(0,5).map(m=>`[#${m.id} "${m.name}"]`).join(' ');
      console.log(`  similar: ${sim}`);
    } else console.log(`TARGET "${t.name}": AMBIGUOUS ${cands.map(m=>`[#${m.id} "${m.name}"]`).join(' ')}`);
    fatal=true; continue;
  }
  const m=cands[0];
  if(seen.has(m.id)){ const prev=matched.find(x=>x.id===m.id); if(prev&&Number(prev.desired)!==Number(t.count)){ console.log(`DUPLICATE #${m.id} ${prev.desired} vs ${t.count}`); fatal=true; } continue; }
  seen.add(m.id);
  matched.push({...m,label:t.name,desired:Number(t.count),kind:t.kind,sharedGroup:t.sharedGroup||null});
  console.log(`MATCH "${t.name}" -> #${m.id} "${m.name}" | current=${m.stock} | closing=${t.count}${t.sharedGroup?` | shared=${t.sharedGroup}`:''}`);
}
if(fatal){ console.log('\nSTOPPED: fix names, run --list'); db.close(); process.exit(2); }

console.log('\nPROPOSED FINAL (NO DEDUCTION):');
const finalById=new Map();
const grouped=new Map();
for(const m of matched) if(m.sharedGroup){ if(!grouped.has(m.sharedGroup)) grouped.set(m.sharedGroup,[]); grouped.get(m.sharedGroup).push(m); }
for(const [g,rows] of grouped){
  const vals=new Set(rows.map(m=>Number(m.desired))); if(vals.size!==1){ console.error(`MISMATCH ${g}`); fatal=true; continue; }
  const finalStock=Number(rows[0].desired);
  console.log(`  SHARED ${g}: FINAL ${finalStock}`);
  for(const m of rows){ finalById.set(Number(m.id),finalStock); console.log(`    #${m.id} "${m.name}": final=${finalStock} (was ${m.stock})`); }
}
for(const m of matched){ if(m.sharedGroup) continue; finalById.set(Number(m.id),Number(m.desired)); console.log(`  #${m.id} "${m.name}": physical ${m.desired} = FINAL ${Number(m.desired)} (was ${m.stock})`); }

if(!apply){ console.log('\n=== DRY RUN ONLY ==='); console.log('Rerun --apply if OK'); db.close(); process.exit(fatal?3:0); }
if(fatal){ db.close(); process.exit(3); }

console.log('\nAPPLYING...');
try{
  db.exec('BEGIN');
  const upd=db.prepare('UPDATE packing_materials SET stock = ? WHERE id = ?');
  for(const m of matched){ const f=finalById.get(Number(m.id)); upd.run(f,m.id); console.log(`UPDATED #${m.id} "${m.name}": ${f} (was ${m.stock})`); }
  db.exec('COMMIT');
  console.log(`\nAPPLIED ${matched.length} rows, ${grouped.size} shared, NO DEDUCTION. Backup v4: ${process.env.TS}`);
}catch(e){ try{db.exec('ROLLBACK');}catch(_){} console.error('FAILED '+e.message); process.exit(4); } finally{ db.close(); }
JS

if (( APPLY )); then
  if systemctl is-active --quiet flavorflow 2>/dev/null; then systemctl start flavorflow || true; sleep 2; curl -sS -m 5 http://127.0.0.1:4000/api/health || true; echo; fi
  echo "=== DONE v4 ==="
else
  echo "Dry-run v4 done"
fi
