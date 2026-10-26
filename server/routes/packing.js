/** routes/packing.js — packing material: master, receipts, consumption, ledger, BOM. */
const express = require('express');
const db = require('../db');
const { tx } = require('../sqlite');
const { requirePerm, bad } = require('../middleware');
const { audit, nowIso, checkPackingLow, dateOnly } = require('../helpers');

const router = express.Router();

/* ffPackingArchiveV3 */
try { db.exec('CREATE TABLE IF NOT EXISTS packing_material_archives (material_id INTEGER PRIMARY KEY, name TEXT NOT NULL, deleted_at TEXT NOT NULL)'); } catch (_) {}
router.use((req, res, next) => {
  if (req.method !== 'GET' || !/\/materials\/?$/.test(String(req.originalUrl || req.url || '').split('?')[0])) return next();
  const send = res.json;
  res.json = (body) => {
    let hidden = new Set();
    try { hidden = new Set(db.prepare('SELECT material_id FROM packing_material_archives').all().map((r) => Number(r.material_id))); } catch (_) {}
    const clean = (arr) => Array.isArray(arr) ? arr.filter((r) => !hidden.has(Number(r && (r.id == null ? r.material_id : r.id)))) : arr;
    if (Array.isArray(body)) body = clean(body);
    else if (body && Array.isArray(body.materials)) body = Object.assign({}, body, { materials: clean(body.materials) });
    return send.call(res, body);
  };
  next();
});

/** Delete/archive a packing material (ff-delfix v3). BOM links removed; ledger and stock history stay. */
router.delete('/materials/:id', requirePerm('packing.manage'), (req, res) => {
  const id = Number(req.params.id);
  const mat = db.prepare('SELECT id, name FROM packing_materials WHERE id = ?').get(id);
  // A material can have packing_txns / stock-journal history with a foreign
  // key. Archive the master row instead of breaking those records. Only the
  // requested material's BOM links are removed; every ledger/history row and
  // the material's stock value remain intact.
  try { db.exec('CREATE TABLE IF NOT EXISTS packing_material_archives (material_id INTEGER PRIMARY KEY, name TEXT NOT NULL, deleted_at TEXT NOT NULL)'); } catch (_) {}
  if (!mat) {
    const old = (() => { try { return db.prepare('SELECT material_id FROM packing_material_archives WHERE material_id = ?').get(id); } catch (_) { return null; } })();
    if (old) { res.json({ ok: true, alreadyDeleted: true, archived: true }); return; }
    res.json({ ok: true, alreadyDeleted: true }); return;
  }
  for (const table of ['packing_bom', 'bom_lines', 'bom']) {
    try { db.prepare('DELETE FROM ' + table + ' WHERE material_id = ?').run(id); } catch (_) {}
  }
  try {
    db.prepare('INSERT OR REPLACE INTO packing_material_archives (material_id, name, deleted_at) VALUES (?, ?, ?)')
      .run(id, mat.name, new Date().toISOString());
  } catch (_) {}
  try { require('../helpers').audit(db, req.user, 'DELETE', 'packing', id, 'Packing material "' + mat.name + '" archived; BOM references removed; ledger preserved'); } catch (_) {}
  res.json({ ok: true, archived: true });
});

/** Delete/archive a packing material (ff-delfix v3). BOM links removed; ledger and stock history stay. */
router.delete('/:id', requirePerm('packing.manage'), (req, res) => {
  const id = Number(req.params.id);
  const mat = db.prepare('SELECT id, name FROM packing_materials WHERE id = ?').get(id);
  // A material can have packing_txns / stock-journal history with a foreign
  // key. Archive the master row instead of breaking those records. Only the
  // requested material's BOM links are removed; every ledger/history row and
  // the material's stock value remain intact.
  try { db.exec('CREATE TABLE IF NOT EXISTS packing_material_archives (material_id INTEGER PRIMARY KEY, name TEXT NOT NULL, deleted_at TEXT NOT NULL)'); } catch (_) {}
  if (!mat) {
    const old = (() => { try { return db.prepare('SELECT material_id FROM packing_material_archives WHERE material_id = ?').get(id); } catch (_) { return null; } })();
    if (old) { res.json({ ok: true, alreadyDeleted: true, archived: true }); return; }
    res.json({ ok: true, alreadyDeleted: true }); return;
  }
  for (const table of ['packing_bom', 'bom_lines', 'bom']) {
    try { db.prepare('DELETE FROM ' + table + ' WHERE material_id = ?').run(id); } catch (_) {}
  }
  try {
    db.prepare('INSERT OR REPLACE INTO packing_material_archives (material_id, name, deleted_at) VALUES (?, ?, ?)')
      .run(id, mat.name, new Date().toISOString());
  } catch (_) {}
  try { require('../helpers').audit(db, req.user, 'DELETE', 'packing', id, 'Packing material "' + mat.name + '" archived; BOM references removed; ledger preserved'); } catch (_) {}
  res.json({ ok: true, archived: true });
});

