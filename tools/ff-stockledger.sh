#!/usr/bin/env bash
# FlavorFlow ERP — STOCK LEDGER (SAP MB51 / MMBE / MB5B style), server side, every tenant + factory.
#   Har item (finished product + raw / packing material) da PURA inward/outward record, document number
#   te running balance naal — jo vi stock badle, entry aape ban jandi hai:
#     PURCHASE (supplier bill no.)  PURCHASE_CANCEL   RECEIPT (GRN / ref no.)   SET_STOCK (physical count)
#     PRODUCTION (batch code, + BOM issue)  RECIPE / CONSUMED (issue)   RECEIVED (manual material GR)
#     DISPATCH (dispatch no. + destination + truck)  DISPATCH_VOID   SALE (invoice no.)  SALE_CANCEL
#     ADJUSTMENT (adjustment code)   OPENING   EXTERNAL / SYNC (script / outside-app change)
#   How: SQLite triggers on inventory.qty_cb/qty_trays and packing_materials.stock write stock_journal rows
#   (nothing can bypass them); an express middleware (mounted before every router) leaves the request's document
#   context (kind, doc no, party, user, business date) for the trigger; billing.js marks bill/invoice numbers.
#   1) core/stockctx.js (new)         — schema + triggers + request context + one-time backfill + reconcile
#   2) core/routes/stock.js (new)     — /api/stock/* : status, ledger[.csv]?type=&id=, register[.csv], balances[.csv], documents
#   3) server.js                      — /* ffStockLedger */ middleware + early mount BEFORE the first /api mount + backfill at boot
#   4) routes/billing.js              — sjMark() on invoice create/cancel + purchase create/cancel (bill no / invoice no / party)
#   Perms: guarded by inventory.view (same as the Inventory screen). Idempotent; backups + node --check + auto-restore.
#   curl -s https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a0858b-flavorflow/tools/ff-stockledger.sh | sudo bash
set -u
if [ -d /opt/flavorflow-saas/core ]; then DIR=/opt/flavorflow-saas/core; MODE=saas; SVC=flavorflow-saas;
elif [ -d /opt/flavorflow/server ]; then DIR=/opt/flavorflow/server; MODE=factory; SVC=flavorflow;
else echo "FATAL: koi server dir nahi labhi"; exit 1; fi
echo "=== FF-STOCKLEDGER ($MODE) $(date) ==="
TS=$(date +%s)
mkdir -p "$DIR/routes"
for F in "$DIR/server.js" "$DIR/routes/billing.js"; do [ -f "$F" ] && cp -a "$F" "$F.bak-stockledger-$TS"; done
echo "BACKUPS ✓ (suffix -stockledger-$TS)"
export FF_DIR="$DIR" FF_TS="$TS"
PV=inventory.view
if [ -f "$DIR/rbac.js" ] && ! grep -q "'inventory.view'" "$DIR/rbac.js"; then PV=products.view; fi

# ---------- 1) core/stockctx.js ----------
cat > "$DIR/stockctx.js" <<'JSFILE'
/** FlavorFlow — STOCK JOURNAL (SAP-style material documents). (ff-stockledger)
 *
 *  Every change of inventory.qty_cb / qty_trays (finished goods) and of
 *  packing_materials.stock (raw & packing material) is written to stock_journal
 *  by SQLite triggers — whichever route, patch or script changed it — so no
 *  movement can slip past the ledger. The request that causes the change leaves
 *  its document context (movement kind, doc no, party, user, business date) in
 *  stock_ctx right before the handler runs; the trigger copies it onto the
 *  journal row. After the response the row gets the document number the
 *  handler generated (dispatch code, batch code, adjustment code …).
 *
 *  Movement kinds (≈ SAP movement types):
 *    PURCHASE (101 GR vs supplier bill)   PURCHASE_CANCEL (102)
 *    RECEIPT (501 GR without PO)          OPENING (561 initial stock)
 *    PRODUCTION (101 GR from order + BOM issue 261)
 *    RECIPE / CONSUMED (261 GI to order)  RECEIVED (501 manual material GR)
 *    DISPATCH (601 GI delivery)           DISPATCH_VOID (602)
 *    SALE (601 GI vs invoice)             SALE_CANCEL (602)
 *    ADJUSTMENT (701/702 approved diff)   SET_STOCK (physical count typed)
 *    REVERSAL / DELETED / SYNC (changed outside the app) / EXTERNAL / OTHER
 */
const db = require('./db');
let seq = 0, lastErr = '';
const str = (v, n) => String(v == null ? '' : v).trim().slice(0, n || 200);
const isYmd = (s) => /^\d{4}-\d{2}-\d{2}$/.test(String(s || ''));
const H = (() => { try { return require('./helpers'); } catch (_) { return {}; } })();
const nowIso = typeof H.nowIso === 'function' ? H.nowIso : () => new Date(Date.now() + 5.5 * 3600e3).toISOString();
const todayIst = () => new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10);
const safeAll = (sql, a) => { try { return db.prepare(sql).all(...(a || [])); } catch (_) { return []; } };
const safeGet = (sql, a) => { try { return db.prepare(sql).get(...(a || [])); } catch (_) { return null; } };
const exec = (sql) => { try { db.exec(sql); return true; } catch (e) { lastErr = e.message; return false; } };
const hasTable = (t) => !!safeGet("SELECT 1 one FROM sqlite_master WHERE type = 'table' AND name = ?", [t]);
const hasCol = (t, c) => safeAll('PRAGMA table_info(' + t + ')').some((r) => r.name === c);
const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const runTx = (fn) => {
  if (typeof db.transaction === 'function') return db.transaction(fn)();
  let sp = false;
  try { db.exec('SAVEPOINT ff_sj'); sp = true; } catch (_) {}
  try { const r = fn(); if (sp) db.exec('RELEASE ff_sj'); return r; }
  catch (e) { if (sp) { try { db.exec('ROLLBACK TO ff_sj'); db.exec('RELEASE ff_sj'); } catch (_) {} } throw e; }
};

// ---------- request context store ----------
// Preferred: AsyncLocalStorage + a SQLite user-defined function — the trigger asks ff_sj_ctx('kind') etc. at the
// exact moment of the write, so the context is always the one of the request doing the write, even when several
// requests are in flight (async auth / body parsing). Fallback (db wrapper without .function): a TEMP table row
// re-asserted after body parse and auth (watch()) — correct whenever the handler writes synchronously after auth.
const { AsyncLocalStorage } = require('async_hooks');
const als = new AsyncLocalStorage();
let current = null; // last request that set a context (fallback when the ALS store is unavailable)
const ctxOf = () => { const s = als.getStore() || current; return s && !s.done ? s.row : null; };
const rawDb = (() => { for (const c of [db, db._db, db.db, db.raw, db.conn, db.native, db.sqlite]) if (c && typeof c.function === 'function') return c; return null; })();
let UDF = false;
if (rawDb && process.env.FF_SJ_NO_UDF !== '1') {
  try {
    rawDb.function('ff_sj_ctx', (field) => { const r = ctxOf(); if (!r) return null; const v = r[String(field)]; return v == null || v === '' ? null : (typeof v === 'number' ? v : String(v)); });
    UDF = true;
  } catch (e) { console.log('[stock-journal] UDF unavailable (' + e.message + ') — using context table'); }
}

