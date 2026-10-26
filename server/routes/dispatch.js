/** routes/dispatch.js — dispatch module: weight calculator, entries, history, detail.
 *  Units: cartons (CB) + trays. Destination instead of driver details. */
const express = require('express');
const db = require('../db');
const { requirePerm, bad } = require('../middleware');
const { audit, nowIso, notifyRoles, calcLine, checkLowStock, round2, dateOnly, weekdayName } = require('../helpers');
const { tx } = require('../sqlite');

const router = express.Router();

const LIST_SQL = `SELECT d.*, u.name created_by_name,
                  (SELECT COUNT(*) FROM dispatch_items di WHERE di.dispatch_id = d.id) line_count
                  FROM dispatches d LEFT JOIN users u ON u.id = d.created_by`;

const DETAIL_SQL = `SELECT d.*, u.name created_by_name FROM dispatches d LEFT JOIN users u ON u.id = d.created_by WHERE d.id = ?`;

function itemsFor(dispatchId) {
  return db.prepare(
    `SELECT di.*, p.name product_name, p.weight_per_cb, p.weight_without_cb, p.bottles_per_cb, p.bottles_per_tray, p.tray_weight pt_tray_weight
     FROM dispatch_items di JOIN products p ON p.id = di.product_id
     WHERE di.dispatch_id = ? ORDER BY di.id`
  ).all(dispatchId);
}

/** Truck Loading Calculator — pure computation, no writes. Used live by the UI. */
router.post('/calculate', requirePerm('dispatch.view'), (req, res) => {
  res.json(compute(req.body.items));
});

function compute(items) {
  if (!Array.isArray(items) || items.length === 0) throw bad('Add at least one product line.');
  const lines = items.map((it, i) => {
    const prod = db.prepare('SELECT * FROM products WHERE id = ? AND active = 1').get(Number(it.productId));
    if (!prod) throw bad(`Line ${i + 1}: product not found.`);
    const l = calcLine(prod, it.cartons, it.trays);
    if (l.trays > 0 && prod.bottles_per_tray === 0) throw bad(`Line ${i + 1} (${prod.name}): this product is not tray-packed.`);
    if (l.cartons === 0 && l.trays === 0) throw bad(`Line ${i + 1} (${prod.name}): enter cartons or trays.`);
    return {
      productId: prod.id, productName: prod.name, bottlesPerCb: prod.bottles_per_cb,
      bottlesPerTray: prod.bottles_per_tray,
      cartons: l.cartons, trays: l.trays,
      cartonWeight: l.cartonWeight, trayWeight: l.trayWeight,
      batchCode: String(it.batchCode||'').trim().toUpperCase(),
      grossWeight: l.grossWeight, totalBottles: l.totalBottles,
    };
  });
  const totals = {
    totalCartons: lines.reduce((a, l) => a + l.cartons, 0),
    totalTrays: lines.reduce((a, l) => a + l.trays, 0),
    totalBottles: lines.reduce((a, l) => a + l.totalBottles, 0),
    cartonWeight: round2(lines.reduce((a, l) => a + l.cartonWeight, 0)),
    trayWeight: round2(lines.reduce((a, l) => a + l.trayWeight, 0)),
    grossWeight: round2(lines.reduce((a, l) => a + l.grossWeight, 0)),
  };
  return { lines, totals };
}

/** Dispatch history */
router.get('/', requirePerm('dispatch.view'), (req, res) => {
  const rows = db.prepare(`${LIST_SQL} ORDER BY d.created_at DESC LIMIT 200`).all();
  rows.forEach((r) => (r.weekday = weekdayName(r.dispatch_date)));
  res.json({ dispatches: rows });
});

/** Dispatch detail (used by the detail screen + PDF export) */
/** ff-truckfix: truck master — number + destination (route). */
router.get('/trucks', requirePerm('dispatch.view'), (req, res) => {
  const trucks = db.prepare('SELECT * FROM dispatch_trucks WHERE active = 1 ORDER BY destination, number').all();
  res.json({ trucks });
});

