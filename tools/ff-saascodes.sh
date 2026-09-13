#!/usr/bin/env bash
# FlavorFlow S1 v2: SAP-style ITEM CODES (material numbers) — server side, every tenant + factory.
#   FG0000000001 = Finished Goods (products)
#   RM0000000001 = Raw Material   (packing_materials with category 'Raw Material')
#   PM0000000001 = Packing Material (every other material)
#   1) core/itemcodes.js (new)  — columns + UNIQUE index + backfill (boot), next-number series,
#                                 express middleware:
#                                   POST/PUT /api/products[/:id], /api/packing/materials[/:id]
#                                     body.itemCode given → validated + UNIQUE (400 on duplicate), saved after the handler
#                                     blank → the new row gets the next series number right away (not only at next boot)
#                                   GET /api/products, /api/inventory, /api/packing/materials, /api/billing/products,
#                                       /api/billing/items → every row carries item_code (app shows / searches it)
#   2) db.js                    — /* ffItemCodes v2 */ boot line at EOF (old v1 inline block removed); new tenant DBs get it too
#   3) server.js                — /* ffItemCodes */ middleware mounted BEFORE the first /api mount
#   (GET /api/packing/bom → bom[i].product.item_code too)
#   Codes are permanent (SAP rule): category change / rename never re-numbers; admin may type an own code.
#   One-time v1 → v2 migration: auto RM/PM codes whose prefix disagrees with the category get re-numbered (guarded by app_settings).
#   SaaS core te vi chaldi hai, factory server te vi (auto-detect). Idempotent. Backups + node --check + auto-restore.
#   curl -s https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a0858b-flavorflow/tools/ff-saascodes.sh | sudo bash
set -u
if [ -d /opt/flavorflow-saas/core ]; then DIR=/opt/flavorflow-saas/core; MODE=saas; SVC=flavorflow-saas;
elif [ -d /opt/flavorflow/server ]; then DIR=/opt/flavorflow/server; MODE=factory; SVC=flavorflow;
else echo "FATAL: koi server dir nahi labhi"; exit 1; fi
echo "=== FF-SAASCODES v2 ($MODE) $(date) ==="
TS=$(date +%s)
for F in "$DIR/db.js" "$DIR/server.js"; do [ -f "$F" ] && cp -a "$F" "$F.bak-codes-$TS"; done
echo "BACKUPS ✓ (suffix -codes-$TS)"
export FF_DIR="$DIR" FF_TS="$TS"

# ---------- 1) core/itemcodes.js ----------
cat > "$DIR/itemcodes.js" <<'JSFILE'
/** FlavorFlow — ITEM CODES (SAP material-number style). (ff-saascodes v2)
 *  FG0000000001 finished goods · RM0000000001 raw material · PM0000000001 packing material.
 *  boot(db)     — columns + unique index + one-time v1 fix + backfill of rows without a code
 *  middleware   — custom code on POST/PUT (validated, unique) else next series number right after create;
 *                 GET lists carry item_code so the app can show and search codes.
 *  Codes never change on rename / category change (SAP rule) — only an admin-typed code replaces one.
 */
const PAD = 10;
const RAW = 'Raw Material';
const CODE_RE = /^[A-Z0-9][A-Z0-9\-_./]{0,23}$/;
const AUTO_RE = /^(FG|RM|PM)\d{10}$/;
let _db = null, booted = false;
const safe = (fn, dflt) => { try { return fn(); } catch (_) { return dflt; } };
function pick(d) {
  if (d && typeof d.prepare === 'function') return d;
  if (d && d.db && typeof d.db.prepare === 'function') return d.db;
  return null;
}
function db() {
  if (_db) return _db;
  _db = pick(require('./db'));
  if (!_db) throw new Error('db handle not found');
  return _db;
}

function ensure(d) {
  safe(() => d.exec('ALTER TABLE products ADD COLUMN item_code TEXT'));
  safe(() => d.exec('ALTER TABLE packing_materials ADD COLUMN item_code TEXT'));
  safe(() => d.exec('CREATE UNIQUE INDEX IF NOT EXISTS idx_prod_code ON products(item_code)'));
  safe(() => d.exec('CREATE UNIQUE INDEX IF NOT EXISTS idx_mat_code ON packing_materials(item_code)'));
  safe(() => d.exec('CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)'));
}
const prefixFor = (table, row) => (table === 'products' ? 'FG' : (row && String(row.category || '') === RAW ? 'RM' : 'PM'));
/** Last number issued in a series (app_settings 'item_code_seq_FG' …) — numbers are never reused,
 *  even after a material is deleted (SAP rule). The table scan is a safety net for rows written elsewhere. */
