/**
 * routes/adjustments.js — Stock adjustment workflow.
 *
 *  CREATE  (adjustments.create)  → status PENDING
 *  APPROVE (adjustments.approve) → applies stock movement, records approver + date
 *  REJECT  (adjustments.approve) → records rejector + date + mandatory reason
 *
 * Every transition lands in the audit log and notifies the requester.
 * Approver permission is limited to: Super Admin, Admin, Store Manager.
 */
const express = require('express');
const db = require('../db');
const { requirePerm, bad } = require('../middleware');
const { audit, nowIso, notifyRoles, notifyUsers, checkLowStock } = require('../helpers');
const { tx } = require('../sqlite');

const router = express.Router();

const APPROVER_ROLES = ['store_manager', 'admin', 'super_admin'];

const LIST_SQL = `
  SELECT a.*, p.name product_name, p.bottles_per_cb,
         ru.name requested_by_name, au.name approved_by_name, ju.name rejected_by_name
  FROM adjustments a
  JOIN products p ON p.id = a.product_id
  JOIN users ru ON ru.id = a.requested_by
  LEFT JOIN users au ON au.id = a.approved_by
  LEFT JOIN users ju ON ju.id = a.rejected_by`;

/** List (all or by status: PENDING | APPROVED | REJECTED). /history alias included. */
router.get('/', requirePerm('adjustments.view'), (req, res) => {
  const status = String(req.query.status || '').toUpperCase();
  const where = ['PENDING', 'APPROVED', 'REJECTED'].includes(status) ? 'WHERE a.status = ?' : '';
  const rows = where
    ? db.prepare(`${LIST_SQL} ${where} ORDER BY a.requested_at DESC`).all(status)
    : db.prepare(`${LIST_SQL} ORDER BY a.requested_at DESC`).all();
  res.json({ adjustments: rows });
});

router.get('/pending', requirePerm('adjustments.approve'), (req, res) => {
  res.json({ adjustments: db.prepare(`${LIST_SQL} WHERE a.status = 'PENDING' ORDER BY a.requested_at`).all() });
});

router.get('/history', requirePerm('adjustments.view'), (req, res) => {
  res.json({ adjustments: db.prepare(`${LIST_SQL} WHERE a.status != 'PENDING' ORDER BY a.requested_at DESC LIMIT 200`).all() });
});

/** Create an adjustment request. */
router.post('/', requirePerm('adjustments.create'), (req, res) => {
  const { reason } = req.body || {};
  const productId = Number(req.body.productId);
  const adjType = String(req.body.adjType || '').toUpperCase();
  const qtyCb = Math.floor(Number(req.body.qtyCb) || 0);
  const qtyLoose = Math.floor(Number(req.body.qtyLoose) || 0);

  const prod = db.prepare('SELECT * FROM products WHERE id = ? AND active = 1').get(productId);
  if (!prod) throw bad('Product not found.', 404);
  if (!['IN', 'OUT'].includes(adjType)) throw bad('Adjustment type must be IN or OUT.');
  if (qtyCb <= 0 && qtyLoose <= 0) throw bad('Enter at least 1 carton or 1 loose bottle.');
  if (!reason || !String(reason).trim()) throw bad('Reason is required.');

  if (adjType === 'OUT') {
    const inv = db.prepare('SELECT qty_cb, qty_loose FROM inventory WHERE product_id = ?').get(productId);
    if (!inv || inv.qty_cb < qtyCb || inv.qty_loose < qtyLoose) {
      throw bad(`Insufficient stock. Available: ${inv ? inv.qty_cb : 0} CB, ${inv ? inv.qty_loose : 0} loose.`, 409);
    }
  }

  const info = db.prepare(
    `INSERT INTO adjustments (code, product_id, adj_type, qty_cb, qty_loose, reason, status, requested_by, requested_at)
     VALUES (?, ?, ?, ?, ?, ?, 'PENDING', ?, ?)`
  ).run('TMP', productId, adjType, qtyCb, qtyLoose, String(reason).trim(), req.user.id, nowIso());
  const id = info.lastInsertRowid;
  const code = `ADJ-${String(1000 + Number(id)).slice(1)}`;
  db.prepare('UPDATE adjustments SET code = ? WHERE id = ?').run(code, id);

  audit(db, req.user, 'CREATE', 'adjustment', id, `${code}: ${adjType} ${qtyCb} CB + ${qtyLoose} loose of "${prod.name}" — ${reason}`);

  notifyRoles(db, APPROVER_ROLES, {
    type: 'approval_pending',
    title: 'Stock adjustment awaiting approval',
    body: `${code} — ${prod.name}: ${adjType} ${qtyCb} CB${qtyLoose ? ` + ${qtyLoose} loose` : ''} (${reason}). Tap to review.`,
    route: `/approvals?focus=${id}`,
    refId: id,
  });

  res.status(201).json(db.prepare(`${LIST_SQL} WHERE a.id = ?`).get(id));
});

