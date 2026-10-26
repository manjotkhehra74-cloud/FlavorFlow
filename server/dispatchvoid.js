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