// ---------- schema ----------
exec(`CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS stock_journal (
  id INTEGER PRIMARY KEY AUTOINCREMENT, item_type TEXT NOT NULL, item_id INTEGER NOT NULL,
  qty REAL NOT NULL DEFAULT 0, qty2 REAL NOT NULL DEFAULT 0, balance REAL, balance2 REAL,
  kind TEXT NOT NULL DEFAULT '', ref TEXT NOT NULL DEFAULT '', doc2 TEXT NOT NULL DEFAULT '', party TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT '', link TEXT NOT NULL DEFAULT '', req_id TEXT NOT NULL DEFAULT '',
  user_id INTEGER, user_name TEXT NOT NULL DEFAULT '', txn_date TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,
  backfilled INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS idx_sj_item ON stock_journal(item_type, item_id, id);
CREATE INDEX IF NOT EXISTS idx_sj_date ON stock_journal(txn_date, id);
CREATE INDEX IF NOT EXISTS idx_sj_req ON stock_journal(req_id);
CREATE INDEX IF NOT EXISTS idx_sj_kind ON stock_journal(kind, txn_date);`);
// Context + shadow live in the connection's TEMP schema (in memory): the per-request context writes never
// touch the tenant DB file, and the TEMP triggers fire only for this process — exactly the writes the
// request context describes. Anything changed by another process is caught by reconcile() → SYNC row.
exec('PRAGMA temp_store = MEMORY');
exec(`CREATE TEMP TABLE IF NOT EXISTS stock_ctx (id INTEGER PRIMARY KEY, req_id TEXT NOT NULL DEFAULT '', kind TEXT NOT NULL DEFAULT '', ref TEXT NOT NULL DEFAULT '',
  doc2 TEXT NOT NULL DEFAULT '', party TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '', link TEXT NOT NULL DEFAULT '', user_id INTEGER,
  user_name TEXT NOT NULL DEFAULT '', txn_date TEXT NOT NULL DEFAULT '', set_at TEXT NOT NULL DEFAULT '');
INSERT OR IGNORE INTO stock_ctx (id) VALUES (1);
CREATE TEMP TABLE IF NOT EXISTS stock_shadow (item_type TEXT NOT NULL, item_id INTEGER NOT NULL, qty REAL NOT NULL DEFAULT 0, qty2 REAL NOT NULL DEFAULT 0, PRIMARY KEY (item_type, item_id));`);
// stale main-schema copies from an earlier build of this module (harmless, but keep the DB tidy)
for (const t of ['stock_ctx', 'stock_shadow']) if (safeGet("SELECT 1 one FROM main.sqlite_master WHERE type = 'table' AND name = ?", [t])) exec('DROP TABLE main.' + t);
for (const r of safeAll("SELECT name FROM main.sqlite_master WHERE type = 'trigger' AND name LIKE 'ff_sj_%'")) exec('DROP TRIGGER main.' + r.name);

let HAS_INV = false, HAS_MAT = false, INV_TRAYS = false, TRIGGERS_OK = false, lastCheck = 0;
const F = (name) => (UDF ? "ff_sj_ctx('" + name + "')" : 'c.' + name);
const CTX_COLS = "CASE WHEN COALESCE(" + F('req_id') + ", '') = '' THEN 'EXTERNAL' ELSE COALESCE(" + F('kind') + ", '') END, COALESCE(" + F('ref') + ", ''), COALESCE(" + F('doc2') + ", ''), COALESCE(" + F('party') + ", ''), CASE WHEN COALESCE(" + F('req_id') + ", '') = '' THEN 'Changed by a script / outside the app' ELSE COALESCE(" + F('note') + ", '') END, COALESCE(" + F('link') + ", ''), COALESCE(" + F('req_id') + ", ''), " + F('user_id') + ", COALESCE(" + F('user_name') + ", ''), CASE WHEN COALESCE(" + F('txn_date') + ", '') <> '' THEN " + F('txn_date') + " ELSE date('now', '+330 minutes') END, strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+330 minutes')";
const CTX_FROM = UDF ? '' : 'FROM (SELECT 1 AS one) LEFT JOIN stock_ctx c ON c.id = 1';
const shadowQ = (type, id, col) => 'COALESCE((SELECT ' + col + " FROM stock_shadow WHERE item_type = '" + type + "' AND item_id = " + id + '), 0)';
function journalTriggers(name, table, type, idNew, idOld, qNew, qOld, q2New, q2Old) {
  const ins = (id, delta, delta2, bal, bal2) =>
    'INSERT INTO stock_journal (item_type, item_id, qty, qty2, balance, balance2, kind, ref, doc2, party, note, link, req_id, user_id, user_name, txn_date, created_at) ' +
    "SELECT '" + type + "', " + id + ', ' + delta + ', ' + delta2 + ', ' + bal + ', ' + bal2 + ', ' + CTX_COLS + ' ' + CTX_FROM + ';';
  const shadow = (id, q, q2) => "INSERT OR REPLACE INTO stock_shadow (item_type, item_id, qty, qty2) VALUES ('" + type + "', " + id + ', ' + q + ', ' + q2 + ');';
  return [
    'DROP TRIGGER IF EXISTS ff_sj_' + name + '_u', 'DROP TRIGGER IF EXISTS ff_sj_' + name + '_i', 'DROP TRIGGER IF EXISTS ff_sj_' + name + '_d',
    'CREATE TEMP TRIGGER ff_sj_' + name + '_u AFTER UPDATE ON ' + table + ' WHEN ' + qNew + ' <> ' + qOld + ' OR ' + q2New + ' <> ' + q2Old + ' BEGIN ' +
      ins(idNew, qNew + ' - ' + qOld, q2New + ' - ' + q2Old, qNew, q2New) + ' ' + shadow(idNew, qNew, q2New) + ' END',
    'CREATE TEMP TRIGGER ff_sj_' + name + '_i AFTER INSERT ON ' + table + ' WHEN ' + qNew + ' <> ' + shadowQ(type, idNew, 'qty') + ' OR ' + q2New + ' <> ' + shadowQ(type, idNew, 'qty2') + ' BEGIN ' +
      ins(idNew, qNew + ' - ' + shadowQ(type, idNew, 'qty'), q2New + ' - ' + shadowQ(type, idNew, 'qty2'), qNew, q2New) + ' ' + shadow(idNew, qNew, q2New) + ' END',
    'CREATE TEMP TRIGGER ff_sj_' + name + '_d AFTER DELETE ON ' + table + ' WHEN ' + qOld + ' <> 0 OR ' + q2Old + ' <> 0 BEGIN ' +
      ins(idOld, '0 - ' + qOld, '0 - ' + q2Old, '0', '0') + " DELETE FROM stock_shadow WHERE item_type = '" + type + "' AND item_id = " + idOld + '; END',
  ];
}
/** (Re)create the triggers — at load and again whenever a mutating request finds them missing
 *  (table rebuilt by the core's schema sync, table created after this module loaded …). */