/** Delete/archive a packing material (ff-delfix v3). BOM links removed; ledger and stock history stay. */
router.delete('/packing/materials/:id', requirePerm('packing.manage'), (req, res) => {
  const id = Number(req.params.id);
  const mat = db.prepare('SELECT id, name FROM packing_materials WHERE id = ?').get(id);
  // A material can have packing_txns / stock-journal history with a foreign
  // key. Archive the master row instead of breaking those records. Only the
  // requested material's BOM links are removed; every ledger/history row and
  // the material's stock value remain intact.
  try { db.exec('CREATE TABLE IF NOT EXISTS packing_material_archives (material_id INTEGER PRIMARY KEY, name TEXT NOT NULL, deleted_at TEXT NOT NULL)'); } catch (_) {}
  if (!mat) {
    const old = (() => { try { return db.prepare('SELECT material_id FROM packing_material_archives WHERE material_id = ?').get(id); } catch (_) { return null; } })();
    if (old) { res.json({ ok: true, alreadyDeleted: true, archived: true }); return; }
    res.json({ ok: true, alreadyDeleted: true }); return;
  }
  for (const table of ['packing_bom', 'bom_lines', 'bom']) {
    try { db.prepare('DELETE FROM ' + table + ' WHERE material_id = ?').run(id); } catch (_) {}
  }
  try {
    db.prepare('INSERT OR REPLACE INTO packing_material_archives (material_id, name, deleted_at) VALUES (?, ?, ?)')
      .run(id, mat.name, new Date().toISOString());
  } catch (_) {}
  try { require('../helpers').audit(db, req.user, 'DELETE', 'packing', id, 'Packing material "' + mat.name + '" archived; BOM references removed; ledger preserved'); } catch (_) {}
  res.json({ ok: true, archived: true });
});

/* ffPackingDeleteCompatV3 */
/** Delete a packing material (ff-delfix). BOM lines removed; ledger entries stay. */
router.delete('/materials/:id', requirePerm('packing.manage'), (req, res) => {
  const id = Number(req.params.id);
  const mat = db.prepare('SELECT id, name FROM packing_materials WHERE id = ?').get(id);
  // DELETE is intentionally idempotent: a cached Packing screen can submit
  // an ID after another cleanup already removed the material. Treat that as
  // success so the stale row disappears on the following GET instead of
  // showing a misleading "Material not found" error.
  if (!mat) { res.json({ ok: true, alreadyDeleted: true }); return; }
  try { db.prepare('DELETE FROM bom_lines WHERE material_id = ?').run(id); } catch (_) {}
  try { db.prepare('DELETE FROM bom WHERE material_id = ?').run(id); } catch (_) {}
  try { db.prepare('DELETE FROM packing_materials WHERE id = ?').run(id); }
  catch (e) { res.status(409).json({ error: 'Cannot delete: material is referenced by other records.' }); return; }
  try { require('../helpers').audit(db, req.user, 'DELETE', 'packing', id, 'Packing material "' + mat.name + '" deleted'); } catch (_) {}
  res.json({ ok: true });
});

/** Delete a packing material (ff-delfix). BOM lines removed; ledger entries stay. */
router.delete('/:id', requirePerm('packing.manage'), (req, res) => {
  const id = Number(req.params.id);
  const mat = db.prepare('SELECT id, name FROM packing_materials WHERE id = ?').get(id);
  // DELETE is intentionally idempotent: a cached Packing screen can submit
  // an ID after another cleanup already removed the material. Treat that as
  // success so the stale row disappears on the following GET instead of
  // showing a misleading "Material not found" error.
  if (!mat) { res.json({ ok: true, alreadyDeleted: true }); return; }
  try { db.prepare('DELETE FROM bom_lines WHERE material_id = ?').run(id); } catch (_) {}
  try { db.prepare('DELETE FROM bom WHERE material_id = ?').run(id); } catch (_) {}
  try { db.prepare('DELETE FROM packing_materials WHERE id = ?').run(id); }
  catch (e) { res.status(409).json({ error: 'Cannot delete: material is referenced by other records.' }); return; }
  try { require('../helpers').audit(db, req.user, 'DELETE', 'packing', id, 'Packing material "' + mat.name + '" deleted'); } catch (_) {}
  res.json({ ok: true });
});

