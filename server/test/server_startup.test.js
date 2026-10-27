'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flavorflow-server-test-'));
process.env.ERP_DB_PATH = path.join(tempDir, 'test.sqlite');
process.env.JWT_SECRET = 'test-only-server-startup-key-never-use-in-production-123';
process.env.FLAVORFLOW_BOOTSTRAP_EMAIL = 'server-test@example.invalid';
process.env.FLAVORFLOW_BOOTSTRAP_PASSWORD = 'server-test-only-password-456';

const { app, db } = require('../server');
const jwt = require('../jwt');
let server;
let baseUrl;

async function fetchJson(pathname, token) {
  const response = await fetch(`${baseUrl}${pathname}`, {
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });
  const text = await response.text();
  let body = text;
  try { body = JSON.parse(text); } catch (_) {}
  return { status: response.status, body };
}

test.before(async () => {
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
  fs.rmSync(tempDir, { recursive: true, force: true });
});

test('full backend mounts drum APIs and blocks the legacy request-log path', async () => {
  const health = await fetchJson('/api/health');
  assert.equal(health.status, 200);
  assert.equal(health.body.ok, true);

  const token = jwt.sign({ uid: 1 });
  const masterProducts = await fetchJson('/api/products', token);
  assert.equal(masterProducts.status, 200);
  const drumProducts = await fetchJson('/api/drums/products', token);
  assert.equal(drumProducts.status, 200);
  assert.equal(drumProducts.body.products.length, masterProducts.body.products.length);
  for (const product of masterProducts.body.products) {
    assert.ok(drumProducts.body.products.some((drumProduct) =>
      drumProduct.master_product_id === product.id && drumProduct.name === product.name));
  }

  const protectedProducts = await fetchJson('/api/drums/products');
  assert.equal(protectedProducts.status, 401);

  const openingBalances = await fetchJson('/api/drums/opening-balances', token);
  assert.equal(openingBalances.status, 200);
  assert.equal(openingBalances.body.balances.length, 11);
  const aggregateDispatches = await fetchJson('/api/drums/aggregate-dispatches', token);
  assert.equal(aggregateDispatches.status, 200);
  assert.deepEqual(aggregateDispatches.body.dispatches, []);
  const destinations = await fetchJson('/api/drums/destinations', token);
  assert.equal(destinations.status, 200);
  assert.ok(destinations.body.destinations.some((row) => row.name === 'Neemrana'));
  const stockAdjustments = await fetchJson('/api/drums/stock-adjustments', token);
  assert.equal(stockAdjustments.status, 200);
  assert.deepEqual(stockAdjustments.body.adjustments, []);
  const packingMaterials = await fetchJson('/api/packing/materials', token);
  assert.equal(packingMaterials.status, 200);
  assert.ok(packingMaterials.body.materials.some((row) => row.name === 'Aseptic Bags'));
  assert.ok(db.prepare('PRAGMA table_info(packing_txns)').all().some((column) => column.name === 'product_id'));
  const protectedOpeningBalances = await fetchJson('/api/drums/opening-balances');
  assert.equal(protectedOpeningBalances.status, 401);

  const trucks = await fetchJson('/api/dispatch/trucks', token);
  assert.equal(trucks.status, 200);
  const productionBatches = await fetchJson('/api/production/batches', token);
  assert.equal(productionBatches.status, 200);
  const dispatchBatches = await fetchJson('/api/dispatch/batches?productId=1', token);
  assert.equal(dispatchBatches.status, 200);

  const logPath = await fetchJson('/ff-requests.txt');
  assert.equal(logPath.status, 404);
});