router.post('/trucks', requirePerm('dispatch.manage'), (req, res) => {
  const b = req.body || {};
  const number = String(b.number || '').trim().toUpperCase();
  const destination = String(b.destination || 'NEEMRANA').trim().toUpperCase();
  if (!number) throw bad('Truck number is required.');
  const now = (typeof nowIso === 'function') ? nowIso() : new Date().toISOString();
  const ex = db.prepare('SELECT id FROM dispatch_trucks WHERE number = ?').get(number);
  if (ex) db.prepare('UPDATE dispatch_trucks SET destination = ?, active = 1 WHERE id = ?').run(destination, ex.id);
  else db.prepare('INSERT INTO dispatch_trucks (number, destination, active, created_at) VALUES (?,?,1,?)').run(number, destination, now);
  try { audit(db, req.user, ex ? 'UPDATE' : 'CREATE', 'dispatch', ex ? ex.id : 0, 'Truck ' + number + ' -> ' + destination); } catch (_) {}
  res.json({ ok: true });
});

router.delete('/trucks/:id', requirePerm('dispatch.manage'), (req, res) => {
  const id = Number(req.params.id);
  const t = db.prepare('SELECT * FROM dispatch_trucks WHERE id = ?').get(id);
  if (!t) throw bad('Truck not found.', 404);
  db.prepare('UPDATE dispatch_trucks SET active = 0 WHERE id = ?').run(id);
  try { audit(db, req.user, 'DELETE', 'dispatch', id, 'Truck ' + t.number + ' removed'); } catch (_) {}
  res.json({ ok: true });
});

/* ff-batchselect */
router.get('/batches', requirePerm('dispatch.view'), (req, res) => {
  const productId = Number((req.query || {}).productId);
  if (!Number.isInteger(productId) || productId <= 0) return res.status(400).json({ error: 'A valid productId is required.' });
  const product = db.prepare('SELECT id, active, name FROM products WHERE id = ?').get(productId);
  if (!product || Number(product.active == null ? 1 : product.active) === 0) return res.status(404).json({ error: 'Product not found.' });
  /* ff-dark220-dispatch-visible */
  const dark220 = String(product.name || '').toLowerCase().replace(/[^a-z0-9]+/g, '') === 'darksoya220gm';
  const dark220Where = dark220 ? "AND ((date(COALESCE(b.planned_date, '')) = '2026-09-21' AND UPPER(TRIM(COALESCE(b.code, ''))) = '6I1516AKS') OR (date(COALESCE(b.planned_date, '')) = '2026-09-25' AND UPPER(TRIM(COALESCE(b.code, ''))) = '6I0021AKS') OR (date(COALESCE(b.planned_date, '')) = '2026-09-26' AND UPPER(TRIM(COALESCE(b.code, ''))) = '6I0021AKS')) " : '';
  const cols = db.prepare('PRAGMA table_info(batches)').all().map((r) => String(r.name));
  const has = (name) => cols.includes(name);
  const producedTrays = has('produced_trays') ? 'COALESCE(b.produced_trays, 0)' : '0';
  const usedTrays = has('used_trays') ? 'COALESCE(b.used_trays, 0)' : '0';
  const date = has('planned_date') ? 'b.planned_date' : "''";
  const rows = db.prepare(
    'SELECT b.id, b.code, ' + date + ' planned_date, ' +
    'COALESCE(b.produced_cb, 0) produced_cb, COALESCE(b.used_cb, 0) used_cb, ' +
    producedTrays + ' produced_trays, ' + usedTrays + ' used_trays ' +
    "FROM batches b WHERE b.product_id = ? AND UPPER(COALESCE(b.status, '')) = 'COMPLETED' " +
    dark220Where +
    "AND (COALESCE(b.produced_cb, 0) - COALESCE(b.used_cb, 0) > 0 OR " + producedTrays + " - " + usedTrays + " > 0) " +
    "ORDER BY COALESCE(b.planned_date, '') ASC, b.id ASC"
  ).all(productId).map((b) => ({
    id: b.id,
    code: String(b.code || '').trim(),
    plannedDate: b.planned_date || '',
    remainingCb: Math.max(0, Number(b.produced_cb || 0) - Number(b.used_cb || 0)),
    remainingTrays: Math.max(0, Number(b.produced_trays || 0) - Number(b.used_trays || 0)),
  }));
  res.json({ batches: rows });
});
/* end ff-batchselect */

