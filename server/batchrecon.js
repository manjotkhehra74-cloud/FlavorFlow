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
/**
 * Backdated production repair.
 *
 * A completed production batch must remain visible in batch-wise stock. Older
 * completion paths could leave its produced quantity in inventory while a
 * stale used_cb counter made the batch look fully consumed; the report then
 * put the quantity in Unassigned. Restore only the unexplained used quantity:
 * dispatch/invoice demand for the product+code is never undone, and the
 * newest planned-date row is repaired first (the usual backdated-entry case).
 * Opening stock remains Unassigned when no completed batch has unexplained
 * consumption to repair.
 */
function repairCompletionDrift(db, opts) {
  const apply = !!(opts && opts.apply);
  const B = cols(db, 'batches'), I = cols(db, 'inventory');
  // Only repair the known failure mode: a batch completed today with an
  // earlier planned/production date. Never reinterpret ordinary opening-stock
  // drift or same-day manual adjustments as a production batch.
  if (!B.includes('used_cb') || !B.includes('produced_cb') || !B.includes('product_id') || !B.includes('planned_date') || !B.includes('completed_at') || !I.includes('product_id') || !I.includes('qty_cb')) return [];
  const hasTrays = B.includes('used_trays') && B.includes('produced_trays') && I.includes('qty_trays');
  const invRows = db.prepare('SELECT product_id pid, COALESCE(qty_cb, 0) stock_cb' + (hasTrays ? ', COALESCE(qty_trays, 0) stock_tr' : ', 0 stock_tr') + ' FROM inventory').all();
  const completed = db.prepare(
    "SELECT id, product_id pid, COALESCE(code, '') code, COALESCE(produced_cb, 0) pcb, COALESCE(used_cb, 0) ucb, " +
    (hasTrays ? 'COALESCE(produced_trays, 0) ptr, COALESCE(used_trays, 0) utr, ' : '0 ptr, 0 utr, ') +
    "COALESCE(planned_date, '') pd, COALESCE(completed_at, '') completed_at " +
    "FROM batches WHERE UPPER(COALESCE(status, '')) = 'COMPLETED' ORDER BY product_id, COALESCE(planned_date, '') DESC, id DESC"
  ).all();
  const demand = demandMap(db);
  const groups = new Map();
  for (const b of completed) {
    const plannedDay = String(b.pd || '').slice(0, 10);
    const completedDay = String(b.completed_at || '').slice(0, 10);
    if (!plannedDay || !completedDay || plannedDay === completedDay) continue;
    const key = n(b.pid) + '|' + String(b.code || '').trim().toUpperCase();
    const g = groups.get(key) || { pid: n(b.pid), rows: [], demandCb: 0, demandTr: 0 };
    g.rows.push(b);
    const d = demand.get(key);
    g.demandCb = d ? n(d.cb) : 0;
    g.demandTr = d ? n(d.tr) : 0;
    groups.set(key, g);
  }
  const gapByProduct = new Map();
  for (const r of invRows) {
    const productRows = completed.filter((b) => n(b.pid) === n(r.pid));
    const batchCb = productRows.reduce((s, b) => s + Math.max(0, n(b.pcb) - n(b.ucb)), 0);
    const batchTr = productRows.reduce((s, b) => s + Math.max(0, n(b.ptr) - n(b.utr)), 0);
    gapByProduct.set(n(r.pid), { cb: Math.max(0, n(r.stock_cb) - batchCb), tr: Math.max(0, n(r.stock_tr) - batchTr) });
  }
  const changes = [];
  for (const g of groups.values()) {
    let excessCb = Math.max(0, g.rows.reduce((s, b) => s + n(b.ucb), 0) - g.demandCb);
    let excessTr = Math.max(0, g.rows.reduce((s, b) => s + n(b.utr), 0) - g.demandTr);
    const gap = gapByProduct.get(g.pid);
    if (!gap || (gap.cb <= 0 && gap.tr <= 0) || (excessCb <= 0 && excessTr <= 0)) continue;
    // rows are already newest planned date first; restore the backdated row
    // before older rows when a code is reused on multiple production dates.
    for (const b of g.rows) {
      if (gap.cb <= 0 && gap.tr <= 0) break;
      const restoreCb = Math.min(gap.cb, excessCb, n(b.ucb));
      const restoreTr = Math.min(gap.tr, excessTr, n(b.utr));
      if (!restoreCb && !restoreTr) continue;
      const nextCb = n(b.ucb) - restoreCb, nextTr = n(b.utr) - restoreTr;
      if (apply) {
        db.prepare('UPDATE batches SET used_cb = ?' + (hasTrays ? ', used_trays = ?' : '') + ' WHERE id = ?')
          .run(...(hasTrays ? [nextCb, nextTr, b.id] : [nextCb, b.id]));
      }
      changes.push({ id: b.id, pid: b.pid, code: b.code, plannedDate: b.pd, restoredCb: restoreCb, restoredTrays: restoreTr });
      gap.cb -= restoreCb; gap.tr -= restoreTr; excessCb -= restoreCb; excessTr -= restoreTr;
    }
  }
  return changes;
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
  // Keep the report self-healing for legacy/backdated completion rows. The
  // repair is conservative and only restores unexplained used_cb/used_trays;
  // dispatch/invoice demand and legitimate opening stock are untouched.
  try { runTx(db, () => repairCompletionDrift(db, { apply: true })); } catch (_) {}
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
module.exports = { reconcile, repairCompletionDrift, demandMap, batchStockRows, stockDiff, deleteBlock, editBlock, runTx, UNASSIGNED };