/** Delete a packing material (ff-delfix). BOM lines removed; ledger entries stay. */
router.delete('/packing/materials/:id', requirePerm('packing.manage'), (req, res) => {
  const id = Number(req.params.id);
  const mat = db.prepare('SELECT id, name FROM packing_materials WHERE id = ?').get(id);
  // DELETE is intentionally idempotent: a cached Packing screen can submit
  // an ID after another cleanup already removed the material. Treat that as
  // success so the stale row disappears on the following GET instead of
  // showing a misleading "Material not found" error.
  if (!mat) { res.json({ ok: true, alreadyDeleted: true }); return; }
  try { db.prepare('DELETE FROM bom_lines WHERE material_id = ?').run(id); } catch (_) {}
  try { db.prepare('DELETE FROM bom WHERE material_id = ?').run(id); } catch (_) {}
  try { db.prepare('DELETE FROM packing_materials WHERE id = ?').run(id); }
  catch (e) { res.status(409).json({ error: 'Cannot delete: material is referenced by other records.' }); return; }
  try { require('../helpers').audit(db, req.user, 'DELETE', 'packing', id, 'Packing material "' + mat.name + '" deleted'); } catch (_) {}
  res.json({ ok: true });
});

/* ffPackingDeleteCompatV2 */
router.get('/materials', requirePerm('packing.view'), (req, res) => {
  const lowOnly = req.query.filter === 'low';
  const rows = db.prepare(
    `SELECT pm.*, CASE WHEN pm.stock < pm.min_stock THEN 1 ELSE 0 END low
     FROM packing_materials pm ${lowOnly ? 'WHERE pm.stock < pm.min_stock' : ''}
     ORDER BY pm.category, pm.name`
  ).all();
  const summary = db.prepare(
    `SELECT COUNT(*) items,
            SUM(CASE WHEN stock < min_stock THEN 1 ELSE 0 END) low_count,
            COUNT(DISTINCT category) categories
     FROM packing_materials`
  ).get();
  res.json({ materials: rows, summary });
});

router.post('/materials', requirePerm('packing.manage'), (req, res) => {
  const b = req.body || {};
  const name = String(b.name || '').trim();
  const category = String(b.category || 'Other').trim();
  const unit = String(b.unit || 'pcs').trim();
  const stock = Number(b.stock ?? 0) || 0;
  const minStock = Number(b.minStock ?? 0) || 0;
  if (!name) throw bad('Material name is required.');
  if (stock < 0 || minStock < 0) throw bad('Stock values cannot be negative.');
  if (db.prepare('SELECT id FROM packing_materials WHERE lower(name) = lower(?)').get(name)) {
    throw bad('A material with this name already exists.', 409);
  }
  const info = db.prepare(
    `INSERT INTO packing_materials (name, category, unit, stock, min_stock, created_at) VALUES (?,?,?,?,?,?)`
  ).run(name, category, unit, stock, minStock, nowIso());
  audit(db, req.user, 'CREATE', 'packing_material', info.lastInsertRowid, `Added packing material "${name}" (${category}), opening ${stock} ${unit}`);
  res.status(201).json({ id: Number(info.lastInsertRowid) });
});