/** Approve — applies the stock movement atomically. Approvers only. */
router.post('/:id/approve', requirePerm('adjustments.approve'), (req, res) => {
  const id = Number(req.params.id);
  const remarks = String((req.body || {}).remarks || '').trim();

  const adj = tx(db, () => {
    const adj = db.prepare('SELECT a.*, p.name product_name FROM adjustments a JOIN products p ON p.id=a.product_id WHERE a.id = ?').get(id);
    if (!adj) throw bad('Adjustment not found.', 404);
    if (adj.status !== 'PENDING') throw bad(`Adjustment ${adj.code} is already ${adj.status.toLowerCase()}.`, 409);

    const inv = db.prepare('SELECT qty_cb, qty_loose FROM inventory WHERE product_id = ?').get(adj.product_id) || { qty_cb: 0, qty_loose: 0 };
    let newCb = inv.qty_cb;
    let newLoose = inv.qty_loose;
    if (adj.adj_type === 'IN') {
      newCb += adj.qty_cb; newLoose += adj.qty_loose;
    } else {
      newCb -= adj.qty_cb; newLoose -= adj.qty_loose;
      if (newCb < 0 || newLoose < 0) {
        throw bad(`Cannot approve — stock would go negative (available ${inv.qty_cb} CB, ${inv.qty_loose} loose).`, 409);
      }
    }
    db.prepare('UPDATE inventory SET qty_cb = ?, qty_loose = ?, updated_at = ? WHERE product_id = ?')
      .run(newCb, newLoose, nowIso(), adj.product_id);
    db.prepare(
      `UPDATE adjustments SET status='APPROVED', approved_by=?, approved_at=?, approval_remarks=? WHERE id=?`
    ).run(req.user.id, nowIso(), remarks || null, id);

    audit(db, req.user, 'APPROVE', 'adjustment', id,
      `${adj.code}: approved ${adj.adj_type} ${adj.qty_cb} CB + ${adj.qty_loose} loose of "${adj.product_name}"${remarks ? ` — remarks: ${remarks}` : ''}`);

    notifyUsers(db, [adj.requested_by], {
      type: 'approval_decision',
      title: `Adjustment ${adj.code} approved`,
      body: `${adj.product_name}: ${adj.adj_type} ${adj.qty_cb} CB approved by ${req.user.name}. Tap to view.`,
      route: '/adjustments',
      refId: id,
    });
    if (adj.adj_type === 'OUT') checkLowStock(db, adj.product_id);
    return adj;
  });

  res.json({ ok: true, adjustment: db.prepare(`${LIST_SQL} WHERE a.id = ?`).get(adj.id) });
});

/** Reject — reason is mandatory. Approvers only. */
router.post('/:id/reject', requirePerm('adjustments.approve'), (req, res) => {
  const id = Number(req.params.id);
  const reason = String((req.body || {}).reason || '').trim();
  const remarks = String((req.body || {}).remarks || '').trim();
  if (!reason) throw bad('A rejection reason is required.');

  const adj = tx(db, () => {
    const adj = db.prepare('SELECT a.*, p.name product_name FROM adjustments a JOIN products p ON p.id=a.product_id WHERE a.id = ?').get(id);
    if (!adj) throw bad('Adjustment not found.', 404);
    if (adj.status !== 'PENDING') throw bad(`Adjustment ${adj.code} is already ${adj.status.toLowerCase()}.`, 409);

    db.prepare(
      `UPDATE adjustments SET status='REJECTED', rejected_by=?, rejected_at=?, reject_reason=?, approval_remarks=? WHERE id=?`
    ).run(req.user.id, nowIso(), reason, remarks || null, id);

    audit(db, req.user, 'REJECT', 'adjustment', id,
      `${adj.code}: rejected (${reason})${remarks ? ` — remarks: ${remarks}` : ''}`);

    notifyUsers(db, [adj.requested_by], {
      type: 'approval_decision',
      title: `Adjustment ${adj.code} rejected`,
      body: `Reason: ${reason}. Tap to view details.`,
      route: '/adjustments',
      refId: id,
    });
    return adj;
  });

  res.json({ ok: true, adjustment: db.prepare(`${LIST_SQL} WHERE a.id = ?`).get(adj.id) });
});

module.exports = router;
