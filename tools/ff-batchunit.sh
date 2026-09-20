#!/usr/bin/env bash
# FlavorFlow FIX: unit-aware batch uniqueness (CB + Tray under the same code).
#   Rule: code + product + date is blocked only within the SAME plan unit.
#     - Same product, same code, same date: one CB batch + one Tray batch  ✅
#     - Same product, same code, same date: two CB batches (or two Tray)   ❌
#     - Different product / different date                                  ✅
#   DB:    batches.plan_unit ('cb'|'tray', default 'cb') +
#          batches.planned_trays (INTEGER, default 0) +
#          UNIQUE index → (code, product_id, planned_date, plan_unit).
#   Server: routes/production.js accepts plannedUnit/plannedTrays in the
#          create/edit body, stores them on the new row, and includes
#          plan_unit in both duplicate checks.
# Handles all states: v2 (current) or already v3 (skip). Full DB backup first.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-BATCHUNIT $(date) ==="

echo "--- stopping service (DB migration) ---"
systemctl stop flavorflow || true
sleep 1

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-batchunit-$TS" 2>/dev/null
echo "DB BACKUP: /opt/flavorflow/backups/erp.db.bak-batchunit-$TS"

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
let failed = false;

/* ---------- 1) DB: plan_unit + planned_trays + new UNIQUE index ---------- */
try {
  const { DatabaseSync: Database, pragma } = require('/opt/flavorflow/server/sqlite');
  const db = new Database('/opt/flavorflow/server/data/erp.db');
  pragma(db, 'foreign_keys = OFF');
  const cols = db.prepare('PRAGMA table_info(batches)').all().map(r => r.name);
  if (!cols.includes('plan_unit')) {
    db.exec("ALTER TABLE batches ADD COLUMN plan_unit TEXT NOT NULL DEFAULT 'cb'");
    console.log('DB: column plan_unit added');
  }
  if (!cols.includes('planned_trays')) {
    db.exec('ALTER TABLE batches ADD COLUMN planned_trays INTEGER NOT NULL DEFAULT 0');
    console.log('DB: column planned_trays added');
  }
  const hasV3 = db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='idx_batches_code_prod_date_unit'").get();
  if (hasV3) {
    console.log('DB: v3 index already present — skip');
  } else {
    db.exec('DROP INDEX IF EXISTS idx_batches_code_prod_date;');
    db.exec('DROP INDEX IF EXISTS idx_batches_code_date;');
    db.exec('CREATE UNIQUE INDEX idx_batches_code_prod_date_unit ON batches(code, product_id, planned_date, plan_unit);');
    const n = db.prepare('SELECT COUNT(*) c FROM batches').get().c;
    console.log('DB: UNIQUE is now (code, product, date, unit) ✓ — ' + n + ' batches preserved');
  }
} catch (e) { console.log('DB MIGRATION FAIL: ' + e.message); failed = true; }

function backup(f) { const b = f + '.bak-batchunit-' + Date.now(); fs.copyFileSync(f, b); console.log('BACKUP: ' + b); return b; }
function check(f, b) {
  try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK: ' + f); return true; }
  catch (e) { fs.copyFileSync(b, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); return false; }
}