function ensure(force) {
  const now = Date.now();
  if (!force && now - lastCheck < 15000) return TRIGGERS_OK; // at most one sqlite_master check per 15 s
  lastCheck = now;
  const inv = hasTable('inventory'), mat = hasTable('packing_materials');
  const want = (inv ? 3 : 0) + (mat ? 3 : 0);
  const have = safeAll("SELECT name FROM sqlite_temp_master WHERE type = 'trigger' AND name LIKE 'ff_sj_%'").length;
  if (!force && TRIGGERS_OK && have === want && inv === HAS_INV && mat === HAS_MAT) return true;
  HAS_INV = inv; HAS_MAT = mat; INV_TRAYS = inv && hasCol('inventory', 'qty_trays');
  // shadow = last known quantity per item (lets INSERT / INSERT OR REPLACE compute a true delta)
  exec('DELETE FROM stock_shadow');
  if (HAS_INV) exec("INSERT OR IGNORE INTO stock_shadow (item_type, item_id, qty, qty2) SELECT 'product', product_id, COALESCE(qty_cb, 0), " + (INV_TRAYS ? 'COALESCE(qty_trays, 0)' : '0') + ' FROM inventory');
  if (HAS_MAT) exec("INSERT OR IGNORE INTO stock_shadow (item_type, item_id, qty, qty2) SELECT 'material', id, COALESCE(stock, 0), 0 FROM packing_materials");
  const trg = [];
  if (HAS_INV) trg.push(...journalTriggers('inv', 'inventory', 'product', 'NEW.product_id', 'OLD.product_id', 'COALESCE(NEW.qty_cb, 0)', 'COALESCE(OLD.qty_cb, 0)', INV_TRAYS ? 'COALESCE(NEW.qty_trays, 0)' : '0', INV_TRAYS ? 'COALESCE(OLD.qty_trays, 0)' : '0'));
  if (HAS_MAT) trg.push(...journalTriggers('mat', 'packing_materials', 'material', 'NEW.id', 'OLD.id', 'COALESCE(NEW.stock, 0)', 'COALESCE(OLD.stock, 0)', '0', '0'));
  let ok = HAS_INV && HAS_MAT;
  for (const s of trg) if (!exec(s)) { ok = false; console.log('[stock-journal] trigger error: ' + lastErr + ' :: ' + s.slice(0, 80)); }
  if (!HAS_INV || !HAS_MAT) console.log('[stock-journal] waiting for tables: inventory=' + HAS_INV + ' packing_materials=' + HAS_MAT);
  TRIGGERS_OK = ok;
  return ok;
}
ensure(true);

// ---------- request context ----------
const apiPath = (req) => { const u = String(req.originalUrl || req.url || '').split('?')[0]; const i = u.indexOf('/api/'); return i === -1 ? u : u.slice(i); };
function classify(req) {
  const m = req.method, p = apiPath(req), b = (req.body && typeof req.body === 'object') ? req.body : {};
  const c = { kind: 'OTHER', ref: '', doc2: '', party: '', note: m + ' ' + p, link: '', txn_date: '' };
  let x;
  if (m === 'POST' && p === '/api/inventory/receipt') Object.assign(c, { kind: 'RECEIPT', ref: str(b.reference || b.refNo || b.billNo, 60), party: str(b.party || b.supplier, 120), note: str(b.note, 200), link: '/inventory', txn_date: isYmd(b.date) ? b.date : '' });
  else if (m === 'PUT' && p === '/api/inventory/stock') Object.assign(c, { kind: 'SET_STOCK', ref: str(b.reference || b.refNo, 60), note: str(b.note, 200) || 'Exact stock typed (physical count)', link: '/inventory' });
  else if (m === 'POST' && p === '/api/adjustments') Object.assign(c, { kind: 'ADJUSTMENT', doc2: str(b.adjType, 20), note: str(b.reason, 200), link: '/adjustments' });
  else if (m === 'POST' && (x = p.match(/^\/api\/adjustments\/(\d+)\/(approve|reject)$/))) {
    const a = safeGet('SELECT code, reason, adj_type FROM adjustments WHERE id = ?', [Number(x[1])]) || safeGet('SELECT code, reason, adj_type FROM stock_adjustments WHERE id = ?', [Number(x[1])]) || {};
    Object.assign(c, { kind: 'ADJUSTMENT', ref: str(a.code, 60), doc2: str(a.adj_type, 20), note: (x[2] === 'reject' ? 'Rejected · ' : 'Approved · ') + str(a.reason, 180), link: '/adjustments' });
  } else if (m === 'POST' && (x = p.match(/^\/api\/production\/batches\/(\d+)\/complete$/))) {
    const bt = safeGet('SELECT code FROM batches WHERE id = ?', [Number(x[1])]) || {};
    Object.assign(c, { kind: 'PRODUCTION', ref: str(bt.code, 60), note: b.consumePacking === false ? '' : 'BOM consumption', link: '/production/batches/' + x[1] });
  } else if ((m === 'PUT' || m === 'PATCH' || m === 'DELETE' || m === 'POST') && (x = p.match(/^\/api\/production\/batches\/(\d+)(?:\/([a-z-]+))?$/))) {
    const bt = safeGet('SELECT code FROM batches WHERE id = ?', [Number(x[1])]) || {};
    Object.assign(c, { kind: m === 'DELETE' ? 'REVERSAL' : 'PRODUCTION', ref: str(bt.code, 60), note: m === 'DELETE' ? 'Production batch deleted' : 'Batch ' + (x[2] || 'edited'), link: '/production/batches/' + x[1] });
  } else if (m === 'POST' && p === '/api/dispatch') Object.assign(c, { kind: 'DISPATCH', party: str(b.destination, 120), note: str(b.truckNumber || b.truck_number, 60), link: '/dispatch', txn_date: isYmd(b.dispatchDate) ? b.dispatchDate : '' });
  else if ((x = p.match(/^\/api\/dispatch\/(\d+)(?:\/([a-z-]+))?$/))) {
    const d = safeGet('SELECT code, destination, truck_number FROM dispatches WHERE id = ?', [Number(x[1])]) || {};
    const voided = x[2] === 'void' || x[2] === 'cancel' || m === 'DELETE';
    Object.assign(c, { kind: voided ? 'DISPATCH_VOID' : 'DISPATCH', ref: str(d.code, 60), party: str(d.destination, 120), note: (voided ? 'Dispatch voided — stock returned' : 'Dispatch ' + (x[2] || 'edited')) + (d.truck_number ? ' · ' + d.truck_number : ''), link: '/dispatch/' + x[1] });
  } else if (m === 'POST' && p === '/api/packing/receive') Object.assign(c, { kind: 'RECEIVED', ref: str(b.reference, 60), party: str(b.party || b.supplier, 120), note: str(b.remark, 200), link: '/packing' });
  else if (m === 'POST' && (p === '/api/packing/consume' || p === '/api/packing/issue')) {
    const pr = b.productId ? safeGet('SELECT name FROM products WHERE id = ?', [Number(b.productId)]) : null;
    Object.assign(c, { kind: 'CONSUMED', ref: str(b.reference, 60), party: pr ? str(pr.name, 120) : '', note: str(b.remark, 200), link: '/packing' });
  } else if (m === 'POST' && p === '/api/packing/recipe-consume') {
    const r = b.recipeId ? safeGet('SELECT name FROM recipes WHERE id = ?', [Number(b.recipeId)]) : null;
    Object.assign(c, { kind: 'RECIPE', ref: r ? str(r.name, 60) : '', note: [b.totalQty ? 'qty ' + b.totalQty : '', str(b.remark, 150)].filter(Boolean).join(' · '), link: '/raw' });
  } else if ((m === 'PUT' || m === 'PATCH') && /^\/api\/packing\/materials\/\d+$/.test(p)) Object.assign(c, { kind: 'SET_STOCK', note: 'Material edited — stock typed', link: '/packing' });
  else if (m === 'POST' && p === '/api/packing/materials') Object.assign(c, { kind: 'OPENING', note: 'New material — opening stock', link: '/packing' });
  else if (m === 'POST' && p === '/api/products') Object.assign(c, { kind: 'OPENING', note: 'New product — opening stock', link: '/products' });
  else if ((m === 'PUT' || m === 'PATCH') && /^\/api\/products\/\d+$/.test(p)) Object.assign(c, { kind: 'SET_STOCK', note: 'Product edited — stock typed', link: '/products' });
  else if (m === 'DELETE' && (/^\/api\/products\/\d+$/.test(p) || /^\/api\/packing\/materials\/\d+$/.test(p))) Object.assign(c, { kind: 'DELETED', note: 'Item deleted from master' });
  else if (p.startsWith('/api/billing/')) Object.assign(c, { kind: 'BILLING', note: '' });
  return c;
}
function writeCtx(s, c, user) {
  s.row = { req_id: s.id, kind: str(c.kind, 24), ref: str(c.ref, 60), doc2: str(c.doc2, 60), party: str(c.party, 120), note: str(c.note, 200), link: str(c.link, 80),
    user_id: user && user.id ? Number(user.id) : null, user_name: user ? str(user.name || user.email, 80) : '', txn_date: isYmd(c.txn_date) ? c.txn_date : '' };
  current = s;
  if (UDF) return;
  try {
    const r = s.row;
    db.prepare('UPDATE stock_ctx SET req_id = ?, kind = ?, ref = ?, doc2 = ?, party = ?, note = ?, link = ?, user_id = ?, user_name = ?, txn_date = ?, set_at = ? WHERE id = 1')
      .run(r.req_id, r.kind, r.ref, r.doc2, r.party, r.note, r.link, r.user_id, r.user_name, r.txn_date, nowIso());
  } catch (_) {}
}
function clearCtx(s) {
  if (current === s) current = null;
  if (UDF) return;
  try { db.prepare("UPDATE stock_ctx SET req_id = '', kind = '', ref = '', doc2 = '', party = '', note = '', link = '', user_id = NULL, user_name = '', txn_date = '' WHERE id = 1 AND req_id = ?").run(s.id); } catch (_) {}
}
const refresh = (req) => { const s = req._ffSj; if (!s || s.done || s.marked) return; s.ctx = classify(req); writeCtx(s, s.ctx, req.user); };
/** Watch a property that a later middleware assigns (req.body by the JSON parser, req.user by auth) and re-write the context when it lands. */
function watch(req, prop) {
  if (Object.prototype.hasOwnProperty.call(req, prop)) return; // already there → classify() saw it
  let v;
  try {
    Object.defineProperty(req, prop, { configurable: true, enumerable: true, get() { return v; }, set(nv) { v = nv; try { refresh(req); } catch (_) {} } });
  } catch (_) {}
}
/** app.use(middleware) — must be registered BEFORE the routers. Safe for GET (no-op). */
let READY = false;
function middleware(req, res, next) {
  try {
    if (req && req.method && req.method !== 'GET' && req.method !== 'HEAD' && req.method !== 'OPTIONS') {
      ensure(false);
      if (!READY) { try { READY = ready() || !/^skipped/.test(String(backfill())); } catch (_) {} }
    }
    if (req && req._ffSj) refresh(req); // mounted twice (early + before the routers) → just re-assert the context
    else if (req && res && req.method && req.method !== 'GET' && req.method !== 'HEAD' && req.method !== 'OPTIONS') {
      const s = req._ffSj = { id: Date.now().toString(36) + '-' + (++seq).toString(36), out: null, done: false, marked: false, ctx: null };
      const oj = res.json;
      if (typeof oj === 'function') res.json = function (body) { try { s.out = body; } catch (_) {} return oj.apply(this, arguments); };
      if (typeof res.on === 'function') { res.on('finish', () => { try { end(req); } catch (_) {} }); res.on('close', () => { try { end(req); } catch (_) {} }); }
      s.ctx = classify(req);
      writeCtx(s, s.ctx, req.user);
      watch(req, 'body'); watch(req, 'user');
      if (UDF) return als.run(s, next); // everything downstream (async auth, body parse, handler) sees this request's context
    }
  } catch (_) {}
  next();
}
/** Precise context from inside a handler (billing: bill no, invoice no, party, business date). Sticky for the rest of the request. */
function mark(req, fields) {
  if (!req) return;
  let s = req._ffSj;
  if (!s) { middleware(req, req.res || {}, () => {}); s = req._ffSj; if (!s) return; }
  s.marked = true;
  s.ctx = Object.assign({}, s.ctx || {}, fields || {});
  writeCtx(s, s.ctx, req.user);
}
function end(req) {
  const s = req && req._ffSj; if (!s || s.done) return; s.done = true;
  try {
    if (safeGet('SELECT 1 one FROM stock_journal WHERE req_id = ? LIMIT 1', [s.id])) {
      const o = s.out && typeof s.out === 'object' ? s.out : {};
      const code = str(o.code || (o.dispatch && o.dispatch.code) || (o.batch && o.batch.code) || (o.adjustment && o.adjustment.code) || o.number, 60);
      const id = o.id || (o.dispatch && o.dispatch.id) || (o.batch && o.batch.id) || 0;
      const k = s.ctx ? s.ctx.kind : '';
      let ref = code, link = '', did = id;
      if (k === 'DISPATCH' && !ref) { const d = safeGet('SELECT id, code FROM dispatches ORDER BY id DESC LIMIT 1'); if (d) { ref = str(d.code, 60); did = d.id; } } // response without the code → newest dispatch (created by this very request)
      if (k === 'DISPATCH' && did) link = '/dispatch/' + did;
      if (k === 'PRODUCTION' && id) link = '/production/batches/' + id;
      if (!ref && req.body && typeof req.body === 'object') ref = str(req.body.reference || req.body.refNo || req.body.billNo, 60);
      if (ref || link) db.prepare("UPDATE stock_journal SET ref = CASE WHEN ref = '' THEN ? ELSE ref END, link = CASE WHEN ? <> '' THEN ? ELSE link END WHERE req_id = ?").run(ref, link, link, s.id);
    }
  } catch (_) {}
  clearCtx(s);
}

