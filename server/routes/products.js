/** routes/products.js — Product Master (Finished Goods, carton + tray specs). */
const express = require('express');
const db = require('../db');
const { requirePerm, bad } = require('../middleware');
const { audit, nowIso } = require('../helpers');
const { syncDrumProductCatalog } = require('../drum_product_catalog');

const router = express.Router();
/* ff-active-products */
router.use((req, res, next) => {
  if (req.method !== 'GET') return next();
  const send = res.json.bind(res);
  res.json = (body) => {
    if (body && Array.isArray(body.products)) {
      const products = body.products.filter((p) => {
        try {
          const row = db.prepare('SELECT active FROM products WHERE id = ?').get(Number(p.id));
          return !row || Number(row.active == null ? 1 : row.active) !== 0;
        } catch (_) { return Number(p.active == null ? 1 : p.active) !== 0; }
      });
      return send(Object.assign({}, body, { products }));
    }
    return send(body);
  };
  next();
});
/* end ff-active-products */

router.get('/', requirePerm('products.view'), (req, res) => {
  const rows = db.prepare(
    `SELECT p.id, p.name, p.weight_per_cb, p.weight_without_cb, p.bottles_per_cb,
            p.bottles_per_tray, p.tray_weight, p.min_stock_cb, p.shelf_life_months, p.active, p.created_at,
            COALESCE(i.qty_cb,0) qty_cb, COALESCE(i.qty_trays,0) qty_trays
     FROM products p LEFT JOIN inventory i ON i.product_id = p.id
     ORDER BY p.sort_order, p.name`
  ).all();
  res.json({ products: rows });
});

function validate(body) {
  const name = String(body.name || '').trim();
  const wcb = Number(body.weightPerCb);
  const wncb = Number(body.weightWithoutCb);
  const bpc = Math.floor(Number(body.bottlesPerCb));
  const bpt = Math.floor(Number(body.bottlesPerTray ?? 0) || 0);
  const tw = bpt > 0 ? Number(body.trayWeight) : 0;
  const minStock = Math.floor(Number(body.minStockCb ?? 0));
  const shelfLifeMonths = Number(body.shelfLifeMonths ?? body.shelf_life_months ?? 24);
  if (!Number.isInteger(shelfLifeMonths) || shelfLifeMonths < 1 || shelfLifeMonths > 240) {
    throw bad('Shelf life must be a whole number of months from 1 to 240.');
  }
  if (!name) throw bad('Product name is required.');
  if (!(wcb > 0)) throw bad('Weight per CB must be greater than 0.');
  if (!(wncb > 0)) throw bad('Weight without CB must be greater than 0.');
  if (!(bpc > 0)) throw bad('Bottles per CB must be a positive integer.');
  if (wncb > wcb) throw bad('Weight without CB cannot exceed weight per CB.');
  if (bpt < 0) throw bad('Bottles per tray cannot be negative.');
  if (bpt > 0 && !(tw > 0)) throw bad('Tray weight must be greater than 0 for tray-packed products.');
  if (!(minStock >= 0)) throw bad('Minimum stock must be 0 or more.');
  return { name, wcb, wncb, bpc, bpt, tw, minStock, shelfLifeMonths };
}

router.post('/', requirePerm('products.manage'), (req, res) => {
  const v = validate(req.body || {});
  const exists = db.prepare('SELECT id FROM products WHERE lower(name)=lower(?)').get(v.name);
  if (exists) throw bad('A product with this name already exists.', 409);
  const legacyDrumProduct = db.prepare(`
    SELECT shelf_life_months FROM drum_products
     WHERE name = ? COLLATE NOCASE AND master_product_id IS NULL
     ORDER BY id LIMIT 1
  `).get(v.name);
  const legacyShelfLife = Number(legacyDrumProduct && legacyDrumProduct.shelf_life_months);
  const shelfLifeMonths = Number.isInteger(legacyShelfLife) && legacyShelfLife >= 1 && legacyShelfLife <= 240
    ? legacyShelfLife
    : v.shelfLifeMonths;
  const info = db.prepare(
    `INSERT INTO products (name, weight_per_cb, weight_without_cb, bottles_per_cb, bottles_per_tray, tray_weight, price, min_stock_cb, shelf_life_months, active, created_at)
     VALUES (?,?,?,?,?,?,0,?,?,1,?)`
  ).run(v.name, v.wcb, v.wncb, v.bpc, v.bpt, v.tw, v.minStock, shelfLifeMonths, nowIso());
  db.prepare('INSERT INTO inventory (product_id, qty_cb, qty_trays, qty_loose, updated_at) VALUES (?,0,0,0,?)')
    .run(info.lastInsertRowid, nowIso());
  syncDrumProductCatalog(db);
  audit(db, req.user, 'CREATE', 'product', info.lastInsertRowid, `Created product "${v.name}"`);
  res.status(201).json({ id: Number(info.lastInsertRowid) });
});

