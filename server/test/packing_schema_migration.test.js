'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flavorflow-packing-migration-'));
process.env.ERP_DB_PATH = path.join(tempDir, 'legacy.sqlite');
process.env.JWT_SECRET = 'test-only-migration-key-never-use-in-production-123';
process.env.FLAVORFLOW_BOOTSTRAP_EMAIL = 'migration-test@example.invalid';
process.env.FLAVORFLOW_BOOTSTRAP_PASSWORD = 'migration-test-password-123456';

const { DatabaseSync } = require('../sqlite');
const legacy = new DatabaseSync(process.env.ERP_DB_PATH);
legacy.exec(`
  CREATE TABLE packing_txns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    material_id INTEGER NOT NULL,
    txn_type TEXT NOT NULL,
    qty REAL NOT NULL,
    txn_date TEXT NOT NULL,
    reference TEXT DEFAULT '',
    remark TEXT DEFAULT '',
    batch_id INTEGER,
    created_by INTEGER,
    created_at TEXT NOT NULL
  );
  CREATE TABLE products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    weight_per_cb REAL NOT NULL,
    weight_without_cb REAL NOT NULL,
    bottles_per_cb INTEGER NOT NULL,
    price REAL NOT NULL DEFAULT 0,
    min_stock_cb INTEGER NOT NULL DEFAULT 0,
    active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL
  );
  INSERT INTO products (name, weight_per_cb, weight_without_cb, bottles_per_cb, created_at)
  VALUES ('Legacy Drum Product', 250, 240, 1, '2024-01-01');
  CREATE TABLE drum_products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE,
    name TEXT NOT NULL UNIQUE,
    shelf_life_months INTEGER NOT NULL CHECK (shelf_life_months > 0),
    active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );
  INSERT INTO drum_products (code, name, shelf_life_months, active, created_at, updated_at)
  VALUES ('OLD', 'Legacy Drum Product', 18, 1, '2024-01-01', '2024-01-01');
`);
legacy.close();

const db = require('../db');

test('migrates product_id, sort order and shelf life while linking existing drum products to Product Master', () => {
  const packingColumns = db.prepare('PRAGMA table_info(packing_txns)').all();
  assert.ok(packingColumns.some((column) => column.name === 'product_id'));
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM packing_txns').get().count, 0);

  const productColumns = db.prepare('PRAGMA table_info(products)').all();
  assert.ok(productColumns.some((column) => column.name === 'sort_order'));
  assert.ok(productColumns.some((column) => column.name === 'shelf_life_months'));
  assert.equal(db.prepare('SELECT shelf_life_months FROM products WHERE name = ?').get('Legacy Drum Product').shelf_life_months, 18, 'existing drum shelf life should be preserved when catalogs are linked');

  const drumColumns = db.prepare('PRAGMA table_info(drum_products)').all();
  assert.ok(drumColumns.some((column) => column.name === 'master_product_id'));
  const linked = db.prepare(`
    SELECT dp.id AS drum_product_id, dp.master_product_id, p.id AS product_id
      FROM drum_products dp JOIN products p ON p.id = dp.master_product_id
     WHERE p.name = ?
  `).get('Legacy Drum Product');
  assert.ok(linked);
  assert.equal(linked.drum_product_id, 1, 'legacy fill product ID must be preserved');
  assert.equal(linked.master_product_id, linked.product_id);
  assert.equal(db.prepare('SELECT shelf_life_months FROM drum_products WHERE id = ?').get(linked.drum_product_id).shelf_life_months, 18);
});

test.after(() => {
  db.close();
  fs.rmSync(tempDir, { recursive: true, force: true });
});