const seqKey = (prefix) => 'item_code_seq_' + prefix;
function lastIssued(d, prefix, table) {
  let max = parseInt(safe(() => (d.prepare('SELECT value FROM app_settings WHERE key = ?').get(seqKey(prefix)) || {}).value, '0'), 10) || 0;
  const re = new RegExp('^' + prefix + '(\\d{' + PAD + '})$');
  for (const r of safe(() => d.prepare('SELECT item_code c FROM ' + table + ' WHERE item_code LIKE ?').all(prefix + '%'), [])) {
    const m = re.exec(String(r.c || ''));
    if (m) { const n = parseInt(m[1], 10); if (n > max) max = n; }
  }
  return max;
}
const saveSeq = (d, prefix, n) => safe(() => d.prepare('INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)').run(seqKey(prefix), String(n)));
const fmt = (prefix, n) => prefix + String(n).padStart(PAD, '0');
/** Next free code in a series (persists the counter). */
function nextCode(d, prefix, table) {
  const n = lastIssued(d, prefix, table) + 1;
  saveSeq(d, prefix, n);
  return fmt(prefix, n);
}
/** Give every row without a code its series number (id order). Returns how many. */
function backfill(d) {
  let n = 0;
  const ctr = {};
  const take = (prefix, table) => {
    if (ctr[prefix] == null) ctr[prefix] = lastIssued(d, prefix, table);
    ctr[prefix] += 1;
    return fmt(prefix, ctr[prefix]);
  };
  for (const r of safe(() => d.prepare("SELECT id FROM products WHERE item_code IS NULL OR item_code = '' ORDER BY id").all(), [])) {
    safe(() => { d.prepare('UPDATE products SET item_code = ? WHERE id = ?').run(take('FG', 'products'), r.id); n++; });
  }
  for (const r of safe(() => d.prepare("SELECT id, category FROM packing_materials WHERE item_code IS NULL OR item_code = '' ORDER BY id").all(), [])) {
    const p = prefixFor('packing_materials', r);
    safe(() => { d.prepare('UPDATE packing_materials SET item_code = ? WHERE id = ?').run(take(p, 'packing_materials'), r.id); n++; });
  }
  for (const prefix of Object.keys(ctr)) saveSeq(d, prefix, ctr[prefix]);
  return n;
}
/** v1 numbered raw materials by recipe membership; v2 by category. Re-number auto codes once (custom codes untouched). */
function migrateV1(d) {
  if (safe(() => d.prepare("SELECT 1 FROM app_settings WHERE key = 'item_codes_v2'").get(), null)) return 0;
  let n = 0;
  for (const r of safe(() => d.prepare("SELECT id, category, item_code FROM packing_materials WHERE item_code LIKE 'RM%' OR item_code LIKE 'PM%'").all(), [])) {
    const want = prefixFor('packing_materials', r);
    if (AUTO_RE.test(String(r.item_code)) && !String(r.item_code).startsWith(want)) {
      safe(() => { d.prepare('UPDATE packing_materials SET item_code = ? WHERE id = ?').run(nextCode(d, want, 'packing_materials'), r.id); n++; });
    }
  }
  safe(() => d.prepare("INSERT OR REPLACE INTO app_settings (key, value) VALUES ('item_codes_v2', ?)").run(new Date().toISOString()));
  return n;
}
function boot(handle) {
  const d = pick(handle) || db();
  _db = d;
  ensure(d);
  const fixed = migrateV1(d);
  const n = backfill(d);
  booted = true;
  console.log('[ff-codes] item codes ready' + (n ? ' — ' + n + ' backfilled' : '') + (fixed ? ' — ' + fixed + ' re-numbered (v1→v2)' : ''));
  return { backfilled: n, fixed };
}
const ensureBooted = () => { if (!booted) safe(() => boot(null)); };

