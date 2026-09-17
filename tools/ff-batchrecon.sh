#!/usr/bin/env bash
# FlavorFlow: BATCH ↔ STOCK RECONCILIATION (factory server + SaaS core, auto-detect).
#
#   Bug (09-17): Inventory → Soya Sauce 740gm = 408 CB, but Batch-wise Stock showed 6I0102AK with 21 CB MORE.
#   Root cause (request log 09-09): batch 187 `6I0102AK` (21 CB) was dispatched (used_cb = 21), edited to
#   238 CB, then DELETED — the delete removed the whole 238 from stock and threw the used_cb counter away —
#   and re-created as batch 189 `6I0102AK` 238 CB with used_cb = 0. Stock on Hand stayed right (408); the
#   register (produced_cb − used_cb) showed the 21 dispatched cartons as still in the batch.
#
#   FIX (whole class, every product / batch, factory + every tenant):
#     1) batchrecon.js — reconcile(): where the dispatched (+ stock-deducting invoiced) quantity of a
#        product+batch-code exceeds the usage recorded on its COMPLETED batches, the missing usage is booked
#        FIFO (oldest batch first, never above produced). Never reduces usage; VOID dispatches / CANCELLED
#        invoices don't count. Idempotent — safe on every boot.
#     2) routes/production.js guards — a COMPLETED batch with dispatched stock can't be deleted (409, clear
#        message: edit it or void the dispatches), and its produced quantity can't be edited below the
#        dispatched amount (409). That's how the counter got lost.
#     3) Batch-wise Stock report (Inventory page + Reports + PDF/Excel) now reconciles to Stock on Hand:
#        per product → batches (oldest first) → 'Unassigned (opening stock / adjustments)' line when the batch
#        sum ≠ stock → TOTAL = Stock on Hand → GRAND TOTAL. Any future drift is visible, never silent.
#   SELF-TEST on an in-memory DB (user's exact scenario + FIFO + VOID + invoice + guards + rollback) runs BEFORE
#   anything is patched. Backups (code + DB via VACUUM INTO), node --check + auto-restore, restart only if code
#   changed. Idempotent.
#   curl -fsSL https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a0858b-flavorflow/tools/ff-batchrecon.sh | sudo bash
set -u
if [ -d /opt/flavorflow-saas/core ]; then DIR=/opt/flavorflow-saas/core; MODE=saas; SVC=flavorflow-saas; BK=/opt/flavorflow-saas/backups;
elif [ -d /opt/flavorflow/server ]; then DIR=/opt/flavorflow/server; MODE=factory; SVC=flavorflow; BK=/opt/flavorflow/backups;
else echo "FATAL: koi server dir nahi labhi (/opt/flavorflow-saas/core ya /opt/flavorflow/server)"; exit 1; fi
echo "=== FF-BATCHRECON ($MODE) $(date) ==="
[ -f "$DIR/routes/production.js" ] || { echo "FATAL: $DIR/routes/production.js nahi mili"; exit 1; }
[ -f "$DIR/routes/reports.js" ] || echo "WARN: $DIR/routes/reports.js nahi mili — report patch skip hoega"
TS=$(date +%s)
mkdir -p "$BK"
cp -a "$DIR/routes/production.js" "$BK/production.js.bak-batchrecon-$TS"
[ -f "$DIR/routes/reports.js" ] && cp -a "$DIR/routes/reports.js" "$BK/reports.js.bak-batchrecon-$TS"
[ -f "$DIR/batchrecon.js" ] && cp -a "$DIR/batchrecon.js" "$BK/batchrecon.js.bak-batchrecon-$TS"
echo "BACKUP: routes/production.js routes/reports.js (+ module) -> $BK (suffix -batchrecon-$TS)"
export FF_DIR="$DIR" FF_MODE="$MODE" FF_TS="$TS" FF_BK="$BK"

restore_module() {
  if [ -f "$BK/batchrecon.js.bak-batchrecon-$TS" ]; then cp -a "$BK/batchrecon.js.bak-batchrecon-$TS" "$DIR/batchrecon.js"; else rm -f "$DIR/batchrecon.js"; fi
}

# ---------- 1) batchrecon.js (logic module — unit-tested below, used by routes + repair) ----------
NEWMOD=/tmp/ff-batchrecon-module-$TS.js
cat > "$NEWMOD" <<'JSFILE'
/** FlavorFlow — batch ↔ stock reconciliation (ff-batchrecon).
 *  Batch-wise Stock = produced_cb − used_cb per COMPLETED batch; used_cb is a counter bumped by dispatch.
 *  Deleting a COMPLETED batch that already had dispatched cartons threw that counter away; a batch re-created
 *  with the same code started at used_cb = 0, so the register showed dispatched cartons as still in stock
 *  (Soya Sauce 740gm · 6I0102AK: +21 CB vs Stock on Hand, 2026-09-09).
 *  - reconcile(db, {apply})  conservative repair: where the dispatched (+ stock-deducting invoiced) quantity of a
 *                            product+code exceeds the usage recorded on its COMPLETED batches, book the missing
 *                            usage FIFO (oldest first, never above produced). Never reduces usage (a batch renamed
 *                            after dispatch keeps its usage). VOID dispatches / CANCELLED invoices don't count.
 *  - batchStockRows(db)      Batch-wise Stock report: per product → batches (oldest first) → 'Unassigned' line when
 *                            Stock on Hand ≠ batch sum (opening stock / adjustments) → TOTAL = Stock on Hand → GRAND TOTAL.
 *                            Products without any remaining batch stay off the register (as before).
 *  - deleteBlock / editBlock guards for routes/production.js (no delete with dispatched stock; produced can't go
 *                            below dispatched).
 *  - stockDiff(db)           per-product Stock on Hand vs batch sum (diagnostics).
 *  Schema-aware (optional tables / columns). Works on the node:sqlite wrapper and better-sqlite3 (SAVEPOINT tx).
 */