router.put('/materials/:id', requirePerm('packing.manage'), (req, res) => {
  const id = Number(req.params.id);
  const m = db.prepare('SELECT * FROM packing_materials WHERE id = ?').get(id);
  if (!m) { res.json({ ok: true, alreadyDeleted: true }); return; }
  const b = req.body || {};
  const name = String(b.name ?? m.name).trim();
  const category = String(b.category ?? m.category).trim();
  const minStock = Number(b.minStock ?? m.min_stock);
  const stock = b.stock === undefined ? m.stock : Number(b.stock);
  if (!name) throw bad('Name is required.');
  if (minStock < 0) throw bad('Minimum stock cannot be negative.');
  if (!(stock >= 0)) throw bad('Stock cannot be negative.');
  if (name.toLowerCase() !== m.name.toLowerCase()
      && db.prepare('SELECT id FROM packing_materials WHERE lower(name) = lower(?) AND id <> ?').get(name, id)) {
    throw bad('A material with this name already exists.', 409);
  }
  db.prepare('UPDATE packing_materials SET name=?, category=?, min_stock=?, stock=? WHERE id=?').run(name, category, minStock, stock, id);
    // Respond before notification fan-out so a stock edit cannot sit behind
  // a slow SQLite/user-notification write until the mobile HTTP timeout.
  res.json({ ok: true });
  // Audit is handled once by the global request middleware.
});

router.get('/ledger', requirePerm('packing.view'), (req, res) => {
  const materialId = Number(req.query.materialId) || null;
  const type = String(req.query.type || '').toUpperCase();
  const conds = [];
  const params = [];
  if (materialId) { conds.push('t.material_id = ?'); params.push(materialId); }
  if (['RECEIVED', 'CONSUMED'].includes(type)) { conds.push('t.txn_type = ?'); params.push(type); }
  const where = conds.length ? `WHERE ${conds.join(' AND ')}` : '';
  const rows = db.prepare(
    `SELECT t.*, m.name material_name, m.unit, u.name created_by_name, b.code batch_code
     FROM packing_txns t
     JOIN packing_materials m ON m.id = t.material_id
     LEFT JOIN users u ON u.id = t.created_by
     LEFT JOIN batches b ON b.id = t.batch_id
     ${where}
     ORDER BY t.created_at DESC, t.id DESC LIMIT 300`
  ).all(...params);
  res.json({ txns: rows });
});

/** Stock receipt — adds to the balance. */
router.post('/receive', requirePerm('packing.manage'), (req, res) => {
  const b = req.body || {};
  const materialId = Number(b.materialId);
  const qty = Number(b.qty);
  const reference = String(b.reference || '').trim();
  const remark = String(b.remark || '').trim();
  const date = dateOnly(String(b.date || nowIso()));
  const m = db.prepare('SELECT * FROM packing_materials WHERE id = ?').get(materialId);
  if (!m) throw bad('Material not found.', 404);
  if (!(qty > 0)) throw bad('Quantity must be greater than 0.');

  db.prepare('UPDATE packing_materials SET stock = stock + ? WHERE id = ?').run(qty, materialId);
  db.prepare(
    `INSERT INTO packing_txns (material_id, txn_type, qty, txn_date, reference, remark, batch_id, created_by, created_at)
     VALUES (?, 'RECEIVED', ?, ?, ?, ?, NULL, ?, ?)`
  ).run(materialId, qty, date, reference, remark, req.user.id, nowIso());
  audit(db, req.user, 'RECEIPT', 'packing_material', materialId, `Received ${qty} ${m.unit} of "${m.name}"${reference ? ` — ${reference}` : ''}`);
  res.json({ ok: true, balance: m.stock + qty });
});

/** Consumption — deducts from the balance. */
router.post('/consume', requirePerm('packing.manage'), (req, res) => {
  const b = req.body || {};
  const materialId = Number(b.materialId);
  const qty = Number(b.qty);
  const reference = String(b.reference || '').trim();
  const remark = String(b.remark || '').trim();
  const date = dateOnly(String(b.date || nowIso()));
  const m = db.prepare('SELECT * FROM packing_materials WHERE id = ?').get(materialId);
  if (!m) throw bad('Material not found.', 404);
  if (!(qty > 0)) throw bad('Quantity must be greater than 0.');
  if (m.stock < qty) throw bad(`Insufficient stock of ${m.name}: available ${m.stock} ${m.unit}, requested ${qty}.`, 409);

  db.prepare('UPDATE packing_materials SET stock = stock - ? WHERE id = ?').run(qty, materialId);
  db.prepare(
    `INSERT INTO packing_txns (material_id, txn_type, qty, txn_date, reference, remark, batch_id, created_by, created_at, product_id)
       VALUES (?, 'CONSUMED', ?, ?, ?, ?, NULL, ?, ?, ?)`
  ).run(materialId, qty, date, reference, remark, req.user.id, nowIso(), /* lossProductTag */ Number((req.body || {}).productId) || null);
  audit(db, req.user, 'CONSUME', 'packing_material', materialId, `Consumed ${qty} ${m.unit} of "${m.name}"${remark ? ` — ${remark}` : ''}`);
  checkPackingLow(db, materialId);
  res.json({ ok: true, balance: m.stock - qty });
});

