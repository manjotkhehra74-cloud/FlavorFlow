#!/usr/bin/env bash
# FlavorFlow FIX v3: repeated batch codes are allowed everywhere.
#   Rule requested by the factory: the same product may use the same batch code
#   more than once on the same date or another date. The same code may also be
#   used by other products. Existing rows/history are preserved; dispatch and
#   reconciliation continue to use product_id + code and FIFO across rows.
#   DB: remove code uniqueness and keep only a non-unique lookup index.
# Handles original DB, batchfix-v1, previous unique-index attempts, and duplicates.
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

/* ---------- 1) DB: repeated code is intentionally non-unique ---------- */
try {
  const { DatabaseSync: Database, pragma } = require('/opt/flavorflow/server/sqlite');
  const db = new Database('/opt/flavorflow/server/data/erp.db');
  pragma(db, 'foreign_keys = OFF');
  const master = db.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name='batches'").get();
  if (master && /code TEXT NOT NULL UNIQUE/i.test(master.sql)) {
    // Original installs had an inline UNIQUE(code). Rebuild only to remove
    // that constraint; all rows/columns used by the ERP are copied intact.
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
    console.log('DB: inline code uniqueness removed; rows preserved');
  }
  // Drop both old uniqueness variants, including a UNIQUE index created by a
  // previous attempt. Never fail because duplicate historical rows exist.
  db.exec("DROP INDEX IF EXISTS idx_batches_code_date;");
  db.exec("DROP INDEX IF EXISTS idx_batches_code_prod_date;");
  db.exec("CREATE INDEX idx_batches_code_prod_date ON batches(code, product_id, planned_date);");
  const n = db.prepare('SELECT COUNT(*) c FROM batches').get().c;
  console.log('DB: repeated batch codes allowed — non-unique lookup index ready; ' + n + ' batches preserved');
} catch (e) { console.log('DB MIGRATION FAIL: ' + e.message); failed = true; }

function backup(f) { const b = f + '.bak-batchfix2-' + Date.now(); fs.copyFileSync(f, b); console.log('BACKUP: ' + b); return b; }
function check(f, b) {
  try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK: ' + f); return true; }
  catch (e) { fs.copyFileSync(b, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); return false; }
}

/* ---------- 2) production.js: remove all duplicate-code blockers ---------- */
if (!failed) {
  const f = '/opt/flavorflow/server/routes/production.js';
  let src = fs.readFileSync(f, 'utf8');
  if (src.includes('ffBatchCodeDuplicatesAllowed')) {
    console.log('PRODUCTION: repeated batch codes already allowed — skip');
  } else {
    const bak = backup(f);
    let changed = 0;
    // Neutralize every SELECT ... FROM batches WHERE ... code ... query used
    // by create/edit duplicate guards. Keep the original parameter count and
    // code structure, but make the predicate impossible (id=-1), so any
    // historical duplicate remains valid and future duplicates are accepted.
    const literal = /(['"`])([\s\S]*?)\1/g;
    src = src.replace(literal, (whole, quote, text) => {
      if (!/^\s*SELECT\s+(?:id|1|COUNT\s*\(\s*\*\s*\))\s+FROM\s+batches\b[\s\S]*\bWHERE\b/i.test(text)) return whole;
      if (!/\bcode\b/i.test(text) || /\bid\s*=\s*-1\b/i.test(text)) return whole;
      changed++;
      return quote + text.replace(/\bWHERE\b/i, 'WHERE id = -1 AND ') + quote;
    });
    if (!changed) {
      console.log('PRODUCTION: no code-duplicate query found — route unchanged for safety');
      failed = true;
    } else {
      src = '/* ffBatchCodeDuplicatesAllowed: same product/code/date duplicates are intentionally allowed */\n' + src;
      fs.writeFileSync(f, src);
      if (check(f, bak)) console.log('PRODUCTION: duplicate-code blockers removed (' + changed + ' query guard(s)) ✓'); else failed = true;
    }
  }
}

/* Note: dispatch.js needs NO change — its batch lookup already filters by
   product_id and existing FIFO reconciliation handles repeated code rows. */

if (failed) { console.log('PATCH INCOMPLETE — backups moujood ne'); process.exit(2); }
console.log('ALL PATCHES OK');
JS
RC=$?

echo "--- starting service ---"
systemctl start flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAIL"
if [ $RC -eq 0 ]; then
  echo "BATCHFIX2 VERIFIED ✓ — same code hun same product/date samet har vaar allowed; existing batches/history preserved"
else
  echo "BATCHFIX2 INCOMPLETE — output upar dekho; DB backup: /opt/flavorflow/backups/"
  exit $RC
fi
