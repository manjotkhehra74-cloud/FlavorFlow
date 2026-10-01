#!/usr/bin/env bash
# FlavorFlow — idempotent production stock addition (factory VPS, no APK).
# Target: White Vinegar 180ml, batch 6I0605K, planned/production date
# 07/09/2026, add exactly 116 CB to finished-goods inventory.
set -u
DIR=/opt/flavorflow/server
[ -d "$DIR" ] || { echo "FATAL: $DIR nahi mili"; exit 1; }
DB="$DIR/data/erp.db"
BK=/opt/flavorflow/backups
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p "$BK"
[ -f "$DB" ] && cp -a "$DB" "$BK/erp.db.bak-add-batch-stock-$TS" && echo "BACKUP: $BK/erp.db.bak-add-batch-stock-$TS"

WAS_RUNNING=0
if systemctl is-active --quiet flavorflow 2>/dev/null; then
  systemctl stop flavorflow
  WAS_RUNNING=1
fi

set +e
DIR="$DIR" node - <<'JS'
'use strict';
const path = process.env.DIR;
const db = require(path + '/db');
const TARGET_CODE = '6I0605K';
const TARGET_DATE = '2026-09-07';
const ADD_CB = 116;
const ADD_KEY = 'PRODUCTION|WHITE-VINEGAR-180ML|' + TARGET_CODE + '|' + TARGET_DATE + '|CB|' + ADD_CB;
const now = new Date().toISOString();
const out = (s) => console.log(String(s));
const cols = (t) => { try { return db.prepare('PRAGMA table_info(' + t + ')').all().map((r) => String(r.name)); } catch (_) { return []; } };
const hasTable = (t) => { try { return !!db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(t); } catch (_) { return false; } };
const norm = (v) => String(v == null ? '' : v).trim().toLowerCase().replace(/[^a-z0-9]+/g, '');
function dateNorm(v) {
  const s = String(v == null ? '' : v).trim();
  let m = /^(\d{4})[-\/]([01]?\d)[-\/]([0-3]?\d)/.exec(s);
  if (m) return m[1] + '-' + String(m[2]).padStart(2, '0') + '-' + String(m[3]).padStart(2, '0');
  m = /^([0-3]?\d)[-\/]([01]?\d)[-\/](\d{2}|\d{4})/.exec(s);
  if (m) return String(Number(m[3]) < 100 ? 2000 + Number(m[3]) : Number(m[3])).padStart(4, '0') + '-' + String(m[2]).padStart(2, '0') + '-' + String(m[1]).padStart(2, '0');
  return s.slice(0, 10);
}
function batchDate(r) {
  for (const k of ['planned_date', 'production_date', 'mfg_date', 'manufacturing_date', 'date']) if (r[k] != null && String(r[k]).trim()) return dateNorm(r[k]);
  return '';
}
function tx(fn) {
  try { db.exec('SAVEPOINT ff_add_batch_stock'); } catch (_) {}
  try { const r = fn(); try { db.exec('RELEASE ff_add_batch_stock'); } catch (_) {} return r; }
  catch (e) { try { db.exec('ROLLBACK TO ff_add_batch_stock'); db.exec('RELEASE ff_add_batch_stock'); } catch (_) {} throw e; }
}
function fail(msg) { out('BATCH STOCK NOT ADDED: ' + msg); process.exitCode = 2; }