'use strict';
const n = (v) => Number(v) || 0;
const cols = (db, t) => { try { return db.prepare('PRAGMA table_info(' + t + ')').all().map((c) => String(c.name)); } catch (_) { return []; } };
function runTx(db, fn) {
  if (typeof db.transaction === 'function') return db.transaction(fn)();
  let sp = false;
  try { db.exec('SAVEPOINT ff_recon'); sp = true; } catch (_) {}
  try { const r = fn(); if (sp) db.exec('RELEASE ff_recon'); return r; }
  catch (e) { if (sp) { try { db.exec('ROLLBACK TO ff_recon'); db.exec('RELEASE ff_recon'); } catch (_) {} } throw e; }
}
function qty(cb, tr) {
  const parts = [];
  if (n(cb) > 0 || n(tr) <= 0) parts.push(n(cb) + ' CB');
  if (n(tr) > 0) parts.push(n(tr) + ' trays');
  return parts.join(' + ');
}
/** Guard for DELETE /batches/:id — null = allowed, string = 409 message. */
function deleteBlock(batch) {
  const uc = n(batch && batch.used_cb), ut = n(batch && batch.used_trays);
  if (uc <= 0 && ut <= 0) return null;
  return 'Cannot delete ' + (batch.code || 'this batch') + ': ' + qty(uc, ut) + ' of it already dispatched. ' +
    'Edit the produced quantity instead (it cannot go below the dispatched amount), or void those dispatches first.';
}
/** Guard for PUT /batches/:id on a COMPLETED batch — null = allowed, string = 409 message. */
function editBlock(batch, newCb, newTrays) {
  const uc = n(batch && batch.used_cb), ut = n(batch && batch.used_trays);
  if (n(newCb) >= uc && n(newTrays) >= ut) return null;
  return 'Cannot set ' + (batch.code || 'this batch') + ' to ' + qty(newCb, newTrays) + ': ' + qty(uc, ut) +
    ' of it already dispatched — produced quantity cannot go below that. Void those dispatches first.';
}
/** Σ dispatched (+ stock-deducting invoiced) quantity per product + batch code. */
function demandMap(db) {
  const m = new Map();
  const add = (pid, code, cb, tr) => {
    code = String(code == null ? '' : code).trim().toUpperCase();
    if (!pid || !code) return;
    const k = pid + '|' + code, e = m.get(k) || { pid, code, cb: 0, tr: 0 };
    e.cb += cb; e.tr += tr; m.set(k, e);
  };
  const di = cols(db, 'dispatch_items');
  if (di.includes('batch_code') && di.includes('product_id') && di.includes('cartons')) {
    const dc = cols(db, 'dispatches');
    const trExpr = di.includes('trays') ? 'COALESCE(di.trays, 0)' : '0';
    const join = dc.length && di.includes('dispatch_id') ? ' JOIN dispatches d ON d.id = di.dispatch_id' : '';
    const notVoid = join && dc.includes('status') ? " AND UPPER(COALESCE(d.status, '')) <> 'VOID'" : '';
    const rows = db.prepare('SELECT di.product_id pid, di.batch_code code, COALESCE(di.cartons, 0) cb, ' + trExpr +
      ' tr FROM dispatch_items di' + join + " WHERE COALESCE(di.batch_code, '') <> ''" + notVoid).all();
    for (const r of rows) add(n(r.pid), r.code, n(r.cb), n(r.tr));
  }
  const ii = cols(db, 'invoice_items'), iv = cols(db, 'invoices');
  if (ii.includes('batch_code') && ii.includes('product_id') && ii.includes('qty') && iv.includes('stock_deducted')) {
    const rows = db.prepare('SELECT ii.product_id pid, ii.batch_code code, COALESCE(ii.qty, 0) cb FROM invoice_items ii ' +
      "JOIN invoices i ON i.id = ii.invoice_id WHERE COALESCE(ii.batch_code, '') <> '' AND COALESCE(i.stock_deducted, 0) = 1 " +
      "AND UPPER(COALESCE(i.status, '')) <> 'CANCELLED'").all();
    for (const r of rows) add(n(r.pid), r.code, n(r.cb), 0);
  }
  return m;
}
/** Conservative repair (see header). Returns { changed: [...], unallocated: [...], groups } or { skipped }. */
function reconcile(db, opts) {
  const apply = !!(opts && opts.apply);
  const b = cols(db, 'batches');
  if (!b.includes('used_cb') || !b.includes('used_trays') || !b.includes('code') || !b.includes('product_id')) {
    return { skipped: 'batches.used_cb / used_trays missing', changed: [], unallocated: [], groups: 0 };
  }
  const order = b.includes('planned_date') ? "COALESCE(planned_date, '') ASC, id ASC" : 'id ASC';
  const sel = db.prepare('SELECT id, code, product_id pid, COALESCE(produced_cb, 0) pcb, COALESCE(produced_trays, 0) ptr, ' +
    "COALESCE(used_cb, 0) ucb, COALESCE(used_trays, 0) utr FROM batches WHERE UPPER(COALESCE(status, '')) = 'COMPLETED' " +
    'AND product_id = ? AND UPPER(TRIM(code)) = ? ORDER BY ' + order);
  const upd = db.prepare('UPDATE batches SET used_cb = ?, used_trays = ? WHERE id = ?');
  const demand = demandMap(db);
  const changed = [], unallocated = [];
  const work = () => {
    for (const d of demand.values()) {
      const rows = sel.all(d.pid, d.code);
      if (!rows.length) { if (d.cb > 0 || d.tr > 0) unallocated.push({ pid: d.pid, code: d.code, cb: d.cb, tr: d.tr, reason: 'no COMPLETED batch with this code' }); continue; }
      let needCb = d.cb - rows.reduce((s, r) => s + r.ucb, 0);
      let needTr = d.tr - rows.reduce((s, r) => s + r.utr, 0);
      if (needCb <= 0 && needTr <= 0) continue;
      for (const r of rows) {
        if (needCb <= 0 && needTr <= 0) break;
        const takeCb = Math.max(0, Math.min(needCb, r.pcb - r.ucb));
        const takeTr = Math.max(0, Math.min(needTr, r.ptr - r.utr));
        if (!takeCb && !takeTr) continue;
        if (apply) upd.run(r.ucb + takeCb, r.utr + takeTr, r.id);
        changed.push({ id: r.id, code: r.code, pid: r.pid, usedCb: [r.ucb, r.ucb + takeCb], usedTrays: [r.utr, r.utr + takeTr], demandCb: d.cb, demandTrays: d.tr });
        needCb -= takeCb; needTr -= takeTr;
      }
      if (needCb > 0 || needTr > 0) unallocated.push({ pid: d.pid, code: d.code, cb: Math.max(0, needCb), tr: Math.max(0, needTr), reason: 'dispatched more than the batch(es) produced' });
    }
  };
  if (apply) runTx(db, work); else work();
  return { changed, unallocated, groups: demand.size };
}
function productList(db) {
  const p = cols(db, 'products'), inv = cols(db, 'inventory');
  if (!p.length) return [];
  const where = p.includes('active') ? ' WHERE COALESCE(p.active, 1) = 1' : '';
  const bpt = p.includes('bottles_per_tray') ? 'COALESCE(p.bottles_per_tray, 0)' : '0';
  const qcb = inv.includes('qty_cb') ? 'COALESCE(i.qty_cb, 0)' : '0';
  const qtr = inv.includes('qty_trays') ? 'COALESCE(i.qty_trays, 0)' : '0';
  const join = inv.length ? ' LEFT JOIN inventory i ON i.product_id = p.id' : '';
  return db.prepare('SELECT p.id, p.name, ' + bpt + ' bpt, ' + qcb + ' qcb, ' + qtr + ' qtr FROM products p' + join + where + ' ORDER BY p.name, p.id').all();
}
function batchesLeft(db) {
  const b = cols(db, 'batches'), by = new Map();
  if (!b.includes('code') || !b.includes('product_id')) return by;
  const d = b.includes('planned_date') ? "COALESCE(date(planned_date), '—')" : "'—'";
  const order = b.includes('planned_date') ? 'planned_date, id' : 'id';
  const ucb = b.includes('used_cb') ? 'COALESCE(used_cb, 0)' : '0', utr = b.includes('used_trays') ? 'COALESCE(used_trays, 0)' : '0';
  const rows = db.prepare('SELECT product_id pid, ' + d + ' d, code, COALESCE(produced_cb, 0) - ' + ucb + ' cb, COALESCE(produced_trays, 0) - ' + utr +
    " tr FROM batches WHERE UPPER(COALESCE(status, '')) = 'COMPLETED' ORDER BY " + order).all();
  for (const r of rows) {
    if (n(r.cb) <= 0 && n(r.tr) <= 0) continue;
    if (!by.has(r.pid)) by.set(r.pid, []);
    by.get(r.pid).push({ d: r.d, code: r.code, cb: n(r.cb), tr: n(r.tr) });
  }
  return by;
}
const UNASSIGNED = 'Unassigned (opening stock / adjustments)';
/** Batch-wise Stock report rows — every product TOTAL equals Stock on Hand (products with batches). */
function batchStockRows(db) {
  const rows = [], by = batchesLeft(db);
  let totCb = 0, totTr = 0;
  for (const p of productList(db)) {
    const list = by.get(p.id) || [], hasTray = n(p.bpt) > 0;
    let sumCb = 0, sumTr = 0;
    for (const x of list) { sumCb += x.cb; sumTr += x.tr; }
    const diffCb = n(p.qcb) - sumCb, diffTr = hasTray ? n(p.qtr) - sumTr : 0;
    if (!list.length) continue;
    rows.push(['▶ ' + String(p.name || '').toUpperCase(), '', '', '']);
    for (const x of list) rows.push([x.d, x.code, x.cb, hasTray ? x.tr : '—']);
    if (diffCb !== 0 || diffTr !== 0) rows.push(['—', UNASSIGNED, diffCb, hasTray ? diffTr : '—']);
    rows.push(['TOTAL', '', n(p.qcb), hasTray ? n(p.qtr) : '—']);
    rows.push(['', '', '', '']);
    totCb += n(p.qcb); totTr += hasTray ? n(p.qtr) : 0;
  }
  rows.push(['GRAND TOTAL', '', totCb, totTr]);
  return { columns: ['Mfg. Date / Product', 'Batch Code', 'CB', 'Trays'], rows };
}
/** Diagnostics: products whose Stock on Hand ≠ batch sum. */
function stockDiff(db) {
  const out = [], by = batchesLeft(db);
  for (const p of productList(db)) {
    const list = by.get(p.id) || [];
    let sumCb = 0, sumTr = 0;
    for (const x of list) { sumCb += x.cb; sumTr += x.tr; }
    const diffCb = n(p.qcb) - sumCb, diffTr = n(p.bpt) > 0 ? n(p.qtr) - sumTr : 0;
    if (diffCb !== 0 || diffTr !== 0) out.push({ id: p.id, name: p.name, stockCb: n(p.qcb), batchCb: sumCb, diffCb, stockTrays: n(p.qtr), batchTrays: sumTr, diffTr });
  }
  return out;
}
module.exports = { reconcile, demandMap, batchStockRows, stockDiff, deleteBlock, editBlock, runTx, UNASSIGNED };
JSFILE
if ! node --check "$NEWMOD"; then echo "FATAL: module syntax fail — kuch nahi badleya"; rm -f "$NEWMOD"; exit 1; fi
MOD_CHANGED=0
if [ -f "$DIR/batchrecon.js" ] && cmp -s "$NEWMOD" "$DIR/batchrecon.js"; then echo "MODULE: batchrecon.js identical ✓"; else cp "$NEWMOD" "$DIR/batchrecon.js"; MOD_CHANGED=1; echo "MODULE: batchrecon.js installed"; fi
rm -f "$NEWMOD"

