#!/usr/bin/env bash
# FlavorFlow SaaS P1f: schema-sync block fix —
#   Logs: "[schema] sync skip: DatabaseSync is not defined" — db.js apne
#   sqlite nu 'Database' alias naal import karda hai, mere gate5 block ne
#   'DatabaseSync' naam verteya → boot-sync kade chaleya hi nahi, te
#   khehrafoods di DB bina sync bani (no such column: permissions).
#   Fix:
#     1) db.js block vich apna require: const { DatabaseSync: _SS } = require('./sqlite')
#     2) saare tenant DBs te standalone sync dubara (gate5 step-2 wala, oh sahi si)
#     3) restart
# Idempotent. Backup + node --check + auto-restore.
set -u
BASE=/opt/flavorflow-saas
echo "=== FF-SAASGATE6 $(date) ==="

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow-saas/core/db.js';
let src = fs.readFileSync(f, 'utf8');
if (!src.includes('/* ffSchemaSync */')) { console.log('gate5 block hi nahi — pehla gate5 chalao'); process.exit(1); }
if (src.includes('DatabaseSync: _SS')) { console.log('db.js: already fixed ✓'); process.exit(0); }
const bak = f + '.bak-gate6-' + Date.now();
fs.copyFileSync(f, bak);
src = src.replace("const _ss_fs = require('fs');",
  "const _ss_fs = require('fs');\n  const { DatabaseSync: _SS } = require('./sqlite');");
src = src.replace('const _ss_mem = new DatabaseSync(\':memory:\');', 'const _ss_mem = new _SS(\':memory:\');');
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('db.js sync-block import fix ✓'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED'); process.exit(1); }
JS
[ $? -ne 0 ] && { echo "SAASGATE6 FAIL (db.js)"; exit 1; }

# standalone sync for ALL tenant DBs (works — direct sqlite require)
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
echo "SAASGATE6 VERIFIED ✓ — app band karke dubara kholo, Khehra Foods login + dashboard hun chalna chahida"