/** Bill of Materials per finished good (composition from the supplied PDF). */
router.get('/bom', requirePerm('packing.view'), (req, res) => {
  const products = db.prepare(
    `SELECT id, name, bottles_per_cb, bottles_per_tray FROM products WHERE active = 1 ORDER BY sort_order, name`
  ).all();
  const rows = db.prepare(
    `SELECT b.product_id, m.name material, m.category, m.unit, b.qty_per_cb, b.qty_per_tray, m.stock
     FROM packing_bom b JOIN packing_materials m ON m.id = b.material_id
     ORDER BY m.name`
  ).all();
  const byProduct = {};
  for (const r of rows) (byProduct[r.product_id] ||= []).push(r);
  res.json({
    bom: products.map((p) => ({
      product: p,
      items: (byProduct[p.id] || []).map((i) => ({
        material: i.material, category: i.category, unit: i.unit,
        perCb: i.qty_per_cb, perTray: i.qty_per_tray, inStock: i.stock,
      })),
    })),
  });
});

/** ff-rawfix: raw-material recipes + auto consumption by total production qty. */
router.get('/recipes', requirePerm('raw.view'), (req, res) => {
  const recipes = db.prepare('SELECT * FROM recipes ORDER BY id').all();
  for (const r of recipes) {
    r.lines = db.prepare(
      'SELECT l.qty_per_batch, m.id material_id, m.name, m.unit, m.stock FROM recipe_lines l JOIN packing_materials m ON m.id = l.material_id WHERE l.recipe_id = ? ORDER BY l.id'
    ).all(r.id);
  }
  res.json({ recipes });
});

router.post('/recipe-consume', requirePerm('raw.manage'), (req, res) => {
  const recipeId = Number((req.body || {}).recipeId);
  const totalQty = Number((req.body || {}).totalQty);
  const remark = String((req.body || {}).remark || '').trim();
  const overrides = (req.body || {}).overrides || {};
  const recipe = db.prepare('SELECT * FROM recipes WHERE id = ?').get(recipeId);
  if (!recipe) throw bad('Recipe not found.', 404);
  if (!(totalQty > 0)) throw bad('Enter the total production quantity (e.g. 15000).');
  const batches = totalQty / recipe.batch_size;
  const lines = db.prepare(
    'SELECT l.qty_per_batch, m.id material_id, m.name, m.unit, m.stock, m.min_stock FROM recipe_lines l JOIN packing_materials m ON m.id = l.material_id WHERE l.recipe_id = ?'
  ).all(recipeId);
  if (!lines.length) throw bad('Recipe has no materials.');
  const nIso = nowIso();
  const today = dateOnly(nIso);
  const warnings = [];
  const consumed = [];
  const result = tx(db, () => {
    const upd = db.prepare('UPDATE packing_materials SET stock = stock - ? WHERE id = ?');
    const ins = db.prepare(
      "INSERT INTO packing_txns (material_id, txn_type, qty, txn_date, reference, remark, created_by, created_at) VALUES (?, 'CONSUMED', ?, ?, ?, ?, ?, ?)"
    );
    const ref = recipe.name + ' × ' + (Math.round(batches * 100) / 100) + ' batches (' + totalQty + ' ' + recipe.batch_unit + ')';
    for (const l of lines) {
      const ovRaw = overrides[l.material_id] ?? overrides[String(l.material_id)]; /* ovSkip */
      const hasOv = ovRaw !== undefined && ovRaw !== null && ovRaw !== '';
      const ov = Number(ovRaw);
      const q = hasOv && ov >= 0 ? Math.round(ov * 1000) / 1000 : Math.round(l.qty_per_batch * batches * 1000) / 1000;
      if (q <= 0) continue;
      upd.run(q, l.material_id);
      ins.run(l.material_id, q, today, ref, remark, req.user.id, nIso);
      consumed.push({ name: l.name, qty: q, unit: l.unit });
      const ns = l.stock - q;
      if (ns < 0) warnings.push(l.name + ': stock went negative (' + (Math.round(ns * 100) / 100) + ') — receive stock');
      else if (ns < l.min_stock) warnings.push(l.name + ': below minimum');
      checkPackingLow(db, l.material_id);
    }
    /* extraMats */
    const lineIds = new Set(lines.map((l) => l.material_id));
    for (const key of Object.keys(overrides)) {
      const mid = Number(key);
      if (!mid || lineIds.has(mid)) continue;
      const q = Math.round(Number(overrides[key]) * 1000) / 1000;
      if (!(q > 0)) continue;
      const m = db.prepare('SELECT id, name, unit, stock, min_stock FROM packing_materials WHERE id = ?').get(mid);
      if (!m) continue;
      upd.run(q, m.id);
      ins.run(m.id, q, today, ref, remark, req.user.id, nIso);
      consumed.push({ name: m.name, qty: q, unit: m.unit });
      const ns2 = m.stock - q;
      if (ns2 < 0) warnings.push(m.name + ': stock went negative (' + (Math.round(ns2 * 100) / 100) + ') — receive stock');
      else if (ns2 < m.min_stock) warnings.push(m.name + ': below minimum');
      checkPackingLow(db, m.id);
    }

    audit(db, req.user, 'CONSUME', 'packing', recipeId, 'Recipe consumption: ' + ref);
    return { batches: Math.round(batches * 100) / 100 };
  });
  res.json({ ok: true, batches: result.batches, consumed, warnings });
});