try {
  if (!hasTable('products') || !hasTable('batches') || !hasTable('inventory')) {
    fail('products/batches/inventory table missing');
  } else {
    const products = db.prepare('SELECT * FROM products').all().filter((p) => {
      const n = norm(p.name);
      return n.includes('vinegar') && n.includes('white') && n.includes('180');
    });
    if (products.length !== 1) {
      fail('White Vinegar 180ml product match count is ' + products.length + (products.length ? ': ' + products.map((p) => p.id + ' ' + p.name).join(' | ') : ''));
    } else {
      const product = products[0];
      const batches = db.prepare('SELECT * FROM batches WHERE product_id = ? AND UPPER(TRIM(code)) = UPPER(?)').all(product.id, TARGET_CODE);
      const target = batches.filter((b) => batchDate(b) === TARGET_DATE);
      if (target.length !== 1) {
        fail('target batch count for product ' + product.id + ' is ' + target.length);
      } else {
        const batch = target[0];
        const batchCols = cols('batches');
        if (hasTable('ff_batch_inventory_additions') && db.prepare('SELECT id FROM ff_batch_inventory_additions WHERE add_key = ?').get(ADD_KEY)) {
          out('BATCH STOCK ALREADY ADDED: ' + ADD_KEY);
        } else {
          const invCols = cols('inventory');
          if (!invCols.includes('product_id') || !invCols.includes('qty_cb')) {
            fail('inventory.product_id/qty_cb column missing');
          } else {
            const inv = db.prepare('SELECT * FROM inventory WHERE product_id = ?').get(product.id);
            const before = Number(inv && inv.qty_cb || 0);
            const after = before + ADD_CB;
            tx(() => {
              db.exec("CREATE TABLE IF NOT EXISTS ff_batch_inventory_additions (id INTEGER PRIMARY KEY AUTOINCREMENT, add_key TEXT NOT NULL UNIQUE, product_id INTEGER NOT NULL, batch_id INTEGER NOT NULL, batch_code TEXT NOT NULL, production_date TEXT NOT NULL, cartons REAL NOT NULL, created_at TEXT NOT NULL, reason TEXT NOT NULL)");
              if (db.prepare('SELECT id FROM ff_batch_inventory_additions WHERE add_key = ?').get(ADD_KEY)) return;
              const ins = db.prepare('INSERT INTO ff_batch_inventory_additions (add_key, product_id, batch_id, batch_code, production_date, cartons, created_at, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
              ins.run(ADD_KEY, Number(product.id), Number(batch.id), TARGET_CODE, TARGET_DATE, ADD_CB, now, 'Production stock added for White Vinegar 180ml');
              if (inv) {
                const set = ['qty_cb = COALESCE(qty_cb, 0) + ?'], args = [ADD_CB];
                if (invCols.includes('updated_at')) { set.push('updated_at = ?'); args.push(now); }
                args.push(product.id);
                db.prepare('UPDATE inventory SET ' + set.join(', ') + ' WHERE product_id = ?').run(...args);
              } else {
                const names = ['product_id', 'qty_cb'], vals = [product.id, ADD_CB];
                if (invCols.includes('qty_trays')) { names.push('qty_trays'); vals.push(0); }
                if (invCols.includes('updated_at')) { names.push('updated_at'); vals.push(now); }
                db.prepare('INSERT INTO inventory (' + names.join(', ') + ') VALUES (' + names.map(() => '?').join(', ') + ')').run(...vals);
              }
              if (hasTable('stock_journal')) {
                const sj = cols('stock_journal');
                const values = {
                  item_type: 'product', item_id: Number(product.id), qty: ADD_CB, qty2: 0,
                  balance: after, balance2: 0, kind: 'PRODUCTION', ref: TARGET_CODE,
                  doc2: '', party: '', note: 'Production stock added · White Vinegar 180ml · 07/09/2026',
                  link: '/stock', req_id: 'ff-add-batch-stock', user_id: null, user_name: 'vps-add-batch-stock',
                  txn_date: TARGET_DATE, created_at: now, backfilled: 0
                };
                const names = sj.filter((c) => Object.prototype.hasOwnProperty.call(values, c));
                if (names.length) db.prepare('INSERT INTO stock_journal (' + names.join(', ') + ') VALUES (' + names.map(() => '?').join(', ') + ')').run(...names.map((n) => values[n]));
              }
              try { require(path + '/helpers').audit(db, { name: 'vps-add-batch-stock' }, 'PRODUCTION', 'product', Number(product.id), 'Added ' + ADD_CB + ' CB to inventory for batch ' + TARGET_CODE + ' dated ' + TARGET_DATE); } catch (_) {}
            });
            out('BATCH STOCK ADDED');
            out('PRODUCT: ' + product.name + ' (id ' + product.id + ')');
            out('BATCH: ' + TARGET_CODE + ' · production ' + TARGET_DATE + ' · batch id ' + batch.id);
            out('INVENTORY: ' + before + ' CB -> ' + after + ' CB (added ' + ADD_CB + ' CB)');
            out('RETURN/ADD KEY: ' + ADD_KEY);
          }
        }
      }
    }
  }
} catch (e) {
  out('BATCH STOCK NOT ADDED: ' + e.message);
  process.exitCode = 2;
}
JS
RC=$?
if [ "$WAS_RUNNING" -eq 1 ]; then systemctl start flavorflow || RC=2; fi
if [ "$RC" -ne 0 ]; then echo "BATCH STOCK FAILED — database backup: $BK/erp.db.bak-add-batch-stock-$TS"; exit "$RC"; fi
echo "BATCH STOCK VERIFIED — no APK required"