// ---------- one-time backfill from the tables that existed before the journal ----------
function backfill() {
  if (safeGet("SELECT 1 one FROM app_settings WHERE key = 'stock_journal'")) { READY = true; return 'already'; }
  ensure(true);
  if (!hasTable('products') || !hasTable('inventory') || !hasTable('packing_materials')) return 'skipped (core tables not created yet)';
  const HAS_INVOICES = hasTable('invoices');
  const out = []; // per item chronological rows
  const push = (rows, r) => rows.push(Object.assign({ qty2: 0, doc2: '', party: '', note: '', by: '', link: '', at: '' }, r));
  const prods = safeAll('SELECT p.id, COALESCE(i.qty_cb, 0) stock, ' + (INV_TRAYS ? 'COALESCE(i.qty_trays, 0)' : '0') + ' stock2 FROM products p LEFT JOIN inventory i ON i.product_id = p.id');
  for (const p of prods) {
    const rows = [];
    for (const r of safeAll("SELECT pi.qty, pi.batch_code, pu.id pid, pu.entry_no, pu.bill_no, COALESCE(NULLIF(pu.received_date, ''), pu.bill_date) d, pu.party_name, pu.created_by_name, pu.created_at FROM purchase_items pi JOIN purchases pu ON pu.id = pi.purchase_id WHERE pi.item_type = 'product' AND pi.item_id = ? AND pu.status != 'CANCELLED' AND pu.stock_added = 1", [p.id]))
      push(rows, { date: r.d, at: r.created_at || '', kind: 'PURCHASE', qty: num(r.qty), ref: r.bill_no, doc2: r.entry_no, party: r.party_name, note: r.batch_code || '', by: r.created_by_name || '', link: '/billing/purchases/' + r.pid });
    for (const r of safeAll("SELECT id bid, code, produced_cb, completed_at, planned_date FROM batches WHERE product_id = ? AND UPPER(status) = 'COMPLETED' AND COALESCE(produced_cb, 0) > 0", [p.id]))
      push(rows, { date: String(r.completed_at || r.planned_date || '').slice(0, 10), at: r.completed_at || '', kind: 'PRODUCTION', qty: num(r.produced_cb), ref: r.code || '', link: '/production/batches/' + r.bid });
    for (const r of safeAll("SELECT di.cartons, di.batch_code, d.id did, d.code, d.dispatch_date, d.destination, d.truck_number, d.created_at, " + (HAS_INVOICES ? "(SELECT number FROM invoices i WHERE i.dispatch_id = d.id AND i.status != 'CANCELLED' LIMIT 1)" : "''") + " inv FROM dispatch_items di JOIN dispatches d ON d.id = di.dispatch_id WHERE di.product_id = ? AND UPPER(COALESCE(d.status, '')) != 'VOID'", [p.id]))
      push(rows, { date: r.dispatch_date, at: r.created_at || '', kind: 'DISPATCH', qty: -num(r.cartons), ref: r.code || '', doc2: r.inv || '', party: r.destination || '', note: [r.truck_number, r.batch_code].filter(Boolean).join(' · '), link: '/dispatch/' + r.did });
    for (const r of safeAll("SELECT ii.qty, ii.batch_code, i.id iid, i.number, i.invoice_date, i.party_name, i.created_by_name, i.created_at FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id WHERE ii.product_id = ? AND i.status != 'CANCELLED' AND i.stock_deducted = 1", [p.id]))
      push(rows, { date: r.invoice_date, at: r.created_at || '', kind: 'SALE', qty: -num(r.qty), ref: r.number, party: r.party_name, note: r.batch_code || '', by: r.created_by_name || '', link: '/billing/' + r.iid });
    out.push({ type: 'product', id: p.id, stock: num(p.stock), stock2: num(p.stock2), rows });
  }
  const purByTxn = {};
  for (const r of safeAll("SELECT pi.txn_id, pi.item_id, pu.id pid, pu.bill_no, pu.entry_no, pu.party_name FROM purchase_items pi JOIN purchases pu ON pu.id = pi.purchase_id WHERE pi.item_type = 'material' AND pi.txn_id IS NOT NULL")) purByTxn[r.txn_id] = r;
  for (const m of safeAll('SELECT id, COALESCE(stock, 0) stock FROM packing_materials')) {
    const rows = [];
    let txns = safeAll('SELECT t.id, t.txn_type, t.qty, t.txn_date, t.reference, t.remark, t.created_at, u.name by_name FROM packing_txns t LEFT JOIN users u ON u.id = t.created_by WHERE t.material_id = ?', [m.id]);
    if (!txns.length) txns = safeAll('SELECT t.id, t.txn_type, t.qty, t.txn_date, t.reference, t.remark, t.created_at FROM packing_txns t WHERE t.material_id = ?', [m.id]);
    for (const r of txns) {
      const pu = purByTxn[r.id], isIn = String(r.txn_type).toUpperCase() === 'RECEIVED';
      push(rows, { date: String(r.txn_date || '').slice(0, 10), at: r.created_at || '', kind: pu ? 'PURCHASE' : (isIn ? 'RECEIVED' : 'CONSUMED'), qty: isIn ? num(r.qty) : -num(r.qty),
        ref: pu ? pu.bill_no : (r.reference || ''), doc2: pu ? pu.entry_no : '', party: pu ? pu.party_name : '', note: r.remark || '', by: r.by_name || '', link: pu ? '/billing/purchases/' + pu.pid : '' });
    }
    out.push({ type: 'material', id: m.id, stock: num(m.stock), stock2: 0, rows });
  }
  const today = todayIst();
  const ins = db.prepare('INSERT INTO stock_journal (item_type, item_id, qty, qty2, balance, balance2, kind, ref, doc2, party, note, link, req_id, user_id, user_name, txn_date, created_at, backfilled) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,\'\',NULL,?,?,?,1)');
  let n = 0;
  runTx(() => {
    for (const it of out) {
      const rows = it.rows.sort((a, b) => (a.date + '|' + a.at).localeCompare(b.date + '|' + b.at));
      const sum = rows.reduce((s, r) => s + r.qty, 0);
      const opening = r2(it.stock - sum);
      if (Math.abs(opening) > 0.0005 || (it.stock2 && !rows.length)) rows.unshift({ date: rows.length ? rows[0].date : today, at: '', kind: 'OPENING', qty: opening, qty2: it.stock2, ref: '', doc2: '', party: '', note: 'Opening stock / manual entries before the journal started (balancing figure)', by: '', link: '' });
      else if (it.stock2 && rows.length) rows[0].qty2 = it.stock2; // trays were not journaled before — carry them on the first row
      let bal = 0, bal2 = 0;
      for (const r of rows) {
        bal = r2(bal + r.qty); bal2 = r2(bal2 + (r.qty2 || 0));
        ins.run(it.type, it.id, r.qty, r.qty2 || 0, bal, bal2, r.kind, str(r.ref, 60), str(r.doc2, 60), str(r.party, 120), str(r.note, 200), str(r.link, 80), str(r.by, 80), r.date || today, r.at || nowIso());
        n++;
      }
    }
    db.prepare("INSERT INTO app_settings (key, value) VALUES ('stock_journal', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value").run(JSON.stringify({ backfilled: nowIso(), rows: n, triggers: TRIGGERS_OK, mode: UDF ? 'als-udf' : 'ctx-table' }));
  });
  READY = true;
  return n + ' rows';
}
/** Safety net: if actual stock ever differs from the last journal balance (write from a process without the
 *  triggers, restored DB …) post a SYNC row so every running balance still ends at today's stock. */
