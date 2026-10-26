/* ffBatchCodeFixV4: repeated batch codes allowed, edit-safe */
/* ffBatchCodeDuplicatesAllowed: same product/code/date duplicates are intentionally allowed */
/** routes/production.js — batches: custom codes, tray output, packing auto-consumption. */
const express = require('express');
const db = require('../db');
const { requirePerm, bad } = require('../middleware');
const { audit, nowIso, notifyRoles, checkPackingLow, dateOnly } = require('../helpers');
const { tx } = require('../sqlite');

const router = express.Router();

const LIST_SQL = `
  SELECT b.*, p.name product_name, p.weight_per_cb, p.bottles_per_cb, p.bottles_per_tray, p.tray_weight,
         cu.name created_by_name, su.name started_by_name, ku.name completed_by_name
  FROM batches b
  JOIN products p ON p.id = b.product_id
  LEFT JOIN users cu ON cu.id = b.created_by
  LEFT JOIN users su ON su.id = b.started_by
  LEFT JOIN users ku ON ku.id = b.completed_by`;

router.get('/batches', requirePerm('production.view'), (req, res) => {
  const status = String(req.query.status || '').toUpperCase();
  const where = ['PLANNED', 'IN_PROGRESS', 'COMPLETED'].includes(status) ? 'WHERE b.status = ?' : '';
  const rows = where
    ? db.prepare(`${LIST_SQL} ${where} ORDER BY b.created_at DESC LIMIT 200`).all(status)
    : db.prepare(`${LIST_SQL} ORDER BY b.created_at DESC LIMIT 200`).all();
  res.json({ batches: rows });
});

router.get('/batches/:id', requirePerm('production.view'), (req, res) => {
  const row = db.prepare(`${LIST_SQL} WHERE b.id = ?`).get(Number(req.params.id));
  if (!row) throw bad('Batch not found.', 404);
  res.json({ batch: row });
});

/** Consume packing per BOM for a produced batch. Must run inside a tx(). */
function consumePackingForBatch(user, batch, producedCb, producedTrays, parts) {
  const warnings = [];
  let lines = 0;
  const bom = db.prepare(
    `SELECT b.material_id, b.qty_per_cb, b.qty_per_tray, m.name, m.stock, m.min_stock
     FROM packing_bom b JOIN packing_materials m ON m.id = b.material_id WHERE b.product_id = ?`
  ).all(batch.product_id);
  const upd = db.prepare('UPDATE packing_materials SET stock = stock - ? WHERE id = ?');
  const insTxn = db.prepare(
    `INSERT INTO packing_txns (material_id, txn_type, qty, txn_date, reference, remark, batch_id, created_by, created_at)
     VALUES (?, 'CONSUMED', ?, ?, ?, '', ?, ?, ?)`
  );
  for (const row of bom) {
    const q = producedCb * row.qty_per_cb + producedTrays * row.qty_per_tray;
    if (q <= 0) continue;
    upd.run(q, row.material_id);
    insTxn.run(row.material_id, q, dateOnly(nowIso()), `Batch ${batch.code} (${parts.join(' + ')})`, batch.id, user.id, nowIso());
    const newStock = row.stock - q;
    if (newStock < 0) warnings.push(`${row.name}: stock went negative (${newStock}) — receive stock urgently`);
    else if (newStock < row.min_stock) warnings.push(`${row.name}: below minimum (${newStock} < ${row.min_stock})`);
    lines += 1;
    checkPackingLow(db, row.material_id);
  }
  return { warnings, lines };
}

/** Create a batch — batch code may be entered manually or left blank for auto.
 *  Default: creates a PLANNED batch (classic board flow).
 *  completeNow=true: ONE-STEP entry — the batch is added straight as COMPLETED,
 *  finished-goods stock is credited immediately and packing is consumed per BOM. */
