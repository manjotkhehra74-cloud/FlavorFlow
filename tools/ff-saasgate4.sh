#!/usr/bin/env bash
# FlavorFlow SaaS P1d: totp_secret column fix —
#   Logs: "[api] no such column: totp_secret" — factory te eh column live DB
#   vich ALTER naal payi si (ff-totpfix), par db.js de CREATE TABLE vich nahi,
#   so navi tenant DB bina column bandi hai → login "Internal server error".
#   Fix (data-driven):
#     1) core files vichon totp_* column names detect karo
#     2) db.js: migrate ton baad ensure-columns block (ALTER try/catch, idempotent)
#     3) maujooda tenant DBs te vi ohi ALTERs laao
# Idempotent. Backup + node --check + auto-restore.
set -u
BASE=/opt/flavorflow-saas
echo "=== FF-SAASGATE4 $(date) ==="
[ -d "$BASE/core" ] || { echo "FATAL: core nahi"; exit 1; }

echo "--- DIAGNOSIS: totp_* references in core ---"
grep -roh "totp_[a-z_]*" "$BASE/core" --include=*.js 2>/dev/null | grep -v node_modules | sort -u

node - <<'JS'
const fs = require('fs'), cp = require('child_process'), path = require('path');
const BASE = '/opt/flavorflow-saas';

// 1) detect totp_* column names from core js (excluding node_modules)
const names = new Set();
function scan(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name.startsWith('.')) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) scan(p);
    else if (e.name.endsWith('.js')) {
      const s = fs.readFileSync(p, 'utf8');
      for (const m of s.matchAll(/totp_[a-z_]+/g)) names.add(m[0]);
    }
  }
}
scan(BASE + '/core');
const cols = [...names];
if (!cols.length) { console.log('koi totp_* reference nahi labhya — kuch hor masla, logs bhejo'); process.exit(1); }
console.log('columns to ensure:', cols.join(', '));
const ddl = cols.map(c => c.endsWith('_enabled')
  ? `try{db.exec("ALTER TABLE users ADD COLUMN ${c} INTEGER NOT NULL DEFAULT 0")}catch(e){}`
  : `try{db.exec("ALTER TABLE users ADD COLUMN ${c} TEXT")}catch(e){}`);

// 2) db.js: ensure-block after migrate() call
const f = BASE + '/core/db.js';
let src = fs.readFileSync(f, 'utf8');
if (!src.includes('/* ffTotpCols */')) {
  const bak = f + '.bak-gate4-' + Date.now();
  fs.copyFileSync(f, bak);
  const call = src.match(/\nmigrate\(\);/) || src.match(/\nmigrate\(\)\s*;/);
  if (!call) { console.log('migrate() call nahi labhya — eh lines bhejo:'); console.log(src.split('\n').filter(l=>l.includes('migrate')).join('\n')); process.exit(1); }
  src = src.replace(call[0], call[0] + '\n/* ffTotpCols */ ' + ddl.join(' '));
  fs.writeFileSync(f, src);
  try { cp.execSync('node --check "' + f + '"'); console.log('db.js ensure-columns ✓'); }
  catch (e) { fs.copyFileSync(bak, f); console.log('db.js SYNTAX FAIL — RESTORED'); process.exit(1); }
} else console.log('db.js: already patched ✓');

// 3) existing tenant DBs
const dataDir = BASE + '/data';
for (const d of fs.readdirSync(dataDir)) {
  if (!d.startsWith('tenant-')) continue;
  const dbf = path.join(dataDir, d, 'erp.db');
  if (!fs.existsSync(dbf)) continue;
  process.env.ERP_DB_PATH = dbf;
  delete require.cache[require.resolve(BASE + '/core/sqlite')];
  const { DatabaseSync } = require(BASE + '/core/sqlite');
  const db = new DatabaseSync(dbf);
  for (const c of cols) {
    try { db.exec('ALTER TABLE users ADD COLUMN ' + c + (c.endsWith('_enabled') ? ' INTEGER NOT NULL DEFAULT 0' : ' TEXT')); console.log(d + ': +' + c); }
    catch (e) { console.log(d + ': ' + c + ' already ✓'); }
  }
  db.close && db.close();
}
JS
[ $? -ne 0 ] && { echo "SAASGATE4 FAIL"; exit 1; }

systemctl restart flavorflow-saas
sleep 3
curl -s -m 8 http://127.0.0.1:4100/api/saas/health && echo ""
echo "SAASGATE4 VERIFIED ✓ — login dubara try karo (Super@123 wala testfoods te, ja navi Demo Spices company apne admin naal)"