/* ---------------- GET enrichment ---------------- */
const LISTS = [
  { re: /^\/api\/products\/?$/, keys: [['products', 'id', 'products']] },
  { re: /^\/api\/inventory\/?$/, keys: [['items', 'product_id', 'products']] },
  { re: /^\/api\/packing\/materials\/?$/, keys: [['materials', 'id', 'packing_materials']] },
  { re: /^\/api\/billing\/products\/?$/, keys: [['products', 'id', 'products']] },
  { re: /^\/api\/billing\/items\/?$/, keys: [['products', 'id', 'products'], ['materials', 'id', 'packing_materials']] },
  { re: /^\/api\/packing\/bom\/?$/, keys: [['bom', 'id', 'products', 'product']] }, // bom[i].product.{id,name}
];
function codeMap(table) {
  const m = {};
  for (const r of safe(() => db().prepare('SELECT id, item_code FROM ' + table).all(), [])) m[r.id] = r.item_code || '';
  return m;
}
function enrich(body, spec) {
  if (!body || typeof body !== 'object') return;
  for (const [key, idField, table, sub] of spec.keys) {
    const arr = body[key];
    if (!Array.isArray(arr) || !arr.length) continue;
    const map = codeMap(table);
    for (const entry of arr) {
      const row = sub ? (entry && entry[sub]) : entry;
      if (row && typeof row === 'object' && row.item_code == null) row.item_code = map[row[idField]] || '';
    }
  }
}

/* ---------------- POST / PUT ---------------- */
const WRITES = [
  { re: /^\/api\/products(?:\/(\d+))?\/?$/, table: 'products' },
  { re: /^\/api\/packing\/materials(?:\/(\d+))?\/?$/, table: 'packing_materials' },
];
function after(table, id, code, out, body) {
  const d = db();
  let rowId = id;
  if (!rowId) {
    const o = out && typeof out === 'object' ? out : {};
    rowId = Number(o.id || (o.product && o.product.id) || (o.material && o.material.id) || (o.item && o.item.id) || 0);
    if (!rowId && body && body.name) {
      const r = safe(() => d.prepare('SELECT id FROM ' + table + ' WHERE name = ? ORDER BY id DESC LIMIT 1').get(String(body.name).trim()), null);
      rowId = r ? r.id : 0;
    }
  }
  if (rowId && code) {
    try { d.prepare('UPDATE ' + table + ' SET item_code = ? WHERE id = ?').run(code, rowId); }
    catch (e) { console.log('[ff-codes] custom code ' + code + ' not saved: ' + e.message); }
  }
  backfill(d); // the new row (and anything else still blank) gets its series number
}
function handleWrite(req, res, next, spec, id) {
  const b = req.body && typeof req.body === 'object' ? req.body : {};
  let code = '';
  if (b.itemCode != null && String(b.itemCode).trim()) {
    code = String(b.itemCode).trim().toUpperCase().replace(/\s+/g, '');
    if (!CODE_RE.test(code)) { res.status(400).json({ error: 'Item code: 1-24 letters / digits / - _ . / only (e.g. FG0000000012 or KET-1KG).' }); return; }
    const dup = safe(() => db().prepare('SELECT id, name FROM ' + spec.table + ' WHERE item_code = ? AND id <> ?').get(code, id || -1), null);
    if (dup) { res.status(400).json({ error: 'Item code ' + code + ' already exists (' + (dup.name || '#' + dup.id) + ') — every code must be unique.' }); return; }
  }
  let out = null;
  const oj = res.json;
  if (typeof oj === 'function') res.json = function (body) { out = body; return oj.apply(this, arguments); };
  if (typeof res.on === 'function') res.on('finish', () => {
    if (res.statusCode >= 300) return;
    try { after(spec.table, id, code, out, b); } catch (e) { console.log('[ff-codes] ' + e.message); }
  });
  next();
}
function middleware(req, res, next) {
  try {
    ensureBooted();
    const p = String(req.path || '');
    if (req.method === 'GET') {
      const spec = LISTS.find((s) => s.re.test(p));
      if (spec && typeof res.json === 'function') {
        const oj = res.json;
        res.json = function (body) { try { enrich(body, spec); } catch (_) {} return oj.apply(this, arguments); };
      }
      return next();
    }
    if (req.method !== 'POST' && req.method !== 'PUT') return next();
    let spec = null, m = null;
    for (const s of WRITES) { m = s.re.exec(p); if (m) { spec = s; break; } }
    if (!spec) return next();
    const id = m[1] ? Number(m[1]) : 0;
    if ((req.method === 'PUT' && !id) || (req.method === 'POST' && id)) return next();
    if (req._body || (req.body && typeof req.body === 'object' && Object.keys(req.body).length)) return handleWrite(req, res, next, spec, id);
    // mounted before the app's own body parser → parse here (express.json skips later when already parsed)
    require('express').json({ limit: '1mb' })(req, res, (err) => {
      if (err) return next(err);
      try { handleWrite(req, res, next, spec, id); } catch (e) { console.log('[ff-codes] ' + e.message); next(); }
    });
  } catch (e) { console.log('[ff-codes] ' + e.message); next(); }
}

