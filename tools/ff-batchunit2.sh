#!/usr/bin/env bash
# FlavorFlow FIX (follow-up to ff-batchunit.sh): body field name mismatch.
#   The app sends `plannedUnit` (and `plannedTrays`) in the create/edit
#   body, but v3 read `req.body.planUnit` — undefined → every plan was
#   checked as CB, so a Tray plan under an existing CB code got a 409.
#   v4 reads `plannedUnit` first (planUnit kept as fallback).
#   No DB changes. Idempotent — re-run safe. Full file backup first.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-BATCHUNIT2 $(date) ==="

echo "--- stopping service ---"
systemctl stop flavorflow || true
sleep 1

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
let failed = false;

function backup(f) { const b = f + '.bak-batchunit2-' + Date.now(); fs.copyFileSync(f, b); console.log('BACKUP: ' + b); return b; }
function check(f, b) {
  try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK: ' + f); return true; }
  catch (e) { fs.copyFileSync(b, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); return false; }
}

const f = '/opt/flavorflow/server/routes/production.js';
let src = fs.readFileSync(f, 'utf8');
const MARKER = "(req.body || {}).plannedUnit";
if (src.includes(MARKER)) {
  console.log('PRODUCTION: already v4 — skip');
} else if (!src.includes("(req.body || {}).planUnit")) {
  console.log('PRODUCTION: v3 planUnit line not found — run ff-batchunit.sh first');
  process.exit(2);
} else {
  const bak = backup(f);
  let ok = true;

  const createV3 = "const planUnit = String((req.body || {}).planUnit) === 'tray' ? 'tray' : 'cb';";
  const createV4 = "const planUnit = String((req.body || {}).plannedUnit || (req.body || {}).planUnit || 'cb') === 'tray' ? 'tray' : 'cb';";
  if (src.includes(createV3)) src = src.replace(createV3, createV4);
  else { console.log('CREATE anchor not found'); ok = false; }

  const editV3 = "const editUnit = String((req.body || {}).planUnit) === 'tray' ? 'tray' : (String(batch.plan_unit) === 'tray' ? 'tray' : 'cb');";
  const editV4 = "const editUnit = String((req.body || {}).plannedUnit || (req.body || {}).planUnit || 'cb') === 'tray' ? 'tray' : (String(batch.plan_unit) === 'tray' ? 'tray' : 'cb');";
  if (ok && src.includes(editV3)) src = src.replace(editV3, editV4);
  else if (ok) { console.log('EDIT anchor not found'); ok = false; }

  if (!ok) { failed = true; }
  else {
    fs.writeFileSync(f, src);
    if (check(f, bak)) console.log('PRODUCTION: patched v4 ✓ (reads plannedUnit)'); else failed = true;
  }
}

if (failed) { console.log('PATCH INCOMPLETE — backups moujood ne'); process.exit(2); }
console.log('ALL PATCHES OK');
JS
RC=$?

echo "--- starting service ---"
systemctl start flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAIL"
if [ $RC -eq 0 ]; then
  echo "BATCHUNIT2 VERIFIED ✓ — Tray plan ab sahi unit vich check hove: same code CB + Tray dono allowed, same unit 2× abhi bhi block"
else
  echo "BATCHUNIT2 INCOMPLETE — output upar dekho; file backup: routes/production.js.bak-batchunit2-*"
fi