function reconcile() {
  let n = 0;
  try {
    const rows = safeAll("SELECT 'product' t, p.id, COALESCE(i.qty_cb, 0) q, " + (INV_TRAYS ? 'COALESCE(i.qty_trays, 0)' : '0') + " q2, (SELECT balance FROM stock_journal j WHERE j.item_type = 'product' AND j.item_id = p.id ORDER BY j.id DESC LIMIT 1) b, (SELECT balance2 FROM stock_journal j WHERE j.item_type = 'product' AND j.item_id = p.id ORDER BY j.id DESC LIMIT 1) b2 FROM products p LEFT JOIN inventory i ON i.product_id = p.id")
      .concat(safeAll("SELECT 'material' t, m.id, COALESCE(m.stock, 0) q, 0 q2, (SELECT balance FROM stock_journal j WHERE j.item_type = 'material' AND j.item_id = m.id ORDER BY j.id DESC LIMIT 1) b, 0 b2 FROM packing_materials m"));
    const ins = db.prepare("INSERT INTO stock_journal (item_type, item_id, qty, qty2, balance, balance2, kind, ref, doc2, party, note, link, req_id, user_id, user_name, txn_date, created_at) VALUES (?,?,?,?,?,?,'SYNC','','','','Stock changed outside the app (script / direct DB edit) — balance synced','','',NULL,'',?,?)");
    const upd = db.prepare('INSERT OR REPLACE INTO stock_shadow (item_type, item_id, qty, qty2) VALUES (?,?,?,?)');
    for (const r of rows) {
      const d = r2(num(r.q) - num(r.b)), d2 = r2(num(r.q2) - num(r.b2));
      if (Math.abs(d) < 0.0005 && Math.abs(d2) < 0.0005) continue;
      if (r.b == null && Math.abs(num(r.q)) < 0.0005 && Math.abs(num(r.q2)) < 0.0005) continue; // never stocked
      ins.run(r.t, r.id, d, d2, r2(num(r.q)), r2(num(r.q2)), todayIst(), nowIso());
      upd.run(r.t, r.id, num(r.q), num(r.q2));
      n++;
    }
  } catch (_) {}
  return n;
}
const ready = () => !!safeGet("SELECT 1 one FROM app_settings WHERE key = 'stock_journal'");

module.exports = { middleware, mark, end, backfill, reconcile, ready, ensure, classify, triggersOk: () => TRIGGERS_OK, mode: () => (UDF ? 'als-udf' : 'ctx-table') };
JSFILE
node --check "$DIR/stockctx.js" || { echo "STOCKCTX SYNTAX FAIL"; exit 1; }
echo "CORE: stockctx.js ✓ (triggers + request context + backfill)"