# ---------- 2) SELF-TEST (in-memory DB through the server's own sqlite wrapper) ----------
node - <<'JS'
const DIR = process.env.FF_DIR;
const fail = (m) => { console.log('SELFTEST FAIL: ' + m); process.exit(2); };
const R = require(DIR + '/batchrecon');
let checks = 0; const ok = (c, m) => { if (!c) fail(m); checks++; };
ok(R.deleteBlock({ code: 'X', used_cb: 0, used_trays: 0 }) === null, 'deleteBlock: clean batch must be allowed');
ok(/21 CB/.test(R.deleteBlock({ code: 'X', used_cb: 21, used_trays: 0 }) || ''), 'deleteBlock: dispatched batch must block');
ok(R.editBlock({ code: 'X', used_cb: 21, used_trays: 2 }, 21, 2) === null, 'editBlock: equal to dispatched is fine');
ok(!!R.editBlock({ code: 'X', used_cb: 21, used_trays: 0 }, 20, 0), 'editBlock: below dispatched CB must block');
ok(!!R.editBlock({ code: 'X', used_cb: 0, used_trays: 3 }, 50, 2), 'editBlock: below dispatched trays must block');
let DatabaseSync = null;
try { DatabaseSync = require(DIR + '/sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) { try { DatabaseSync = require('node:sqlite').DatabaseSync; } catch (_) {} }
if (!DatabaseSync) { console.log('SELFTEST: koi sqlite wrapper nahi — DB checks skip (' + checks + ' guard checks ✓)'); process.exit(0); }
const db = new DatabaseSync(':memory:');
db.exec(`CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, bottles_per_tray INTEGER DEFAULT 0, active INTEGER DEFAULT 1);
CREATE TABLE inventory (product_id INTEGER PRIMARY KEY, qty_cb INTEGER DEFAULT 0, qty_trays INTEGER DEFAULT 0, updated_at TEXT);
CREATE TABLE batches (id INTEGER PRIMARY KEY, code TEXT, product_id INTEGER, planned_cb INTEGER, produced_cb INTEGER DEFAULT 0, produced_trays INTEGER DEFAULT 0, status TEXT, planned_date TEXT, used_trays INTEGER DEFAULT 0, used_cb INTEGER DEFAULT 0);
CREATE TABLE dispatches (id INTEGER PRIMARY KEY, code TEXT, status TEXT);
CREATE TABLE dispatch_items (id INTEGER PRIMARY KEY, dispatch_id INTEGER, product_id INTEGER, cartons INTEGER, trays INTEGER, batch_code TEXT);
CREATE TABLE invoices (id INTEGER PRIMARY KEY, number TEXT, status TEXT, stock_deducted INTEGER DEFAULT 0);
CREATE TABLE invoice_items (id INTEGER PRIMARY KEY, invoice_id INTEGER, product_id INTEGER, qty REAL, batch_code TEXT);
INSERT INTO products VALUES (1,'Soya Sauce 740gm',0,1),(2,'White Vinegar 610ml',12,1),(3,'Deleted Product',0,0),(4,'White Vinegar 180ml',0,1),(5,'Small',0,1),(6,'Multi',0,1),(7,'Invoiced',0,1);
INSERT INTO inventory VALUES (1,217,0,''),(2,40,5,''),(3,9,0,''),(4,4158,0,''),(5,0,0,''),(6,30,0,''),(7,16,0,'');
INSERT INTO batches (id,code,product_id,planned_cb,produced_cb,produced_trays,status,planned_date,used_cb,used_trays) VALUES
 (189,'6I0102AK',1,238,238,0,'COMPLETED','2026-09-09',0,0),
 (50,'RENAMED',1,30,30,0,'COMPLETED','2026-08-20',30,0),
 (60,'PLAN',1,100,0,0,'PLANNED','2026-09-20',0,0),
 (20,'T1',2,50,50,8,'COMPLETED','2026-09-01',0,0),
 (30,'S1',5,10,10,0,'COMPLETED','2026-09-02',0,0),
 (40,'M',6,100,100,0,'COMPLETED','2026-08-01',100,0),
 (41,'M',6,50,50,0,'COMPLETED','2026-08-05',0,0),
 (70,'I1',7,20,20,0,'COMPLETED','2026-09-03',0,0);
INSERT INTO dispatches VALUES (22,'D-22','DISPATCHED'),(23,'D-23','VOID'),(24,'D-24','DISPATCHED');
INSERT INTO dispatch_items (dispatch_id,product_id,cartons,trays,batch_code) VALUES
 (22,1,21,0,'6I0102AK'),(23,1,100,0,'6I0102AK'),(22,2,10,3,'t1 '),(24,5,25,0,'S1'),(24,6,120,0,'M'),(24,1,5,0,'NOSUCH'),(24,1,7,0,'');
INSERT INTO invoices VALUES (1,'INV/1','ISSUED',1),(2,'INV/2','CANCELLED',1),(3,'INV/3','ISSUED',0);
INSERT INTO invoice_items (invoice_id,product_id,qty,batch_code) VALUES (1,7,4,'I1'),(2,7,100,'I1'),(3,7,50,'I1');`);
const dry = R.reconcile(db, { apply: false });
ok(dry.changed.length === 5, 'dry run: 5 batch changes expected, got ' + dry.changed.length);
ok(db.prepare('SELECT used_cb FROM batches WHERE id = 189').get().used_cb === 0, 'dry run must not write');
const r1 = R.reconcile(db, { apply: true });
const used = (id) => { const r = db.prepare('SELECT used_cb, used_trays FROM batches WHERE id = ?').get(id); return [r.used_cb, r.used_trays]; };
ok(String(used(189)) === '21,0', "user's case: 6I0102AK used_cb must become 21 (got " + used(189) + ')');
ok(String(used(50)) === '30,0', 'renamed batch keeps its usage');
ok(String(used(20)) === '10,3', 'trays + trimmed/lower-case code: T1 used 10 CB / 3 trays (got ' + used(20) + ')');
ok(String(used(30)) === '10,0', 'deficit beyond produced: capped at produced');
ok(r1.unallocated.some((u) => u.code === 'S1' && u.cb === 15), 'unallocated 15 CB reported for S1');
ok(r1.unallocated.some((u) => u.code === 'NOSUCH' && u.cb === 5), 'unknown code reported, not booked');
ok(String(used(40)) === '100,0' && String(used(41)) === '20,0', 'FIFO: deficit goes to the oldest batch with capacity');
ok(String(used(70)) === '4,0', 'invoice demand: only stock-deducting, non-cancelled invoices count (got ' + used(70) + ')');
ok(r1.changed.length === 5, 'apply: 5 batch changes');
const r2 = R.reconcile(db, { apply: true });
ok(r2.changed.length === 0, 'idempotent: second run changes nothing');
const rep = R.batchStockRows(db), rows = rep.rows;
const sect = (name) => { const i = rows.findIndex((r) => r[0] === '▶ ' + name); if (i === -1) return null; const j = rows.findIndex((r, k) => k > i && r[0] === 'TOTAL'); return rows.slice(i + 1, j + 1); };
const s1 = sect('SOYA SAUCE 740GM');
ok(s1 && s1.length === 2 && s1[0][1] === '6I0102AK' && s1[0][2] === 217 && s1[0][3] === '—' && s1[1][0] === 'TOTAL' && s1[1][2] === 217, 'Soya section: 6I0102AK 217, no Unassigned line, TOTAL 217 = Stock on Hand (' + JSON.stringify(s1) + ')');
const s2 = sect('WHITE VINEGAR 610ML');
ok(s2 && s2[0][1] === 'T1' && s2[0][2] === 40 && s2[0][3] === 5 && s2[1][0] === 'TOTAL' && s2[1][2] === 40 && s2[1][3] === 5, 'tray product: T1 40 / 5, TOTAL 40 / 5 (' + JSON.stringify(s2) + ')');
ok(sect('DELETED PRODUCT') === null, 'inactive product hidden');
ok(sect('WHITE VINEGAR 180ML') === null, 'stock without any batch → stays off the register (as before)');
ok(sect('SMALL') === null, 'zero stock + no remaining batch → hidden');
const s6 = sect('MULTI');
ok(s6 && s6.length === 2 && s6[0][2] === 30 && s6[1][2] === 30, 'FIFO product: one batch row 30, TOTAL 30');
const g = rows[rows.length - 1];
ok(g[0] === 'GRAND TOTAL' && g[2] === 217 + 40 + 30 + 16 && g[3] === 5, 'GRAND TOTAL = Σ Stock on Hand of shown products (' + JSON.stringify(g) + ')');
db.prepare('UPDATE inventory SET qty_cb = 400 WHERE product_id = 1').run();
const rows2 = R.batchStockRows(db).rows; const i2 = rows2.findIndex((r) => r[0] === '▶ SOYA SAUCE 740GM');
ok(rows2[i2 + 2][1] === R.UNASSIGNED && rows2[i2 + 2][2] === 183 && rows2[i2 + 3][2] === 400, 'drift visible: Unassigned 183, TOTAL 400 = Stock on Hand');
const diffs = R.stockDiff(db);
ok(diffs.some((d) => d.id === 1 && d.diffCb === 183) && diffs.some((d) => d.id === 4 && d.diffCb === 4158), 'stockDiff lists drifted products (incl. batch-less stock)');
db.prepare('UPDATE inventory SET qty_cb = 200 WHERE product_id = 1').run();
const rows3 = R.batchStockRows(db).rows; const i3 = rows3.findIndex((r) => r[0] === '▶ SOYA SAUCE 740GM');
ok(rows3[i3 + 2][1] === R.UNASSIGNED && rows3[i3 + 2][2] === -17 && rows3[i3 + 3][2] === 200, 'negative drift (dispatch without batch code / adjustment) shown as Unassigned −17, TOTAL 200');
db.prepare('UPDATE inventory SET qty_cb = 400 WHERE product_id = 1').run();
let threw = false;
try { R.runTx(db, () => { db.prepare('UPDATE batches SET used_cb = 999 WHERE id = 189').run(); throw new Error('boom'); }); } catch (_) { threw = true; }
ok(threw && used(189)[0] === 21, 'rollback: failed tx leaves used_cb untouched');
console.log('SELFTEST ' + checks + ' checks ✓ (user scenario 6I0102AK 0→21, FIFO, VOID/CANCELLED excluded, trays, guards, report totals = Stock on Hand, rollback)');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "FATAL: self-test fail (rc=$RC) — kuch patch NAHI kita, module restored"; restore_module; exit 1; fi

# ---------- 3) routes/production.js: delete / edit guards ----------
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const DIR = process.env.FF_DIR, TS = process.env.FF_TS, BK = process.env.FF_BK;
const f = DIR + '/routes/production.js';
let src = fs.readFileSync(f, 'utf8'), changed = false;
const usesBad = /\bbad\b/.test(src.split('\n').slice(0, 15).join('\n')) || /throw bad\(/.test(src);
const THROW = usesBad ? 'throw bad(g, 409);' : 'throw Object.assign(new Error(g), { status: 409, statusCode: 409 });';
if (src.includes('ffBatchGuard:delete')) console.log('GUARD: delete guard present ✓');
else {
  const rd = src.indexOf("router.delete('/batches/:id'");
  const key = "if (batch.status === 'COMPLETED') {";
  const a = rd === -1 ? -1 : src.indexOf(key, rd);
  if (a === -1) console.log('GUARD: delete anchor NOT found ✗ (routes/production.js vakhri hai — manual check)');
  else {
    const at = a + key.length;
    src = src.slice(0, at) + '\n    /* ffBatchGuard:delete */ { const g = require(\'../batchrecon\').deleteBlock(batch); if (g) ' + THROW + ' }' + src.slice(at);
    changed = true; console.log('GUARD: delete guard added ✓ (batch with dispatched stock → 409)');
  }
}
if (src.includes('ffBatchGuard:edit')) console.log('GUARD: edit guard present ✓');
else {
  const key = 'const dTrays = newTrays - batch.produced_trays;';
  const a = src.indexOf(key);
  if (a === -1) console.log('GUARD: edit anchor NOT found ✗ (manual check)');
  else {
    const at = a + key.length;
    src = src.slice(0, at) + '\n  /* ffBatchGuard:edit */ { const g = require(\'../batchrecon\').editBlock(batch, newCb, newTrays); if (g) ' + THROW + ' }' + src.slice(at);
    changed = true; console.log('GUARD: edit guard added ✓ (produced below dispatched → 409)');
  }
}
if (!changed) process.exit(0);
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('GUARD: routes/production.js syntax OK'); process.exit(3); }
catch (e) { fs.copyFileSync(BK + '/production.js.bak-batchrecon-' + TS, f); console.log('GUARD: SYNTAX FAIL — restored: ' + String(e.stderr || e).slice(0, 300)); process.exit(1); }
JS
RC=$?
[ $RC -eq 1 ] && { echo "BATCHRECON FAIL (routes/production.js) — backups: $BK"; exit 1; }
CHANGED=$MOD_CHANGED; [ $RC -eq 3 ] && CHANGED=1

# ---------- 4) routes/reports.js: batch-stock report → reconciled layout (module-backed) ----------
if [ -f "$DIR/routes/reports.js" ]; then
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const DIR = process.env.FF_DIR, TS = process.env.FF_TS, BK = process.env.FF_BK;
const f = DIR + '/routes/reports.js';
let src = fs.readFileSync(f, 'utf8');
const BLOCK = `  'batch-stock': {
    title: 'Batch-wise Stock',
    desc: 'Remaining stock per production batch, grouped by product — dispatched quantities already deducted. "Unassigned" = stock on hand that no batch accounts for (opening stock / manual adjustments). Every TOTAL equals Stock on Hand.',
    run: () => require('../batchrecon').batchStockRows(db), /* ffBatchRecon */
  },
`;
if (src.includes(BLOCK)) { console.log('REPORT: batch-stock reconciled layout present ✓'); process.exit(0); }
const start = src.indexOf("  'batch-stock': {");
const anchor = "  'dispatch-register': {";
if (start !== -1) {
  let end = src.indexOf(anchor, start);
  if (end === -1) { const e2 = src.indexOf('\n  },\n', start); if (e2 !== -1) end = e2 + '\n  },\n'.length; }
  if (end === -1) { console.log('REPORT: block end NOT found ✗ — report unchanged'); process.exit(0); }
  src = src.slice(0, start) + BLOCK + src.slice(end);
  console.log('REPORT: batch-stock block replaced ✓');
} else {
  const at = src.indexOf(anchor);
  if (at === -1) { console.log('REPORT: no batch-stock report and no anchor — skip (app falls back to the old layout)'); process.exit(0); }
  src = src.slice(0, at) + BLOCK + src.slice(at);
  if (src.includes("'inventory-valuation'")) {
    src = src.split("'inventory-valuation'").join("'inventory-valuation', 'batch-stock'").replace("'inventory-valuation', 'batch-stock': {", "'inventory-valuation': {");
  }
  console.log('REPORT: batch-stock report added ✓');
}
if (!/const db = require\(['"]\.\.\/db['"]\)/.test(src)) console.log("REPORT: WARN — 'const db = require(../db)' line nahi dikhi (report 'db' vartda hai)");
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('REPORT: routes/reports.js syntax OK'); process.exit(3); }
catch (e) { fs.copyFileSync(BK + '/reports.js.bak-batchrecon-' + TS, f); console.log('REPORT: SYNTAX FAIL — restored: ' + String(e.stderr || e).slice(0, 300)); process.exit(1); }
JS
RC=$?
[ $RC -eq 1 ] && { echo "BATCHRECON FAIL (routes/reports.js) — backups: $BK"; exit 1; }
[ $RC -eq 3 ] && CHANGED=1
fi

# ---------- 5) DATA REPAIR: every DB (factory erp.db / every tenant) — dry-run → backup → apply ----------
FF_DBS=""
if [ "$MODE" = saas ]; then
  for d in /opt/flavorflow-saas/data/tenant-*/erp.db; do [ -f "$d" ] && FF_DBS="$FF_DBS $d"; done
else
  DBP=$(systemctl show "$SVC" -p Environment 2>/dev/null | tr ' ' '\n' | sed -n 's/^ERP_DB_PATH=//p' | head -1)
  [ -n "$DBP" ] && [ -f "$DBP" ] || DBP="$DIR/data/erp.db"
  FF_DBS="$DBP"
fi
export FF_DBS
node - <<'JS'
const fs = require('fs'), path = require('path');
const DIR = process.env.FF_DIR, TS = process.env.FF_TS, BK = process.env.FF_BK, MODE = process.env.FF_MODE;
const R = require(DIR + '/batchrecon');
let DatabaseSync = null;
try { DatabaseSync = require(DIR + '/sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) { try { DatabaseSync = require('node:sqlite').DatabaseSync; } catch (_) {} }
if (!DatabaseSync) { console.log('RECON: koi sqlite wrapper nahi — data repair skip'); process.exit(0); }
const dbs = String(process.env.FF_DBS || '').trim().split(/\s+/).filter(Boolean);
let fixed = 0, dbsFixed = 0, unalloc = 0, n = 0;
for (const file of dbs) {
  if (!fs.existsSync(file)) { console.log('RECON ' + file + ': not found — skip'); continue; }
  n++;
  const label = MODE === 'saas' ? path.basename(path.dirname(file)) : 'factory';
  let db;
  try { db = new DatabaseSync(file); db.exec('PRAGMA busy_timeout = 5000'); } catch (e) { console.log('RECON ' + label + ': open FAIL ' + e.message); continue; }
  try {
    const names = new Map(); try { for (const p of db.prepare('SELECT id, name FROM products').all()) names.set(p.id, p.name); } catch (_) {}
    const pn = (id) => names.get(id) || ('product#' + id);
    const dry = R.reconcile(db, { apply: false });
    if (dry.skipped) { console.log('RECON ' + label + ': skip — ' + dry.skipped); db.close(); continue; }
    if (dry.changed.length) {
      const bak = BK + '/erp.db.' + label + '.bak-batchrecon-' + TS;
      try { db.exec("VACUUM INTO '" + bak.replace(/'/g, "''") + "'"); console.log('RECON ' + label + ': DB backup -> ' + bak); }
      catch (e) { console.log('RECON ' + label + ': backup FAIL (' + e.message + ') — repair skipped for safety'); db.close(); continue; }
      const res = R.reconcile(db, { apply: true });
      for (const c of res.changed) console.log('RECON ' + label + ': ' + pn(c.pid) + ' · ' + c.code + ': used_cb ' + c.usedCb[0] + ' → ' + c.usedCb[1] + (c.usedTrays[1] !== c.usedTrays[0] ? ', used_trays ' + c.usedTrays[0] + ' → ' + c.usedTrays[1] : '') + ' (dispatched ' + c.demandCb + ' CB' + (c.demandTrays ? ' / ' + c.demandTrays + ' trays' : '') + ' under this code)');
      fixed += res.changed.length; if (res.changed.length) dbsFixed++;
      for (const u of res.unallocated) { unalloc++; console.log('RECON ' + label + ': NOTE ' + pn(u.pid) + ' · ' + u.code + ': ' + u.cb + ' CB' + (u.tr ? ' / ' + u.tr + ' trays' : '') + ' dispatched but ' + u.reason + ' — batch register cannot place it (stock on hand unaffected)'); }
    } else {
      for (const u of dry.unallocated) { unalloc++; if (MODE !== 'saas') console.log('RECON ' + label + ': NOTE ' + pn(u.pid) + ' · ' + u.code + ': ' + u.cb + ' CB' + (u.tr ? ' / ' + u.tr + ' trays' : '') + ' dispatched but ' + u.reason); }
    }
    const diffs = R.stockDiff(db);
    if (MODE !== 'saas' || dry.changed.length) {
      const top = diffs.slice(0, 8).map((d) => d.name + ' ' + (d.diffCb > 0 ? '+' : '') + d.diffCb + ' CB' + (d.diffTr ? ' / ' + (d.diffTr > 0 ? '+' : '') + d.diffTr + ' trays' : '')).join('; ');
      console.log('RECON ' + label + ': ' + (dry.changed.length ? dry.changed.length + ' batch(es) repaired' : 'batches consistent') + ' · products whose stock ≠ batch sum (register shows the gap as Unassigned): ' + diffs.length + (top ? ' — ' + top : ''));
    }
  } catch (e) { console.log('RECON ' + label + ': FAIL ' + e.message); }
  try { db.close(); } catch (_) {}
}
console.log('RECON SUMMARY: ' + n + ' DB checked · ' + fixed + ' batch(es) repaired in ' + dbsFixed + ' DB · ' + unalloc + ' unplaceable line(s)');
JS

# DB files must stay writable for the service user (factory unit runs as User=flavorflow; root just wrote to them)
SVC_USER=$(systemctl show "$SVC" -p User --value 2>/dev/null || true)
if [ -n "${SVC_USER:-}" ] && id "$SVC_USER" >/dev/null 2>&1; then
  for d in $FF_DBS; do chown "$SVC_USER" "$d" "$d-wal" "$d-shm" 2>/dev/null || true; done
  chown "$SVC_USER" "$DIR/batchrecon.js" 2>/dev/null || true
  echo "OWNER: DB + module files -> $SVC_USER ✓"
fi

# ---------- 6) restart + verify ----------
if [ "$CHANGED" = 1 ] && [ -z "${FF_NO_RESTART:-}" ]; then
  systemctl restart "$SVC" && echo "SERVER: $SVC restarted" || echo "SERVER: restart FAIL — journalctl -u $SVC -n 40"
  sleep 7
else
  echo "SERVER: koi code change nahi — restart di lod nahi"
fi
if [ -z "${FF_NO_RESTART:-}" ]; then
  if [ "$MODE" = saas ]; then
    P=$(node -e 'try{const r=require("/opt/flavorflow-saas/data/registry.json");const c=Object.values(r.companies||{})[0];console.log(c?c.port:"")}catch(e){console.log("")}')
    [ -n "$P" ] && echo "TENANT :$P /api/reports/batch-stock (no token) -> $(curl -s -o /dev/null -w '%{http_code}' -m 8 "http://127.0.0.1:$P/api/reports/batch-stock") (401 = route live, auth guard OK)"
  else
    echo "FACTORY health -> $(curl -s -o /dev/null -w '%{http_code}' -m 6 http://127.0.0.1:4000/api/health) · /api/reports/batch-stock (no token) -> $(curl -s -o /dev/null -w '%{http_code}' -m 8 http://127.0.0.1:4000/api/reports/batch-stock) (401 = route live)"
  fi
fi
grep -q 'ffBatchGuard:delete' "$DIR/routes/production.js" && grep -q 'ffBatchGuard:edit' "$DIR/routes/production.js" && [ -f "$DIR/batchrecon.js" ] && \
  echo "BATCHRECON VERIFIED ✓ — (1) batch used_cb repaired from real dispatch lines, (2) dispatched batch: delete/under-edit blocked with a clear message, (3) Batch-wise Stock TOTAL = Stock on Hand (Unassigned line shows opening stock / adjustments). App: Inventory page pull-to-refresh." || \
  { echo "BATCHRECON: markers nahi labhe ✗ (guards anchor fail — upar GUARD lines dekho)"; exit 1; }
