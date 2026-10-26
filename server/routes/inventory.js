/** routes/inventory.js — finished goods stock (cartons + trays) + goods receipt. */
const express = require('express');
const db = require('../db');
const { requirePerm, bad } = require('../middleware');
const { audit, nowIso, notifyRoles } = require('../helpers');

const router = express.Router();
/* ff-active-inventory-products */
router.use((req, res, next) => {
  if (req.method !== 'GET') return next();
  const send = res.json.bind(res);
  res.json = (body) => {
    if (body && Array.isArray(body.items)) {
      const items = body.items.filter((item) => {
        if (item.product_id == null) return true;
        try {
          const p = db.prepare('SELECT active FROM products WHERE id = ?').get(Number(item.product_id));
          return !p || Number(p.active == null ? 1 : p.active) !== 0;
        } catch (_) { return Number(item.active == null ? 1 : item.active) !== 0; }
      });
      return send(Object.assign({}, body, { items }));
    }
    return send(body);
  };
  next();
});
/* end ff-active-inventory-products */

function rowSql(where = '') {
  return `
    SELECT p.id product_id, p.name, p.weight_per_cb, p.weight_without_cb, p.bottles_per_cb,
           p.bottles_per_tray, p.tray_weight, p.min_stock_cb,
           i.qty_cb, i.qty_trays, i.updated_at,
           (i.qty_cb * p.bottles_per_cb + i.qty_trays * p.bottles_per_tray) total_bottles,
           ROUND(i.qty_cb * p.weight_per_cb + i.qty_trays * p.tray_weight, 2) gross_kg,
           CASE WHEN i.qty_cb < p.min_stock_cb THEN 1 ELSE 0 END low
    FROM inventory i JOIN products p ON p.id = i.product_id
    WHERE p.active = 1 ${where}
    ORDER BY p.sort_order, p.name`;
}

router.get('/', requirePerm('inventory.view'), (req, res) => {
  const lowOnly = req.query.filter === 'low';
  const rows = db.prepare(rowSql(lowOnly ? 'AND i.qty_cb < p.min_stock_cb' : '')).all();
  const summary = db.prepare(
    `SELECT COALESCE(SUM(qty_cb),0) total_cb,
            COALESCE(SUM(qty_trays),0) total_trays,
            COALESCE(SUM(qty_cb * p.bottles_per_cb + qty_trays * p.bottles_per_tray),0) total_bottles,
            SUM(CASE WHEN qty_cb < min_stock_cb THEN 1 ELSE 0 END) low_count
     FROM inventory i JOIN products p ON p.id = i.product_id WHERE p.active = 1`
  ).get();
  res.json({ items: rows, summary });
});

/** Goods receipt (authorized roles only — store manager / admin+). */
router.post('/receipt', requirePerm('inventory.manage'), (req, res) => {
  const { productId, note } = req.body || {};
  const cb = Math.floor(Number(req.body.qtyCb) || 0);
  const trays = Math.floor(Number(req.body.qtyTrays) || 0);
  const prod = db.prepare('SELECT * FROM products WHERE id = ? AND active = 1').get(Number(productId));
  if (!prod) throw bad('Product not found.', 404);
  if (cb <= 0 && trays <= 0) throw bad('Enter at least 1 carton or 1 tray.');
  if (trays > 0 && prod.bottles_per_tray === 0) throw bad(`${prod.name} is not tray-packed — trays are not accepted.`);

  db.prepare(
    `INSERT INTO inventory (product_id, qty_cb, qty_trays, updated_at) VALUES (?,?,?,?)
     ON CONFLICT(product_id) DO UPDATE SET qty_cb = qty_cb + ?, qty_trays = qty_trays + ?, updated_at = ?`
  ).run(prod.id, cb, trays, nowIso(), cb, trays, nowIso());

  const parts = [];
  if (cb > 0) parts.push(`${cb} CB`);
  if (trays > 0) parts.push(`${trays} trays`);
  audit(db, req.user, 'RECEIPT', 'inventory', prod.id, `Received ${parts.join(' + ')} of "${prod.name}"${note ? ` — ${note}` : ''}`);
  notifyRoles(db, ['store_manager', 'admin', 'super_admin'], {
    type: 'info',
    title: `Stock received: ${prod.name}`,
    body: `${parts.join(' + ')} added to inventory. Tap to open Inventory.`,
    route: '/inventory',
    refId: prod.id,
  });
  res.json({ ok: true });
});

/** Set exact stock (opening stock entry / correction) — replaces current quantities. */
router.put('/stock', requirePerm('inventory.manage'), (req, res) => {
  const prod = db.prepare('SELECT * FROM products WHERE id = ? AND active = 1').get(Number((req.body || {}).productId));
  if (!prod) throw bad('Product not found.', 404);
  const cb = Math.floor(Number(req.body.qtyCb));
  const trays = Math.floor(Number(req.body.qtyTrays) || 0);
  if (!(cb >= 0)) throw bad('Cartons must be 0 or more.');
  if (!(trays >= 0)) throw bad('Trays must be 0 or more.');
  if (trays > 0 && prod.bottles_per_tray === 0) throw bad(`${prod.name} is not tray-packed — trays are not accepted.`);
  const before = db.prepare('SELECT qty_cb, qty_trays FROM inventory WHERE product_id = ?').get(prod.id);
  db.prepare(
    `INSERT INTO inventory (product_id, qty_cb, qty_trays, updated_at) VALUES (?,?,?,?)
     ON CONFLICT(product_id) DO UPDATE SET qty_cb = ?, qty_trays = ?, updated_at = ?`
  ).run(prod.id, cb, trays, nowIso(), cb, trays, nowIso());
  const note = String(req.body.note || '').trim();
  audit(db, req.user, 'UPDATE', 'inventory', prod.id,
    `Stock set for "${prod.name}": ${before ? `${before.qty_cb} CB + ${before.qty_trays} trays` : 'none'} → ${cb} CB + ${trays} trays${note ? ` — ${note}` : ''}`);
  res.json({ ok: true });
});

const { xlsxBuffer } = require('../xlsx');

router.get('/stock.xlsx', requirePerm('inventory.view'), (req, res) => {
  const rows = db.prepare(rowSql()).all();
  const data = rows.map((r) => [
    r.name, r.qty_cb, r.qty_trays, r.bottles_per_cb, r.bottles_per_tray, r.total_bottles, r.gross_kg, r.min_stock_cb,
    r.low ? 'LOW' : 'OK',
  ]);
  const buf = xlsxBuffer(
    ['Product', 'Cartons (CB)', 'Trays', 'Bottles / CB', 'Bottles / Tray', 'Total Bottles', 'Gross kg', 'Min (CB)', 'Status'],
    data,
    'Stock'
  );
  audit(db, req.user, 'EXPORT', 'inventory', '0', 'Stock report exported to Excel');
  res.setHeader('content-type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('content-disposition', `attachment; filename="flavorflow-stock-${new Date().toISOString().slice(0, 10)}.xlsx"`);
  res.end(buf);
});

module.exports = router;