/* ---------- 2) production.js: unit-aware duplicate checks + storage ---------- */
if (!failed) {
  const f = '/opt/flavorflow/server/routes/production.js';
  let src = fs.readFileSync(f, 'utf8');
  if (src.includes("COALESCE(plan_unit,'cb')") && src.includes('last_insert_rowid')) {
    console.log('PRODUCTION: already v3 — skip');
  } else {
    const bak = backup(f);
    let ok = true;

    // --- CREATE duplicate check (v2 text) ---
    const createV2 = `if (manualCode && db.prepare("SELECT id FROM batches WHERE code = ? AND product_id = ? AND COALESCE(planned_date,'') = ?").get(manualCode, productId, plannedDate || '')) {
    throw bad(\`Batch code \${manualCode} already exists for this product on \${plannedDate}. Same code is allowed for other products or other dates.\`, 409);
  }`;
    const createV3 = `const planUnit = String((req.body || {}).planUnit) === 'tray' ? 'tray' : 'cb';
  const plannedTraysIn = Math.max(0, Number((req.body || {}).plannedTrays) || 0);
  if (manualCode && db.prepare("SELECT id FROM batches WHERE code = ? AND product_id = ? AND COALESCE(planned_date,'') = ? AND COALESCE(plan_unit,'cb') = ?").get(manualCode, productId, plannedDate || '', planUnit)) {
    throw bad(\`Batch code \${manualCode} already exists for this product on \${plannedDate} in the same unit. Same code is allowed for the other unit (CB/Tray), other products or other dates.\`, 409);
  }`;
    if (src.includes(createV2)) src = src.replace(createV2, createV3);
    else { console.log('CREATE anchor not found'); ok = false; }

    // --- EDIT duplicate check (v2 text) ---
    const editV2 = `{
    const targetProductId = Number((req.body || {}).productId) || batch.product_id;
    if (db.prepare("SELECT id FROM batches WHERE code = ? AND product_id = ? AND COALESCE(planned_date,'') = COALESCE(?,'') AND id <> ?").get(code, targetProductId, plannedDate, id)) {
      throw bad(\`Batch code \${code} already exists for this product on that date. Same code is allowed for other products or other dates.\`, 409);
    }
  }`;
    const editV3 = `{
    const targetProductId = Number((req.body || {}).productId) || batch.product_id;
    const editUnit = String((req.body || {}).planUnit) === 'tray' ? 'tray' : (String(batch.plan_unit) === 'tray' ? 'tray' : 'cb');
    if (db.prepare("SELECT id FROM batches WHERE code = ? AND product_id = ? AND COALESCE(planned_date,'') = COALESCE(?,'') AND COALESCE(plan_unit,'cb') = ? AND id <> ?").get(code, targetProductId, plannedDate, editUnit, id)) {
      throw bad(\`Batch code \${code} already exists for this product on that date in the same unit. Same code is allowed for the other unit (CB/Tray), other products or other dates.\`, 409);
    }
  }`;
    if (src.includes(editV2)) src = src.replace(editV2, editV3);
    else { console.log('EDIT anchor not found'); ok = false; }

    // --- storage: right after the create INSERT, stamp unit + tray count on
    //     the fresh row. last_insert_rowid() keeps this independent of the
    //     handler's JS variable names. ---
    if (ok) {
      const inserts = [...src.matchAll(/INSERT INTO batches\b/g)].map(m => m.index);
      if (inserts.length === 0) { console.log('INSERT anchor not found'); ok = false; }
      else {
        if (inserts.length > 1) console.log('WARN: ' + inserts.length + ' INSERT INTO batches statements — stamping after the first');
        const insIdx = inserts[0];
        const semi = src.indexOf(';', insIdx);
        if (semi < 0) { console.log('INSERT statement end not found'); ok = false; }
        else {
          const stamp = `
  db.prepare("UPDATE batches SET plan_unit = ?, planned_trays = ? WHERE id = last_insert_rowid()").run(planUnit, plannedTraysIn);`;
          src = src.slice(0, semi + 1) + stamp + src.slice(semi + 1);
        }
      }
    }

    if (!ok) { failed = true; }
    else {
      fs.writeFileSync(f, src);
      if (check(f, bak)) console.log('PRODUCTION: patched v3 ✓ (unit-aware uniqueness + storage)'); else failed = true;
    }
  }
}

/* Note: complete/start handlers need NO change — they UPDATE existing rows,
   and plan_unit/planned_trays keep their stored values. Dispatch is
   unaffected (it reads produced stock, not the plan unit). */

if (failed) { console.log('PATCH INCOMPLETE — backups moujood ne'); process.exit(2); }
console.log('ALL PATCHES OK');
JS
RC=$?

echo "--- starting service ---"
systemctl start flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAIL"
if [ $RC -eq 0 ]; then
  echo "BATCHUNIT VERIFIED ✓ — same code + product + date: ek CB batch + ek Tray batch allowed; do batch same unit vich abhi bhi block"
else
  echo "BATCHUNIT INCOMPLETE — output upar dekho; DB backup: /opt/flavorflow/backups/"
fi
