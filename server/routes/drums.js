'use strict';

const express = require('express');
const db = require('../db');
const { requirePerm, bad } = require('../middleware');
const { audit, nowIso } = require('../helpers');
const { tx } = require('../sqlite');
const { parseIsoDate, addMonths, normalizePackagingType, normalizeGrossWeight } = require('../drum_utils');

const router = express.Router();
const FILL_SELECT = `
  SELECT f.id, f.plant_id, pl.name AS plant_name, f.fill_number, f.batch_id,
         b.batch_code, b.product_id, p.name AS product_name,
         b.manufacturing_date, b.expiry_date, b.shelf_life_months,
         f.packaging_type, f.gross_weight_kg, f.status, f.created_at,
         f.dispatched_at
    FROM drum_fills f
    JOIN drum_plants pl ON pl.id = f.plant_id
    JOIN drum_batches b ON b.id = f.batch_id
    JOIN drum_products p ON p.id = b.product_id`;

function positiveId(value, label) {
  const id = Number(value);
  if (!Number.isInteger(id) || id <= 0) throw bad(`${label} is required.`);
  return id;
}

function shelfLifeMonths(value) {
  const months = Number(value);
  if (!Number.isInteger(months) || months < 1 || months > 240) {
    throw bad('Shelf life must be a whole number of months from 1 to 240.');
  }
  return months;
}

function validDate(value, label) {
  const date = String(value || '').trim();
  if (!parseIsoDate(date)) throw bad(`${label} must be a valid YYYY-MM-DD date.`);
  return date;
}

function validFillWeights(body) {
  const source = body.grossWeightsKg ?? body.weightsKg;
  if (!Array.isArray(source) || source.length < 1 || source.length > 500) {
    throw bad('Provide between 1 and 500 individual gross drum weights.');
  }
  try {
    return source.map((value) => normalizeGrossWeight(value));
  } catch (error) {
    throw bad(error.message);
  }
}

function validFillNumberRange(body, weightCount) {
  const fromValue = body.fillNumberFrom ?? body.fill_number_from;
  const toValue = body.fillNumberTo ?? body.fill_number_to;
  if (fromValue === undefined && toValue === undefined) return null;
  if (fromValue == null || toValue == null) throw bad('Enter both the first and last drum number.');

  const from = Number(fromValue);
  const to = Number(toValue);
  if (!Number.isSafeInteger(from) || from <= 0 || !Number.isSafeInteger(to) || to <= 0) {
    throw bad('Drum numbers must be positive whole numbers.');
  }
  if (to < from) throw bad('Last drum number cannot be less than the first drum number.');
  if (!Number.isSafeInteger(to + 1)) throw bad('Drum number range is too large.');

  const count = to - from + 1;
  if (count > 500) throw bad('A single fill can include at most 500 numbered drums.');
  if (count !== weightCount) {
    throw bad(`Drum numbers ${from}–${to} cover ${count} drums; enter one gross weight for each drum.`);
  }
  return { from, to };
}

function positiveDrumCount(value) {
  const count = Number(value);
  if (!Number.isSafeInteger(count) || count <= 0) throw bad('Drum count must be a positive whole number.');
  return count;
}

function positiveAggregateWeight(value) {
  const weight = Number(value);
  if (!Number.isFinite(weight) || weight <= 0 || weight > 100000000) {
    throw bad('Total gross weight must be greater than 0 kg and at most 100,000,000 kg.');
  }
  return Math.round(weight * 1000) / 1000;
}

function rowsForDispatch(dispatchId) {
  return db.prepare(`${FILL_SELECT}
      JOIN drum_dispatch_items di ON di.fill_id = f.id
     WHERE di.dispatch_id = ?
     ORDER BY f.fill_number`).all(dispatchId);
}

/** Separate drum product catalog; it does not alter the bottled/carton products table. */
router.get('/products', requirePerm('inventory.view'), (_req, res) => {
  const products = db.prepare(
    'SELECT id, code, name, shelf_life_months, active, created_at, updated_at FROM drum_products ORDER BY name COLLATE NOCASE'
  ).all();
  res.json({ products });
});