router.post('/batches', requirePerm('production.manage'), (req, res) => {
  const productId = Number((req.body || {}).productId);
  const plannedCb = Math.floor(Number(req.body.plannedCb) || 0);
  const plannedDate = dateOnly(String(req.body.plannedDate || ''));
  const remarks = String(req.body.remarks || '').trim();
  const manualCode = String(req.body.code || '').trim().toUpperCase();
  const completeNow = req.body.completeNow === true;

  const prod = db.prepare('SELECT * FROM products WHERE id = ? AND active = 1').get(productId);
  if (!prod) throw bad('Product not found.', 404);
  if (manualCode && !/^[A-Z0-9][A-Z0-9\-_/]{1,29}$/.test(manualCode)) {
    throw bad('Batch code must be 2–30 characters: letters, numbers, dash, slash or underscore.');
  }
  const planUnit = String((req.body || {}).plannedUnit || (req.body || {}).planUnit || 'cb') === 'tray' ? 'tray' : 'cb';
  const plannedTraysIn = Math.max(0, Number((req.body || {}).plannedTrays) || 0);
  if (manualCode && db.prepare("SELECT id FROM batches WHERE id = -1 AND  code = ? AND product_id = ? AND COALESCE(planned_date,'') = ? AND COALESCE(plan_unit,'cb') = ?").get(manualCode, productId, plannedDate || '', planUnit)) {
    throw bad(`Batch code ${manualCode} already exists for this product on ${plannedDate} in the same unit. Same code is allowed for the other unit (CB/Tray), other products or other dates.`, 409);
  }

  /* ---- ONE-STEP: add batch directly as completed (stock in, packing out) ---- */
  if (completeNow) {
    const producedCb = Math.floor(Number(req.body.producedCb ?? req.body.plannedCb) || 0);
    const producedTrays = Math.floor(Number(req.body.producedTrays) || 0);
    const consumePacking = req.body.consumePacking !== false; // default ON
    if (producedCb <= 0 && producedTrays <= 0) throw bad('Enter produced cartons and/or trays.');
    if (!plannedDate) throw bad('Production date is required (YYYY-MM-DD).');
    if (producedTrays > 0 && prod.bottles_per_tray === 0) {
      throw bad(`${prod.name} is not tray-packed — produced trays must be 0.`);
    }

    const done = tx(db, () => {
      const info = db.prepare(
        `INSERT INTO batches (code, product_id, planned_cb, produced_cb, produced_trays, plan_unit, planned_trays, status, planned_date, remarks, created_by, created_at, completed_by, completed_at)
         VALUES ('TMP', ?, ?, ?, ?, ?, ?, 'COMPLETED', ?, ?, ?, ?, ?, ?)`
      ).run(productId, producedCb, producedCb, producedTrays, planUnit, plannedTraysIn, plannedDate, remarks, req.user.id, nowIso(), req.user.id, nowIso());
  db.prepare("UPDATE batches SET plan_unit = ?, planned_trays = ? WHERE id = last_insert_rowid()").run(planUnit, plannedTraysIn);
      const id = info.lastInsertRowid;
      const code = manualCode || `B-${2600 + Number(id)}`;
      db.prepare('UPDATE batches SET code = ? WHERE id = ?').run(code, id);
      db.prepare(
        `INSERT INTO inventory (product_id, qty_cb, qty_trays, updated_at) VALUES (?,?,?,?)
         ON CONFLICT(product_id) DO UPDATE SET qty_cb = qty_cb + ?, qty_trays = qty_trays + ?, updated_at = ?`
      ).run(productId, producedCb, producedTrays, nowIso(), producedCb, producedTrays, nowIso());

      const parts = [];
      if (producedCb > 0) parts.push(`${producedCb} CB`);
      if (producedTrays > 0) parts.push(`${producedTrays} trays`);
      const batch = { id, code, product_id: productId, product_name: prod.name };

      audit(db, req.user, 'CREATE', 'batch', id, `${code}: ${prod.name} — ${parts.join(' + ')} produced on ${plannedDate}`);
      audit(db, req.user, 'COMPLETE', 'batch', id, `${code}: ${parts.join(' + ')} of "${prod.name}" into stock`);

      let packing = { warnings: [], lines: 0 };
      if (consumePacking) packing = consumePackingForBatch(req.user, batch, producedCb, producedTrays, parts);

      notifyRoles(
        db,
        ['production_manager', 'store_manager', 'dispatch_manager', 'admin', 'super_admin', 'management_director'],
        {
          type: 'production_completed',
          title: 'Production batch completed',
          body: `${code} — ${prod.name}: ${parts.join(' + ')} produced and moved to stock. Tap for batch details.`,
          route: `/production/batches/${id}`,
          refId: id,
        }
      );
      return { id, code, packing };
    });

    return res.status(201).json({
      ok: true,
      id: done.id,
      code: done.code,
      batch: db.prepare(`${LIST_SQL} WHERE b.id = ?`).get(done.id),
      packing: done.packing,
    });
  }

  /* ---- classic planned flow (batch board) ---- */
  if (plannedCb <= 0) throw bad('Planned quantity must be at least 1 CB.');
  if (!plannedDate) throw bad('Planned date is required (YYYY-MM-DD).');

  const planUnitV5 = String((req.body || {}).plannedUnit || (req.body || {}).planUnit || 'cb') === 'tray' ? 'tray' : 'cb';
  const planTraysV5 = Math.floor(Number((req.body || {}).plannedTrays) || 0);
  let result;
  try { result = tx(db, () => {
    const info = db.prepare(
      `INSERT INTO batches (code, product_id, planned_cb, planned_trays, plan_unit, status, planned_date, remarks, created_by, created_at)
       VALUES ('TMP', ?, ?, ?, ?, 'PLANNED', ?, ?, ?, ?)`
    ).run(productId, plannedCb, planTraysV5, planUnitV5, plannedDate, remarks, req.user.id, nowIso());
    const id = info.lastInsertRowid;
    const code = manualCode || `B-${2600 + Number(id)}`;
    db.prepare('UPDATE batches SET code = ? WHERE id = ?').run(code, id);
    return { id, code };
  }); } catch (e) { if (/UNIQUE constraint failed: batches/.test(String((e && e.message) || e))) throw bad('Eh code is product te is date layi pehla hi hai (same unit). Same code sirf dooji unit (CB/Tray), dooje product ja dooji date layi allowed hai.', 409); throw e; }

  audit(db, req.user, 'CREATE', 'batch', result.id, `${result.code}: ${prod.name} × ${plannedCb} CB planned for ${plannedDate}`);
  notifyRoles(db, ['production_manager', 'production_supervisor'], {
    type: 'info', title: `New batch planned: ${result.code}`,
    body: `${prod.name} — ${plannedCb} CB planned for ${plannedDate}. Tap to open Production.`,
    route: `/production/batches/${result.id}`, refId: result.id,
  });
  res.status(201).json(result);
});