router.get('/:id', requirePerm('dispatch.view'), (req, res) => {
  const dispatch = db.prepare(DETAIL_SQL).get(Number(req.params.id));
  if (!dispatch) throw bad('Dispatch not found.', 404);
  dispatch.weekday = weekdayName(dispatch.dispatch_date);
  res.json({ dispatch, items: itemsFor(dispatch.id) });
});

/** Create a dispatch entry — validated, transactional, stock-decrementing. */
router.post('/', requirePerm('dispatch.manage'), (req, res) => {
  const b = req.body || {};
  const destination = String(b.destination || '').trim().toUpperCase();
  const truckNumber = String(b.truckNumber || '').trim().toUpperCase();
  const remarks = String(b.remarks || '').trim();
  const dispatchDate = dateOnly(String(b.dispatchDate || nowIso()));

  if (!destination) throw bad('Destination is required (NEEMRANA / MATIALA / other).');
  if (destination.length > 60) throw bad('Destination is too long.');
  if (!truckNumber) throw bad('Truck / vehicle number is required.');

  const result = tx(db, () => {
    const { lines, totals } = compute(b.items);

    for (const l of lines) {
      const inv = db.prepare('SELECT qty_cb, qty_trays FROM inventory WHERE product_id = ?').get(l.productId);
      if (!inv || inv.qty_cb < l.cartons || inv.qty_trays < l.trays) {
        throw bad(`Insufficient stock for ${l.productName}: need ${l.cartons} CB + ${l.trays} trays, have ${inv ? inv.qty_cb : 0} CB + ${inv ? inv.qty_trays : 0} trays.`, 409);
      }
    }

    const info = db.prepare(
      `INSERT INTO dispatches (code, dispatch_date, destination, truck_number, driver_name, driver_phone, invoice_no, lr_no, remarks, status,
        total_cartons, total_trays, total_bottles, carton_weight, tray_weight, gross_weight, created_by, created_at)
       VALUES ('TMP', ?, ?, ?, '', '', '', '', ?, 'DISPATCHED', ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(dispatchDate, destination, truckNumber, remarks,
      totals.totalCartons, totals.totalTrays, totals.totalBottles,
      totals.cartonWeight, totals.trayWeight, totals.grossWeight, req.user.id, nowIso());
    const id = info.lastInsertRowid;
    const code = `DSP-${String(id).padStart(4, '0')}`;
    db.prepare('UPDATE dispatches SET code = ? WHERE id = ?').run(code, id);

    const insItem = db.prepare(
      `INSERT INTO dispatch_items (dispatch_id, product_id, batch_code, cartons, trays, total_bottles, carton_weight, tray_weight, gross_weight)
       VALUES (?,?,?,?,?,?,?,?,?)`
    );
    const updInv = db.prepare('UPDATE inventory SET qty_cb = qty_cb - ?, qty_trays = qty_trays - ?, updated_at = ? WHERE product_id = ?');
            // batch-aware dispatch (FIFO across all COMPLETED batches sharing the code)
            for (const l of lines) {
              const bCode = (l.batchCode||'').trim();
              if (!bCode) {
                /* ff-stockfix2: auto-pick the oldest batch group that can cover this line,
                   so stock is ALWAYS charged to a batch (no more "dispatched but still shown"). */
                const needCb = Number(l.cartons) || 0, needTr = Number(l.trays) || 0;
                const cand = db.prepare("SELECT code FROM batches WHERE product_id = ? AND status = 'COMPLETED' " +
                  "GROUP BY code " +
                  "HAVING SUM(produced_cb - COALESCE(used_cb,0)) >= ? AND SUM(COALESCE(produced_trays,0) - COALESCE(used_trays,0)) >= ? " +
                  "ORDER BY MIN(COALESCE(planned_date,'')), MIN(id) LIMIT 1").get(l.productId, needCb, needTr);
                if (cand && cand.code) { bCode = String(cand.code).trim(); l.batchCode = bCode; }
              }
              if (!bCode) {
                /* ff-batch-required */
                const hasBatchStock = db.prepare("SELECT 1 FROM batches WHERE product_id = ? AND UPPER(COALESCE(status, '')) = 'COMPLETED' AND (COALESCE(produced_cb,0) - COALESCE(used_cb,0) > 0 OR COALESCE(produced_trays,0) - COALESCE(used_trays,0) > 0) LIMIT 1").get(l.productId);
                if (hasBatchStock) throw bad('Select a batch code for this product before dispatch.', 400);
                continue;
              }
              let bchs = db.prepare("SELECT id, produced_cb, COALESCE(used_cb,0) AS ucb, produced_trays, COALESCE(used_trays,0) AS ut FROM batches WHERE code = ? AND product_id = ? AND status = 'COMPLETED' ORDER BY planned_date ASC, id ASC").all(bCode, l.productId);
              if (Number(l.batchId) > 0) { /* ff-batch-id */
                bchs = db.prepare("SELECT id, produced_cb, COALESCE(used_cb,0) AS ucb, produced_trays, COALESCE(used_trays,0) AS ut FROM batches WHERE id = ? AND product_id = ? AND status = 'COMPLETED'").all(Number(l.batchId), l.productId);
              }
              if (!bchs.length) throw bad(`Batch ${bCode} not found for this product (or not COMPLETED yet).`, 400);
              let cbAvail = 0, traysAvail = 0;
              for (const b of bchs) { cbAvail += (b.produced_cb||0) - b.ucb; traysAvail += (b.produced_trays||0) - b.ut; }
              if (l.cartons > cbAvail) throw bad(`Batch ${bCode} only has ${cbAvail} CB left (need ${l.cartons}).`, 409);
              if (l.trays > traysAvail) throw bad(`Batch ${bCode} only has ${traysAvail} trays left (need ${l.trays}).`, 409);
              let needCb = l.cartons, needTr = l.trays;
              for (const b of bchs) {
                const takeCb = Math.min(needCb, (b.produced_cb||0) - b.ucb);
                const takeTr = Math.min(needTr, (b.produced_trays||0) - b.ut);
                if (takeCb > 0 || takeTr > 0) db.prepare('UPDATE batches SET used_cb = COALESCE(used_cb,0) + ?, used_trays = COALESCE(used_trays,0) + ? WHERE id = ?').run(takeCb, takeTr, b.id);
                needCb -= takeCb; needTr -= takeTr;
                if (needCb <= 0 && needTr <= 0) break;
              }
            }
    for (const l of lines) {
      insItem.run(id, l.productId, (l.batchCode||'').trim()||null, l.cartons, l.trays, l.totalBottles, l.cartonWeight, l.trayWeight, l.grossWeight);
      updInv.run(l.cartons, l.trays, nowIso(), l.productId);
      checkLowStock(db, l.productId);
    }

    const parts = [`${totals.totalCartons} CB`];
    if (totals.totalTrays > 0) parts.push(`${totals.totalTrays} trays`);
    audit(db, req.user, 'DISPATCH', 'dispatch', id,
      `${code}: ${truckNumber} → ${destination} — ${parts.join(' + ')}, gross ${totals.grossWeight} kg`);

    notifyRoles(db, ['dispatch_manager', 'store_manager', 'admin', 'super_admin', 'management_director'], {
      type: 'dispatch_alert',
      title: `Truck dispatched to ${destination}`,
      body: `${code} — ${parts.join(' + ')} (${totals.grossWeight} kg gross). Tap to open Dispatch.`,
      route: `/dispatch/${id}`,
      refId: id,
    });
    return { id, code, totals, weekday: weekdayName(dispatchDate) };
  });

  res.status(201).json(result);
});




/* ffDispatchVoid v2 */
/** Void a wrong dispatch (ff-dispatchfix): every line's stock goes back to inventory and to the batch it came
 *  from; the row stays in history as VOID. Logic lives in ../dispatchvoid.js — SAVEPOINT transaction, so it
 *  works on the node:sqlite wrapper (the old ff-voidfix route called better-sqlite3's db.transaction → 500). */
router.post('/:id/void', requirePerm('dispatch.manage'), (req, res) => {
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

module.exports = router;
