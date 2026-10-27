'use strict';

process.env.ERP_DB_PATH = ':memory:';
process.env.JWT_SECRET = 'test-only-secret-that-is-never-used-in-production-123456';
process.env.FLAVORFLOW_BOOTSTRAP_EMAIL = 'drum-test@example.invalid';
process.env.FLAVORFLOW_BOOTSTRAP_PASSWORD = 'test-only-password-123456';

const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const db = require('../db');
const products = require('../routes/products');
const drums = require('../routes/drums');
const { errorHandler } = require('../middleware');

let server;
let baseUrl;

function call(path, { method = 'GET', body } = {}) {
  return fetch(`${baseUrl}${path}`, {
    method,
    headers: { 'content-type': 'application/json' },
    body: body == null ? undefined : JSON.stringify(body),
  }).then(async (response) => ({
    status: response.status,
    body: await response.json(),
  }));
}

test.before(async () => {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.user = { id: 1, name: 'Drum API Test', role: 'super_admin', permissions: ['*'] };
    next();
  });
  app.use('/api/products', products);
  app.use('/api/drums', drums);
  app.use(errorHandler);
  server = app.listen(0, '127.0.0.1');
  await new Promise((resolve, reject) => {
    server.once('listening', resolve);
    server.once('error', reject);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test.after(async () => {
  if (server) await new Promise((resolve) => server.close(resolve));
  db.close();
});

test('drum fills keep a plant-wide sequence, individual gross weights, shelf-life expiry and outbound history', async () => {
  const now = new Date().toISOString();
  const legacyDrumProductId = Number(db.prepare(`
    INSERT INTO drum_products (code, name, shelf_life_months, active, created_at, updated_at)
    VALUES ('AMP', 'Aseptic Mango Pulp', 18, 1, ?, ?)
  `).run(now, now).lastInsertRowid);
  const masterProduct24 = await call('/api/products', {
    method: 'POST',
    body: { name: 'Aseptic Mango Pulp', weightPerCb: 250, weightWithoutCb: 240, bottlesPerCb: 1, shelfLifeMonths: 24 },
  });
  assert.equal(masterProduct24.status, 201);
  const masterProduct18 = await call('/api/products', {
    method: 'POST',
    body: { name: 'Liner Tomato Paste', weightPerCb: 250, weightWithoutCb: 240, bottlesPerCb: 1, shelfLifeMonths: 18 },
  });
  assert.equal(masterProduct18.status, 201);

  const masterList = await call('/api/products');
  assert.ok(masterList.body.products.some((row) => row.name === 'Aseptic Mango Pulp' && row.id === masterProduct24.body.id));
  assert.equal(masterList.body.products.find((row) => row.id === masterProduct24.body.id).shelf_life_months, 18);
  const drumCatalog = await call('/api/drums/products');
  const product24 = drumCatalog.body.products.find((row) => row.master_product_id === masterProduct24.body.id);
  const product18 = drumCatalog.body.products.find((row) => row.master_product_id === masterProduct18.body.id);
  assert.ok(product24);
  assert.ok(product18);
  assert.equal(product24.id, legacyDrumProductId, 'linking a legacy product must preserve its fill-history ID');
  assert.equal(product24.shelf_life_months, 18, 'adding a legacy drum product to Product Master should preserve its shelf life');
  const reusedProduct = await call('/api/drums/products', {
    method: 'POST',
    body: { name: 'Aseptic Mango Pulp', shelfLifeMonths: 24 },
  });
  assert.equal(reusedProduct.status, 200);
  assert.equal(reusedProduct.body.product.id, product24.id);
  const drumOnlyProduct = await call('/api/drums/products', {
    method: 'POST',
    body: { name: 'Do Not Duplicate', shelfLifeMonths: 18 },
  });
  assert.equal(drumOnlyProduct.status, 409);
  const invalidRegisterPhoto = await call('/api/drums/register-ocr', {
    method: 'POST',
    body: { imageBase64: Buffer.from('not an image').toString('base64'), fillNumberFrom: 1, fillNumberTo: 1 },
  });
  assert.equal(invalidRegisterPhoto.status, 400);

  const defaultPlants = await call('/api/drums/plants');
  assert.ok(defaultPlants.body.plants.some((row) => row.name === 'Khadur Sahib'));
  const defaultDestinations = await call('/api/drums/destinations');
  assert.ok(defaultDestinations.body.destinations.some((row) => row.name === 'Neemrana'));
  const customDestination = await call('/api/drums/destinations', {
    method: 'POST',
    body: { name: 'Delhi Hub' },
  });
  assert.equal(customDestination.status, 201);
  const dispatchPlant = await call('/api/drums/dispatch-plants', {
    method: 'POST',
    body: { name: 'Dispatch Yard' },
  });
  assert.equal(dispatchPlant.status, 201);
  assert.equal(dispatchPlant.body.plant.name, 'Dispatch Yard');

  const plant = await call('/api/drums/plants', { method: 'POST', body: { name: 'Test Plant' } });
  assert.equal(plant.status, 201);
  const plantId = plant.body.plant.id;

  const firstBatch = await call('/api/drums/fills', {
    method: 'POST',
    body: {
      plantId,
      productId: product24.id,
      batchCode: 'MANGO-01',
      manufacturingDate: '2025-01-31',
      packagingType: 'aseptic_bag',
      grossWeightsKg: [230.1, 231.25],
    },
  });
  assert.equal(firstBatch.status, 201);
  assert.deepEqual(firstBatch.body.assigned_numbers, [1, 2]);
  assert.deepEqual(firstBatch.body.fills.map((fill) => fill.gross_weight_kg), [230.1, 231.25]);
  assert.equal(firstBatch.body.batch.expiry_date, '2026-07-31');

  const secondBatch = await call('/api/drums/fills', {
    method: 'POST',
    body: {
      plantId,
      productId: product18.id,
      batchCode: 'TOMATO-01',
      manufacturingDate: '2025-10-01',
      packagingType: 'liner_bag',
      grossWeightsKg: [220.5],
    },
  });
  assert.equal(secondBatch.status, 201);
  assert.deepEqual(secondBatch.body.assigned_numbers, [3]);
  assert.equal(secondBatch.body.batch.expiry_date, '2027-04-01');

  const rangePlant = await call('/api/drums/plants', { method: 'POST', body: { name: 'Range Test Plant' } });
  assert.equal(rangePlant.status, 201);
  const rangePlantId = rangePlant.body.plant.id;
  const rangeFill = await call('/api/drums/fills', {
    method: 'POST',
    body: {
      plantId: rangePlantId,
      productId: product24.id,
      batchCode: 'MANGO-RANGE-01',
      manufacturingDate: '2025-02-01',
      packagingType: 'aseptic_bag',
      fillNumberFrom: 40,
      fillNumberTo: 42,
      grossWeightsKg: [215.75, 216.25, 217],
    },
  });
  assert.equal(rangeFill.status, 201);
  assert.deepEqual(rangeFill.body.assigned_numbers, [40, 41, 42]);
  assert.equal(rangeFill.body.first_fill_number, 40);
  assert.equal(rangeFill.body.last_fill_number, 42);
  assert.deepEqual(rangeFill.body.fills.map((fill) => fill.gross_weight_kg), [215.75, 216.25, 217]);

  const rangePlantRows = await call('/api/drums/plants');
  assert.equal(rangePlantRows.body.plants.find((row) => row.id === rangePlantId).next_fill_number, 43);
  const nextAutomaticFill = await call('/api/drums/fills', {
    method: 'POST',
    body: {
      plantId: rangePlantId,
      productId: product24.id,
      batchCode: 'MANGO-RANGE-02',
      manufacturingDate: '2025-02-02',
      packagingType: 'aseptic_bag',
      grossWeightsKg: [219.5],
    },
  });
  assert.equal(nextAutomaticFill.status, 201);
  assert.deepEqual(nextAutomaticFill.body.assigned_numbers, [43]);

  const mismatchedRange = await call('/api/drums/fills', {
    method: 'POST',
    body: {
      plantId: rangePlantId,
      productId: product24.id,
      batchCode: 'MANGO-RANGE-03',
      manufacturingDate: '2025-02-03',
      packagingType: 'aseptic_bag',
      fillNumberFrom: 50,
      fillNumberTo: 52,
      grossWeightsKg: [220, 221],
    },
  });
  assert.equal(mismatchedRange.status, 400);

  const duplicateRange = await call('/api/drums/fills', {
    method: 'POST',
    body: {
      plantId: rangePlantId,
      productId: product24.id,
      batchCode: 'MANGO-RANGE-04',
      manufacturingDate: '2025-02-04',
      packagingType: 'aseptic_bag',
      fillNumberFrom: 41,
      fillNumberTo: 42,
      grossWeightsKg: [220, 221],
    },
  });
  assert.equal(duplicateRange.status, 409);

  const beforeDispatch = await call(`/api/drums/stock?plantId=${plantId}`);
  assert.equal(beforeDispatch.body.summary.drum_count, 3);

  const dispatch = await call('/api/drums/dispatches', {
    method: 'POST',
    body: {
      plantId,
      truckNumber: 'pb-02-aa-1234',
      destination: 'Delhi Hub',
      dispatchDateTime: '2026-10-20T10:30:00+05:30',
      fillIds: firstBatch.body.fills.map((fill) => fill.id),
    },
  });
  assert.equal(dispatch.status, 201);
  assert.equal(dispatch.body.dispatch.destination, 'Delhi Hub');
  assert.equal(dispatch.body.dispatch.dispatch_datetime, '2026-10-20T05:00:00.000Z');
  assert.equal(dispatch.body.drum_count, 2);
  assert.deepEqual(dispatch.body.drum_numbers, [1, 2]);

  const afterDispatch = await call(`/api/drums/stock?plantId=${plantId}`);
  assert.equal(afterDispatch.body.summary.drum_count, 1);
  assert.equal(afterDispatch.body.stock[0].available_drums, 1);

  const detail = await call(`/api/drums/dispatches/${dispatch.body.dispatch.id}`);
  assert.equal(detail.status, 200);
  assert.equal(detail.body.drums.length, 2);
  assert.deepEqual(detail.body.drums.map((fill) => fill.fill_number), [1, 2]);

  const duplicate = await call('/api/drums/dispatches', {
    method: 'POST',
    body: {
      plantId,
      truckNumber: 'PB-02-AA-1234',
      dispatchDateTime: '2026-10-20T11:00:00+05:30',
      fillIds: firstBatch.body.fills.map((fill) => fill.id),
    },
  });
  assert.equal(duplicate.status, 409);

  const openingBalances = await call('/api/drums/opening-balances');
  assert.equal(openingBalances.status, 200);
  assert.equal(openingBalances.body.summary.available_drums, 20279);
  assert.equal(openingBalances.body.summary.available_kg, 4471159.5);
  const pearPulpBalance = openingBalances.body.balances.find((balance) => balance.product_name === 'Pear Pulp');
  const carrotPasteBalance = openingBalances.body.balances.find((balance) => balance.product_name === 'Carrot Paste Salt Mix (10%)');
  assert.equal(pearPulpBalance.available_drums, 6);
  assert.equal(pearPulpBalance.available_kg, 1270);
  assert.equal(carrotPasteBalance.available_drums, 4086);
  assert.equal(carrotPasteBalance.available_kg, 903267);

  const aggregateDispatch = await call('/api/drums/aggregate-dispatches', {
    method: 'POST',
    body: {
      openingBalanceId: pearPulpBalance.id,
      plantId,
      truckNumber: 'pb-02-aa-1234',
      destination: 'Neemrana',
      dispatchDateTime: '2026-10-22T11:30:00+05:30',
      drumCount: 2,
      grossWeightKg: 420.5,
    },
  });
  assert.equal(aggregateDispatch.status, 201);
  assert.equal(aggregateDispatch.body.dispatch.product_name, 'Pear Pulp');
  assert.equal(aggregateDispatch.body.dispatch.drum_count, 2);
  assert.equal(aggregateDispatch.body.dispatch.gross_weight_kg, 420.5);
  assert.equal(aggregateDispatch.body.balance.available_drums, 4);
  assert.equal(aggregateDispatch.body.balance.available_kg, 849.5);

  const aggregateHistory = await call('/api/drums/aggregate-dispatches');
  assert.equal(aggregateHistory.status, 200);
  assert.equal(aggregateHistory.body.dispatches.length, 1);
  assert.equal(aggregateHistory.body.dispatches[0].product_name, 'Pear Pulp');

  const overdraw = await call('/api/drums/aggregate-dispatches', {
    method: 'POST',
    body: {
      openingBalanceId: pearPulpBalance.id,
      plantId,
      truckNumber: 'PB-02-AA-1234',
      drumCount: 5,
      grossWeightKg: 100,
    },
  });
  assert.equal(overdraw.status, 409);

  const kgOverdraw = await call('/api/drums/aggregate-dispatches', {
    method: 'POST',
    body: {
      openingBalanceId: pearPulpBalance.id,
      plantId,
      truckNumber: 'PB-02-AA-1234',
      drumCount: 1,
      grossWeightKg: 900,
    },
  });
  assert.equal(kgOverdraw.status, 409);
  const unchangedBalance = await call('/api/drums/opening-balances');
  const pearPulpAfterRejectedDispatch = unchangedBalance.body.balances.find((balance) => balance.product_name === 'Pear Pulp');
  assert.equal(pearPulpAfterRejectedDispatch.available_drums, 4);
  assert.equal(pearPulpAfterRejectedDispatch.available_kg, 849.5);

  const trackedDrumsBeforeCorrection = await call('/api/drums/stock');
  const mangoTracked = trackedDrumsBeforeCorrection.body.stock
    .filter((row) => row.product_name === 'Aseptic Mango Pulp')
    .reduce((total, row) => ({ drums: total.drums + row.available_drums, kg: total.kg + row.gross_weight_kg }), { drums: 0, kg: 0 });
  assert.equal(mangoTracked.drums, 4);
  const tooLowCorrection = await call('/api/drums/stock-adjustments', {
    method: 'POST',
    body: { productName: 'Aseptic Mango Pulp', targetDrums: 3, targetKg: 800, reason: 'Below tracked stock' },
  });
  assert.equal(tooLowCorrection.status, 409);

  const correction = await call('/api/drums/stock-adjustments', {
    method: 'POST',
    body: { productName: 'Aseptic Mango Pulp', targetDrums: 6, targetKg: 1300, reason: 'Verified physical count' },
  });
  assert.equal(correction.status, 201);
  assert.equal(correction.body.adjustment.previous_drums, 4);
  assert.equal(correction.body.adjustment.corrected_drums, 6);
  assert.equal(correction.body.balance.available_drums, 2);
  assert.equal(correction.body.balance.available_kg, 431.5);
  const adjustmentHistory = await call('/api/drums/stock-adjustments');
  assert.equal(adjustmentHistory.body.adjustments.length, 1);
  assert.equal(adjustmentHistory.body.adjustments[0].reason, 'Verified physical count');
  const trackedAfterCorrection = await call('/api/drums/fills?status=ALL');
  assert.equal(trackedAfterCorrection.body.fills.length, 7);
  assert.ok(trackedAfterCorrection.body.fills.some((row) => row.status === 'DISPATCHED'));

  const shelfLifeChange = await call(`/api/drums/products/${product24.id}`, {
    method: 'PUT',
    body: { shelfLifeMonths: 30 },
  });
  assert.equal(shelfLifeChange.status, 200);
  assert.equal(shelfLifeChange.body.product.shelf_life_months, 30);
  const updatedMasterProducts = await call('/api/products');
  assert.equal(updatedMasterProducts.body.products.find((row) => row.id === masterProduct24.body.id).shelf_life_months, 30);
  const batchHistory = await call(`/api/drums/batches?plantId=${plantId}`);
  assert.equal(batchHistory.body.batches.find((row) => row.id === firstBatch.body.batch.id).expiry_date, '2026-07-31');
});
