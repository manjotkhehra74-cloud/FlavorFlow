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
  const products = await fetchJson('/api/drums/products', token);
  assert.equal(products.status, 200);
  assert.deepEqual(products.body.products, []);

  const protectedProducts = await fetchJson('/api/drums/products');
  assert.equal(protectedProducts.status, 401);

  const trucks = await fetchJson('/api/dispatch/trucks', token);
  assert.equal(trucks.status, 200);
  const productionBatches = await fetchJson('/api/production/batches', token);
  assert.equal(productionBatches.status, 200);
  const dispatchBatches = await fetchJson('/api/dispatch/batches?productId=1', token);
  assert.equal(dispatchBatches.status, 200);

  const logPath = await fetchJson('/ff-requests.txt');
  assert.equal(logPath.status, 404);
});