router.put('/:id', requirePerm('products.manage'), (req, res) => {
  const id = Number(req.params.id);
  const prod = db.prepare('SELECT * FROM products WHERE id=?').get(id);
  if (!prod) throw bad('Product not found.', 404);
  const body = req.body || {};
  const v = validate({
    ...body,
    name: body.name ?? prod.name,
    shelfLifeMonths: body.shelfLifeMonths ?? body.shelf_life_months ?? prod.shelf_life_months,
  });
  db.prepare(
    `UPDATE products SET name=?, weight_per_cb=?, weight_without_cb=?, bottles_per_cb=?, bottles_per_tray=?, tray_weight=?, min_stock_cb=?, shelf_life_months=?, active=? WHERE id=?`
  ).run(v.name, v.wcb, v.wncb, v.bpc, v.bpt, v.tw, v.minStock, v.shelfLifeMonths, body.active === false ? 0 : 1, id);
  syncDrumProductCatalog(db);
  audit(db, req.user, 'UPDATE', 'product', id, `Updated product "${v.name}"`);
  res.json({ ok: true });
});

/** Soft-delete a product (ff-delfix v2). Inventory row is removed; history (dispatches, batches, reports) stays. */
router.delete('/:id', requirePerm('products.manage'), (req, res) => {
  const id = Number(req.params.id);
  const prod = db.prepare('SELECT id, name FROM products WHERE id = ? AND active = 1').get(id);
  if (!prod) { res.status(404).json({ error: 'Product not found.' }); return; }
  db.prepare('UPDATE products SET active = 0 WHERE id = ?').run(id);
  syncDrumProductCatalog(db);
  db.prepare('DELETE FROM inventory WHERE product_id = ?').run(id); // clear stock row too
  try { require('../helpers').audit(db, req.user, 'DELETE', 'product', id, 'Product "' + prod.name + '" deleted (soft) — inventory row removed'); } catch (_) {}
  res.json({ ok: true });
});

/** ff-product-delete-safe */
router.delete('/:id', requirePerm('products.manage'), (req, res) => {
  const id = Number(req.params.id);
  const p = db.prepare('SELECT id, name, active FROM products WHERE id = ?').get(id);
  if (!p || Number(p.active == null ? 1 : p.active) === 0) return res.status(404).json({ error: 'Product not found.' });
  const inv = db.prepare('SELECT COALESCE(qty_cb, 0) cb, COALESCE(qty_trays, 0) trays FROM inventory WHERE product_id = ?').get(id) || { cb: 0, trays: 0 };
  const b = db.prepare("SELECT COUNT(*) n FROM batches WHERE product_id = ? AND UPPER(COALESCE(status, '')) = 'COMPLETED' AND (COALESCE(produced_cb, 0) - COALESCE(used_cb, 0) > 0 OR COALESCE(produced_trays, 0) - COALESCE(used_trays, 0) > 0)").get(id);
  if (Number(inv.cb) > 0 || Number(inv.trays) > 0 || Number(b.n) > 0) return res.status(409).json({ error: 'Cannot delete a product with stock or a remaining production batch. Dispatch/use the stock first.' });
  db.prepare('UPDATE products SET active = 0 WHERE id = ?').run(id);
  syncDrumProductCatalog(db);
  try { db.prepare('DELETE FROM inventory WHERE product_id = ?').run(id); } catch (_) {}
  try { require('../helpers').audit(db, req.user, 'DELETE', 'product', id, 'Product "' + p.name + '" archived — empty stock'); } catch (_) {}
  res.json({ ok: true });
});
/* end ff-product-delete-safe */

module.exports = router;