/** ff-rawfix4: edit a recipe — batch size + qty/batch per material (0 = remove line). */
router.put('/recipes/:id', requirePerm('raw.manage'), (req, res) => {
  const id = Number(req.params.id);
  const recipe = db.prepare('SELECT * FROM recipes WHERE id = ?').get(id);
  if (!recipe) throw bad('Recipe not found.', 404);
  const b = req.body || {};
  const batchSize = Number(b.batchSize);
  const lines = Array.isArray(b.lines) ? b.lines : [];
  tx(db, () => {
    if (batchSize > 0) db.prepare('UPDATE recipes SET batch_size = ? WHERE id = ?').run(batchSize, id);
    for (const l of lines) {
      const mid = Number(l.materialId);
      const q = Number(l.qtyPerBatch);
      if (!mid || isNaN(q)) continue;
      const ex = db.prepare('SELECT id FROM recipe_lines WHERE recipe_id = ? AND material_id = ?').get(id, mid);
      if (q <= 0) { if (ex) db.prepare('DELETE FROM recipe_lines WHERE id = ?').run(ex.id); continue; }
      if (ex) db.prepare('UPDATE recipe_lines SET qty_per_batch = ? WHERE id = ?').run(q, ex.id);
      else db.prepare('INSERT INTO recipe_lines (recipe_id, material_id, qty_per_batch) VALUES (?,?,?)').run(id, mid, q);
    }
  });
  audit(db, req.user, 'UPDATE', 'packing', id, 'Recipe "' + recipe.name + '" edited');
  res.json({ ok: true });
});

/** ff-lossfix: monthly packing loss% (factory sheet). */
function lossWholeSplit(total, weights) {
  const sumW = weights.reduce((a, b) => a + b, 0);
  if (sumW <= 0 || total <= 0) return weights.map(() => 0);
  const raw = weights.map((w) => total * w / sumW);
  const base = raw.map(Math.floor);
  let left = Math.round(total) - base.reduce((a, b) => a + b, 0);
  const order = raw.map((v, i) => [v - base[i], i]).sort((a, b) => b[0] - a[0]);
  for (let k = 0; k < order.length && left > 0; k++, left--) base[order[k][1]] += 1;
  return base;
}

