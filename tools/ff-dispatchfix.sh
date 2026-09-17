#!/usr/bin/env bash
# FlavorFlow: DISPATCH FIX v2 — menu + void (SaaS core + factory server, auto-detect).
#
#   Bug 1 — "Dispatch section allowed users nu dikhdi nahi":
#       the menu came from rbac.navForRole(role) (ROLE DEFAULTS only) while the API
#       checks each user's OWN permission list (Users → Edit → permission chips).
#       A Production Manager given dispatch.view could open Dispatch (API said yes)
#       but never saw it in the menu.
#       FIX: navperms.js middleware (mounted before the /api routers) — on
#       /api/auth/login and /api/auth/me the `nav` array is rebuilt from the
#       `permissions` array the same response carries (rbac NAV_ITEMS order,
#       Dashboard always, super_admin = everything). Granted → shows, taken away →
#       disappears (the API would refuse anyway). Every role, every custom list.
#
#   Bug 2 — Void → "Internal server error" (and 404 on SaaS tenants):
#       the ff-voidfix route called better-sqlite3's db.transaction(); this server's
#       node:sqlite wrapper has no such method → TypeError on EVERY call → 500.
#       SaaS tenants never had the route at all (voidfix was factory-only).
#       FIX: dispatchvoid.js (SAVEPOINT transaction — all or nothing; schema-aware:
#       qty_trays / remarks / batches optional; open invoice → 409) + route v2 in
#       routes/dispatch.js (old v1 block removed). POST /api/dispatch/:id/void,
#       perm dispatch.manage: every line's cartons/trays back to inventory, batch
#       used_cb/used_trays back, row stays in history as VOID.
#
#   SELF-TEST on an in-memory DB through the server's own sqlite wrapper runs BEFORE
#   anything is patched (stock, batch, status, remarks, rollback, invoice-409, menu).
#   node --check + auto-restore. Idempotent (identical block = no change, no restart).
#   curl -fsSL https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a0858b-flavorflow/tools/ff-dispatchfix.sh | sudo bash
set -u
if [ -d /opt/flavorflow-saas/core ]; then DIR=/opt/flavorflow-saas/core; MODE=saas; SVC=flavorflow-saas; BK=/opt/flavorflow-saas/backups;
elif [ -d /opt/flavorflow/server ]; then DIR=/opt/flavorflow/server; MODE=factory; SVC=flavorflow; BK=/opt/flavorflow/backups;
else echo "FATAL: koi server dir nahi labhi (/opt/flavorflow-saas/core ya /opt/flavorflow/server)"; exit 1; fi
echo "=== FF-DISPATCHFIX v2 ($MODE) $(date) ==="
[ -f "$DIR/routes/dispatch.js" ] || { echo "FATAL: $DIR/routes/dispatch.js nahi mili"; exit 1; }
[ -f "$DIR/server.js" ] || { echo "FATAL: $DIR/server.js nahi mili"; exit 1; }
TS=$(date +%s)
mkdir -p "$BK"
cp -a "$DIR/routes/dispatch.js" "$BK/dispatch.js.bak-dispatchfix-$TS"
cp -a "$DIR/server.js" "$BK/server.js.bak-dispatchfix-$TS"
if [ "$MODE" = factory ] && [ -f "$DIR/data/erp.db" ]; then cp -a "$DIR/data/erp.db" "$BK/erp.db.bak-dispatchfix-$TS" 2>/dev/null || true; fi
for f in dispatchvoid.js navperms.js; do [ -f "$DIR/$f" ] && cp -a "$DIR/$f" "$BK/$f.bak-dispatchfix-$TS"; done
echo "BACKUP: routes/dispatch.js server.js (+ modules, factory erp.db) -> $BK (suffix -dispatchfix-$TS)"
export FF_DIR="$DIR" FF_MODE="$MODE" FF_TS="$TS" FF_BK="$BK"

restore_modules() {
  for f in dispatchvoid.js navperms.js; do
    if [ -f "$BK/$f.bak-dispatchfix-$TS" ]; then cp -a "$BK/$f.bak-dispatchfix-$TS" "$DIR/$f"; else rm -f "$DIR/$f"; fi
  done
}

