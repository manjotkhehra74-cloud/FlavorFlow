'use strict';

process.env.ERP_DB_PATH = ':memory:';
process.env.JWT_SECRET = 'test-only-packing-key-never-use-in-production-123';
process.env.FLAVORFLOW_BOOTSTRAP_EMAIL = 'packing-test@example.invalid';
process.env.FLAVORFLOW_BOOTSTRAP_PASSWORD = 'packing-test-password-123456';

const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const db = require('../db');
const packing = require('../routes/packing');
const { errorHandler } = require('../middleware');

let server;
let baseUrl;

function call(path, { method = 'GET', body } = {}) {
  return fetch(`${baseUrl}${path}`, {
    method,
    headers: { 'content-type': 'application/json' },
    body: body == null ? undefined : JSON.stringify(body),
  }).then(async (response) => ({ status: response.status, body: await response.json() }));
}

test.before(async () => {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.user = { id: 1, name: 'Packing API Test', role: 'super_admin', permissions: ['*'] };
    next();
  });
  app.use('/api/packing', packing);
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

test('Aseptic Bags is seeded and manual consumption records quantity, product and ledger history', async () => {
  const materials = await call('/api/packing/materials');
  assert.equal(materials.status, 200);
  const bags = materials.body.materials.find((row) => row.name === 'Aseptic Bags');
  assert.ok(bags);
  assert.equal(bags.stock, 0);
  assert.equal(bags.unit, 'pcs');

  const received = await call('/api/packing/receive', {
    method: 'POST',
    body: { materialId: bags.id, qty: 12, reference: 'Opening bags' },
  });
  assert.equal(received.status, 200);
  assert.equal(received.body.balance, 12);

  const consumed = await call('/api/packing/consume', {
    method: 'POST',
    body: { materialId: bags.id, qty: 3, productId: 1, reference: 'FILL-01', remark: 'Actual use' },
  });
  assert.equal(consumed.status, 200);
  assert.equal(consumed.body.balance, 9);
  assert.equal(db.prepare("SELECT product_id FROM packing_txns WHERE txn_type = 'CONSUMED' AND material_id = ?").get(bags.id).product_id, 1);

  const ledger = await call(`/api/packing/ledger?materialId=${bags.id}&type=CONSUMED`);
  assert.equal(ledger.status, 200);
  assert.equal(ledger.body.txns.length, 1);
  assert.equal(ledger.body.txns[0].qty, 3);
  assert.equal(ledger.body.txns[0].reference, 'FILL-01');
});