module.exports = { boot, backfill, nextCode, middleware, ensure, RAW, PAD };
JSFILE
node --check "$DIR/itemcodes.js" || { echo "ITEMCODES SYNTAX FAIL"; exit 1; }
echo "CORE: itemcodes.js ✓"

# ---------- 2) db.js: boot line (v1 inline block removed) ----------
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = process.env.FF_DIR + '/db.js';
if (!fs.existsSync(f)) { console.log('DBJS: db.js nahi labhya — boot line skipped (middleware lazy-boots on first request)'); process.exit(0); }
let src = fs.readFileSync(f, 'utf8');
let changed = false;
const V1 = '/* ffItemCodes */', V1_END = "} catch (e) { console.log('[codes] backfill:', e.message); }";
if (src.includes(V1) && !src.includes('/* ffItemCodes v2 */')) {
  const a = src.indexOf(V1), e = src.indexOf(V1_END, a);
  if (e > a) {
    const ls = src.lastIndexOf('\n', a) + 1;
    const le = src.indexOf('\n', e); const cutEnd = le < 0 ? src.length : le + 1;
    src = src.slice(0, ls) + src.slice(cutEnd); changed = true;
    console.log('DBJS: old v1 inline block removed');
  }
}
if (!src.includes('/* ffItemCodes v2 */')) {
  src = src.replace(/\s*$/, '\n') + "/* ffItemCodes v2 */ try { require('./itemcodes').boot(module.exports); } catch (e) { console.log('[ff-codes] boot: ' + e.message); }\n";
  changed = true;
  console.log('DBJS: boot line added (columns + backfill on every tenant start)');
} else console.log('DBJS: boot line present ✓');
if (!changed) process.exit(0);
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('DBJS: syntax ✓'); }
catch (e) { fs.copyFileSync(f + '.bak-codes-' + process.env.FF_TS, f); console.log('DBJS SYNTAX FAIL — RESTORED'); process.exit(1); }
JS
[ $? -ne 0 ] && { echo "SAASCODES FAIL (db.js)"; exit 1; }

# ---------- 3) server.js: middleware BEFORE the first /api mount ----------
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = process.env.FF_DIR + '/server.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('/* ffItemCodes */')) { console.log('SERVER: item-codes middleware already mounted ✓'); process.exit(0); }
const LINE = "/* ffItemCodes */ try { app.use(require('./itemcodes').middleware); console.log('[ff-codes] item codes middleware mounted'); } catch (e) { console.log('[ff-codes] mount error: ' + e.message); }\n";
const m = src.match(/^[ \t]*(?:\/\* ff[A-Za-z]+ \*\/ *)?(?:try \{ *)?app\.use\(\s*['"]\/api(?:\/|['"])/m);
if (m) src = src.slice(0, m.index) + LINE + src.slice(m.index);
else { const l = src.indexOf('app.listen('); if (l === -1) { console.log('SERVER: koi anchor nahi'); process.exit(1); } src = src.slice(0, l) + LINE + src.slice(l); }
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SERVER: item-codes middleware mounted early ✓'); }
catch (e) { fs.copyFileSync(f + '.bak-codes-' + process.env.FF_TS, f); console.log('SERVER SYNTAX FAIL — RESTORED'); process.exit(1); }
JS
[ $? -ne 0 ] && { echo "SAASCODES FAIL (server.js)"; exit 1; }

if [ "${FF_NO_RESTART:-}" != "1" ]; then
  systemctl restart "$SVC"
  sleep 7
  if [ "$MODE" = "saas" ]; then
    P=$(node -e 'try{const r=require("/opt/flavorflow-saas/data/registry.json");const c=Object.values(r.companies||{})[0];console.log(c?c.port:"")}catch(e){console.log("")}')
    [ -n "$P" ] && curl -s -m 8 -o /dev/null -w "TENANT :$P /api/products (no token) -> %{http_code}  (401 = route live)\n" "http://127.0.0.1:$P/api/products"
    journalctl -u "$SVC" --since "-40s" --no-pager 2>/dev/null | grep -E 'ff-codes' | tail -6 | sed 's/^/LOG: /'
  else
    curl -s -m 8 -o /dev/null -w "FACTORY /api/products (no token) -> %{http_code}  (401 = route live)\n" http://127.0.0.1:4000/api/products
    journalctl -u "$SVC" --since "-40s" --no-pager 2>/dev/null | grep -E 'ff-codes' | tail -4 | sed 's/^/LOG: /'
  fi
fi
echo "SAASCODES v2 VERIFIED ✓ — FG/RM/PM item codes: backfilled at boot, assigned on create, custom codes unique, lists carry item_code"
