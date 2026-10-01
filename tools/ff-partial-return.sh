#!/usr/bin/env bash
# FlavorFlow — exact partial dispatch return (factory VPS, no APK).
# Target: White Vinegar 1 Ltr, batch 6I0605K, production date 07/09/2026,
#         return exactly 116 CB only. Other products/lines on the same date
#         are never touched. The dispatch history is retained in
#         ff_partial_dispatch_returns and the active dispatch quantity is
#         reduced so reconciliation/invoice demand sees the return.
set -u
DIR=/opt/flavorflow/server
[ -d "$DIR" ] || { echo "FATAL: $DIR nahi mili"; exit 1; }
DB="$DIR/data/erp.db"
BK=/opt/flavorflow/backups
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p "$BK"
[ -f "$DB" ] && cp -a "$DB" "$BK/erp.db.bak-partial-return-$TS" && echo "BACKUP: $BK/erp.db.bak-partial-return-$TS"

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
const RETURN_CB = 116;
const RETURN_KEY = 'VINEGAR-WHITE-1L|' + TARGET_CODE + '|' + TARGET_DATE + '|CB|' + RETURN_CB;
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
  try { db.exec('SAVEPOINT ff_partial_return'); } catch (_) {}
  try { const r = fn(); try { db.exec('RELEASE ff_partial_return'); } catch (_) {} return r; }
  catch (e) { try { db.exec('ROLLBACK TO ff_partial_return'); db.exec('RELEASE ff_partial_return'); } catch (_) {} throw e; }
}
function fail(msg) { out('PARTIAL RETURN NOT APPLIED: ' + msg); process.exitCode = 2; }