# ---------- 2) routes/stock.js ----------
cat > "$DIR/routes/stock.js" <<'JSFILE'
/** FlavorFlow — STOCK LEDGER routes (SAP MB51 / MMBE style) over stock_journal. (ff-stockledger) */
const express = require('express');
const router = express.Router();
const db = require('../db');
const SJ = require('../stockctx');
const MW = (() => { try { return require('../middleware'); } catch (_) { return {}; } })();
const authRequired = typeof MW.authRequired === 'function' ? MW.authRequired : (req, res, next) => next();
const perm = (p) => (typeof MW.requirePerm === 'function' ? MW.requirePerm(p) : (req, res, next) => next());
const PERM_VIEW = '__PV__';

const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const str = (v, n) => String(v == null ? '' : v).trim().slice(0, n || 200);
const isYmd = (s) => /^\d{4}-\d{2}-\d{2}$/.test(String(s || ''));
const bad = (res, msg, code) => res.status(code || 400).json({ error: msg });
const todayIst = () => new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10);
const safeAll = (sql, a) => { try { return db.prepare(sql).all(...(a || [])); } catch (_) { return []; } };
const safeGet = (sql, a) => { try { return db.prepare(sql).get(...(a || [])); } catch (_) { return null; } };
const hasCol = (t, c) => safeAll('PRAGMA table_info(' + t + ')').some((r) => r.name === c);
const P_CODE = hasCol('products', 'item_code') ? 'item_code' : hasCol('products', 'code') ? 'code' : hasCol('products', 'sku') ? 'sku' : null;
const M_CODE = hasCol('packing_materials', 'item_code') ? 'item_code' : hasCol('packing_materials', 'code') ? 'code' : null;
const P_ACTIVE = hasCol('products', 'active');
const KINDS = ['PURCHASE', 'PURCHASE_CANCEL', 'RECEIPT', 'RECEIVED', 'OPENING', 'PRODUCTION', 'CONSUMED', 'RECIPE', 'DISPATCH', 'DISPATCH_VOID', 'SALE', 'SALE_CANCEL', 'ADJUSTMENT', 'SET_STOCK', 'REVERSAL', 'DELETED', 'BILLING', 'OTHER'];
const IN_KINDS = { PURCHASE: 1, RECEIPT: 1, RECEIVED: 1, OPENING: 1, PRODUCTION: 1, DISPATCH_VOID: 1, SALE_CANCEL: 1 };
const OUT_KINDS = { DISPATCH: 1, SALE: 1, CONSUMED: 1, RECIPE: 1, PURCHASE_CANCEL: 1 };

function range(req) {
  const t = todayIst();
  const to = isYmd(req.query.to) ? String(req.query.to) : t;
  const from = isYmd(req.query.from) ? String(req.query.from) : (to.slice(0, 8) + '01');
  return { from, to };
}
function itemMaster() {
  const map = {};
  for (const p of safeAll('SELECT id, name' + (P_CODE ? ', ' + P_CODE + ' code' : '') + (P_ACTIVE ? ', active' : '') + ', COALESCE((SELECT qty_cb FROM inventory i WHERE i.product_id = products.id), 0) stock FROM products'))
    map['product:' + p.id] = { type: 'product', id: p.id, name: p.name, code: p.code || '', unit: 'pack', category: 'Finished goods', stock: num(p.stock), active: P_ACTIVE ? p.active !== 0 : true };
  for (const m of safeAll('SELECT id, name, unit, category, COALESCE(stock, 0) stock' + (M_CODE ? ', ' + M_CODE + ' code' : '') + ' FROM packing_materials'))
    map['material:' + m.id] = { type: 'material', id: m.id, name: m.name, code: m.code || '', unit: m.unit || '', category: m.category || 'Material', stock: num(m.stock), active: true };
  return map;
}
const dirOf = (r) => (num(r.qty) > 0 || (num(r.qty) === 0 && num(r.qty2) > 0) ? 'in' : 'out');
function shape(r, master) {
  const it = master ? master[r.item_type + ':' + r.item_id] : null;
  return {
    id: r.id, type: r.item_type, itemId: r.item_id, item: it ? it.name : (r.item_type + ' #' + r.item_id), code: it ? it.code : '', unit: it ? it.unit : '', category: it ? it.category : '',
    date: r.txn_date, at: r.created_at, kind: r.kind || 'OTHER', dir: dirOf(r), qty: Math.abs(num(r.qty)), signed: r2(num(r.qty)), qty2: r2(num(r.qty2)), balance: r2(num(r.balance)), balance2: r2(num(r.balance2)),
    ref: r.ref || '', doc2: r.doc2 || '', party: r.party || '', note: r.note || '', by: r.user_name || '', link: r.link || '', backfilled: !!r.backfilled,
  };
}
function where(req, opts) {
  const w = [], a = [];
  const q = req.query;
  if (opts && opts.item) { w.push('j.item_type = ? AND j.item_id = ?'); a.push(opts.item.type, opts.item.id); }
  if (opts && opts.range) { w.push('j.txn_date >= ? AND j.txn_date <= ?'); a.push(opts.range.from, opts.range.to); }
  if (q.kind && KINDS.includes(String(q.kind).toUpperCase())) { w.push('j.kind = ?'); a.push(String(q.kind).toUpperCase()); }
  if (q.dir === 'in') w.push('(j.qty > 0 OR (j.qty = 0 AND j.qty2 > 0))');
  if (q.dir === 'out') w.push('(j.qty < 0 OR (j.qty = 0 AND j.qty2 < 0))');
  if (q.type === 'product' || q.type === 'material') { w.push('j.item_type = ?'); a.push(q.type); }
  if (q.q) { const s = '%' + str(q.q, 60) + '%'; w.push('(j.ref LIKE ? OR j.doc2 LIKE ? OR j.party LIKE ? OR j.note LIKE ? OR j.user_name LIKE ?)'); a.push(s, s, s, s, s); }
  return { sql: w.length ? ' WHERE ' + w.join(' AND ') : '', args: a };
}

router.use(authRequired);

router.get('/status', perm(PERM_VIEW), (req, res) => {
  const meta = safeGet("SELECT value FROM app_settings WHERE key = 'stock_journal'");
  const n = safeGet('SELECT COUNT(*) n, MIN(txn_date) first, MAX(txn_date) last FROM stock_journal') || {};
  res.json({ ok: true, ready: SJ.ready(), triggers: SJ.triggersOk(), mode: typeof SJ.mode === 'function' ? SJ.mode() : '', rows: num(n.n), first: n.first || '', last: n.last || '', meta: meta ? JSON.parse(meta.value) : null, kinds: KINDS });
});

/** Per-item ledger (SAP MB51 for one material): every movement, oldest→newest balance, returned newest first. */
router.get('/ledger', perm(PERM_VIEW), (req, res) => {
  const type = req.query.type === 'material' ? 'material' : 'product';
  const id = Number(req.query.id) || 0;
  if (!id) return bad(res, 'id is required.');
  const master = itemMaster();
  const it = master[type + ':' + id];
  if (!it) return bad(res, (type === 'product' ? 'Product' : 'Material') + ' not found.', 404);
  const hasRange = isYmd(req.query.from) || isYmd(req.query.to);
  const rg = hasRange ? range(req) : null;
  const w = where(req, { item: { type, id }, range: rg });
  const rows = safeAll('SELECT j.* FROM stock_journal j' + w.sql + ' ORDER BY j.txn_date, j.id', w.args).map((r) => shape(r, master));
  let opening = 0, opening2 = 0;
  if (rg) { const o = safeGet('SELECT COALESCE(SUM(qty), 0) s, COALESCE(SUM(qty2), 0) s2 FROM stock_journal WHERE item_type = ? AND item_id = ? AND txn_date < ?', [type, id, rg.from]); opening = r2(o ? o.s : 0); opening2 = r2(o ? o.s2 : 0); }
  let totalIn = 0, totalOut = 0;
  for (const r of rows) { if (r.dir === 'in') totalIn += r.qty; else totalOut += r.qty; }
  const closing = rows.length ? rows[rows.length - 1].balance : opening;
  const ledgerStock = safeGet('SELECT balance, balance2 FROM stock_journal WHERE item_type = ? AND item_id = ? ORDER BY id DESC LIMIT 1', [type, id]);
  const drift = ledgerStock ? r2(it.stock - num(ledgerStock.balance)) : r2(it.stock);
  rows.reverse();
  res.json({ type, id, name: it.name, code: it.code, unit: it.unit, category: it.category, stock: r2(it.stock), from: rg ? rg.from : '', to: rg ? rg.to : '',
    opening, opening2, totalIn: r2(totalIn), totalOut: r2(totalOut), closing: r2(closing), drift, rows: rows.slice(0, 3000) });
});