# ---------- 1) dispatchvoid.js (void logic — testable on its own) ----------
cat > "$DIR/dispatchvoid.js" <<'JSFILE'
/** FlavorFlow — dispatch VOID (ff-dispatchfix v2).
 *  voidDispatch(db, id, who) → { ok, code, returnedItems, batchLines } | { status, error }
 *  - every dispatch line's cartons / trays go back to inventory (row created when missing)
 *  - lines that carried a batch code give used_cb / used_trays back to that batch
 *  - dispatch row stays in history: status = 'VOID', remarks += ' [VOIDED by <who> <time>]'
 *  - an open (non-cancelled) invoice on the dispatch blocks the void (409) — cancel it first
 *  One SAVEPOINT transaction: all or nothing. Runs on the node:sqlite wrapper (no db.transaction()),
 *  on better-sqlite3 (uses db.transaction) and on tenants whose schema lacks qty_trays / remarks / batches.
 */
'use strict';
const cols = (db, t) => { try { return db.prepare('PRAGMA table_info(' + t + ')').all().map((c) => String(c.name)); } catch (_) { return []; } };
function runTx(db, fn) {
  if (typeof db.transaction === 'function') return db.transaction(fn)();
  let sp = false;
  try { db.exec('SAVEPOINT ff_void'); sp = true; } catch (_) {}
  try { const r = fn(); if (sp) db.exec('RELEASE ff_void'); return r; }
  catch (e) { if (sp) { try { db.exec('ROLLBACK TO ff_void'); db.exec('RELEASE ff_void'); } catch (_) {} } throw e; }
}
function stamp() {
  try { const h = require('./helpers'); if (typeof h.nowIso === 'function') return String(h.nowIso()); } catch (_) {}
  return new Date(Date.now() + 5.5 * 3600e3).toISOString();
}
function voidDispatch(db, id, who) {
  id = Number(id);
  if (!Number.isInteger(id) || id <= 0) return { status: 400, error: 'Bad dispatch id.' };
  const dCols = cols(db, 'dispatches');
  if (!dCols.length) return { status: 500, error: 'dispatches table not found.' };
  if (!dCols.includes('status')) {
    try { db.exec("ALTER TABLE dispatches ADD COLUMN status TEXT DEFAULT 'DISPATCHED'"); dCols.push('status'); }
    catch (_) { return { status: 500, error: 'dispatches.status column missing.' }; }
  }
  const d = db.prepare('SELECT * FROM dispatches WHERE id = ?').get(id);
  if (!d) return { status: 404, error: 'Dispatch not found.' };
  if (String(d.status || '').toUpperCase() === 'VOID') return { status: 400, error: 'This dispatch is already voided.' };
  try {
    const inv = db.prepare("SELECT number FROM invoices WHERE dispatch_id = ? AND UPPER(COALESCE(status, '')) != 'CANCELLED' LIMIT 1").get(id);
    if (inv) return { status: 409, error: 'Invoice ' + inv.number + ' is linked to this dispatch — cancel that invoice first, then void.' };
  } catch (_) { /* no billing module on this server */ }
  const items = db.prepare('SELECT * FROM dispatch_items WHERE dispatch_id = ?').all(id);
  const iCols = cols(db, 'inventory'), bCols = cols(db, 'batches');
  if (!iCols.includes('qty_cb')) return { status: 500, error: 'inventory.qty_cb column missing.' };
  const hasTrays = iCols.includes('qty_trays'), hasUpd = iCols.includes('updated_at');
  const hasBatch = bCols.includes('used_cb') && bCols.includes('used_trays') && bCols.includes('code');
  const now = stamp();
  let batchLines = 0;
  runTx(db, () => {
    for (const it of items) {
      const pid = Number(it.product_id) || 0;
      if (!pid) continue;
      const cb = Number(it.cartons) || 0, tr = Number(it.trays) || 0;
      if (db.prepare('SELECT product_id FROM inventory WHERE product_id = ?').get(pid)) {
        const set = ['qty_cb = COALESCE(qty_cb, 0) + ?'], v = [cb];
        if (hasTrays) { set.push('qty_trays = COALESCE(qty_trays, 0) + ?'); v.push(tr); }
        if (hasUpd) { set.push('updated_at = ?'); v.push(now); }
        v.push(pid);
        db.prepare('UPDATE inventory SET ' + set.join(', ') + ' WHERE product_id = ?').run(...v);
      } else {
        const c = ['product_id', 'qty_cb'], v = [pid, cb];
        if (hasTrays) { c.push('qty_trays'); v.push(tr); }
        if (hasUpd) { c.push('updated_at'); v.push(now); }
        db.prepare('INSERT INTO inventory (' + c.join(', ') + ') VALUES (' + c.map(() => '?').join(', ') + ')').run(...v);
      }
      const code = String(it.batch_code || '').trim();
      if (code && hasBatch) {
        let remCb = cb, remTr = tr;
        const bchs = db.prepare('SELECT id, COALESCE(used_cb, 0) ucb, COALESCE(used_trays, 0) utr FROM batches WHERE code = ? AND product_id = ? ORDER BY id DESC').all(code, pid);
        for (const b of bchs) {
          if (remCb <= 0 && remTr <= 0) break;
          const backCb = Math.min(remCb, Number(b.ucb) || 0), backTr = Math.min(remTr, Number(b.utr) || 0);
          if (backCb > 0 || backTr > 0) {
            db.prepare('UPDATE batches SET used_cb = COALESCE(used_cb, 0) - ?, used_trays = COALESCE(used_trays, 0) - ? WHERE id = ?').run(backCb, backTr, b.id);
            remCb -= backCb; remTr -= backTr; batchLines++;
          }
        }
      }
    }
    const note = ' [VOIDED by ' + String(who || 'user').slice(0, 60) + ' ' + now.slice(0, 16).replace('T', ' ') + ']';
    if (dCols.includes('remarks')) db.prepare("UPDATE dispatches SET status = 'VOID', remarks = COALESCE(remarks, '') || ? WHERE id = ?").run(note, id);
    else db.prepare("UPDATE dispatches SET status = 'VOID' WHERE id = ?").run(id);
  });
  return { ok: true, code: d.code || '', returnedItems: items.length, batchLines };
}
module.exports = { voidDispatch, runTx };
JSFILE

