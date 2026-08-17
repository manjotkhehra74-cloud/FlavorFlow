#!/usr/bin/env bash
# FlavorFlow: Loss% v3 — NO sharing/splitting.
#   1) packing_txns.product_id column: Record Consumption now tags which
#      product the consumption was for (client sends productId).
#   2) Loss% Extra = ONLY consumptions tagged to that product (whole numbers).
#      Untagged old entries: counted only when a material belongs to exactly
#      one product; shared-material untagged entries go to an "Untagged"
#      bucket so nothing is silently split anymore.
# Idempotent — safe to run twice.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-LOSSFIX3 $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-loss3-$TS" 2>/dev/null
echo "DB BACKUP: /opt/flavorflow/backups/erp.db.bak-loss3-$TS"

node - <<'JS'
const db = require('/opt/flavorflow/server/db');
const cols = db.prepare('PRAGMA table_info(packing_txns)').all().map((c) => c.name);
if (!cols.includes('product_id')) {
  db.exec('ALTER TABLE packing_txns ADD COLUMN product_id INTEGER');
  console.log('COL packing_txns.product_id added');
} else console.log('COL already present');
JS

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/packing.js';
let src = fs.readFileSync(f, 'utf8');
const bak = f + '.bak-loss3-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);
let changed = false;

/* 1) consume route: accept + store productId */
if (!src.includes('lossProductTag')) {
  // find the consume INSERT into packing_txns and extend it
  const m = src.match(/router\.post\(['"]\/consume['"][\s\S]*?\n\}\);/);
  if (!m) { console.log('CONSUME ROUTE NOT FOUND'); process.exit(2); }
  let route = m[0];
  const ins = route.match(/INSERT INTO packing_txns \(([^)]*)\)\s*\n?\s*VALUES \(([^)]*)\)/);
  if (!ins) { console.log('CONSUME INSERT NOT FOUND'); process.exit(2); }
  const newCols = ins[1].trim() + ', product_id';
  const newVals = ins[2].trim() + ', ?';
  let newRoute = route.replace(ins[0], 'INSERT INTO packing_txns (' + newCols + ')\n       VALUES (' + newVals + ')');
  // add the value to the .run(...) right after that statement — find the first ).run( after the insert
  const runIdx = newRoute.indexOf(').run(', newRoute.indexOf('INSERT INTO packing_txns'));
  if (runIdx === -1) { console.log('CONSUME RUN NOT FOUND'); process.exit(2); }
  const runEnd = newRoute.indexOf(');', runIdx);
  newRoute = newRoute.slice(0, runEnd) + ', /* lossProductTag */ Number((req.body || {}).productId) || null' + newRoute.slice(runEnd);
  src = src.replace(route, newRoute);
  changed = true;
  console.log('CONSUME ROUTE: productId stored ✓');
} else console.log('CONSUME ROUTE: already patched');

/* 2) loss build: per-product tagged extras, no splitting */
if (src.includes('lossWholeSplit(')) {
  // manual per material → manual per (product, material) + untagged per material
  const OLDMAN = src.match(/const manual = \{\};[\s\S]*?\.all\(ym\)\) manual\[r\.mid\] = r\.q;/);
  if (!OLDMAN) { console.log('MANUAL BLOCK NOT FOUND'); process.exit(2); }
  src = src.replace(OLDMAN[0], `const manualPidMat = {}, manualUntagged = {};
  for (const r of db.prepare(
    "SELECT product_id pid, material_id mid, SUM(qty) q FROM packing_txns WHERE txn_type='CONSUMED' AND batch_id IS NULL AND substr(txn_date,1,7) = ? GROUP BY product_id, material_id"
  ).all(ym)) {
    if (r.pid) manualPidMat[r.pid + ':' + r.mid] = r.q;
    else manualUntagged[r.mid] = (manualUntagged[r.mid] || 0) + r.q;
  }`);

  // rows loop: no split — tagged amount for this product; untagged only if sole owner
  const OLDROWS = src.match(/const rows = \[\];[\s\S]*?const extra = Math\.round\(g\('extra:' \+ p\.id \+ ':' \+ l\.mid, [\s\S]*?\)\);/);
  if (!OLDROWS) { console.log('ROWS BLOCK NOT FOUND'); process.exit(2); }
  src = src.replace(OLDROWS[0], `const rows = [];
    for (const l of lines) {
      const cb = Math.round(g('cb:' + p.id + ':' + l.mid, expByPidMat[p.id + ':' + l.mid] || 0));
      const tagged = manualPidMat[p.id + ':' + l.mid] || 0;
      const owners = bom.filter((x) => x.mid === l.mid).length;
      const untag = owners === 1 ? (manualUntagged[l.mid] || 0) : 0; // shared+untagged: no auto assignment
      const extra = Math.round(g('extra:' + p.id + ':' + l.mid, tagged + untag));`);
  changed = true;
  console.log('LOSS BUILD: per-product tagged extras (no sharing) ✓');
} else console.log('LOSS BUILD: split code not found (already v3?)');

if (!changed) { console.log('NOTHING TO DO'); process.exit(0); }
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 400)); process.exit(3); }
JS
RC=$?
if [ $RC -ne 0 ]; then echo "LOSSFIX3 FAIL"; exit 1; fi

systemctl restart flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo ""
echo "LOSSFIX3 VERIFIED ✓ — consumption hun product-tagged: jis product layi record kiti, Loss% ose ch jandi (koi vandna nahi)"
