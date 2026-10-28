'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flavorflow-drum-catalog-migration-'));
process.env.ERP_DB_PATH = path.join(tempDir, 'legacy.sqlite');
process.env.JWT_SECRET = 'test-only-drum-catalog-key-never-use-in-production-123';
process.env.FLAVORFLOW_BOOTSTRAP_EMAIL = 'drum-catalog-test@example.invalid';
process.env.FLAVORFLOW_BOOTSTRAP_PASSWORD = 'drum-catalog-test-password-123456';

const db = require('../db');
const { syncDrumProductsFromOpeningBalances } = require('../drum_opening_products');

function addMasterProduct(name, createdAt) {
  const result = db.prepare(`
    INSERT INTO products
      (name, weight_per_cb, weight_without_cb, bottles_per_cb, bottles_per_tray,
       tray_weight, price, min_stock_cb, active, created_at)
    VALUES (?, 1, 1, 1, 0, 0, 0, 0, 1, ?)
  `).run(name, createdAt);
  return Number(result.lastInsertRowid);
}

test('unlinks historical drum products and removes unused Product Master imports', () => {
  db.exec('ALTER TABLE drum_products ADD COLUMN master_product_id INTEGER REFERENCES products(id)');
  db.exec('CREATE UNIQUE INDEX idx_drum_products_master_product ON drum_products(master_product_id) WHERE master_product_id IS NOT NULL');

  const now = new Date().toISOString();
  const insertMapping = db.prepare(`
    INSERT INTO drum_products
      (master_product_id, code, name, shelf_life_months, active, created_at, updated_at)
    VALUES (?, NULL, ?, 24, 1, ?, ?)
  `);

  const bottleMasterId = db.prepare('SELECT id FROM products WHERE name = ?').get('Soya Sauce 740gm').id;
  insertMapping.run(bottleMasterId, 'Soya Sauce 740gm', now, now);

  const pearMasterId = addMasterProduct('Pear Pulp', now);
  db.prepare('UPDATE drum_products SET master_product_id = ?, active = 0 WHERE name = ?')
    .run(pearMasterId, 'Pear Pulp');

  const trackedMasterId = addMasterProduct('Tracked Drum Product', now);
  const trackedProduct = insertMapping.run(trackedMasterId, 'Tracked Drum Product', now, now);
  const plantId = db.prepare('SELECT id FROM drum_plants ORDER BY id LIMIT 1').get().id;
  db.prepare(`
    INSERT INTO drum_batches
      (batch_code, plant_id, product_id, manufacturing_date, shelf_life_months, expiry_date, created_at)
    VALUES ('LEGACY-TRACKED', ?, ?, '2026-01-01', 24, '2028-01-01', ?)
  `).run(plantId, Number(trackedProduct.lastInsertRowid), now);

  syncDrumProductsFromOpeningBalances(db);

  assert.equal(db.prepare('SELECT id FROM drum_products WHERE name = ?').get('Soya Sauce 740gm'), undefined);
  const pear = db.prepare('SELECT master_product_id, active FROM drum_products WHERE name = ?').get('Pear Pulp');
  assert.equal(pear.master_product_id, null);
  assert.equal(pear.active, 1);
  const tracked = db.prepare('SELECT master_product_id, active FROM drum_products WHERE name = ?').get('Tracked Drum Product');
  assert.equal(tracked.master_product_id, null);
  assert.equal(tracked.active, 1);

  const openingNames = db.prepare('SELECT product_name FROM drum_opening_balances').all().map((row) => row.product_name);
  const drumNames = new Set(db.prepare('SELECT name FROM drum_products WHERE active = 1').all().map((row) => row.name));
  for (const name of openingNames) assert.ok(drumNames.has(name), `${name} should remain available for drum fills`);
  assert.ok(db.prepare('SELECT id FROM products WHERE name = ?').get('Soya Sauce 740gm'), 'Product Master data must remain unchanged');
});

test.after(() => {
  db.close();
  fs.rmSync(tempDir, { recursive: true, force: true });
});