router.post('/products', requirePerm('inventory.manage'), (req, res) => {
  const body = req.body || {};
  const name = String(body.name || '').trim();
  const code = String(body.code || '').trim().toUpperCase() || null;
  const months = shelfLifeMonths(body.shelfLifeMonths ?? body.shelf_life_months);
  if (!name || name.length > 120) throw bad('Product name is required and must be 120 characters or fewer.');
  if (code && code.length > 40) throw bad('Product code must be 40 characters or fewer.');
  if (db.prepare('SELECT id FROM drum_products WHERE name = ? COLLATE NOCASE').get(name)) {
    throw bad('A drum product with that name already exists.', 409);
  }
  if (code && db.prepare('SELECT id FROM drum_products WHERE code = ?').get(code)) {
    throw bad('A drum product with that code already exists.', 409);
  }
  const now = nowIso();
  const result = db.prepare(
    'INSERT INTO drum_products (code, name, shelf_life_months, active, created_at, updated_at) VALUES (?, ?, ?, 1, ?, ?)'
  ).run(code, name, months, now, now);
  const product = db.prepare('SELECT id, code, name, shelf_life_months, active FROM drum_products WHERE id = ?').get(Number(result.lastInsertRowid));
  try { audit(db, req.user, 'CREATE', 'drum_product', product.id, `${name}; shelf life ${months} months`); } catch (_) {}
  res.status(201).json({ product });
});

/** Changing a product shelf life only affects batches created from now on. */
router.put('/products/:id', requirePerm('inventory.manage'), (req, res) => {
  const id = positiveId(req.params.id, 'Product ID');
  const months = shelfLifeMonths(req.body && (req.body.shelfLifeMonths ?? req.body.shelf_life_months));
  const product = db.prepare('SELECT id, name, active FROM drum_products WHERE id = ?').get(id);
  if (!product) throw bad('Drum product not found.', 404);
  const now = nowIso();
  db.prepare('UPDATE drum_products SET shelf_life_months = ?, updated_at = ? WHERE id = ?').run(months, now, id);
  try { audit(db, req.user, 'UPDATE', 'drum_product', id, `${product.name}; future batches use ${months} months`); } catch (_) {}
  res.json({ product: db.prepare('SELECT id, code, name, shelf_life_months, active FROM drum_products WHERE id = ?').get(id) });
});

router.get('/plants', requirePerm('inventory.view'), (_req, res) => {
  const plants = db.prepare('SELECT id, name, active, next_fill_number FROM drum_plants ORDER BY name COLLATE NOCASE').all();
  res.json({ plants });
});

router.post('/plants', requirePerm('inventory.manage'), (req, res) => {
  const name = String((req.body || {}).name || '').trim();
  if (!name || name.length > 120) throw bad('Plant name is required and must be 120 characters or fewer.');
  const existing = db.prepare('SELECT id, name, active, next_fill_number FROM drum_plants WHERE name = ? COLLATE NOCASE').get(name);
  if (existing) {
    if (!existing.active) db.prepare('UPDATE drum_plants SET active = 1 WHERE id = ?').run(existing.id);
    return res.json({ plant: { ...existing, active: 1 } });
  }
  const result = db.prepare('INSERT INTO drum_plants (name, active, next_fill_number, created_at) VALUES (?, 1, 1, ?)').run(name, nowIso());
  const plant = db.prepare('SELECT id, name, active, next_fill_number FROM drum_plants WHERE id = ?').get(Number(result.lastInsertRowid));
  try { audit(db, req.user, 'CREATE', 'drum_plant', plant.id, name); } catch (_) {}
  res.status(201).json({ plant });
});

router.get('/batches', requirePerm('inventory.view'), (req, res) => {
  const plantId = req.query.plantId ? positiveId(req.query.plantId, 'Plant ID') : null;
  const where = plantId ? 'WHERE b.plant_id = ?' : '';
  const params = plantId ? [plantId] : [];
  const batches = db.prepare(`
    SELECT b.id, b.batch_code, b.plant_id, pl.name AS plant_name,
           b.product_id, p.name AS product_name, b.manufacturing_date,
           b.expiry_date, b.shelf_life_months, b.created_at,
           COUNT(f.id) AS total_drums,
           SUM(CASE WHEN f.status = 'AVAILABLE' THEN 1 ELSE 0 END) AS available_drums
      FROM drum_batches b
      JOIN drum_plants pl ON pl.id = b.plant_id
      JOIN drum_products p ON p.id = b.product_id
      LEFT JOIN drum_fills f ON f.batch_id = b.id
      ${where}
     GROUP BY b.id
     ORDER BY b.manufacturing_date DESC, b.id DESC
     LIMIT 500`).all(...params);
  res.json({ batches });
});

