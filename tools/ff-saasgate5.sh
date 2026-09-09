#!/usr/bin/env bash
# FlavorFlow SaaS P1e: FULL SCHEMA SYNC (whack-a-mole khatam) —
#   totp_secret fix hoya te dashboard te agla missing column aa gaya —
#   factory DB te mahine-bhar ALTER-scripts lagiyan ne jo db.js CREATEs
#   vich nahi. Eh script factory de schema-dump (~/factory-schema.json)
#   ton HAR table/column/index tenant DBs vich ensure kardi hai:
#     1) ~/factory-schema.json → /opt/flavorflow-saas/schema/
#     2) db.js: boot te schema-sync block (har NAVI tenant DB vi poori)
#     3) maujooda tenant DBs te turant sync
#   (dump banaun di command FACTORY VM te: script thalle print karegi je file nahi)
# Idempotent. Backup + node --check + auto-restore.
set -u
BASE=/opt/flavorflow-saas
echo "=== FF-SAASGATE5 $(date) ==="
[ -d "$BASE/core" ] || { echo "FATAL: core nahi"; exit 1; }

SRC="/home/manjotkhehra74/factory-schema.json"
[ -f "$SRC" ] || SRC="$HOME/factory-schema.json"
if [ ! -f "$SRC" ]; then
  echo "FATAL: factory-schema.json nahi labhi."
  echo "PEHLA FACTORY VM te eh chalao, fer file DOWNLOAD→UPLOAD karke ethe ~ vich pao:"
  echo "  sudo node -e \"const db=require('/opt/flavorflow/server/db'); const rows=db.prepare(\\\"SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL\\\").all(); require('fs').writeFileSync('/home/manjotkhehra74/factory-schema.json', JSON.stringify(rows)); console.log('SCHEMA DUMP ->', rows.length, 'objects')\""
  exit 1
fi
mkdir -p "$BASE/schema"
cp -f "$SRC" "$BASE/schema/factory-schema.json"
echo "schema dump ✓ ($(wc -c < "$BASE/schema/factory-schema.json") bytes)"

# 1) db.js: boot-time schema sync block
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow-saas/core/db.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('/* ffSchemaSync */')) { console.log('db.js: schema-sync already ✓'); }
else {
  const bak = f + '.bak-gate5-' + Date.now();
  fs.copyFileSync(f, bak);
  const call = src.match(/\nmigrate\(\);/);
  if (!call) { console.log('migrate() call nahi labhya'); process.exit(1); }
  const BLOCK = `
/* ffSchemaSync */
try {
  const _ss_fs = require('fs');
  const _ss_dump = JSON.parse(_ss_fs.readFileSync('/opt/flavorflow-saas/schema/factory-schema.json', 'utf8'));
  const _ss_mem = new DatabaseSync(':memory:');
  for (const o of _ss_dump) { if (o.type === 'table' && !o.name.startsWith('sqlite_')) { try { _ss_mem.exec(o.sql); } catch (e) {} } }
  for (const o of _ss_dump) {
    if (o.name && o.name.startsWith('sqlite_')) continue;
    if (o.type === 'table') {
      const ex = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name=?").get(o.name);
      if (!ex) { try { db.exec(o.sql); console.log('[schema] +table ' + o.name); } catch (e) {} continue; }
      let want = [], have = new Set();
      try { want = _ss_mem.prepare('PRAGMA table_info(' + o.name + ')').all(); } catch (e) { continue; }
      try { for (const c of db.prepare('PRAGMA table_info(' + o.name + ')').all()) have.add(c.name); } catch (e) { continue; }
      for (const c of want) {
        if (have.has(c.name)) continue;
        let ddl = 'ALTER TABLE ' + o.name + ' ADD COLUMN ' + c.name + ' ' + (c.type || 'TEXT');
        if (c.dflt_value !== null && c.dflt_value !== undefined) ddl += (c.notnull ? ' NOT NULL' : '') + ' DEFAULT ' + c.dflt_value;
        try { db.exec(ddl); console.log('[schema] +col ' + o.name + '.' + c.name); } catch (e) {}
      }
    } else { try { db.exec(o.sql); } catch (e) {} }
  }
} catch (e) { console.log('[schema] sync skip:', e.message); }
`;
  src = src.replace(call[0], call[0] + BLOCK);
  fs.writeFileSync(f, src);
  try { cp.execSync('node --check "' + f + '"'); console.log('db.js schema-sync ✓'); }
  catch (e) { fs.copyFileSync(bak, f); console.log('db.js SYNTAX FAIL — RESTORED'); process.exit(1); }
}
JS
[ $? -ne 0 ] && { echo "SAASGATE5 FAIL (db.js)"; exit 1; }

# 2) existing tenant DBs: run the same sync now (db.js boot will also do it)
node - <<'JS'
const fs = require('fs'), path = require('path');
const BASE = '/opt/flavorflow-saas';
const { DatabaseSync } = require(BASE + '/core/sqlite');
const dump = JSON.parse(fs.readFileSync(BASE + '/schema/factory-schema.json', 'utf8'));
const mem = new DatabaseSync(':memory:');
for (const o of dump) { if (o.type === 'table' && !o.name.startsWith('sqlite_')) { try { mem.exec(o.sql); } catch (e) {} } }
for (const d of fs.readdirSync(BASE + '/data')) {
  if (!d.startsWith('tenant-')) continue;
  const dbf = path.join(BASE + '/data', d, 'erp.db');
  if (!fs.existsSync(dbf)) continue;
  const db = new DatabaseSync(dbf);
  let n = 0;
  for (const o of dump) {
    if (o.name && o.name.startsWith('sqlite_')) continue;
    if (o.type === 'table') {
      const ex = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name=?").get(o.name);
      if (!ex) { try { db.exec(o.sql); n++; console.log(d + ': +table ' + o.name); } catch (e) {} continue; }
      let want = []; const have = new Set();
      try { want = mem.prepare('PRAGMA table_info(' + o.name + ')').all(); } catch (e) { continue; }
      for (const c of db.prepare('PRAGMA table_info(' + o.name + ')').all()) have.add(c.name);
      for (const c of want) {
        if (have.has(c.name)) continue;
        let ddl = 'ALTER TABLE ' + o.name + ' ADD COLUMN ' + c.name + ' ' + (c.type || 'TEXT');
        if (c.dflt_value !== null && c.dflt_value !== undefined) ddl += (c.notnull ? ' NOT NULL' : '') + ' DEFAULT ' + c.dflt_value;
        try { db.exec(ddl); n++; console.log(d + ': +col ' + o.name + '.' + c.name); } catch (e) {}
      }
    } else { try { db.exec(o.sql); } catch (e) {} }
  }
  console.log(d + ': sync done (' + n + ' changes)');
}
JS

systemctl restart flavorflow-saas
sleep 3
curl -s -m 8 http://127.0.0.1:4100/api/saas/health && echo ""
echo "SAASGATE5 VERIFIED ✓ — app band karke dubara kholo, dashboard hun chalna chahida"
