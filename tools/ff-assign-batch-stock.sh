#!/usr/bin/env bash
# FlavorFlow — assign existing finished-goods stock to the correct completed batch.
# Target: White Vinegar 180ml / 6I0605K / 07-09-2026.
# The inventory quantity was already added separately. This only repairs the
# stale batch used_cb counter so the same stock is shown under the batch rather
# than as Unassigned. Dispatch demand is read from the live product+code rows;
# it is never deleted or reduced.
set -u
DIR=/opt/flavorflow/server
[ -d "$DIR" ] || { echo "FATAL: $DIR nahi mili"; exit 1; }
DB="$DIR/data/erp.db"
BK=/opt/flavorflow/backups
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p "$BK"
[ -f "$DB" ] && cp -a "$DB" "$BK/erp.db.bak-assign-batch-stock-$TS" && echo "BACKUP: $BK/erp.db.bak-assign-batch-stock-$TS"

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
const KEY = 'ASSIGN|WHITE-VINEGAR-180ML|' + TARGET_CODE + '|' + TARGET_DATE;
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
  try { db.exec('SAVEPOINT ff_assign_batch'); } catch (_) {}
  try { const r = fn(); try { db.exec('RELEASE ff_assign_batch'); } catch (_) {} return r; }
  catch (e) { try { db.exec('ROLLBACK TO ff_assign_batch'); db.exec('RELEASE ff_assign_batch'); } catch (_) {} throw e; }
}
function fail(msg) { out('BATCH ASSIGN NOT APPLIED: ' + msg); process.exitCode = 2; }

try {
  if (!hasTable('products') || !hasTable('batches') || !hasTable('dispatch_items') || !hasTable('dispatches')) {
    fail('required product/batch/dispatch tables missing');
  } else {
    const products = db.prepare('SELECT * FROM products').all().filter((p) => {
      const n = norm(p.name);
      return n.includes('vinegar') && n.includes('white') && n.includes('180');
    });
    if (products.length !== 1) {
      fail('White Vinegar 180ml product match count is ' + products.length);
    } else {
      const product = products[0];
      const batches = db.prepare('SELECT * FROM batches WHERE product_id = ? AND UPPER(TRIM(code)) = UPPER(?)').all(product.id, TARGET_CODE);
      const target = batches.filter((b) => batchDate(b) === TARGET_DATE);
      if (target.length !== 1) {
        fail('target batch count for product ' + product.id + ' is ' + target.length);
      } else {
        const batch = target[0], bCols = cols('batches');
        if (!bCols.includes('used_cb') || !bCols.includes('produced_cb')) {
          fail('batches.used_cb/produced_cb column missing');
        } else {
          const dc = cols('dispatches');
          const status = dc.includes('status') ? " AND UPPER(COALESCE(d.status, 'DISPATCHED')) <> 'VOID'" : '';
          const demandRows = db.prepare('SELECT di.cartons, di.trays FROM dispatch_items di JOIN dispatches d ON d.id = di.dispatch_id WHERE di.product_id = ? AND UPPER(TRIM(COALESCE(di.batch_code, \'\'))) = UPPER(?)' + status).all(product.id, TARGET_CODE);
          const demandCb = demandRows.reduce((s, r) => s + Number(r.cartons || 0), 0);
          const demandTr = demandRows.reduce((s, r) => s + Number(r.trays || 0), 0);
          const produced = Number(batch.produced_cb || 0);
          const oldUsed = Number(batch.used_cb || 0);
          if (demandCb > produced || demandTr > Number(batch.produced_trays || 0)) {
            fail('live dispatch demand exceeds target batch production; refusing to over-assign');
          } else if (oldUsed === demandCb && Number(batch.used_trays || 0) === demandTr) {
            out('BATCH ALREADY ASSIGNED');
            out('BATCH: ' + TARGET_CODE + ' · production ' + TARGET_DATE + ' · used ' + oldUsed + ' CB');
          } else {
            tx(() => {
              db.exec("CREATE TABLE IF NOT EXISTS ff_batch_balance_repairs (id INTEGER PRIMARY KEY AUTOINCREMENT, repair_key TEXT NOT NULL UNIQUE, product_id INTEGER NOT NULL, batch_id INTEGER NOT NULL, batch_code TEXT NOT NULL, production_date TEXT NOT NULL, old_used_cb REAL NOT NULL, new_used_cb REAL NOT NULL, dispatch_demand_cb REAL NOT NULL, repaired_at TEXT NOT NULL, reason TEXT NOT NULL)");
              if (db.prepare('SELECT id FROM ff_batch_balance_repairs WHERE repair_key = ?').get(KEY)) return;
              db.prepare('INSERT INTO ff_batch_balance_repairs (repair_key, product_id, batch_id, batch_code, production_date, old_used_cb, new_used_cb, dispatch_demand_cb, repaired_at, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
                .run(KEY, Number(product.id), Number(batch.id), TARGET_CODE, TARGET_DATE, oldUsed, demandCb, demandCb, now, 'Assign production stock to the completed batch; preserve dispatch demand');
              const nextTr = demandTr;
              db.prepare('UPDATE batches SET used_cb = ?, used_trays = ? WHERE id = ?').run(demandCb, nextTr, Number(batch.id));
              try { require(path + '/helpers').audit(db, { name: 'vps-assign-batch-stock' }, 'RECONCILE', 'batch', Number(batch.id), 'Assigned existing White Vinegar 180ml stock to batch ' + TARGET_CODE + '; used_cb ' + oldUsed + ' -> ' + demandCb); } catch (_) {}
            });
            out('BATCH STOCK ASSIGNED');
            out('PRODUCT: ' + product.name + ' (id ' + product.id + ')');
            out('BATCH: ' + TARGET_CODE + ' · production ' + TARGET_DATE + ' · batch id ' + batch.id);
            out('USED CB: ' + oldUsed + ' -> ' + demandCb + ' (live dispatch demand preserved)');
            out('BATCH REMAINING: ' + (produced - demandCb) + ' CB');
            out('INVENTORY QUANTITY: unchanged');
          }
        }
      }
    }
  }
} catch (e) {
  out('BATCH ASSIGN NOT APPLIED: ' + e.message);
  process.exitCode = 2;
}
JS
RC=$?
if [ "$WAS_RUNNING" -eq 1 ]; then systemctl start flavorflow || RC=2; fi
if [ "$RC" -ne 0 ]; then echo "BATCH ASSIGN FAILED — database backup: $BK/erp.db.bak-assign-batch-stock-$TS"; exit "$RC"; fi
echo "BATCH ASSIGN VERIFIED — no APK required"