/** Peek the next auto batch code (for the form hint). */
router.get('/next-code', requirePerm('production.manage'), (req, res) => {
  const maxId = db.prepare('SELECT COALESCE(MAX(id),0) v FROM batches').get().v;
  res.json({ nextCode: `B-${2600 + maxId + 1}` });
});

router.post('/batches/:id/start', requirePerm('production.execute'), (req, res) => {
  const id = Number(req.params.id);
  const batch = db.prepare('SELECT b.*, p.name product_name FROM batches b JOIN products p ON p.id=b.product_id WHERE b.id = ?').get(id);
  if (!batch) throw bad('Batch not found.', 404);
  if (batch.status !== 'PLANNED') throw bad(`Batch ${batch.code} is ${batch.status.toLowerCase()} — only planned batches can be started.`, 409);

  db.prepare(`UPDATE batches SET status='IN_PROGRESS', started_by=?, started_at=? WHERE id=?`).run(req.user.id, nowIso(), id);
  audit(db, req.user, 'START', 'batch', id, `${batch.code} started on line`);
  notifyRoles(db, ['production_manager'], {
    type: 'info', title: `Batch started: ${batch.code}`,
    body: `${batch.product_name} — started by ${req.user.name}. Tap to view.`,
    route: `/production/batches/${id}`, refId: id,
  });
  res.json({ ok: true });
});