/** All-items movement register for a period (SAP MB51 list) — newest first. */
function registerRows(req) {
  const rg = range(req), master = itemMaster();
  const w = where(req, { range: rg });
  const rows = safeAll('SELECT j.* FROM stock_journal j' + w.sql + ' ORDER BY j.txn_date DESC, j.id DESC LIMIT 5000', w.args).map((r) => shape(r, master));
  return { rg, rows };
}
router.get('/register', perm(PERM_VIEW), (req, res) => {
  const { rg, rows } = registerRows(req);
  let inQ = 0, outQ = 0; const kinds = {};
  for (const r of rows) { if (r.dir === 'in') inQ += r.qty; else outQ += r.qty; kinds[r.kind] = (kinds[r.kind] || 0) + 1; }
  res.json({ from: rg.from, to: rg.to, count: rows.length, totalIn: r2(inQ), totalOut: r2(outQ), kinds, rows });
});
const esc = (v) => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"';
router.get('/register.csv', perm(PERM_VIEW), (req, res) => {
  const { rg, rows } = registerRows(req);
  const head = ['Date', 'Item', 'Code', 'Type', 'Movement', 'In/Out', 'Qty', 'Unit', 'Balance', 'Doc / Bill No', 'Entry No', 'Party', 'Note', 'By', 'Recorded at'];
  const lines = [head.join(',')];
  for (const r of rows) lines.push([r.date, r.item, r.code, r.type, r.kind, r.dir.toUpperCase(), r.signed, r.unit, r.balance, r.ref, r.doc2, r.party, r.note, r.by, r.at].map(esc).join(','));
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', 'attachment; filename="stock-register-' + rg.from + '-to-' + rg.to + '.csv"');
  res.send('\ufeff' + lines.join('\r\n'));
});
router.get('/ledger.csv', perm(PERM_VIEW), (req, res) => {
  const type = req.query.type === 'material' ? 'material' : 'product';
  const id = Number(req.query.id) || 0;
  const master = itemMaster(), it = master[type + ':' + id];
  if (!it) return bad(res, 'Item not found.', 404);
  const rows = safeAll('SELECT j.* FROM stock_journal j WHERE j.item_type = ? AND j.item_id = ? ORDER BY j.txn_date, j.id', [type, id]).map((r) => shape(r, master));
  const head = ['Date', 'Movement', 'In/Out', 'Qty', 'Unit', 'Balance', 'Doc / Bill No', 'Entry No', 'Party', 'Note', 'By', 'Recorded at'];
  const lines = [esc(it.name + (it.code ? ' [' + it.code + ']' : '')), head.join(',')];
  for (const r of rows) lines.push([r.date, r.kind, r.dir.toUpperCase(), r.signed, r.unit, r.balance, r.ref, r.doc2, r.party, r.note, r.by, r.at].map(esc).join(','));
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', 'attachment; filename="stock-ledger-' + type + '-' + id + '.csv"');
  res.send('\ufeff' + lines.join('\r\n'));
});

/** Period balances per item (SAP MB5B): opening, in, out, closing, current stock. */
function balanceRows(req) {
  const rg = range(req), master = itemMaster();
  const typeF = req.query.type === 'product' || req.query.type === 'material' ? String(req.query.type) : '';
  const agg = {};
  for (const r of safeAll('SELECT item_type, item_id, COALESCE(SUM(CASE WHEN txn_date < ? THEN qty ELSE 0 END), 0) opening, COALESCE(SUM(CASE WHEN txn_date >= ? AND txn_date <= ? AND qty > 0 THEN qty ELSE 0 END), 0) qin, COALESCE(SUM(CASE WHEN txn_date >= ? AND txn_date <= ? AND qty < 0 THEN -qty ELSE 0 END), 0) qout, COALESCE(SUM(CASE WHEN txn_date <= ? THEN qty ELSE 0 END), 0) closing, SUM(CASE WHEN txn_date >= ? AND txn_date <= ? THEN 1 ELSE 0 END) moves, MAX(CASE WHEN txn_date >= ? AND txn_date <= ? THEN txn_date END) last FROM stock_journal GROUP BY item_type, item_id', [rg.from, rg.from, rg.to, rg.from, rg.to, rg.to, rg.from, rg.to, rg.from, rg.to]))
    agg[r.item_type + ':' + r.item_id] = r;
  const q = str(req.query.q, 60).toLowerCase();
  const rows = [];
  for (const k of Object.keys(master)) {
    const it = master[k]; if (typeF && it.type !== typeF) continue;
    if (q && !(it.name.toLowerCase().includes(q) || it.code.toLowerCase().includes(q) || it.category.toLowerCase().includes(q))) continue;
    const a = agg[k] || { opening: 0, qin: 0, qout: 0, closing: 0, moves: 0, last: '' };
    if (!it.active && !num(a.moves) && !num(a.closing)) continue;
    if (req.query.moved === '1' && !num(a.moves)) continue;
    rows.push({ type: it.type, itemId: it.id, item: it.name, code: it.code, unit: it.unit, category: it.category, opening: r2(a.opening), qin: r2(a.qin), qout: r2(a.qout), closing: r2(a.closing), stock: r2(it.stock), moves: num(a.moves), last: a.last || '' });
  }
  rows.sort((x, y) => (x.type === y.type ? x.item.localeCompare(y.item) : (x.type === 'product' ? -1 : 1)));
  return { rg, rows };
}
router.get('/balances', perm(PERM_VIEW), (req, res) => {
  const { rg, rows } = balanceRows(req);
  const t = rows.reduce((s, r) => { s.qin += r.qin; s.qout += r.qout; s.moves += r.moves; return s; }, { qin: 0, qout: 0, moves: 0 });
  res.json({ from: rg.from, to: rg.to, count: rows.length, totalIn: r2(t.qin), totalOut: r2(t.qout), moves: t.moves, rows });
});
router.get('/balances.csv', perm(PERM_VIEW), (req, res) => {
  const { rg, rows } = balanceRows(req);
  const head = ['Item', 'Code', 'Type', 'Category', 'Unit', 'Opening', 'In', 'Out', 'Closing', 'Stock now', 'Movements', 'Last movement'];
  const lines = [head.join(',')];
  for (const r of rows) lines.push([r.item, r.code, r.type, r.category, r.unit, r.opening, r.qin, r.qout, r.closing, r.stock, r.moves, r.last].map(esc).join(','));
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', 'attachment; filename="stock-balances-' + rg.from + '-to-' + rg.to + '.csv"');
  res.send('\ufeff' + lines.join('\r\n'));
});

