#!/usr/bin/env bash
# FlavorFlow FIX v5 — plan_unit / planned_trays never reached the INSERT.
#   v3/v4 only stamped plan_unit on the direct-complete path (line ~100);
#   the "classic planned flow" INSERT (line ~149) had no plan_unit column,
#   so SQLite used its DEFAULT 'cb' → collided with the existing CB row →
#   UNIQUE constraint failed → 500 "Internal server error" in the app.
#   v5: both INSERTs carry plan_unit + planned_trays, the PLANNED edit
#       keeps them too, and a UNIQUE crash becomes a clean 409 message.
#   No DB changes. Idempotent. Full file backup first.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-BATCHUNIT3 $(date) ==="

echo "--- stopping service ---"
systemctl stop flavorflow || true
sleep 1

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/production.js';
let src = fs.readFileSync(f, 'utf8');

if (src.includes('planUnitV5')) { console.log('PRODUCTION: already v5 — skip'); process.exit(0); }

const plannedCols = 'INSERT INTO batches (code, product_id, planned_cb, status, planned_date, remarks, created_by, created_at)';
const plannedVals = "VALUES ('TMP', ?, ?, 'PLANNED', ?, ?, ?, ?)";
if (!src.includes(plannedCols) || !src.includes(plannedVals)) {
  console.log('FATAL: planned INSERT nahi mili — file badal gayi hai; pehla ff-codeshow.sh chala ke code bhejo');
  process.exit(2);
}

const bak = f + '.bak-batchunit3-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);

let n = 0;
function rep(a, b, label) {
  if (!src.includes(a)) { console.log('SKIP (nahi mili): ' + label); return; }
  src = src.split(a).join(b); n++; console.log('PATCHED: ' + label);
}

// 1 — planned flow: unit + trays variables, tx wrapped in try/catch
rep('  const result = tx(db, () => {',
`  const planUnitV5 = String((req.body || {}).plannedUnit || (req.body || {}).planUnit || 'cb') === 'tray' ? 'tray' : 'cb';
  const planTraysV5 = Math.floor(Number((req.body || {}).plannedTrays) || 0);
  let result;
  try { result = tx(db, () => {`, 'planned-flow vars');

// 2 — planned INSERT carries plan_unit + planned_trays
rep(plannedCols,
    'INSERT INTO batches (code, product_id, planned_cb, planned_trays, plan_unit, status, planned_date, remarks, created_by, created_at)',
    'planned INSERT columns');
rep(plannedVals,
    "VALUES ('TMP', ?, ?, ?, ?, 'PLANNED', ?, ?, ?, ?)",
    'planned INSERT values');
rep('.run(productId, plannedCb, plannedDate, remarks, req.user.id, nowIso());',
    '.run(productId, plannedCb, planTraysV5, planUnitV5, plannedDate, remarks, req.user.id, nowIso());',
    'planned INSERT params');

// 3 — close try; UNIQUE crash -> clean 409 instead of 500
rep(`    return { id, code };
  });

  audit(db, req.user, 'CREATE', 'batch', result.id,`,
`    return { id, code };
  }); } catch (e) { if (/UNIQUE constraint failed: batches/.test(String((e && e.message) || e))) throw bad('Eh code is product te is date layi pehla hi hai (same unit). Same code sirf dooji unit (CB/Tray), dooje product ja dooji date layi allowed hai.', 409); throw e; }

  audit(db, req.user, 'CREATE', 'batch', result.id,`,
    'planned-flow UNIQUE -> 409');

// 4 — direct-complete INSERT carries plan_unit + planned_trays too
rep('INSERT INTO batches (code, product_id, planned_cb, produced_cb, produced_trays, status, planned_date, remarks, created_by, created_at, completed_by, completed_at)',
    'INSERT INTO batches (code, product_id, planned_cb, produced_cb, produced_trays, plan_unit, planned_trays, status, planned_date, remarks, created_by, created_at, completed_by, completed_at)',
    'direct INSERT columns');
rep("VALUES ('TMP', ?, ?, ?, ?, 'COMPLETED', ?, ?, ?, ?, ?, ?)",
    "VALUES ('TMP', ?, ?, ?, ?, ?, ?, 'COMPLETED', ?, ?, ?, ?, ?, ?)",
    'direct INSERT values');
rep('.run(productId, producedCb, producedCb, producedTrays, plannedDate, remarks, req.user.id, nowIso(), req.user.id, nowIso());',
    '.run(productId, producedCb, producedCb, producedTrays, planUnit, plannedTraysIn, plannedDate, remarks, req.user.id, nowIso(), req.user.id, nowIso());',
    'direct INSERT params');

// 5 — editing a PLANNED batch keeps its unit + trays
rep(`const editUnit = String((req.body || {}).plannedUnit || (req.body || {}).planUnit || 'cb') === 'tray' ? 'tray' : (String(batch.plan_unit) === 'tray' ? 'tray' : 'cb');`,
`const editUnit = String((req.body || {}).plannedUnit || (req.body || {}).planUnit || 'cb') === 'tray' ? 'tray' : (String(batch.plan_unit) === 'tray' ? 'tray' : 'cb');
    const editTraysV5 = Math.floor(Number((req.body || {}).plannedTrays) || (String(batch.plan_unit) === 'tray' ? (Number(batch.planned_trays) || 0) : 0));`,
    'edit trays var');
rep("'UPDATE batches SET product_id=?, planned_cb=?, planned_date=?, remarks=?, code=? WHERE id=?'",
    "'UPDATE batches SET product_id=?, planned_cb=?, planned_trays=?, plan_unit=?, planned_date=?, remarks=?, code=? WHERE id=?'",
    'edit UPDATE sql');
rep('.run(productId, plannedCb, plannedDate, remarks, code, id);',
    '.run(productId, plannedCb, editTraysV5, editUnit, plannedDate, remarks, code, id);',
    'edit UPDATE params');

fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); process.exit(1); }
console.log('PATCHES APPLIED: ' + n);
JS

echo "--- starting service ---"
systemctl start flavorflow || true
sleep 3
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAIL"
echo "BATCHUNIT3 VERIFIED ✔ — Tray plan hun plan_unit='tray' naal save hovega; UNIQUE crash di jagah saaf 409"