/** Complete: record CB (+trays for tray products), update stock, optionally consume packing per BOM. */
router.post('/batches/:id/complete', requirePerm('production.execute'), (req, res) => {
  const id = Number(req.params.id);
  const producedCb = Math.floor(Number(req.body.producedCb) || 0);
  const producedTrays = Math.floor(Number(req.body.producedTrays) || 0);
  const consumePacking = req.body.consumePacking !== false; // default ON
  if (producedCb <= 0 && producedTrays <= 0) throw bad('Enter produced cartons and/or trays.');

  const outcome = tx(db, () => {
    const batch = db.prepare('SELECT b.*, p.name product_name FROM batches b JOIN products p ON p.id=b.product_id WHERE b.id = ?').get(id);
    if (!batch) throw bad('Batch not found.', 404);
    if (batch.status !== 'IN_PROGRESS') throw bad(`Batch ${batch.code} is ${batch.status.toLowerCase()} — start it before completing.`, 409);
    const prod = db.prepare('SELECT * FROM products WHERE id = ?').get(batch.product_id);
    if (producedTrays > 0 && prod.bottles_per_tray === 0) {
      throw bad(`${prod.name} is not tray-packed — produced trays must be 0.`);
    }

    db.prepare(`UPDATE batches SET status='COMPLETED', produced_cb=?, produced_trays=?, completed_by=?, completed_at=? WHERE id=?`)
      .run(producedCb, producedTrays, req.user.id, nowIso(), id);
    db.prepare(
      `INSERT INTO inventory (product_id, qty_cb, qty_trays, updated_at) VALUES (?,?,0,?)
       ON CONFLICT(product_id) DO UPDATE SET qty_cb = qty_cb + ?, qty_trays = qty_trays + ?, updated_at = ?`
    ).run(batch.product_id, producedCb, nowIso(), producedCb, producedTrays, nowIso());

    const parts = [];
    if (producedCb > 0) parts.push(`${producedCb} CB`);
    if (producedTrays > 0) parts.push(`${producedTrays} trays`);
    audit(db, req.user, 'COMPLETE', 'batch', id, `${batch.code}: ${parts.join(' + ')} of "${batch.product_name}" into stock`);

    /* packing material auto-consumption per BOM */
    let packing = { warnings: [], lines: 0 };
    if (consumePacking) packing = consumePackingForBatch(req.user, batch, producedCb, producedTrays, parts);
    const { warnings, lines } = packing;

    notifyRoles(
      db,
      ['production_manager', 'store_manager', 'dispatch_manager', 'admin', 'super_admin', 'management_director'],
      {
        type: 'production_completed',
        title: 'Production batch completed',
        body: `${batch.code} — ${batch.product_name}: ${parts.join(' + ')} produced and moved to stock. Tap for batch details.`,
        route: `/production/batches/${id}`,
        refId: id,
      }
    );
    return { batch, warnings, lines };
  });

  res.json({
    ok: true,
    batch: db.prepare(`${LIST_SQL} WHERE b.id = ?`).get(id),
    packing: { lines: outcome.lines, warnings: outcome.warnings },
  });
});

/** Edit a batch.
 *  PLANNED  → full edit, no stock effect.
 *  COMPLETED→ code/remarks/date + produced quantities; finished-goods stock moves by the difference.
 *  IN_PROGRESS → blocked (finish or delete it first). */
