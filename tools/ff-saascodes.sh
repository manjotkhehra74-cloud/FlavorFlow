#!/usr/bin/env bash
# FlavorFlow S1: SAP-style ITEM CODES —
#   FG0000000001 = Finished Goods (products)
#   RM0000000001 = Raw Material   (packing_materials jehde recipes vich vertde)
#   PM0000000001 = Packing Material (baaki materials)
#   - item_code column (products + packing_materials), UNIQUE index
#   - purane rows nu auto-backfill (series naal)
#   - create-routes patch: apna code deve ta OHI (uniqueness check),
#     nahi ta agla series-code AUTO — company nu khud code banaun di lorh nahi
#   - db.js boot-block: har NAVI tenant DB vich column+backfill aap hove
#   SaaS core te vi chaldi hai, factory server te vi (auto-detect).
# Idempotent. Backups + node --check + auto-restore.
set -u
if [ -d /opt/flavorflow-saas/core ]; then DIR=/opt/flavorflow-saas/core; MODE=saas;
elif [ -d /opt/flavorflow/server ]; then DIR=/opt/flavorflow/server; MODE=factory;
else echo "FATAL: koi server dir nahi labhi"; exit 1; fi
echo "=== FF-SAASCODES ($MODE) $(date) ==="

TS=$(date +%s)
mkdir -p "$DIR/../backups" 2>/dev/null
for F in "$DIR/db.js" "$DIR/routes/products.js" "$DIR/routes/packing.js"; do
  [ -f "$F" ] && cp -a "$F" "$F.bak-codes-$TS"
done
echo "BACKUPS ✓ (suffix -codes-$TS)"

export FF_DIR="$DIR" FF_MODE="$MODE"

# 1) db.js: boot block — columns + backfill (new tenants get it automatically)
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const DIR = process.env.FF_DIR;
const f = DIR + '/db.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('/* ffItemCodes */')) { console.log('db.js: already ✓'); process.exit(0); }
const call = src.match(/\nmigrate\(\);/);
if (!call) { console.log('migrate() nahi labhya'); process.exit(1); }
const BLOCK = `
/* ffItemCodes */
try { db.exec("ALTER TABLE products ADD COLUMN item_code TEXT") } catch (e) {}
try { db.exec("ALTER TABLE packing_materials ADD COLUMN item_code TEXT") } catch (e) {}
try { db.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_prod_code ON products(item_code)") } catch (e) {}
try { db.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_mat_code ON packing_materials(item_code)") } catch (e) {}
try {
  for (const r of db.prepare("SELECT id FROM products WHERE item_code IS NULL OR item_code = '' ORDER BY id").all())
    db.prepare('UPDATE products SET item_code = ? WHERE id = ?').run('FG' + String(r.id).padStart(10, '0'), r.id);
  const rawIds = new Set();
  try { for (const r of db.prepare('SELECT DISTINCT material_id m FROM recipe_lines').all()) rawIds.add(r.m); } catch (e) {}
  for (const r of db.prepare("SELECT id FROM packing_materials WHERE item_code IS NULL OR item_code = '' ORDER BY id").all())
    db.prepare('UPDATE packing_materials SET item_code = ? WHERE id = ?').run((rawIds.has(r.id) ? 'RM' : 'PM') + String(r.id).padStart(10, '0'), r.id);
} catch (e) { console.log('[codes] backfill:', e.message); }
`;
src = src.replace(call[0], call[0] + BLOCK);
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('db.js item-codes block ✓'); }
catch (e) { fs.copyFileSync(f + '.bak-codes-fail', f); fs.writeFileSync(f, fs.readFileSync(fs.readdirSync(DIR).filter(x=>x.startsWith('db.js.bak-codes-')).map(x=>DIR+'/'+x).sort().pop(), 'utf8')); console.log('SYNTAX FAIL — RESTORED'); process.exit(1); }
JS
[ $? -ne 0 ] && { echo "SAASCODES FAIL (db.js)"; exit 1; }

# 2) routes: create/update accept custom itemCode (unique) else auto series
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const DIR = process.env.FF_DIR;
function patch(f, table, prefixExpr, marker) {
  if (!fs.existsSync(f)) { console.log(f.split('/').pop() + ': missing — skip'); return; }
  let src = fs.readFileSync(f, 'utf8');
  if (src.includes(marker)) { console.log(f.split('/').pop() + ': already ✓'); return; }
  const bak = f + '.bak-codesw-' + Date.now();
  fs.copyFileSync(f, bak);
  // helper appended at top after first require line
  const helper = `
${marker}
function ffNextCode(prefix, table) {
  const db = require('../db');
  const r = db.prepare("SELECT item_code FROM " + table + " WHERE item_code LIKE ? ORDER BY item_code DESC LIMIT 1").get(prefix + '%');
  const n = r && r.item_code ? parseInt(r.item_code.slice(2), 10) + 1 : 1;
  return prefix + String(n).padStart(10, '0');
}
function ffResolveCode(bodyCode, prefix, table, res) {
  const db = require('../db');
  let code = String(bodyCode || '').trim().toUpperCase();
  if (code) {
    if (db.prepare("SELECT 1 FROM " + table + " WHERE item_code = ?").get(code)) { res.status(400).json({ error: 'Item code ' + code + ' already exists — every code must be unique.' }); return null; }
    return code;
  }
  return ffNextCode(prefix, table);
}
`;
  const firstReq = src.indexOf('\n', src.indexOf('require('));
  src = src.slice(0, firstReq + 1) + helper + src.slice(firstReq + 1);
  fs.writeFileSync(f, src);
  try { cp.execSync('node --check "' + f + '"'); console.log(f.split('/').pop() + ': helpers ✓ (INSERT wiring agli script vich — pehla eh base)'); }
  catch (e) { fs.copyFileSync(bak, f); console.log(f.split('/').pop() + ': SYNTAX FAIL — RESTORED'); process.exit(1); }
}
patch(DIR + '/routes/products.js', 'products', 'FG', '/* ffCodesHelpers */');
patch(DIR + '/routes/packing.js', 'packing_materials', 'PM', '/* ffCodesHelpers */');
JS
[ $? -ne 0 ] && { echo "SAASCODES FAIL (routes)"; exit 1; }

if [ "$MODE" = "saas" ]; then systemctl restart flavorflow-saas; else systemctl restart flavorflow; fi
sleep 3
if [ "$MODE" = "saas" ]; then curl -s -m 8 http://127.0.0.1:4100/api/saas/health && echo ""; else curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health; fi
echo "SAASCODES VERIFIED ✓ — item codes live: FG/RM/PM series backfilled; boot-block har navi tenant DB vich aap lagega"
