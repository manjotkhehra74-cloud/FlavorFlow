#!/usr/bin/env bash
# FlavorFlow FIX: allow the SAME batch code on a DIFFERENT date.
#  - DB: batches.code UNIQUE → UNIQUE(code, planned_date)  (table rebuild, full backup first)
#  - routes/production.js: create/edit duplicate checks become code+date aware
#  - routes/dispatch.js: batch deduction becomes FIFO across all COMPLETED
#    batches sharing that code (oldest date first)
# Idempotent — safe to run twice. Service is stopped during the DB rebuild.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-BATCHFIX $(date) ==="

echo "--- stopping service (DB rebuild needs exclusive access) ---"
systemctl stop flavorflow || true
sleep 1

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-batchfix-$TS" 2>/dev/null
cp -a data/erp.db-wal "/opt/flavorflow/backups/erp.db-wal.bak-batchfix-$TS" 2>/dev/null || true
cp -a data/erp.db-shm "/opt/flavorflow/backups/erp.db-shm.bak-batchfix-$TS" 2>/dev/null || true
echo "DB BACKUP: /opt/flavorflow/backups/erp.db.bak-batchfix-$TS"

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
let failed = false;

/* ---------- 1) DB: rebuild batches without UNIQUE(code) ---------- */
try {
  const { DatabaseSync: Database, pragma } = require('/opt/flavorflow/server/sqlite');
  const db = new Database('/opt/flavorflow/server/data/erp.db');
  pragma(db, 'foreign_keys = OFF');
  const master = db.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name='batches'").get();
  if (!master || !/code TEXT NOT NULL UNIQUE/.test(master.sql)) {
    console.log('DB: already migrated — skip');
  } else {
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
      CREATE UNIQUE INDEX idx_batches_code_date ON batches(code, planned_date);
      CREATE INDEX idx_batches_status ON batches(status);
      COMMIT;
    `);
    const n = db.prepare('SELECT COUNT(*) c FROM batches').get().c;
    console.log('DB: migrated ✓ (' + n + ' batches preserved, UNIQUE is now code+date)');
  }
} catch (e) { console.log('DB MIGRATION FAIL: ' + e.message); failed = true; }

function backup(f) { const b = f + '.bak-batchfix-' + Date.now(); fs.copyFileSync(f, b); console.log('BACKUP: ' + b); return b; }
function check(f, b) {
  try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK: ' + f); return true; }
  catch (e) { fs.copyFileSync(b, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); return false; }
}

/* ---------- 2) production.js: date-aware duplicate checks ---------- */
if (!failed) {
  const f = '/opt/flavorflow/server/routes/production.js';
  let src = fs.readFileSync(f, 'utf8');
  if (src.includes('Same code is allowed on a different date')) {
    console.log('PRODUCTION: already patched — skip');
  } else {
    const bak = backup(f);
    const a1 = "if (manualCode && db.prepare('SELECT id FROM batches WHERE code = ?').get(manualCode)) {\n    throw bad(`Batch code ${manualCode} already exists. Choose another code.`, 409);\n  }";
    const b1 = "if (manualCode && db.prepare(\"SELECT id FROM batches WHERE code = ? AND COALESCE(planned_date,'') = ?\").get(manualCode, plannedDate || '')) {\n    throw bad(`Batch code ${manualCode} already exists on ${plannedDate}. Same code is allowed on a different date.`, 409);\n  }";
    const a2 = "if (db.prepare('SELECT id FROM batches WHERE code = ? AND id <> ?').get(code, id)) {\n    throw bad(`Batch code ${code} already exists. Choose another code.`, 409);\n  }";
    const b2 = "if (db.prepare(\"SELECT id FROM batches WHERE code = ? AND COALESCE(planned_date,'') = COALESCE(?,'') AND id <> ?\").get(code, plannedDate, id)) {\n    throw bad(`Batch code ${code} already exists on that date. Same code is allowed on a different date.`, 409);\n  }";
    if (!src.includes(a1) || !src.includes(a2)) { console.log('PRODUCTION: anchors not found — manual check di lod'); failed = true; }
    else {
      src = src.replace(a1, b1).replace(a2, b2);
      fs.writeFileSync(f, src);
      if (check(f, bak)) console.log('PRODUCTION: patched ✓'); else failed = true;
    }
  }
}

/* ---------- 3) dispatch.js: FIFO deduction across same-code batches ---------- */
if (!failed) {
  const f = '/opt/flavorflow/server/routes/dispatch.js';
  let src = fs.readFileSync(f, 'utf8');
  if (src.includes('ORDER BY planned_date ASC, id ASC')) {
    console.log('DISPATCH: already patched — skip');
  } else {
    const bak = backup(f);
    const start = src.indexOf('// batch-aware dispatch');
    const endAnchor = '.run(l.cartons, l.trays, bch.id);';
    const endIdx = src.indexOf(endAnchor, start);
    if (start === -1 || endIdx === -1) { console.log('DISPATCH: anchors not found'); failed = true; }
    else {
      const closeIdx = src.indexOf('}', endIdx + endAnchor.length); // closing brace of the for-loop
      const NEW = `// batch-aware dispatch (FIFO across all COMPLETED batches sharing the code)
            for (const l of lines) {
              const bCode = (l.batchCode||'').trim();
              if (!bCode) continue;
              const bchs = db.prepare("SELECT id, produced_cb, COALESCE(used_cb,0) AS ucb, produced_trays, COALESCE(used_trays,0) AS ut FROM batches WHERE code = ? AND product_id = ? AND status = 'COMPLETED' ORDER BY planned_date ASC, id ASC").all(bCode, l.productId);
              if (!bchs.length) throw bad(\`Batch \${bCode} not found for this product (or not COMPLETED yet).\`, 400);
              let cbAvail = 0, traysAvail = 0;
              for (const b of bchs) { cbAvail += (b.produced_cb||0) - b.ucb; traysAvail += (b.produced_trays||0) - b.ut; }
              if (l.cartons > cbAvail) throw bad(\`Batch \${bCode} only has \${cbAvail} CB left (need \${l.cartons}).\`, 409);
              if (l.trays > traysAvail) throw bad(\`Batch \${bCode} only has \${traysAvail} trays left (need \${l.trays}).\`, 409);
              let needCb = l.cartons, needTr = l.trays;
              for (const b of bchs) {
                const takeCb = Math.min(needCb, (b.produced_cb||0) - b.ucb);
                const takeTr = Math.min(needTr, (b.produced_trays||0) - b.ut);
                if (takeCb > 0 || takeTr > 0) db.prepare('UPDATE batches SET used_cb = COALESCE(used_cb,0) + ?, used_trays = COALESCE(used_trays,0) + ? WHERE id = ?').run(takeCb, takeTr, b.id);
                needCb -= takeCb; needTr -= takeTr;
                if (needCb <= 0 && needTr <= 0) break;
              }
            }`;
      src = src.slice(0, start) + NEW + src.slice(closeIdx + 1);
      fs.writeFileSync(f, src);
      if (check(f, bak)) console.log('DISPATCH: patched ✓ (FIFO)'); else failed = true;
    }
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
  echo "BATCHFIX VERIFIED ✓ — same batch code hun different date te add ho sakda; same date te block rahega"
else
  echo "BATCHFIX INCOMPLETE — output upar dekho; DB backup: /opt/flavorflow/backups/"
fi