router.put('/batches/:id', requirePerm('production.manage'), (req, res) => {
  const id = Number(req.params.id);
  const batch = db.prepare('SELECT * FROM batches WHERE id = ?').get(id);
  if (!batch) throw bad('Batch not found.', 404);
  if (batch.status === 'IN_PROGRESS') {
    throw bad(`Batch ${batch.code} is in progress — it can be edited only while planned or after completion.`, 409);
  }

  const remarks = String(req.body.remarks ?? batch.remarks).trim();
  const plannedDate = dateOnly(String(req.body.plannedDate || '')) || batch.planned_date;
  const code = (String(req.body.code ?? batch.code).trim().toUpperCase()) || batch.code;
  if (!/^[A-Z0-9][A-Z0-9\-_/]{1,29}$/.test(code)) {
    throw bad('Batch code must be 2–30 characters: letters, numbers, dash, slash or underscore.');
  }
  {
    const targetProductId = Number((req.body || {}).productId) || batch.product_id;
    const editUnit = String((req.body || {}).plannedUnit || (req.body || {}).planUnit || 'cb') === 'tray' ? 'tray' : (String(batch.plan_unit) === 'tray' ? 'tray' : 'cb');
    const editTraysV5 = Math.floor(Number((req.body || {}).plannedTrays) || (String(batch.plan_unit) === 'tray' ? (Number(batch.planned_trays) || 0) : 0));
    if (db.prepare("SELECT id FROM batches WHERE id = -1 AND  code = ? AND product_id = ? AND COALESCE(planned_date,'') = COALESCE(?,'') AND COALESCE(plan_unit,'cb') = ? AND id <> ?").get(code, targetProductId, plannedDate, editUnit, id)) {
      throw bad(`Batch code ${code} already exists for this product on that date in the same unit. Same code is allowed for the other unit (CB/Tray), other products or other dates.`, 409);
    }
  }

  if (batch.status === 'PLANNED') {
    const productId = Number(req.body.productId) || batch.product_id;
    const plannedCb = Math.floor(Number(req.body.plannedCb) || 0);
    const prod = db.prepare('SELECT * FROM products WHERE id = ? AND active = 1').get(productId);
    if (!prod) throw bad('Product not found.', 404);
    if (plannedCb <= 0) throw bad('Planned quantity must be at least 1 CB.');
    db.prepare('UPDATE batches SET product_id=?, planned_cb=?, planned_trays=?, plan_unit=?, planned_date=?, remarks=?, code=? WHERE id=?')
      .run(productId, plannedCb, editTraysV5, editUnit, plannedDate, remarks, code, id);
    audit(db, req.user, 'UPDATE', 'batch', id, `${batch.code} edited → ${code}: ${prod.name} × ${plannedCb} CB for ${plannedDate}`);
    return res.json({ ok: true, id, code });
  }

  // COMPLETED — adjust produced quantities; stock moves by the difference
  const prod = db.prepare('SELECT * FROM products WHERE id = ?').get(batch.product_id);
  const newCb = Math.floor(Number(req.body.producedCb ?? batch.produced_cb) || 0);
  const newTrays = Math.floor(Number(req.body.producedTrays ?? batch.produced_trays) || 0);
  if (newCb <= 0 && newTrays <= 0) throw bad('Produced cartons and trays cannot both be 0.');
  if (newTrays > 0 && prod.bottles_per_tray === 0) throw bad(`${prod.name} is not tray-packed — trays are not accepted.`);
  const dCb = newCb - batch.produced_cb;
  const dTrays = newTrays - batch.produced_trays;
  /* ffBatchGuard:edit */ { const g = require('../batchrecon').editBlock(batch, newCb, newTrays); if (g) throw bad(g, 409); }
  const inv = db.prepare('SELECT qty_cb, qty_trays FROM inventory WHERE product_id = ?').get(batch.product_id) || { qty_cb: 0, qty_trays: 0 };
  if (inv.qty_cb + dCb < 0 || inv.qty_trays + dTrays < 0) {
    throw bad(`Cannot set produced to ${newCb} CB / ${newTrays} trays: only ${inv.qty_cb} CB / ${inv.qty_trays} trays in stock (some already dispatched). Correct the stock in Inventory first.`, 409);
  }
  tx(db, () => {
    db.prepare('UPDATE inventory SET qty_cb = qty_cb + ?, qty_trays = qty_trays + ?, updated_at = ? WHERE product_id = ?')
      .run(dCb, dTrays, nowIso(), batch.product_id);
    db.prepare('UPDATE batches SET produced_cb=?, produced_trays=?, planned_date=?, remarks=?, code=? WHERE id=?')
      .run(newCb, newTrays, plannedDate, remarks, code, id);
  });
  const sign = (n, unit) => `${n >= 0 ? '+' : ''}${n} ${unit}`;
  audit(db, req.user, 'UPDATE', 'batch', id,
    `${batch.code} edited → ${code}: produced ${batch.produced_cb} CB / ${batch.produced_trays} trays → ${newCb} CB / ${newTrays} trays (stock ${sign(dCb, 'CB')}, ${sign(dTrays, 'trays')})`);
  res.json({ ok: true, id, code });
});

