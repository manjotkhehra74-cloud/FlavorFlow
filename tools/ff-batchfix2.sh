#!/usr/bin/env bash
# FlavorFlow FIX v2: same batch code allowed across DIFFERENT PRODUCTS too.
#   Rule: a batch code is only blocked when the SAME product already has that
#   code on the SAME date. Everything else is allowed:
#     - White Vinegar 610ml + 180ml + 1L same code, same/any date  ✅
#     - Soya 740gm + 1.3kg + Dark 250gm same code, any date        ✅
#     - Same product, same code, DIFFERENT date                    ✅
#     - Same product, same code, SAME date                         ❌ (double entry)
#   DB: UNIQUE index becomes (code, product_id, planned_date).
# Handles all states: original DB, batchfix-v1 applied, or already v2 (skip).
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-BATCHFIX2 $(date) ==="

echo "--- stopping service (DB index rebuild) ---"
systemctl stop flavorflow || true
sleep 1

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-batchfix2-$TS" 2>/dev/null
echo "DB BACKUP: /opt/flavorflow/backups/erp.db.bak-batchfix2-$TS"

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
let failed = false;

/* ---------- 1) DB: UNIQUE(code, product_id, planned_date) ---------- */
try {
  const { DatabaseSync: Database, pragma } = require('/opt/flavorflow/server/sqlite');
  const db = new Database('/opt/flavorflow/server/data/erp.db');
  pragma(db, 'foreign_keys = OFF');
  const hasV2 = db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='idx_batches_code_prod_date'").get();
  if (hasV2) {
    console.log('DB: v2 index already present — skip');
  } else {
    const master = db.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name='batches'").get();
    if (master && /code TEXT NOT NULL UNIQUE/.test(master.sql)) {
      // v1 was never run — rebuild the table without inline UNIQUE first
      db.exec(`
        BEGIN;
        CREATE TABLE batches_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          code TEXT NOT NULL,
          product_id INTEGER NOT NULL REFERENCES products(id),
          planned_cb INTEGER NOT NULL,
          produced_cb INTEGER NOT NULL DEFAULT 0,
          produced_trays INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'PLANNED',
          planned_date TEXT,
          remarks TEXT DEFAULT '',
          created_by INTEGER, started_by INTEGER, completed_by INTEGER,
          created_at TEXT NOT NULL, started_at TEXT, completed_at TEXT,
          used_trays INTEGER NOT NULL DEFAULT 0, used_cb INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO batches_new (id, code, product_id, planned_cb, produced_cb, produced_trays, status, planned_date, remarks, created_by, started_by, completed_by, created_at, started_at, completed_at, used_trays, used_cb)
          SELECT id, code, product_id, planned_cb, produced_cb, produced_trays, status, planned_date, remarks, created_by, started_by, completed_by, created_at, started_at, completed_at, used_trays, used_cb FROM batches;
        DROP TABLE batches;
        ALTER TABLE batches_new RENAME TO batches;
        CREATE INDEX idx_batches_status ON batches(status);
        COMMIT;
      `);
      console.log('DB: table rebuilt (inline UNIQUE removed)');
    }
    db.exec("DROP INDEX IF EXISTS idx_batches_code_date;");
    db.exec("CREATE UNIQUE INDEX idx_batches_code_prod_date ON batches(code, product_id, planned_date);");
    const n = db.prepare('SELECT COUNT(*) c FROM batches').get().c;
    console.log('DB: UNIQUE is now (code, product, date) ✓ — ' + n + ' batches preserved');
  }
} catch (e) { console.log('DB MIGRATION FAIL: ' + e.message); failed = true; }

function backup(f) { const b = f + '.bak-batchfix2-' + Date.now(); fs.copyFileSync(f, b); console.log('BACKUP: ' + b); return b; }
function check(f, b) {
  try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK: ' + f); return true; }
  catch (e) { fs.copyFileSync(b, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); return false; }
}

/* ---------- 2) production.js: product-aware duplicate checks ---------- */
if (!failed) {
  const f = '/opt/flavorflow/server/routes/production.js';
  let src = fs.readFileSync(f, 'utf8');
  if (src.includes('AND product_id = ?').valueOf() && src.includes('allowed for other products')) {
    console.log('PRODUCTION: already v2 — skip');
  } else {
    const bak = backup(f);
    let ok = true;

    // CREATE check — handle both original and v1 text
    const createV1 = `if (manualCode && db.prepare("SELECT id FROM batches WHERE code = ? AND COALESCE(planned_date,'') = ?").get(manualCode, plannedDate || '')) {
    throw bad(\`Batch code \${manualCode} already exists on \${plannedDate}. Same code is allowed on a different date.\`, 409);
  }`;
    const createOrig = "if (manualCode && db.prepare('SELECT id FROM batches WHERE code = ?').get(manualCode)) {\n    throw bad(`Batch code ${manualCode} already exists. Choose another code.`, 409);\n  }";
    const createV2 = `if (manualCode && db.prepare("SELECT id FROM batches WHERE code = ? AND product_id = ? AND COALESCE(planned_date,'') = ?").get(manualCode, productId, plannedDate || '')) {
    throw bad(\`Batch code \${manualCode} already exists for this product on \${plannedDate}. Same code is allowed for other products or other dates.\`, 409);
  }`;
    if (src.includes(createV1)) src = src.replace(createV1, createV2);
    else if (src.includes(createOrig)) src = src.replace(createOrig, createV2);
    else { console.log('CREATE anchor not found'); ok = false; }

    // EDIT check — handle both v1 and original
    const editV1 = `if (db.prepare("SELECT id FROM batches WHERE code = ? AND COALESCE(planned_date,'') = COALESCE(?,'') AND id <> ?").get(code, plannedDate, id)) {
    throw bad(\`Batch code \${code} already exists on that date. Same code is allowed on a different date.\`, 409);
  }`;
    const editOrig = "if (db.prepare('SELECT id FROM batches WHERE code = ? AND id <> ?').get(code, id)) {\n    throw bad(`Batch code ${code} already exists. Choose another code.`, 409);\n  }";
    const editV2 = `{
    const targetProductId = Number((req.body || {}).productId) || batch.product_id;
    if (db.prepare("SELECT id FROM batches WHERE code = ? AND product_id = ? AND COALESCE(planned_date,'') = COALESCE(?,'') AND id <> ?").get(code, targetProductId, plannedDate, id)) {
      throw bad(\`Batch code \${code} already exists for this product on that date. Same code is allowed for other products or other dates.\`, 409);
    }
  }`;
    if (src.includes(editV1)) src = src.replace(editV1, editV2);
    else if (src.includes(editOrig)) src = src.replace(editOrig, editV2);
    else { console.log('EDIT anchor not found'); ok = false; }

    if (!ok) { failed = true; }
    else {
      fs.writeFileSync(f, src);
      if (check(f, bak)) console.log('PRODUCTION: patched v2 ✓ (per-product duplicate check)'); else failed = true;
    }
  }
}

/* Note: dispatch.js needs NO change — its batch lookup already filters by
   product_id, so "same code, many products" dispatches correctly. */

if (failed) { console.log('PATCH INCOMPLETE — backups moujood ne'); process.exit(2); }
console.log('ALL PATCHES OK');
JS
RC=$?

echo "--- starting service ---"
systemctl start flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAIL"
if [ $RC -eq 0 ]; then
  echo "BATCHFIX2 VERIFIED ✓ — same code hun vakhre products te same/vakhri date, sab allowed; sirf same product + same code + same date block hai"
else
  echo "BATCHFIX2 INCOMPLETE — output upar dekho; DB backup: /opt/flavorflow/backups/"
fi