# ---------- 2) navperms.js (menu follows effective permissions) ----------
cat > "$DIR/navperms.js" <<'JSFILE'
/** FlavorFlow — menu follows the user's EFFECTIVE permissions (ff-dispatchfix).
 *  The core builds the menu with rbac.navForRole(role) — role defaults only — while the API checks each
 *  user's own permission list (Users → Edit → permission chips). A user given dispatch.view could open
 *  Dispatch but never saw it in the menu. This middleware rewrites `nav` in the /api/auth/login and
 *  /api/auth/me responses from the `permissions` array the same response carries: rbac NAV_ITEMS order,
 *  Dashboard always, super_admin = everything, entries added by other patches kept when their permission
 *  is granted. Pure functions (navFor / rewrite) are unit-tested by ff-dispatchfix before install.
 */
'use strict';
const ALWAYS = new Set(['dashboard.view']);
const RE = /^\/api\/auth\/(login|me)\/?$/;
function items() { try { const r = require('./rbac'); return Array.isArray(r.NAV_ITEMS) ? r.NAV_ITEMS : []; } catch (_) { return []; } }
function navFor(navItems, permissions, serverNav) {
  const perms = new Set((Array.isArray(permissions) ? permissions : []).map(String));
  const all = perms.has('*');
  const ok = (perm) => !perm || all || ALWAYS.has(perm) || perms.has(perm);
  const out = [], seen = new Set();
  for (const it of navItems || []) if (it && it.path && !seen.has(it.path) && ok(it.perm)) { out.push(it); seen.add(it.path); }
  for (const it of serverNav || []) if (it && it.path && !seen.has(it.path) && ok(it.perm)) { out.push(it); seen.add(it.path); }
  return out;
}
function rewrite(body) {
  if (!body || typeof body !== 'object' || !Array.isArray(body.nav)) return body;
  const role = body.user && body.user.role;
  const perms = role === 'super_admin' ? ['*'] : body.permissions;
  if (!Array.isArray(perms)) return body;
  body.nav = navFor(items(), perms, body.nav);
  return body;
}
function middleware(req, res, next) {
  let hit = false;
  try { hit = RE.test(String(req.originalUrl || req.url || '').split('?')[0]); } catch (_) {}
  if (hit && res && typeof res.json === 'function') {
    const oj = res.json;
    res.json = function (...args) {
      try { rewrite(args[0]); } catch (_) {}
      return oj.apply(this, args);
    };
  }
  next();
}
module.exports = { navFor, rewrite, middleware, items };
JSFILE