function lossYm() {
  const d = new Date(Date.now() + 330 * 60 * 1000); // IST
  return d.toISOString().slice(0, 7);
}
function lossOpenMonth() {
  let m = db.prepare("SELECT ym FROM loss_months WHERE status = 'OPEN' ORDER BY ym DESC LIMIT 1").get();
  if (!m) {
    const ym = lossYm();
    db.prepare("INSERT OR IGNORE INTO loss_months (ym, status, created_at) VALUES (?, 'OPEN', ?)").run(ym, nowIso());
    m = { ym };
  }
  return m.ym;
}
function lossVals(ym) {
  const o = {};
  for (const r of db.prepare('SELECT key, value FROM loss_values WHERE ym = ?').all(ym)) o[r.key] = r.value;
  return o;
}
function lossBuild(ym) {
  const V = lossVals(ym);
  const g = (k, dflt) => (V[k] !== undefined ? V[k] : dflt);
  /* lossAddMode: manual edit = baseline; auto data AFTER the edit adds on.
     base:<key> = auto value captured at edit time. */
  const A = {}; lossBuild._autos = A;
  const gA = (k, auto) => {
    A[k] = auto;
    if (V[k] === undefined) return auto;
    const b = V['base:' + k];
    return V[k] + (b === undefined ? 0 : Math.max(0, auto - b));
  };
  const products = db.prepare('SELECT * FROM products WHERE active = 1 ORDER BY sort_order, name').all();
  const prodAgg = {};
  for (const r of db.prepare(
    "SELECT product_id, SUM(produced_cb) cb, SUM(produced_trays) tr FROM batches WHERE status='COMPLETED' AND substr(COALESCE(planned_date,''),1,7) = ? GROUP BY product_id"
  ).all(ym)) prodAgg[r.product_id] = r;
  const dispAgg = {};
  for (const r of db.prepare(
    "SELECT di.product_id pid, SUM(di.cartons) cb FROM dispatch_items di JOIN dispatches d ON d.id = di.dispatch_id WHERE substr(d.dispatch_date,1,7) = ? GROUP BY di.product_id"
  ).all(ym)) dispAgg[r.pid] = r.cb;

  const top = [];
  const actualByProduct = {}; // lossfix6-cascade
  let tProj = 0, tOpen = 0, tAct = 0, tClose = 0;
  for (const p of products) {
    const actual = Math.round(gA('act:' + p.id, (prodAgg[p.id] || {}).cb || 0));
    actualByProduct[p.id] = actual;
    const projection = g('proj:' + p.id, 0);
    const opening = g('open:' + p.id, 0);
    const oa = opening + actual;
    const adherence = projection > 0 ? Math.round(oa / projection * 1000) / 10 : 0;
    const closing = gA('close:' + p.id, Math.max(0, oa - (dispAgg[p.id] || 0)));
    top.push({ productId: p.id, name: p.name, projection, opening, actual, openingActual: oa, adherence, closing });
    tProj += projection; tOpen += opening; tAct += actual; tClose += Number(closing) || 0;
  }
  top.push({ productId: 0, name: 'Total', projection: tProj, opening: tOpen, actual: tAct, openingActual: tOpen + tAct, adherence: tProj > 0 ? Math.round((tOpen + tAct) / tProj * 1000) / 10 : 0, closing: tClose });

  // expected material usage per product (BOM × production)
  const bom = db.prepare(
    'SELECT b.product_id pid, b.material_id mid, b.qty_per_cb qc, b.qty_per_tray qt, m.name mname FROM packing_bom b JOIN packing_materials m ON m.id = b.material_id ORDER BY b.product_id, b.material_id'
  ).all();
  const expByMat = {}, expByPidMat = {};
  for (const l of bom) {
    const a = prodAgg[l.pid] || { cb: 0, tr: 0 };
    const exp = (actualByProduct[l.pid] ?? (a.cb || 0)) * l.qc + (a.tr || 0) * l.qt;
    expByPidMat[l.pid + ':' + l.mid] = exp;
    expByMat[l.mid] = (expByMat[l.mid] || 0) + exp;
  }
  // manual consumption per material this month (not batch-linked)
  const manualPidMat = {}, manualUntagged = {};
  for (const r of db.prepare(
    "SELECT product_id pid, material_id mid, SUM(qty) q FROM packing_txns WHERE txn_type='CONSUMED' AND batch_id IS NULL AND substr(txn_date,1,7) = ? GROUP BY product_id, material_id"
  ).all(ym)) {
    if (r.pid) manualPidMat[r.pid + ':' + r.mid] = r.q;
    else manualUntagged[r.mid] = (manualUntagged[r.mid] || 0) + r.q;
  }

  const sections = [];
  for (const p of products) {
    const lines = bom.filter((l) => l.pid === p.id);
    if (!lines.length) continue;
    const rows = [];
    for (const l of lines) {
      const cb = Math.round(gA('cb:' + p.id + ':' + l.mid, expByPidMat[p.id + ':' + l.mid] || 0));
      const tagged = manualPidMat[p.id + ':' + l.mid] || 0;
      const owners = bom.filter((x) => x.mid === l.mid).length;
      const untag = owners === 1 ? (manualUntagged[l.mid] || 0) : 0; // shared+untagged: no auto assignment
      const extra = Math.round(gA('extra:' + p.id + ':' + l.mid, tagged + untag));
      const total = cb + extra;
      const loss = cb > 0 ? Math.round(extra / cb * 10000) / 100 : 0;
      rows.push({ materialId: l.mid, name: l.mname, cb, extra, total, lossPct: loss });
    }
    sections.push({ productId: p.id, name: p.name, rows });
  }
  return { ym, top, sections }; // lossfix6: Actual-to-BOM cascade and Closing total
}