/** Documents list: distinct doc numbers in a period (quick lookup by bill / dispatch / batch no). */
router.get('/documents', perm(PERM_VIEW), (req, res) => {
  const rg = range(req);
  const rows = safeAll("SELECT kind, ref, doc2, party, link, MIN(txn_date) date, COUNT(*) lines, SUM(CASE WHEN qty > 0 THEN qty ELSE 0 END) qin, SUM(CASE WHEN qty < 0 THEN -qty ELSE 0 END) qout FROM stock_journal WHERE txn_date >= ? AND txn_date <= ? AND ref <> '' GROUP BY kind, ref, doc2, party, link ORDER BY date DESC LIMIT 2000", [rg.from, rg.to]);
  res.json({ from: rg.from, to: rg.to, rows: rows.map((r) => ({ kind: r.kind, ref: r.ref, doc2: r.doc2, party: r.party, link: r.link, date: r.date, lines: r.lines, qin: r2(r.qin), qout: r2(r.qout) })) });
});

module.exports = router;
JSFILE
sed -i "s/__PV__/$PV/" "$DIR/routes/stock.js"
node --check "$DIR/routes/stock.js" || { echo "ROUTE SYNTAX FAIL"; exit 1; }
echo "ROUTES: routes/stock.js ✓ (guard: $PV)"

# ---------- 3) server.js: middleware first + early mount + backfill ----------
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = process.env.FF_DIR + '/server.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('/* ffStockLedger */')) { console.log('SERVER: stock ledger already mounted ✓'); process.exit(0); }
const LINE = "/* ffStockLedger */ try { const _sj = require('./stockctx'); app.use(_sj.middleware); app.use('/api/stock', require('./routes/stock')); setTimeout(() => { try { console.log('[ff-stockledger] backfill: ' + _sj.backfill() + ', reconcile: ' + _sj.reconcile()); } catch (e) { console.log('[ff-stockledger] backfill error: ' + e.message); } }, 1500); console.log('[ff-stockledger] /api/stock mounted'); } catch (e) { console.log('[ff-stockledger] mount error: ' + e.message); }\n";
// The middleware must run before ANY router that changes stock → put it before the first app.use('/api…')
// (ff-billing / ff-industry early mounts included) so it is the first /api-level handler.
const m = src.match(/^[ \t]*(?:\/\* ff[A-Za-z]+ \*\/ *)?(?:try \{ *)?app\.use\(\s*['"]\/api(?:\/|['"])/m);
if (m) src = src.slice(0, m.index) + LINE + src.slice(m.index);
else { const l = src.indexOf('app.listen('); if (l === -1) { console.log('SERVER: koi anchor nahi'); process.exit(1); } src = src.slice(0, l) + LINE + src.slice(l); }
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SERVER: stock-journal middleware + /api/stock mounted early ✓'); }
catch (e) { fs.copyFileSync(f + '.bak-stockledger-' + process.env.FF_TS, f); console.log('SERVER SYNTAX FAIL — RESTORED'); process.exit(1); }
JS
[ $? -ne 0 ] && { echo "STOCKLEDGER FAIL (server.js)"; exit 1; }

# ---------- 4) routes/billing.js: precise document context (bill no / invoice no / party) ----------
if [ -f "$DIR/routes/billing.js" ]; then
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = process.env.FF_DIR + '/routes/billing.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('/* ffStockLedger */')) { console.log('BILLING: marks already present ✓'); process.exit(0); }
const edits = [
  ["const PERM_VIEW = 'billing.view', PERM_MANAGE = 'billing.manage';",
   "const PERM_VIEW = 'billing.view', PERM_MANAGE = 'billing.manage';\nconst SJ = (() => { try { return require('../stockctx'); } catch (_) { return null; } })(); /* ffStockLedger */\nconst sjMark = (req, f) => { try { if (SJ) SJ.mark(req, f); } catch (_) {} };"],
  ["    if (deductStock) adjustStock(c.items, -1);\n",
   "    if (deductStock) { sjMark(req, { kind: 'SALE', ref: n.number, party: pName, note: dispatchCode ? 'against dispatch ' + dispatchCode : '', link: '/billing/' + id, txn_date: date }); adjustStock(c.items, -1); }\n"],
  ["    if (inv.stock_deducted) adjustStock(items, +1);\n",
   "    if (inv.stock_deducted) { sjMark(req, { kind: 'SALE_CANCEL', ref: inv.number, party: inv.party_name, note: 'Invoice cancelled — stock restored' + ((req.body || {}).reason ? ' · ' + str(req.body.reason, 120) : ''), link: '/billing/' + inv.id }); adjustStock(items, +1); }\n"],
  ["    if (addStock) applyPurchaseStock(saved, +1, { date: recv, reference: 'Bill ' + billNo + ' · ' + pName, remark: remarks, userId: userId(req) });\n",
   "    if (addStock) { sjMark(req, { kind: 'PURCHASE', ref: billNo, doc2: n.number, party: pName, note: remarks, link: '/billing/purchases/' + id, txn_date: recv }); applyPurchaseStock(saved, +1, { date: recv, reference: 'Bill ' + billNo + ' · ' + pName, remark: remarks, userId: userId(req) }); }\n"],
  ["    if (p.stock_added) applyPurchaseStock(items, -1, {});\n",
   "    if (p.stock_added) { sjMark(req, { kind: 'PURCHASE_CANCEL', ref: p.bill_no, doc2: p.entry_no, party: p.party_name, note: 'Supplier bill cancelled — stock reversed' + ((req.body || {}).reason ? ' · ' + str(req.body.reason, 120) : ''), link: '/billing/purchases/' + p.id }); applyPurchaseStock(items, -1, {}); }\n"],
];
let n = 0;
for (const [a, b] of edits) { if (src.includes(a)) { src = src.replace(a, b); n++; } }
if (n < 2) { console.log('BILLING: anchors nahi labhe (' + n + '/5) — billing rows generic context naal likhe jaange (ref = invoice/bill no fer vi response ton aa janda hai)'); process.exit(0); }
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('BILLING: ' + n + '/5 stock-journal marks ✓ (bill no / invoice no / party on every billing movement)'); }
catch (e) { fs.copyFileSync(f + '.bak-stockledger-' + process.env.FF_TS, f); console.log('BILLING SYNTAX FAIL — RESTORED (generic context only)'); }
JS
else echo "BILLING: routes/billing.js nahi — pehla ff-billing.sh chalao (stock ledger fer vi kaam karega)"; fi

if [ "${FF_NO_RESTART:-}" != "1" ]; then
  systemctl restart "$SVC"
  sleep 7
  if [ "$MODE" = "saas" ]; then
    P=$(node -e 'try{const r=require("/opt/flavorflow-saas/data/registry.json");const c=Object.values(r.companies||{})[0];console.log(c?c.port:"")}catch(e){console.log("")}')
    [ -n "$P" ] && curl -s -m 8 -o /dev/null -w "TENANT :$P /api/stock/status (no token) -> %{http_code}  (401 = route live, auth guard OK)\n" "http://127.0.0.1:$P/api/stock/status"
    journalctl -u "$SVC" --since "-40s" --no-pager 2>/dev/null | grep -E 'ff-stockledger|stock-journal' | tail -6 | sed 's/^/LOG: /'
  else
    curl -s -m 8 -o /dev/null -w "FACTORY /api/stock/status (no token) -> %{http_code}  (401 = route live)\n" http://127.0.0.1:4000/api/stock/status
    journalctl -u "$SVC" --since "-40s" --no-pager 2>/dev/null | grep -E 'ff-stockledger|stock-journal' | tail -4 | sed 's/^/LOG: /'
  fi
fi
echo "STOCKLEDGER DONE ✓ — app: Stock Ledger (har item di IN/OUT history bill/dispatch/batch no. te running balance naal, all-items register, period balances, CSV)"