/** Delete a batch.
 *  PLANNED / IN_PROGRESS → free delete (no stock or packing effects yet).
 *  COMPLETED → reverses its produced stock and its packing consumption, then deletes.
 *  Blocked with a clear message if some produced stock is already gone (dispatched/adjusted). */
router.delete('/batches/:id', requirePerm('production.manage'), (req, res) => {
  const id = Number(req.params.id);
  const batch = db.prepare('SELECT b.*, p.name product_name FROM batches b JOIN products p ON p.id = b.product_id WHERE b.id = ?').get(id);
  if (!batch) throw bad('Batch not found.', 404);

  if (batch.status === 'COMPLETED') {
    /* ffBatchGuard:delete */ { const g = require('../batchrecon').deleteBlock(batch); if (g) throw bad(g, 409); }
    const inv = db.prepare('SELECT qty_cb, qty_trays FROM inventory WHERE product_id = ?').get(batch.product_id) || { qty_cb: 0, qty_trays: 0 };
    if (inv.qty_cb < batch.produced_cb || inv.qty_trays < batch.produced_trays) {
      throw bad(`Cannot delete ${batch.code}: it produced ${batch.produced_cb} CB / ${batch.produced_trays} trays but only ${inv.qty_cb} CB / ${inv.qty_trays} trays are in stock (some already dispatched or adjusted). Set the stock in Inventory first, then delete.`, 409);
    }
    tx(db, () => {
      db.prepare('UPDATE inventory SET qty_cb = qty_cb - ?, qty_trays = qty_trays - ?, updated_at = ? WHERE product_id = ?')
        .run(batch.produced_cb, batch.produced_trays, nowIso(), batch.product_id);
      for (const t of db.prepare(`SELECT * FROM packing_txns WHERE batch_id = ? AND txn_type = 'CONSUMED'`).all(id)) {
        db.prepare('UPDATE packing_materials SET stock = stock + ? WHERE id = ?').run(t.qty, t.material_id);
      }
      db.prepare('DELETE FROM packing_txns WHERE batch_id = ?').run(id);
      db.prepare('DELETE FROM batches WHERE id = ?').run(id);
    });
    audit(db, req.user, 'DELETE', 'batch', id,
      `${batch.code} deleted — ${batch.produced_cb} CB + ${batch.produced_trays} trays removed from stock; its packing consumption was reversed`);
    return res.json({ ok: true });
  }

  db.prepare('DELETE FROM batches WHERE id = ?').run(id);
  audit(db, req.user, 'DELETE', 'batch', id, `${batch.code} (${batch.product_name} × ${batch.planned_cb} CB) deleted`);
  res.json({ ok: true });
});

module.exports = router;