router.get('/loss', requirePerm('loss.view'), (req, res) => {
  const ymQ = String(req.query.ym || '').trim();
  if (ymQ) {
    const a = db.prepare('SELECT data FROM loss_archive WHERE ym = ?').get(ymQ);
    if (a) { res.json(JSON.parse(a.data)); return; }
  }
  const ym = lossOpenMonth();
  const out = lossBuild(ym);
  out.archives = db.prepare('SELECT ym FROM loss_archive ORDER BY ym DESC LIMIT 24').all().map((r) => r.ym);
  res.json(out);
});

router.put('/loss/cell', requirePerm('loss.manage'), (req, res) => {
  const key = String((req.body || {}).key || '').trim();
  const value = Number((req.body || {}).value);
  if (!/^(proj|open|act|close|cb|extra):[0-9]+(:[0-9]+)?$/.test(key) || isNaN(value)) throw bad('Bad cell.');
  const ym = lossOpenMonth();
  db.prepare('INSERT INTO loss_values (ym, key, value) VALUES (?,?,?) ON CONFLICT(ym, key) DO UPDATE SET value = excluded.value').run(ym, key, value);
  // lossfix7: Actual edits clear product CB overrides.
  const actMatch = /^act:([0-9]+)$/.exec(key);
  if (actMatch) {
    const pid = Number(actMatch[1]);
    db.prepare('DELETE FROM loss_values WHERE ym = ? AND (key LIKE ? OR key LIKE ?)')
      .run(ym, 'cb:' + pid + ':%', 'base:cb:' + pid + ':%');
  }
  /* lossAddMode: remember the auto value at edit time so future data adds on */
  if (/^(act|cb|extra|close):/.test(key)) {
    try {
      lossBuild(ym);
      const a = (lossBuild._autos || {})[key];
      if (a !== undefined) db.prepare('INSERT INTO loss_values (ym, key, value) VALUES (?,?,?) ON CONFLICT(ym, key) DO UPDATE SET value = excluded.value').run(ym, 'base:' + key, a);
    } catch (_) {}
  }
  audit(db, req.user, 'UPDATE', 'packing', 0, 'Loss sheet ' + ym + ': ' + key + ' = ' + value);
  res.json({ ok: true });
});

router.post('/loss/close', requirePerm('loss.manage'), (req, res) => {
  const ym = lossOpenMonth();
  const data = lossBuild(ym);
  tx(db, () => {
    db.prepare('INSERT OR REPLACE INTO loss_archive (ym, data, closed_at) VALUES (?,?,?)').run(ym, JSON.stringify(data), nowIso());
    db.prepare("UPDATE loss_months SET status = 'CLOSED' WHERE ym = ?").run(ym);
    const [y, m] = ym.split('-').map(Number);
    const next = new Date(Date.UTC(y, m, 1)).toISOString().slice(0, 7);
    db.prepare("INSERT OR IGNORE INTO loss_months (ym, status, created_at) VALUES (?, 'OPEN', ?)").run(next, nowIso());
    // closing → next month opening
    for (const t of data.top) {
      if (!t.productId) continue;
      const c = Number(t.closing) || 0;
      db.prepare('INSERT INTO loss_values (ym, key, value) VALUES (?,?,?) ON CONFLICT(ym, key) DO UPDATE SET value = excluded.value').run(next, 'open:' + t.productId, c);
    }
  });
  audit(db, req.user, 'UPDATE', 'packing', 0, 'Loss month ' + ym + ' closed — closings rolled to next month openings');
  res.json({ ok: true, closed: ym });
});

module.exports = router;