try {
  if (!hasTable('products') || !hasTable('batches') || !hasTable('dispatches') || !hasTable('dispatch_items') || !hasTable('inventory')) {
    fail('required stock/dispatch tables missing');
  } else {
    const pc = cols('products'), bc = cols('batches'), dic = cols('dispatch_items'), dc = cols('dispatches');
    if (!pc.includes('name') || !bc.includes('code') || !dic.includes('product_id') || !dic.includes('cartons')) {
      fail('required columns missing (product/name, batch/code, dispatch_items/product_id/cartons)');
    } else {
      const products = db.prepare('SELECT * FROM products').all().filter((p) => {
        const n = norm(p.name);
        return n.includes('vinegar') && n.includes('white') && (n.includes('1ltr') || n.includes('1l'));
      });
      if (products.length !== 1) {
        fail('White Vinegar 1 Ltr product match count is ' + products.length + (products.length ? ': ' + products.map((p) => p.id + ' ' + p.name).join(' | ') : ''));
      } else {
        const product = products[0];
        const batches = db.prepare('SELECT * FROM batches WHERE product_id = ? AND UPPER(TRIM(code)) = UPPER(?)').all(product.id, TARGET_CODE);
        const targetBatches = batches.filter((b) => batchDate(b) === TARGET_DATE);
        const otherDates = batches.filter((b) => batchDate(b) !== TARGET_DATE).map((b) => b.id + ':' + batchDate(b));
        if (targetBatches.length !== 1) {
          fail('target batch count for product ' + product.id + ' is ' + targetBatches.length + (otherDates.length ? '; same code other dates=' + otherDates.join(',') : ''));
        } else if (otherDates.length) {
          fail('same product/code exists on other production dates (' + otherDates.join(',') + '); refusing ambiguous dispatch return');
        } else {
          const batch = targetBatches[0];
          const bCols = cols('batches');
          if (!bCols.includes('used_cb')) {
            fail('batches.used_cb column missing');
          } else {
            const already = hasTable('ff_partial_dispatch_returns') && db.prepare('SELECT id FROM ff_partial_dispatch_returns WHERE return_key = ?').get(RETURN_KEY);
            if (already) {
              out('PARTIAL RETURN ALREADY APPLIED: ' + RETURN_KEY);
            } else {
              const statusSql = dc.includes('status') ? " AND UPPER(COALESCE(d.status, 'DISPATCHED')) <> 'VOID'" : '';
              const rows = db.prepare('SELECT di.*, d.code dispatch_code, d.dispatch_date, d.status dispatch_status FROM dispatch_items di JOIN dispatches d ON d.id = di.dispatch_id WHERE di.product_id = ? AND UPPER(TRIM(COALESCE(di.batch_code, \'\'))) = UPPER(?)' + statusSql + ' ORDER BY COALESCE(d.dispatch_date, \'\'), d.id, di.id').all(product.id, TARGET_CODE);
              const live = rows.filter((r) => Number(r.cartons) > 0);
              const total = live.reduce((s, r) => s + Number(r.cartons || 0), 0);
              if (total < RETURN_CB) {
                fail('matching active dispatched quantity is only ' + total + ' CB; requested ' + RETURN_CB + ' CB');
              } else if (bCols.includes('used_cb') && Number(batch.used_cb || 0) < RETURN_CB) {
                fail('target batch used_cb is ' + Number(batch.used_cb || 0) + ' CB; refusing negative batch balance');
              } else {
                const invCols = cols('inventory');
                const inv = db.prepare('SELECT * FROM inventory WHERE product_id = ?').get(product.id);
                const picks = [];
                let rem = RETURN_CB;
                // Return from the newest matching dispatch lines first. This
                // never touches another product or another batch code.
                for (const r of [...live].sort((a, b) => (String(b.dispatch_date || '') + ':' + b.id).localeCompare(String(a.dispatch_date || '') + ':' + a.id))) {
                  if (rem <= 0) break;
                  const q = Math.min(rem, Number(r.cartons || 0));
                  if (q > 0) { picks.push({ row: r, q }); rem -= q; }
                }
                const dispatchIds = [...new Set(picks.map((x) => Number(x.row.dispatch_id)))];
                let invoiceBlock = '';
                if (hasTable('invoices') && cols('invoices').includes('dispatch_id')) {
                  for (const did of dispatchIds) {
                    const ic = cols('invoices');
                    const status = ic.includes('status') ? " AND UPPER(COALESCE(status, '')) <> 'CANCELLED'" : '';
                    const invr = db.prepare('SELECT number FROM invoices WHERE dispatch_id = ?' + status + ' LIMIT 1').get(did);
                    if (invr) { invoiceBlock = 'dispatch ' + did + ' has active invoice ' + (invr.number || ''); break; }
                  }
                }
                if (invoiceBlock) {
                  fail(invoiceBlock + '; cancel/adjust invoice first');
                } else if (rem !== 0) {
                  fail('could not select exactly ' + RETURN_CB + ' CB');
                } else {
                  tx(() => {
                    db.exec("CREATE TABLE IF NOT EXISTS ff_partial_dispatch_returns (id INTEGER PRIMARY KEY AUTOINCREMENT, return_key TEXT NOT NULL, dispatch_item_id INTEGER NOT NULL, dispatch_id INTEGER NOT NULL, product_id INTEGER NOT NULL, batch_code TEXT NOT NULL, production_date TEXT NOT NULL, cartons REAL NOT NULL, created_at TEXT NOT NULL, created_by TEXT NOT NULL, reason TEXT NOT NULL)");
                    const ins = db.prepare('INSERT INTO ff_partial_dispatch_returns (return_key, dispatch_item_id, dispatch_id, product_id, batch_code, production_date, cartons, created_at, created_by, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
                    for (const x of picks) {
                      const r = x.row;
                      ins.run(RETURN_KEY, Number(r.id), Number(r.dispatch_id), Number(product.id), TARGET_CODE, TARGET_DATE, x.q, now, 'vps-partial-return', 'Exact return: White Vinegar 1 Ltr, production 07/09/2026');
                      db.prepare('UPDATE dispatch_items SET cartons = COALESCE(cartons, 0) - ? WHERE id = ?').run(x.q, Number(r.id));
                    }
                    if (inv) {
                      const set = ['qty_cb = COALESCE(qty_cb, 0) + ?'], args = [RETURN_CB];
                      if (invCols.includes('updated_at')) { set.push('updated_at = ?'); args.push(now); }
                      args.push(product.id);
                      db.prepare('UPDATE inventory SET ' + set.join(', ') + ' WHERE product_id = ?').run(...args);
                    } else {
                      const names = ['product_id', 'qty_cb'], vals = [product.id, RETURN_CB];
                      if (invCols.includes('qty_trays')) { names.push('qty_trays'); vals.push(0); }
                      if (invCols.includes('updated_at')) { names.push('updated_at'); vals.push(now); }
                      db.prepare('INSERT INTO inventory (' + names.join(', ') + ') VALUES (' + names.map(() => '?').join(', ') + ')').run(...vals);
                    }
                    db.prepare('UPDATE batches SET used_cb = COALESCE(used_cb, 0) - ? WHERE id = ?').run(RETURN_CB, Number(batch.id));
                    try { require(path + '/helpers').audit(db, { name: 'vps-partial-return' }, 'RETURN', 'dispatch', Number(picks[0].row.dispatch_id), 'Returned exactly ' + RETURN_CB + ' CB of White Vinegar 1 Ltr, batch ' + TARGET_CODE + ', production ' + TARGET_DATE); } catch (_) {}
                  });
                  out('PARTIAL RETURN DONE');
                  out('PRODUCT: ' + product.name + ' (id ' + product.id + ')');
                  out('BATCH: ' + TARGET_CODE + ' · production ' + TARGET_DATE + ' · batch id ' + batch.id);
                  out('RETURNED: ' + RETURN_CB + ' CB');
                  out('DISPATCH LINES UPDATED: ' + picks.map((x) => (x.row.dispatch_code || x.row.dispatch_id) + ' -> ' + x.q + ' CB').join(', '));
                  out('OTHER PRODUCTS/SAME-DATE LINES: untouched');
                  out('RETURN KEY: ' + RETURN_KEY);
                }
              }
            }
          }
        }
      }
    }
  }
} catch (e) {
  out('PARTIAL RETURN NOT APPLIED: ' + e.message);
  process.exitCode = 2;
}
JS
RC=$?
if [ "$WAS_RUNNING" -eq 1 ]; then systemctl start flavorflow || RC=2; fi
if [ "$RC" -ne 0 ]; then echo "PARTIAL RETURN FAILED — database backup: $BK/erp.db.bak-partial-return-$TS"; exit "$RC"; fi
echo "PARTIAL RETURN VERIFIED — no APK required"
