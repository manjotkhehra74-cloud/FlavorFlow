/** db.js — SQLite schema + seed data. Seeds/migrates automatically on boot. */
const path = require('path');
const fs = require('fs');
const bcrypt = require('bcryptjs');
const { audit } = require('./helpers');
const { DatabaseSync: Database, tx, pragma } = require('./sqlite');

const DB_PATH = process.env.ERP_DB_PATH || path.join(__dirname, 'data', 'erp.db');
fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });

const db = new Database(DB_PATH);
pragma(db, 'journal_mode = WAL');
pragma(db, 'foreign_keys = ON');

function migrate() {
  db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 1,
    permissions TEXT NOT NULL DEFAULT '[]',
    totp_secret TEXT NOT NULL DEFAULT '',
    totp_pending_secret TEXT NOT NULL DEFAULT '',
    totp_enabled INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    weight_per_cb REAL NOT NULL,       -- kg, gross weight of one carton (CB)
    weight_without_cb REAL NOT NULL,   -- kg, net product weight of one CB
    bottles_per_cb INTEGER NOT NULL,
    bottles_per_tray INTEGER NOT NULL DEFAULT 0,  -- 0 = no tray variant
    tray_weight REAL NOT NULL DEFAULT 0,          -- kg, gross weight of one tray
    price REAL NOT NULL DEFAULT 0,
    min_stock_cb INTEGER NOT NULL DEFAULT 0,
    active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS inventory (
    product_id INTEGER PRIMARY KEY REFERENCES products(id),
    qty_cb INTEGER NOT NULL DEFAULT 0,
    qty_trays INTEGER NOT NULL DEFAULT 0,
    qty_loose INTEGER NOT NULL DEFAULT 0,          -- legacy, unused
    updated_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS batches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL UNIQUE,
    product_id INTEGER NOT NULL REFERENCES products(id),
    planned_cb INTEGER NOT NULL,
    produced_cb INTEGER NOT NULL DEFAULT 0,
    produced_trays INTEGER NOT NULL DEFAULT 0,
    used_cb INTEGER NOT NULL DEFAULT 0,
    used_trays INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'PLANNED',
    planned_date TEXT,
    remarks TEXT DEFAULT '',
    created_by INTEGER, started_by INTEGER, completed_by INTEGER,
    created_at TEXT NOT NULL, started_at TEXT, completed_at TEXT
  );

  CREATE TABLE IF NOT EXISTS plans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL UNIQUE,
    product_id INTEGER NOT NULL REFERENCES products(id),
    target_cb INTEGER NOT NULL,
    start_date TEXT NOT NULL,
    due_date TEXT NOT NULL,
    priority TEXT NOT NULL DEFAULT 'MEDIUM',
    status TEXT NOT NULL DEFAULT 'PLANNED',
    remarks TEXT DEFAULT '',
    created_by INTEGER, created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS adjustments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL UNIQUE,
    product_id INTEGER NOT NULL REFERENCES products(id),
    adj_type TEXT NOT NULL,                        -- IN | OUT
    qty_cb INTEGER NOT NULL DEFAULT 0,
    qty_loose INTEGER NOT NULL DEFAULT 0,          -- legacy, unused
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'PENDING',
    requested_by INTEGER NOT NULL,
    requested_at TEXT NOT NULL,
    approved_by INTEGER, approved_at TEXT, approval_remarks TEXT,
    rejected_by INTEGER, rejected_at TEXT, reject_reason TEXT,
    FOREIGN KEY (requested_by) REFERENCES users(id)
  );

  CREATE TABLE IF NOT EXISTS dispatches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL UNIQUE,
    dispatch_date TEXT NOT NULL,
    destination TEXT NOT NULL DEFAULT '',
    truck_number TEXT NOT NULL,
    driver_name TEXT NOT NULL DEFAULT '',
    driver_phone TEXT DEFAULT '',
    invoice_no TEXT NOT NULL,
    lr_no TEXT DEFAULT '',
    remarks TEXT DEFAULT '',
    status TEXT NOT NULL DEFAULT 'DISPATCHED',
    total_cartons INTEGER NOT NULL DEFAULT 0,
    total_trays INTEGER NOT NULL DEFAULT 0,
    total_bottles INTEGER NOT NULL DEFAULT 0,
    carton_weight REAL NOT NULL DEFAULT 0,
    tray_weight REAL NOT NULL DEFAULT 0,
    gross_weight REAL NOT NULL DEFAULT 0,
    total_loose INTEGER NOT NULL DEFAULT 0,        -- legacy, unused
    loose_weight REAL NOT NULL DEFAULT 0,          -- legacy, unused
    total_value REAL NOT NULL DEFAULT 0,           -- legacy, unused
    created_by INTEGER, created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS dispatch_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    dispatch_id INTEGER NOT NULL REFERENCES dispatches(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id),
    batch_code TEXT,
    cartons INTEGER NOT NULL DEFAULT 0,
    trays INTEGER NOT NULL DEFAULT 0,
    total_bottles INTEGER NOT NULL DEFAULT 0,
    carton_weight REAL NOT NULL DEFAULT 0,
    tray_weight REAL NOT NULL DEFAULT 0,
    gross_weight REAL NOT NULL DEFAULT 0,
    loose_bottles INTEGER NOT NULL DEFAULT 0,      -- legacy, unused
    loose_weight REAL NOT NULL DEFAULT 0,          -- legacy, unused
    line_value REAL NOT NULL DEFAULT 0             -- legacy, unused
  );

  CREATE TABLE IF NOT EXISTS dispatch_trucks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    number TEXT NOT NULL UNIQUE,
    destination TEXT NOT NULL DEFAULT 'NEEMRANA',
    active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS packing_materials (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    category TEXT NOT NULL DEFAULT 'Other',
    unit TEXT NOT NULL DEFAULT 'pcs',
    stock REAL NOT NULL DEFAULT 0,
    min_stock REAL NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS packing_bom (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL REFERENCES products(id),
    material_id INTEGER NOT NULL REFERENCES packing_materials(id),
    qty_per_cb REAL NOT NULL DEFAULT 0,
    qty_per_tray REAL NOT NULL DEFAULT 0,
    UNIQUE(product_id, material_id)
  );

  CREATE TABLE IF NOT EXISTS packing_txns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    material_id INTEGER NOT NULL REFERENCES packing_materials(id),
    txn_type TEXT NOT NULL,                        -- RECEIVED | CONSUMED
    qty REAL NOT NULL,
    txn_date TEXT NOT NULL,
    reference TEXT DEFAULT '',
    remark TEXT DEFAULT '',
    batch_id INTEGER,
    created_by INTEGER, created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS notifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT DEFAULT '',
    route TEXT NOT NULL DEFAULT '/notifications',
    ref_id TEXT,
    is_read INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER, user_name TEXT, role TEXT,
    action TEXT NOT NULL, entity TEXT NOT NULL, entity_id TEXT,
    details TEXT DEFAULT '', created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS drum_plants (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    active INTEGER NOT NULL DEFAULT 1,
    next_fill_number INTEGER NOT NULL DEFAULT 1 CHECK (next_fill_number > 0),
    created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS drum_products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE,
    name TEXT NOT NULL UNIQUE,
    shelf_life_months INTEGER NOT NULL CHECK (shelf_life_months > 0),
    active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS drum_batches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_code TEXT NOT NULL,
    plant_id INTEGER NOT NULL REFERENCES drum_plants(id),
    product_id INTEGER NOT NULL REFERENCES drum_products(id),
    manufacturing_date TEXT NOT NULL,
    shelf_life_months INTEGER NOT NULL CHECK (shelf_life_months > 0),
    expiry_date TEXT NOT NULL,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL,
    UNIQUE (plant_id, product_id, batch_code)
  );

  CREATE TABLE IF NOT EXISTS drum_fills (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    plant_id INTEGER NOT NULL REFERENCES drum_plants(id),
    fill_number INTEGER NOT NULL CHECK (fill_number > 0),
    batch_id INTEGER NOT NULL REFERENCES drum_batches(id),
    packaging_type TEXT NOT NULL CHECK (packaging_type IN ('aseptic_bag', 'liner_bag')),
    gross_weight_kg REAL NOT NULL CHECK (gross_weight_kg > 0),
    status TEXT NOT NULL DEFAULT 'AVAILABLE' CHECK (status IN ('AVAILABLE', 'DISPATCHED')),
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL,
    dispatched_at TEXT,
    UNIQUE (plant_id, fill_number)
  );

  CREATE TABLE IF NOT EXISTS drum_dispatches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    plant_id INTEGER NOT NULL REFERENCES drum_plants(id),
    dispatch_datetime TEXT NOT NULL,
    truck_number TEXT NOT NULL,
    destination TEXT NOT NULL DEFAULT 'Neemrana',
    drum_count INTEGER NOT NULL CHECK (drum_count > 0),
    gross_weight_kg REAL NOT NULL DEFAULT 0,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS drum_dispatch_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    dispatch_id INTEGER NOT NULL REFERENCES drum_dispatches(id) ON DELETE CASCADE,
    fill_id INTEGER NOT NULL UNIQUE REFERENCES drum_fills(id),
    fill_number INTEGER NOT NULL,
    gross_weight_kg REAL NOT NULL
  );

  CREATE INDEX IF NOT EXISTS idx_drum_fills_stock ON drum_fills(plant_id, status, batch_id);
  CREATE INDEX IF NOT EXISTS idx_drum_batches_product ON drum_batches(product_id, plant_id, batch_code);
  CREATE INDEX IF NOT EXISTS idx_drum_dispatch_date ON drum_dispatches(dispatch_datetime);
  CREATE INDEX IF NOT EXISTS idx_drum_dispatch_items_dispatch ON drum_dispatch_items(dispatch_id);

  CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, is_read);
  CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity, entity_id);
  CREATE INDEX IF NOT EXISTS idx_dispatch_created ON dispatches(created_at);
  CREATE INDEX IF NOT EXISTS idx_batches_status ON batches(status);
  CREATE INDEX IF NOT EXISTS idx_packing_txns ON packing_txns(material_id);
  `);

  /* ---- upgrades for databases created by older versions ---- */
  const ensureColumn = (table, col, ddl) => {
    const cols = db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name);
    if (!cols.includes(col)) db.exec(`ALTER TABLE ${table} ADD COLUMN ${ddl}`);
  };
  ensureColumn('users', 'permissions', `permissions TEXT NOT NULL DEFAULT '[]'`);
  ensureColumn('users', 'totp_secret', `totp_secret TEXT NOT NULL DEFAULT ''`);
  ensureColumn('users', 'totp_pending_secret', `totp_pending_secret TEXT NOT NULL DEFAULT ''`);
  ensureColumn('users', 'totp_enabled', 'totp_enabled INTEGER NOT NULL DEFAULT 0');
  ensureColumn('products', 'bottles_per_tray', 'bottles_per_tray INTEGER NOT NULL DEFAULT 0');
  ensureColumn('products', 'tray_weight', 'tray_weight REAL NOT NULL DEFAULT 0');
  ensureColumn('inventory', 'qty_trays', 'qty_trays INTEGER NOT NULL DEFAULT 0');
  ensureColumn('batches', 'produced_trays', 'produced_trays INTEGER NOT NULL DEFAULT 0');
  ensureColumn('batches', 'used_cb', 'used_cb INTEGER NOT NULL DEFAULT 0');
  ensureColumn('batches', 'used_trays', 'used_trays INTEGER NOT NULL DEFAULT 0');
  ensureColumn('dispatches', 'destination', `destination TEXT NOT NULL DEFAULT ''`);
  ensureColumn('dispatches', 'total_trays', 'total_trays INTEGER NOT NULL DEFAULT 0');
  ensureColumn('dispatches', 'tray_weight', 'tray_weight REAL NOT NULL DEFAULT 0');
  ensureColumn('dispatch_items', 'batch_code', 'batch_code TEXT');
  ensureColumn('dispatch_items', 'trays', 'trays INTEGER NOT NULL DEFAULT 0');
  ensureColumn('dispatch_items', 'tray_weight', 'tray_weight REAL NOT NULL DEFAULT 0');

  /* default tray specs for tray-packed products (editable in Product Master) */
  const trayDefaults = [
    ['Soya Sauce 740gm', 18, 13.62],   // 13.32 net + 0.30 tray/shrink
    ['White Vinegar 610ml', 18, 11.28],
    ['Brown Vinegar 610ml', 18, 11.28],
    ['Soya Sauce 1.3kg', 12, 15.90],
    ['White Vinegar 1 Ltr', 12, 12.30],
  ];
  const upd = db.prepare('UPDATE products SET bottles_per_tray = ?, tray_weight = ? WHERE name = ? AND bottles_per_tray = 0');
  for (const [name, bpt, tw] of trayDefaults) upd.run(bpt, tw, name);
}

/* ---------------------------------- seed ---------------------------------- */

function ts(daysOffset, hour = 10) {
  const d = new Date(Date.now() + daysOffset * 86400000);
  d.setUTCHours(hour, 15, 0, 0);
  return d.toISOString().replace('T', ' ').replace(/\..+$/, '');
}

function seedUsers() {
  if (db.prepare('SELECT COUNT(*) c FROM users').get().c > 0) return;

  tx(db, () => {
    const bootstrapEmail = String(process.env.FLAVORFLOW_BOOTSTRAP_EMAIL || '').trim().toLowerCase();
    const bootstrapPassword = String(process.env.FLAVORFLOW_BOOTSTRAP_PASSWORD || '');
    const bootstrapName = String(process.env.FLAVORFLOW_BOOTSTRAP_NAME || 'Super Admin').trim() || 'Super Admin';
    const users = bootstrapEmail && bootstrapPassword.length >= 12
      ? [[bootstrapName, bootstrapEmail, bootstrapPassword, 'super_admin']]
      : [];
    if (!users.length) {
      console.warn('[db] No initial user created; configure FLAVORFLOW_BOOTSTRAP_EMAIL and a 12+ character FLAVORFLOW_BOOTSTRAP_PASSWORD for a fresh database.');
    }
    const insUser = db.prepare(`INSERT INTO users (name, email, password_hash, role, active, created_at) VALUES (?,?,?,?,1,?)`);
    for (const [name, email, pw, role] of users) insUser.run(name, email, bcrypt.hashSync(pw, 10), role, ts(-60));

    /* products — exact Finished Goods data + tray specs (per Packing Material BOM) */
    // [name, weightPerCB, weightWithoutCB, bottlesPerCB, minStockCB, bottlesPerTray, trayWeight]
    const products = [
      ['Soya Sauce 740gm',    15.0, 13.32, 18, 40, 18, 13.62],
      ['Dark Soya 250gm',     10.4,  6.00, 24, 35,  0, 0],
      ['Soya Sauce 1.3kg',    17.3, 15.60, 12, 30, 12, 15.90],
      ['Soya Sauce 4.7kg',    20.4, 18.80,  4, 25,  0, 0],
      ['White Vinegar 610ml', 12.4, 10.98, 18, 30, 18, 11.28],
      ['Brown Vinegar 610ml', 12.4, 10.98, 18, 20, 18, 11.28],
      ['White Vinegar 180ml', 10.0,  4.32, 24, 25,  0, 0],
      ['White Vinegar 1 Ltr', 14.5, 12.00, 12, 30, 12, 12.30],
      ['White Vinegar 4 Ltr', 17.7, 16.00,  4, 20,  0, 0],
    ];
    const insProd = db.prepare(
      `INSERT INTO products (name, weight_per_cb, weight_without_cb, bottles_per_cb, price, min_stock_cb, bottles_per_tray, tray_weight, active, created_at)
       VALUES (?,?,?,?,0,?,?,?,1,?)`
    );
    for (const p of products) insProd.run(...p, ts(-60));

    /* inventory — FRESH START: every finished good at 0 CB / 0 trays.
       The business enters opening stock itself (Inventory → Set Stock). */
    const insInv = db.prepare('INSERT INTO inventory (product_id, qty_cb, qty_trays, qty_loose, updated_at) VALUES (?,0,0,0,?)');
    for (let pid = 1; pid <= products.length; pid++) insInv.run(pid, ts(0));

    /* No seed batches, plans, adjustments, dispatches or notifications —
       production, dispatch, stock and ledger all start from zero. */

    if (users.length) audit(db, { id: 1, name: users[0][0], role: 'super_admin' }, 'SEED', 'system', 0, 'Bootstrap administrator created');
  });

  console.log('[db] fresh database created (everything at zero — ready for real data)');
}

/* ---- packing material master + BOM (from the supplied Packing Material PDF) ---- */

function seedPacking() {
  if (db.prepare('SELECT COUNT(*) c FROM packing_materials').get().c > 0) return;

  tx(db, () => {
    // [name, category, opening stock (0 — fresh start), min stock]
    const materials = [
      ['Glass Bottles 250gm', 'Bottles', 0, 10000],
      ['Glass Bottles 180ml', 'Bottles', 0, 10000],
      ['HDPE Bottle (610/740)', 'Bottles', 0, 12000],
      ['HDPE Bottle (1.3/1 Ltr)', 'Bottles', 0, 8000],
      ['Jerry Can 4 Ltr', 'Jerry Cans', 0, 2000],
      ['Jerry Can 4.7kg', 'Jerry Cans', 0, 2000],
      ['Lug Cap (250)', 'Caps', 0, 15000],
      ['Red Cap (180)', 'Caps', 0, 15000],
      ['Cap Orange (610)', 'Caps', 0, 12000],
      ['Cap Purple (740)', 'Caps', 0, 12000],
      ['Red Cap (1.3 / 1 Ltr)', 'Caps', 0, 10000],
      ['Dark S Label (250)', 'Labels', 0, 12000],
      ['Label White (180)', 'Labels', 0, 12000],
      ['Label Front 4 Ltr', 'Labels', 0, 4000],
      ['Label Front 4.7', 'Labels', 0, 4000],
      ['Label Soya 1.3', 'Labels', 0, 6000],
      ['Label Vinegar 1 Ltr', 'Labels', 0, 6000],
      ['Hologram M (250)', 'Holograms', 0, 12000],
      ['Hologram (180)', 'Holograms', 0, 12000],
      ['Plug (180)', 'Plugs', 0, 12000],
      ['Shrink Sleeve White 610', 'Sleeves', 0, 10000],
      ['Shrink Sleeve Brown 610', 'Sleeves', 0, 10000],
      ['Shrink Sleeve 740', 'Sleeves', 0, 10000],
      ['Carton CB 250', 'Cartons', 0, 500],
      ['Carton CB 180', 'Cartons', 0, 500],
      ['Carton CB (610/740)', 'Cartons', 0, 1000],
      ['Carton CB (1.3/1 Ltr)', 'Cartons', 0, 800],
      ['Carton CB 4 Ltr', 'Cartons', 0, 400],
      ['Carton CB 4.7', 'Cartons', 0, 400],
      ['Tray (740/610)', 'Trays', 0, 1000],
      ['Tray (1.3/1 Ltr)', 'Trays', 0, 1000],
      ['Tray Cap (740/610)', 'Tray Caps', 0, 1000],
      ['Tray Cap (1.3/1 Ltr)', 'Tray Caps', 0, 1000],
    ];
    const insMat = db.prepare(
      `INSERT INTO packing_materials (name, category, unit, stock, min_stock, created_at) VALUES (?,?,'pcs',?,?,?)`
    );
    const matId = {};
    for (const [name, cat, stk, min] of materials) {
      const info = insMat.run(name, cat, stk, min, ts(-30));
      matId[name] = info.lastInsertRowid;
    }

    // productId → [ [materialName, perCB, perTray], ... ]
    const M = (n) => matId[n];
    const bom = {
      2: [[M('Lug Cap (250)'), 24, 0], [M('Dark S Label (250)'), 24, 0], [M('Hologram M (250)'), 24, 0], [M('Glass Bottles 250gm'), 24, 0], [M('Carton CB 250'), 1, 0]],
      7: [[M('Red Cap (180)'), 24, 0], [M('Label White (180)'), 24, 0], [M('Hologram (180)'), 24, 0], [M('Plug (180)'), 24, 0], [M('Glass Bottles 180ml'), 24, 0], [M('Carton CB 180'), 1, 0]],
      5: [[M('Cap Orange (610)'), 18, 18], [M('Shrink Sleeve White 610'), 18, 18], [M('HDPE Bottle (610/740)'), 18, 18], [M('Carton CB (610/740)'), 1, 0], [M('Tray (740/610)'), 0, 1], [M('Tray Cap (740/610)'), 0, 1]],
      6: [[M('Cap Orange (610)'), 18, 18], [M('Shrink Sleeve Brown 610'), 18, 18], [M('HDPE Bottle (610/740)'), 18, 18], [M('Carton CB (610/740)'), 1, 0], [M('Tray (740/610)'), 0, 1], [M('Tray Cap (740/610)'), 0, 1]],
      9: [[M('Jerry Can 4 Ltr'), 4, 0], [M('Label Front 4 Ltr'), 4, 0], [M('Carton CB 4 Ltr'), 1, 0]],
      4: [[M('Jerry Can 4.7kg'), 4, 0], [M('Label Front 4.7'), 4, 0], [M('Carton CB 4.7'), 1, 0]],
      1: [[M('Cap Purple (740)'), 18, 18], [M('Shrink Sleeve 740'), 18, 18], [M('HDPE Bottle (610/740)'), 18, 18], [M('Carton CB (610/740)'), 1, 0], [M('Tray (740/610)'), 0, 1], [M('Tray Cap (740/610)'), 0, 1]],
      3: [[M('Red Cap (1.3 / 1 Ltr)'), 12, 12], [M('Label Soya 1.3'), 12, 12], [M('HDPE Bottle (1.3/1 Ltr)'), 12, 12], [M('Carton CB (1.3/1 Ltr)'), 1, 0], [M('Tray (1.3/1 Ltr)'), 0, 1], [M('Tray Cap (1.3/1 Ltr)'), 0, 1]],
      8: [[M('Red Cap (1.3 / 1 Ltr)'), 12, 12], [M('Label Vinegar 1 Ltr'), 12, 12], [M('HDPE Bottle (1.3/1 Ltr)'), 12, 12], [M('Carton CB (1.3/1 Ltr)'), 1, 0], [M('Tray (1.3/1 Ltr)'), 0, 1], [M('Tray Cap (1.3/1 Ltr)'), 0, 1]],
    };
    const insBom = db.prepare(
      `INSERT INTO packing_bom (product_id, material_id, qty_per_cb, qty_per_tray) VALUES (?,?,?,?)`
    );
    for (const [pid, rows] of Object.entries(bom)) {
      for (const [mid, perCb, perTray] of rows) insBom.run(Number(pid), mid, perCb, perTray);
    }

    /* Ledger starts empty — receipts & consumption are entered by the business. */
  });

  console.log('[db] seeded packing material catalog');
}

migrate();
seedUsers();
seedPacking();

/* one-time fix: trays & tray caps are consumed per TRAY produced, never per CB */
db.prepare(
  `UPDATE packing_bom SET qty_per_cb = 0
   WHERE qty_per_cb <> 0
     AND material_id IN (SELECT id FROM packing_materials WHERE category IN ('Trays','Tray Caps'))`
).run();

/* v2.1 & v2.2: merge packaging that is physically the same item across products
   (trays 740=610 & 1.3=1Ltr · HDPE bottles 610=740 & 1.3=1Ltr · cartons 610=740 & 1.3=1Ltr · 250gm rename).
   Stock adds up, BOM lines and ledger entries are re-pointed — runs on every boot, fully idempotent. */
function mergeSharedPacking() {
  const find = db.prepare('SELECT * FROM packing_materials WHERE name = ?');
  const pairs = [
    ['Tray (740/610)', ['Tray 740', 'Tray 610']],
    ['Tray Cap (740/610)', ['Tray Cap 740', 'Tray Cap 610']],
    ['Tray (1.3/1 Ltr)', ['Tray 1.3', 'Tray 1 Ltr']],
    ['Tray Cap (1.3/1 Ltr)', ['Tray Cap 1.3', 'Tray Cap 1 Ltr']],
    ['HDPE Bottle (610/740)', ['HDPE Bottle 740ml', 'HDPE Bottle 610ml', 'HDPE Bottle 740gm', 'HDPE Bottle 740']],
    ['Carton CB (610/740)', ['Carton CB 740', 'Carton CB 610']],
    ['HDPE Bottle (1.3/1 Ltr)', ['HDPE Bottle 1.3kg', 'HDPE Bottle 1.3', 'HDPE Bottle 1 Ltr', 'HDPE Bottle 1.0']],
    ['Carton CB (1.3/1 Ltr)', ['Carton CB 1.3', 'Carton CB 1 Ltr', 'Carton CB 1.0']],
    ['Glass Bottles 250gm', ['Glass Bottles 250ml']], // rename only: 250 is gm, not ml
  ];
  for (const [mergedName, oldNames] of pairs) {
    const present = oldNames.map((n) => find.get(n)).filter(Boolean);
    if (present.length === 0) continue; // fresh DB or fully merged already
    const keeper = find.get(mergedName) || present[0]; // single old row → it is simply renamed; several → merged into first
    tx(db, () => {
      db.prepare('UPDATE packing_materials SET name = ? WHERE id = ?').run(mergedName, keeper.id);
      for (const row of present) {
        if (row.id === keeper.id) continue;
        db.prepare('UPDATE packing_materials SET stock = stock + ? WHERE id = ?').run(row.stock, keeper.id);
        // re-point BOM lines, unless the keeper already has a line for that product
        for (const b of db.prepare('SELECT * FROM packing_bom WHERE material_id = ?').all(row.id)) {
          const clash = db.prepare('SELECT id FROM packing_bom WHERE product_id = ? AND material_id = ?').get(b.product_id, keeper.id);
          if (clash) db.prepare('DELETE FROM packing_bom WHERE id = ?').run(b.id);
          else db.prepare('UPDATE packing_bom SET material_id = ? WHERE id = ?').run(keeper.id, b.id);
        }
        db.prepare('UPDATE packing_txns SET material_id = ? WHERE material_id = ?').run(keeper.id, row.id);
        db.prepare('DELETE FROM packing_materials WHERE id = ?').run(row.id);
      }
    });
  }
}
mergeSharedPacking();

module.exports = db;