/** Available stock grouped by product, packaging, batch and source plant. */
router.get('/stock', requirePerm('inventory.view'), (req, res) => {
  const plantId = req.query.plantId ? positiveId(req.query.plantId, 'Plant ID') : null;
  const where = plantId ? 'AND f.plant_id = ?' : '';
  const params = plantId ? [plantId] : [];
  const stock = db.prepare(`
    SELECT f.plant_id, pl.name AS plant_name,
           b.product_id, p.name AS product_name,
           b.id AS batch_id, b.batch_code, b.manufacturing_date, b.expiry_date,
           f.packaging_type,
           COUNT(f.id) AS available_drums,
           ROUND(SUM(f.gross_weight_kg), 3) AS gross_weight_kg
      FROM drum_fills f
      JOIN drum_plants pl ON pl.id = f.plant_id
      JOIN drum_batches b ON b.id = f.batch_id
      JOIN drum_products p ON p.id = b.product_id
     WHERE f.status = 'AVAILABLE' ${where}
     GROUP BY f.plant_id, pl.name, b.product_id, p.name, b.id, b.batch_code,
              b.manufacturing_date, b.expiry_date, f.packaging_type
     ORDER BY pl.name COLLATE NOCASE, p.name COLLATE NOCASE, b.expiry_date, b.batch_code, f.packaging_type`).all(...params);
  const summary = stock.reduce((sum, row) => {
    sum.drum_count += Number(row.available_drums || 0);
    sum.gross_weight_kg += Number(row.gross_weight_kg || 0);
    return sum;
  }, { drum_count: 0, gross_weight_kg: 0 });
  summary.gross_weight_kg = Math.round(summary.gross_weight_kg * 1000) / 1000;
  res.json({ stock, summary });
});

/** Mutable product-level opening balances imported from the report PDF. */
router.get('/opening-balances', requirePerm('inventory.view'), (_req, res) => {
  const balances = db.prepare(`
    SELECT id, product_name, snapshot_date, opening_drums, opening_kg,
           available_drums, ROUND(available_kg, 3) AS available_kg
      FROM drum_opening_balances
     ORDER BY product_name COLLATE NOCASE`).all();
  const summary = balances.reduce((total, balance) => {
    total.available_drums += Number(balance.available_drums || 0);
    total.available_kg += Number(balance.available_kg || 0);
    return total;
  }, { available_drums: 0, available_kg: 0 });
  summary.available_kg = Math.round(summary.available_kg * 1000) / 1000;
  res.json({ balances, summary });
});

/** Individual filled drums; fill_number is a never-reused, plant-wide fill/sticker number. */
router.get('/fills', requirePerm('inventory.view'), (req, res) => {
  const clauses = [];
  const params = [];
  if (req.query.plantId) { clauses.push('f.plant_id = ?'); params.push(positiveId(req.query.plantId, 'Plant ID')); }
  if (req.query.productId) { clauses.push('b.product_id = ?'); params.push(positiveId(req.query.productId, 'Product ID')); }
  const status = String(req.query.status || 'ALL').trim().toUpperCase();
  if (status !== 'ALL') {
    if (!['AVAILABLE', 'DISPATCHED'].includes(status)) throw bad('Status must be AVAILABLE, DISPATCHED, or ALL.');
    clauses.push('f.status = ?');
    params.push(status);
  }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  const fills = db.prepare(`${FILL_SELECT} ${where} ORDER BY f.created_at DESC, f.fill_number DESC LIMIT 1000`).all(...params);
  res.json({ fills });
});

/**
 * Fill one or more drums for a batch. Each input weight creates a separate fill record
 * and gets its own never-reused, plant-wide number, optionally from an explicit range
 * (not a permanent iron-drum ID).
 */