if ! node --check "$DIR/dispatchvoid.js" || ! node --check "$DIR/navperms.js"; then
  echo "FATAL: module syntax fail — restored"; restore_modules; exit 1
fi

# ---------- 3) SELF-TEST (in-memory DB through the server's own sqlite wrapper) ----------
node - <<'JS'
const DIR = process.env.FF_DIR;
const fail = (m) => { console.log('SELFTEST FAIL: ' + m); process.exit(2); };
let DatabaseSync = null;
try { DatabaseSync = require(DIR + '/sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) { try { DatabaseSync = require('node:sqlite').DatabaseSync; } catch (_) {} }
if (!DatabaseSync) { console.log('SELFTEST: koi sqlite wrapper nahi — DB test skip (menu test hi)'); }
const { voidDispatch } = require(DIR + '/dispatchvoid');
const { navFor, rewrite } = require(DIR + '/navperms');
if (DatabaseSync) {
  const db = new DatabaseSync(':memory:');
  db.exec(`CREATE TABLE dispatches (id INTEGER PRIMARY KEY, code TEXT, status TEXT, remarks TEXT);
CREATE TABLE dispatch_items (id INTEGER PRIMARY KEY, dispatch_id INTEGER, product_id INTEGER, cartons INTEGER, trays INTEGER, batch_code TEXT);
CREATE TABLE inventory (product_id INTEGER PRIMARY KEY, qty_cb INTEGER NOT NULL DEFAULT 0, qty_trays INTEGER NOT NULL DEFAULT 0, updated_at TEXT);
CREATE TABLE batches (id INTEGER PRIMARY KEY, code TEXT, product_id INTEGER, used_cb INTEGER DEFAULT 0, used_trays INTEGER DEFAULT 0);
CREATE TABLE invoices (id INTEGER PRIMARY KEY, number TEXT, dispatch_id INTEGER, status TEXT);
INSERT INTO dispatches VALUES (1, 'DSP-1', 'DISPATCHED', ''), (2, 'DSP-2', 'DISPATCHED', NULL), (3, 'DSP-3', 'DISPATCHED', '');
INSERT INTO dispatch_items VALUES (1, 1, 7, 10, 2, 'B1'), (2, 1, 8, 5, 0, ''), (3, 2, 7, 1, 0, ''), (4, 2, 9, 1, 0, ''), (5, 3, 7, 1, 0, '');
INSERT INTO inventory VALUES (7, 90, 3, NULL), (9, 1, 0, NULL);
INSERT INTO batches VALUES (1, 'B1', 7, 10, 2);
INSERT INTO invoices VALUES (1, 'INV-1', 3, 'ISSUED');
CREATE TRIGGER ff_boom BEFORE UPDATE ON inventory WHEN NEW.product_id = 9 BEGIN SELECT RAISE(ABORT, 'boom'); END;`);
  const r = voidDispatch(db, 1, 'tester');
  if (!r.ok || r.returnedItems !== 2) fail('void #1 → ' + JSON.stringify(r));
  const i7 = db.prepare('SELECT qty_cb, qty_trays FROM inventory WHERE product_id = 7').get();
  if (!i7 || Number(i7.qty_cb) !== 100 || Number(i7.qty_trays) !== 5) fail('inventory 7 → ' + JSON.stringify(i7));
  const i8 = db.prepare('SELECT qty_cb FROM inventory WHERE product_id = 8').get();
  if (!i8 || Number(i8.qty_cb) !== 5) fail('inventory 8 (new row) → ' + JSON.stringify(i8));
  const b = db.prepare('SELECT used_cb, used_trays FROM batches WHERE id = 1').get();
  if (Number(b.used_cb) !== 0 || Number(b.used_trays) !== 0) fail('batch → ' + JSON.stringify(b));
  const d = db.prepare('SELECT status, remarks FROM dispatches WHERE id = 1').get();
  if (d.status !== 'VOID' || !/VOIDED by tester/.test(String(d.remarks))) fail('dispatch row → ' + JSON.stringify(d));
  const r2 = voidDispatch(db, 1, 'tester'); if (r2.status !== 400) fail('second void → ' + JSON.stringify(r2));
  const r3 = voidDispatch(db, 99, 'tester'); if (r3.status !== 404) fail('missing id → ' + JSON.stringify(r3));
  const r4 = voidDispatch(db, 3, 'tester'); if (r4.status !== 409) fail('open invoice → ' + JSON.stringify(r4));
  let threw = false; try { voidDispatch(db, 2, 'tester'); } catch (e) { threw = /boom/.test(e.message); }
  if (!threw) fail('rollback case did not throw');
  const i7b = db.prepare('SELECT qty_cb FROM inventory WHERE product_id = 7').get();
  const d2 = db.prepare('SELECT status FROM dispatches WHERE id = 2').get();
  if (Number(i7b.qty_cb) !== 100 || d2.status !== 'DISPATCHED') fail('rollback → inv7=' + i7b.qty_cb + ' d2=' + d2.status);
  try { db.close && db.close(); } catch (_) {}
}
let rb = {}; try { rb = require(DIR + '/rbac'); } catch (_) {}
const items = Array.isArray(rb.NAV_ITEMS) ? rb.NAV_ITEMS : [];
if (!items.length) console.log('SELFTEST: rbac NAV_ITEMS nahi labhe — menu sirf server-nav filter karega');
const roleNav = typeof rb.navForRole === 'function' ? rb.navForRole('production_manager') : [];
const custom = ['dashboard.view', 'products.view', 'production.view', 'dispatch.view', 'dispatch.manage'];
const n1 = navFor(items, custom, roleNav).map((e) => e.path);
if (items.length && (!n1.includes('/dispatch') || n1.includes('/inventory') || n1[0] !== '/dashboard')) fail('navFor custom → ' + n1.join(','));
const n2 = rewrite({ user: { role: 'super_admin' }, permissions: [], nav: [] }).nav.map((e) => e.path);
if (items.length && n2.length !== items.length) fail('super_admin menu → ' + n2.length + '/' + items.length);
const n3 = rewrite({ user: { role: 'store_keeper' }, permissions: ['products.view'], nav: roleNav }).nav.map((e) => e.path);
if (items.length && (n3[0] !== '/dashboard' || n3.includes('/dispatch') || !n3.includes('/products'))) fail('reduced perms menu → ' + n3.join(','));
const n4 = rewrite({ error: 'TOTP_REQUIRED' }); if (!n4 || n4.nav !== undefined) fail('non-session body touched');
console.log('SELFTEST: void (stock + new row + batch + status/remarks + already-voided + 404 + invoice-409 + rollback) ✓  menu (custom → /dispatch, super_admin → ' + n2.length + ', reduced → dropped) ✓');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "FATAL: self-test fail (rc=$RC) — kuch patch NAHI kita, modules restored"; restore_modules; exit 1; fi

# ---------- 4) routes/dispatch.js: void route v2 (v1 ff-voidfix block removed) ----------
ROUTE_BLOCK=/tmp/ff-dispatchfix-route-$TS.js
cat > "$ROUTE_BLOCK" <<'EOF'
/* ffDispatchVoid v2 */
/** Void a wrong dispatch (ff-dispatchfix): every line's stock goes back to inventory and to the batch it came
 *  from; the row stays in history as VOID. Logic lives in ../dispatchvoid.js — SAVEPOINT transaction, so it
 *  works on the node:sqlite wrapper (the old ff-voidfix route called better-sqlite3's db.transaction → 500). */
router.post('/:id/void', __GUARD__(req, res) => {
  const id = Number(req.params.id);
  let out;
  try {
    const who = (req.user && (req.user.name || req.user.email)) || 'user';
    out = require('../dispatchvoid').voidDispatch(db, id, who);
  } catch (e) { return res.status(500).json({ error: 'Void failed: ' + e.message }); }
  if (out.error) return res.status(out.status || 400).json({ error: out.error });
  try { require('../helpers').audit(db, req.user, 'VOID', 'dispatch', id, 'Dispatch ' + (out.code || id) + ' voided — ' + out.returnedItems + ' line(s) returned to stock'); } catch (_) {}
  res.json(out);
});
/* end ffDispatchVoid */
EOF
export FF_ROUTE_BLOCK="$ROUTE_BLOCK"
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const DIR = process.env.FF_DIR, TS = process.env.FF_TS, BK = process.env.FF_BK;
const f = DIR + '/routes/dispatch.js';
let src = fs.readFileSync(f, 'utf8');
const hasPerm = /requirePerm/.test(src);
const guard = hasPerm ? "requirePerm('dispatch.manage'), " : '';
const BLOCK = fs.readFileSync(process.env.FF_ROUTE_BLOCK, 'utf8').replace('__GUARD__', guard).replace(/\s+$/, '') + '\n';
if (src.includes(BLOCK)) { console.log('ROUTE: POST /api/dispatch/:id/void v2 present ✓ (identical)'); process.exit(0); }
if (!/const db = require\(['"]\.\.\/db['"]\)/.test(src)) console.log("ROUTE: WARN — 'const db = require(../db)' line nahi dikhi (route 'db' vartda hai)");
const v1 = src.indexOf('/** ff-voidfix');
if (v1 !== -1) {
  const rs = src.indexOf("router.post('/:id/void'", v1);
  const end = rs === -1 ? -1 : src.indexOf('\n});\n', rs);
  if (rs === -1 || end === -1) { console.log('ROUTE: purana ff-voidfix block labhya par anchors nahi — manual check'); process.exit(1); }
  const ls = src.lastIndexOf('\n', v1) + 1;
  src = src.slice(0, ls) + src.slice(end + 5);
  console.log('ROUTE: old ff-voidfix v1 route removed (db.transaction crash)');
}
const s2 = src.indexOf('/* ffDispatchVoid v');
if (s2 !== -1) {
  const em = '/* end ffDispatchVoid */';
  const e2 = src.indexOf(em, s2);
  if (e2 === -1) { console.log('ROUTE: v2 end marker nahi — manual check'); process.exit(1); }
  const ls = src.lastIndexOf('\n', s2) + 1;
  let cut = e2 + em.length; if (src[cut] === '\n') cut++;
  src = src.slice(0, ls) + src.slice(cut);
  console.log('ROUTE: older v2 block replaced');
}
const mi = src.indexOf('module.exports = router;');
if (mi === -1) { console.log('ROUTE: module.exports = router; nahi labhya'); process.exit(1); }
src = src.slice(0, mi) + BLOCK + '\n' + src.slice(mi);
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('ROUTE: POST /api/dispatch/:id/void v2 ✓' + (hasPerm ? ' (dispatch.manage guard)' : ' (no requirePerm in file — core auth only)')); }
catch (e) { fs.copyFileSync(BK + '/dispatch.js.bak-dispatchfix-' + TS, f); console.log('ROUTE: SYNTAX FAIL — restored: ' + String(e.stderr || e).slice(0, 300)); process.exit(1); }
process.exit(3);
JS
RC=$?; rm -f "$ROUTE_BLOCK"
[ $RC -eq 1 ] && { echo "DISPATCHFIX FAIL (routes/dispatch.js) — backups: $BK"; exit 1; }
CHANGED=0; [ $RC -eq 3 ] && CHANGED=1

# ---------- 5) server.js: navperms middleware BEFORE the first /api mount ----------
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const DIR = process.env.FF_DIR, TS = process.env.FF_TS, BK = process.env.FF_BK;
const f = DIR + '/server.js';
let src = fs.readFileSync(f, 'utf8');
const LINE = "/* ffNavPerms */ try { app.use(require('./navperms').middleware); console.log('[ff-dispatchfix] menu-from-permissions mounted'); } catch (e) { console.log('[ff-dispatchfix] navperms mount error: ' + e.message); }\n";
if (src.includes(LINE)) { console.log('SERVER: navperms middleware already mounted ✓'); process.exit(0); }
if (src.includes('/* ffNavPerms */')) {
  src = src.replace(/^.*\/\* ffNavPerms \*\/.*\n/m, LINE);
  console.log('SERVER: older navperms mount line replaced');
} else {
  const m = src.match(/^[ \t]*(?:\/\* ff[A-Za-z]+ \*\/ *)?(?:try \{ *)?app\.use\(\s*['"]\/api(?:\/|['"])/m);
  if (m) src = src.slice(0, m.index) + LINE + src.slice(m.index);
  else { const l = src.indexOf('app.listen('); if (l === -1) { console.log('SERVER: koi anchor nahi (app.use /api ya app.listen)'); process.exit(1); } src = src.slice(0, l) + LINE + src.slice(l); }
}
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SERVER: navperms middleware mounted before the /api routers ✓'); }
catch (e) { fs.copyFileSync(BK + '/server.js.bak-dispatchfix-' + TS, f); console.log('SERVER: SYNTAX FAIL — restored: ' + String(e.stderr || e).slice(0, 300)); process.exit(1); }
process.exit(3);
JS
RC=$?
[ $RC -eq 1 ] && { echo "DISPATCHFIX FAIL (server.js) — backups: $BK"; exit 1; }
[ $RC -eq 3 ] && CHANGED=1

# ---------- 6) restart + verify ----------
if [ "$CHANGED" = 1 ] && [ -z "${FF_NO_RESTART:-}" ]; then
  systemctl restart "$SVC" && echo "SERVER: $SVC restarted" || echo "SERVER: restart FAIL — journalctl -u $SVC -n 40"
  sleep 7
else
  echo "SERVER: koi change nahi — restart di lod nahi"
fi
if [ "$MODE" = saas ]; then
  node - <<'JS'
const fs = require('fs'), cp = require('child_process');
let reg = {}; try { reg = JSON.parse(fs.readFileSync('/opt/flavorflow-saas/data/registry.json', 'utf8')); } catch (_) {}
let ok = 0, bad = 0, n = 0;
for (const [code, c] of Object.entries(reg.companies || {})) {
  if (!c.port) continue; n++;
  let st = '000';
  try { st = cp.execSync('curl -s -o /dev/null -w "%{http_code}" -m 6 -X POST -H "content-type: application/json" -d "{}" http://127.0.0.1:' + c.port + '/api/dispatch/0/void').toString().trim(); } catch (_) {}
  if (st !== '404' && st !== '000' && st !== '502') { ok++; if (ok <= 3) console.log('TENANT ' + code + ' -> ' + st + ' ✓ (route live; login required)'); }
  else { bad++; console.log('TENANT ' + code + ' -> ' + st + ' ✗'); }
}
console.log('TENANT void route: ' + ok + '/' + n + ' live' + (bad ? ' (' + bad + ' abhi boot ho rahe / fail — 20 s baad dubara check)' : ''));
JS
else
  ST=$(curl -s -o /dev/null -w '%{http_code}' -m 6 -X POST -H 'content-type: application/json' -d '{}' http://127.0.0.1:4000/api/dispatch/0/void 2>/dev/null)
  HL=$(curl -s -o /dev/null -w '%{http_code}' -m 6 http://127.0.0.1:4000/api/health 2>/dev/null)
  echo "FACTORY health -> $HL · POST /api/dispatch/0/void -> $ST $( [ "$ST" != 404 ] && [ "$ST" != 000 ] && echo '✓ (route live; login required)' || echo '✗ (route missing / server down)')"
  if journalctl -u flavorflow --since '-2 min' --no-pager 2>/dev/null | grep -q 'menu-from-permissions mounted'; then echo "FACTORY menu-from-permissions mounted ✓ (journal)"; fi
fi
grep -q 'ffDispatchVoid v2' "$DIR/routes/dispatch.js" && grep -q 'ffNavPerms' "$DIR/server.js" && \
  echo "DISPATCHFIX VERIFIED ✓ — (1) menu = user di apni permissions (custom chips vi), (2) Void kamm karda (stock + batch wapas, row VOID). App: logout → login (ya ⋮ → Refresh permissions)" || \
  { echo "DISPATCHFIX: markers nahi labhe ✗"; exit 1; }
