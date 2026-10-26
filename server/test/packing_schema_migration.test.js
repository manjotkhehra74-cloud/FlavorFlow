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
`);
legacy.close();

const db = require('../db');

test('migrates product_id onto an existing packing transaction table', () => {
  const columns = db.prepare('PRAGMA table_info(packing_txns)').all();
  assert.ok(columns.some((column) => column.name === 'product_id'));
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM packing_txns').get().count, 0);
});

test.after(() => {
  db.close();
  fs.rmSync(tempDir, { recursive: true, force: true });
});