router.post('/fills', requirePerm('inventory.manage'), (req, res) => {
  const body = req.body || {};
  const plantId = positiveId(body.plantId ?? body.plant_id, 'Plant');
  const productId = positiveId(body.productId ?? body.product_id, 'Product');
  const batchCode = String(body.batchCode ?? body.batch_code ?? '').trim().toUpperCase();
  if (!batchCode || batchCode.length > 80) throw bad('Batch code is required and must be 80 characters or fewer.');
  const manufacturingDate = validDate(body.manufacturingDate ?? body.manufacturing_date, 'Manufacturing/packing date');
  const rawExpiry = String(body.expiryDate ?? body.expiry_date ?? '').trim();
  const requestedExpiry = rawExpiry ? validDate(rawExpiry, 'Expiry date') : null;
  const packagingValue = body.packagingType ?? body.packaging_type;
  let packagingType;
  try { packagingType = normalizePackagingType(packagingValue); } catch (error) { throw bad(error.message); }
  const weights = validFillWeights(body);
  const requestedNumberRange = validFillNumberRange(body, weights.length);

  const plant = db.prepare('SELECT id, name, active, next_fill_number FROM drum_plants WHERE id = ?').get(plantId);
  if (!plant || !plant.active) throw bad('Source plant not found or inactive.', 404);
  const product = db.prepare('SELECT id, name, shelf_life_months, active FROM drum_products WHERE id = ?').get(productId);
  if (!product || !product.active) throw bad('Drum product not found or inactive.', 404);

  if (requestedExpiry && requestedExpiry < manufacturingDate) throw bad('Expiry date cannot be earlier than the manufacturing/packing date.');
  let defaultExpiry;
  try { defaultExpiry = addMonths(manufacturingDate, product.shelf_life_months); } catch (error) { throw bad(error.message); }

  const createdAt = nowIso();
  const result = tx(db, () => {
    const lockedPlant = db.prepare('SELECT id, active, next_fill_number FROM drum_plants WHERE id = ?').get(plantId);
    if (!lockedPlant || !lockedPlant.active) throw bad('Source plant not found or inactive.', 404);
    const lockedProduct = db.prepare('SELECT id, name, shelf_life_months, active FROM drum_products WHERE id = ?').get(productId);
    if (!lockedProduct || !lockedProduct.active) throw bad('Drum product not found or inactive.', 404);

    let batch = db.prepare(
      'SELECT id, manufacturing_date, expiry_date, shelf_life_months FROM drum_batches WHERE plant_id = ? AND product_id = ? AND batch_code = ?'
    ).get(plantId, productId, batchCode);
    if (batch) {
      if (batch.manufacturing_date !== manufacturingDate) {
        throw bad('That batch code already exists for this product and plant with a different manufacturing date.', 409);
      }
      if (requestedExpiry && batch.expiry_date !== requestedExpiry) {
        throw bad('That batch already has a saved expiry date; existing batch expiry cannot be changed while adding drums.', 409);
      }
    } else {
      const expiryDate = requestedExpiry || defaultExpiry;
      const insertedBatch = db.prepare(`
        INSERT INTO drum_batches
          (batch_code, plant_id, product_id, manufacturing_date, shelf_life_months, expiry_date, created_by, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      ).run(batchCode, plantId, productId, manufacturingDate, lockedProduct.shelf_life_months, expiryDate, req.user.id, createdAt);
      batch = { id: Number(insertedBatch.lastInsertRowid), manufacturing_date: manufacturingDate, expiry_date: expiryDate, shelf_life_months: lockedProduct.shelf_life_months };
    }

    const firstNumber = requestedNumberRange ? requestedNumberRange.from : Number(lockedPlant.next_fill_number);
    const lastNumber = requestedNumberRange ? requestedNumberRange.to : firstNumber + weights.length - 1;
    const existingNumber = db.prepare(`
      SELECT fill_number FROM drum_fills
       WHERE plant_id = ? AND fill_number BETWEEN ? AND ?
       ORDER BY fill_number LIMIT 1`).get(plantId, firstNumber, lastNumber);
    if (existingNumber) {
      throw bad(`Drum number ${existingNumber.fill_number} is already registered at ${plant.name}. Choose a free range.`, 409);
    }

    const insertFill = db.prepare(`
      INSERT INTO drum_fills
        (plant_id, fill_number, batch_id, packaging_type, gross_weight_kg, status, created_by, created_at)
      VALUES (?, ?, ?, ?, ?, 'AVAILABLE', ?, ?)`);
    const fillIds = [];
    for (let index = 0; index < weights.length; index++) {
      const insert = insertFill.run(plantId, firstNumber + index, batch.id, packagingType, weights[index], req.user.id, createdAt);
      fillIds.push(Number(insert.lastInsertRowid));
    }
    const nextFillNumber = Math.max(Number(lockedPlant.next_fill_number), lastNumber + 1);
    db.prepare('UPDATE drum_plants SET next_fill_number = ? WHERE id = ?').run(nextFillNumber, plantId);

    try { audit(db, req.user, 'CREATE', 'drum_fill', batch.id, `${product.name} ${batchCode}; ${weights.length} drum(s) numbered ${firstNumber}–${lastNumber}`); } catch (_) {}
    return { batchId: batch.id, firstNumber, lastNumber, fillIds };
  });

  const fills = result.fillIds.map((id) => db.prepare(`${FILL_SELECT} WHERE f.id = ?`).get(id));
  res.status(201).json({
    batch: db.prepare('SELECT id, batch_code, plant_id, product_id, manufacturing_date, shelf_life_months, expiry_date FROM drum_batches WHERE id = ?').get(result.batchId),
    fills,
    assigned_numbers: fills.map((fill) => fill.fill_number),
    first_fill_number: result.firstNumber,
    last_fill_number: result.lastNumber,
  });
});

router.get('/dispatches', requirePerm('dispatch.view'), (req, res) => {
  const plantId = req.query.plantId ? positiveId(req.query.plantId, 'Plant ID') : null;
  const where = plantId ? 'WHERE d.plant_id = ?' : '';
  const params = plantId ? [plantId] : [];
  const dispatches = db.prepare(`
    SELECT d.id, d.plant_id, pl.name AS plant_name, d.dispatch_datetime,
           d.truck_number, d.destination, d.drum_count, d.gross_weight_kg,
           d.created_by, u.name AS created_by_name, d.created_at
      FROM drum_dispatches d
      JOIN drum_plants pl ON pl.id = d.plant_id
      LEFT JOIN users u ON u.id = d.created_by
      ${where}
     ORDER BY d.dispatch_datetime DESC, d.id DESC LIMIT 500`).all(...params);
  res.json({ dispatches });
});

router.get('/dispatches/:id', requirePerm('dispatch.view'), (req, res) => {
  const id = positiveId(req.params.id, 'Dispatch ID');
  const dispatch = db.prepare(`
    SELECT d.id, d.plant_id, pl.name AS plant_name, d.dispatch_datetime,
           d.truck_number, d.destination, d.drum_count, d.gross_weight_kg,
           d.created_by, u.name AS created_by_name, d.created_at
      FROM drum_dispatches d
      JOIN drum_plants pl ON pl.id = d.plant_id
      LEFT JOIN users u ON u.id = d.created_by
     WHERE d.id = ?`).get(id);
  if (!dispatch) throw bad('Drum dispatch not found.', 404);
  res.json({ dispatch, drums: rowsForDispatch(id) });
});

/** Outbound only: selected available drums are removed from source stock. No receipt route exists. */
router.post('/dispatches', requirePerm('dispatch.manage'), (req, res) => {
  const body = req.body || {};
  const plantId = positiveId(body.plantId ?? body.plant_id, 'Source plant');
  const truckNumber = String(body.truckNumber ?? body.truck_number ?? '').trim().toUpperCase();
  if (!truckNumber || truckNumber.length > 50) throw bad('Truck number is required and must be 50 characters or fewer.');
  const rawDateTime = body.dispatchDateTime ?? body.dispatch_datetime;
  const dispatchTime = rawDateTime ? new Date(rawDateTime) : new Date();
  if (!Number.isFinite(dispatchTime.getTime())) throw bad('Dispatch date/time is invalid.');
  const dispatchDateTime = dispatchTime.toISOString();
  const inputIds = body.fillIds ?? body.fill_ids;
  if (!Array.isArray(inputIds) || inputIds.length < 1 || inputIds.length > 500) {
    throw bad('Select between 1 and 500 available drums to dispatch.');
  }
  const fillIds = inputIds.map((value) => positiveId(value, 'Drum fill ID'));
  if (new Set(fillIds).size !== fillIds.length) throw bad('A drum was selected more than once.');
  const createdAt = nowIso();

  const result = tx(db, () => {
    const plant = db.prepare('SELECT id, name, active FROM drum_plants WHERE id = ?').get(plantId);
    if (!plant || !plant.active) throw bad('Source plant not found or inactive.', 404);
    const placeholders = fillIds.map(() => '?').join(',');
    const fills = db.prepare(`${FILL_SELECT} WHERE f.id IN (${placeholders}) AND f.plant_id = ? ORDER BY f.fill_number`).all(...fillIds, plantId);
    if (fills.length !== fillIds.length) throw bad('One or more selected drums do not belong to this plant.', 409);
    const unavailable = fills.filter((fill) => fill.status !== 'AVAILABLE');
    if (unavailable.length) throw bad('One or more selected drums have already been dispatched.', 409);

    const count = fills.length;
    const totalGross = Math.round(fills.reduce((sum, fill) => sum + Number(fill.gross_weight_kg), 0) * 1000) / 1000;
    const insertedDispatch = db.prepare(`
      INSERT INTO drum_dispatches
        (plant_id, dispatch_datetime, truck_number, destination, drum_count, gross_weight_kg, created_by, created_at)
      VALUES (?, ?, ?, 'Neemrana', ?, ?, ?, ?)`
    ).run(plantId, dispatchDateTime, truckNumber, count, totalGross, req.user.id, createdAt);
    const dispatchId = Number(insertedDispatch.lastInsertRowid);
    const insertItem = db.prepare('INSERT INTO drum_dispatch_items (dispatch_id, fill_id, fill_number, gross_weight_kg) VALUES (?, ?, ?, ?)');
    const updateFill = db.prepare("UPDATE drum_fills SET status = 'DISPATCHED', dispatched_at = ? WHERE id = ? AND status = 'AVAILABLE'");
    for (const fill of fills) {
      insertItem.run(dispatchId, fill.id, fill.fill_number, fill.gross_weight_kg);
      const update = updateFill.run(dispatchDateTime, fill.id);
      if (Number(update.changes) !== 1) throw bad(`Drum ${fill.fill_number} is no longer available.`, 409);
    }
    try { audit(db, req.user, 'DISPATCH', 'drum_dispatch', dispatchId, `${count} drum(s), truck ${truckNumber}, outbound to Neemrana`); } catch (_) {}
    return { dispatchId, count, totalGross, fillNumbers: fills.map((fill) => fill.fill_number) };
  });

  const dispatch = db.prepare(`
    SELECT d.id, d.plant_id, pl.name AS plant_name, d.dispatch_datetime,
           d.truck_number, d.destination, d.drum_count, d.gross_weight_kg,
           d.created_by, d.created_at
      FROM drum_dispatches d JOIN drum_plants pl ON pl.id = d.plant_id WHERE d.id = ?`).get(result.dispatchId);
  res.status(201).json({ dispatch, drum_numbers: result.fillNumbers, drum_count: result.count, gross_weight_kg: result.totalGross });
});

/** Aggregate opening-stock dispatches track product, count and kg without inventing drum IDs. */
router.get('/aggregate-dispatches', requirePerm('dispatch.view'), (_req, res) => {
  const dispatches = db.prepare(`
    SELECT d.id, d.opening_balance_id, d.product_name, d.plant_id,
           pl.name AS plant_name, d.dispatch_datetime, d.truck_number,
           d.destination, d.drum_count, d.gross_weight_kg,
           d.created_by, u.name AS created_by_name, d.created_at
      FROM drum_aggregate_dispatches d
      JOIN drum_plants pl ON pl.id = d.plant_id
      LEFT JOIN users u ON u.id = d.created_by
     ORDER BY d.dispatch_datetime DESC, d.id DESC
     LIMIT 500`).all();
  res.json({ dispatches });
});

/** Partial dispatch from the aggregate opening balance; the operator enters the actual total kg. */
router.post('/aggregate-dispatches', requirePerm('dispatch.manage'), (req, res) => {
  const body = req.body || {};
  const openingBalanceId = positiveId(body.openingBalanceId ?? body.opening_balance_id, 'Opening balance');
  const plantId = positiveId(body.plantId ?? body.plant_id, 'Source plant');
  const truckNumber = String(body.truckNumber ?? body.truck_number ?? '').trim().toUpperCase();
  if (!truckNumber || truckNumber.length > 50) throw bad('Truck number is required and must be 50 characters or fewer.');
  const rawDateTime = body.dispatchDateTime ?? body.dispatch_datetime;
  const dispatchTime = rawDateTime ? new Date(rawDateTime) : new Date();
  if (!Number.isFinite(dispatchTime.getTime())) throw bad('Dispatch date/time is invalid.');
  const dispatchDateTime = dispatchTime.toISOString();
  const drumCount = positiveDrumCount(body.drumCount ?? body.drum_count);
  const grossWeightKg = positiveAggregateWeight(body.grossWeightKg ?? body.gross_weight_kg ?? body.totalKg ?? body.total_kg);
  const createdAt = nowIso();

  const dispatchId = tx(db, () => {
    const plant = db.prepare('SELECT id, name, active FROM drum_plants WHERE id = ?').get(plantId);
    if (!plant || !plant.active) throw bad('Source plant not found or inactive.', 404);
    const balance = db.prepare(`
      SELECT id, product_name, available_drums, available_kg
        FROM drum_opening_balances WHERE id = ?`).get(openingBalanceId);
    if (!balance) throw bad('Aggregate opening balance not found.', 404);
    if (drumCount > Number(balance.available_drums)) {
      throw bad(`Only ${balance.available_drums} aggregate drum(s) remain for ${balance.product_name}.`, 409);
    }
    if (grossWeightKg > Number(balance.available_kg) + 0.0005) {
      throw bad(`Only ${balance.available_kg} kg remain for ${balance.product_name}.`, 409);
    }

    const update = db.prepare(`
      UPDATE drum_opening_balances
         SET available_drums = available_drums - ?,
             available_kg = MAX(0, ROUND(available_kg - ?, 3)),
             updated_at = ?
       WHERE id = ? AND available_drums >= ? AND available_kg + 0.0005 >= ?`)
      .run(drumCount, grossWeightKg, createdAt, openingBalanceId, drumCount, grossWeightKg);
    if (Number(update.changes) !== 1) throw bad('This aggregate stock changed; refresh and try again.', 409);

    const inserted = db.prepare(`
      INSERT INTO drum_aggregate_dispatches
        (opening_balance_id, product_name, plant_id, dispatch_datetime, truck_number,
         destination, drum_count, gross_weight_kg, created_by, created_at)
      VALUES (?, ?, ?, ?, ?, 'Neemrana', ?, ?, ?, ?)`)
      .run(openingBalanceId, balance.product_name, plantId, dispatchDateTime, truckNumber,
        drumCount, grossWeightKg, req.user.id, createdAt);
    const id = Number(inserted.lastInsertRowid);
    try {
      audit(db, req.user, 'DISPATCH', 'drum_aggregate_dispatch', id,
        `${balance.product_name}; ${drumCount} drum(s), ${grossWeightKg} kg, truck ${truckNumber}`);
    } catch (_) {}
    return id;
  });

  const dispatch = db.prepare(`
    SELECT d.id, d.opening_balance_id, d.product_name, d.plant_id,
           pl.name AS plant_name, d.dispatch_datetime, d.truck_number,
           d.destination, d.drum_count, d.gross_weight_kg,
           d.created_by, d.created_at
      FROM drum_aggregate_dispatches d
      JOIN drum_plants pl ON pl.id = d.plant_id
     WHERE d.id = ?`).get(dispatchId);
  const balance = db.prepare(`
    SELECT id, product_name, snapshot_date, opening_drums, opening_kg,
           available_drums, ROUND(available_kg, 3) AS available_kg
      FROM drum_opening_balances WHERE id = ?`).get(openingBalanceId);
  res.status(201).json({ dispatch, balance });
});

module.exports = router;
