#!/usr/bin/env bash
# FlavorFlow — read-only integrity diagnostic for the two reported products.
# No writes, no service stop/restart. It prints inventory, every batch balance,
# dispatch allocations/status and unassigned drift so a repair can be exact.
set -u
DIR=/opt/flavorflow/server
DB="$DIR/data/erp.db"
[ -f "$DB" ] || { echo "FATAL: DB not found: $DB"; exit 1; }
export FF_DB="$DB"
echo "=== FF-CURRENTDIAG $(date) ==="
node - <<'JS'
let db;
try { db = require('/opt/flavorflow/server/db'); } catch (e) { console.log('DB OPEN FAILED: ' + e.message); process.exit(1); }
const n = (v) => Number(v) || 0;
const cols = (t) => db.prepare('PRAGMA table_info(' + t + ')').all().map((r) => String(r.name));
const pc = cols('products'), bc = cols('batches'), ic = cols('inventory'), dc = cols('dispatches'), dic = cols('dispatch_items');
const products = db.prepare('SELECT id, name' + (pc.includes('active') ? ', active' : '') + ' FROM products ORDER BY id').all()
  .filter((p) => /dark\s*soya\s*220|white\s*vinegar\s*180/i.test(p.name));
console.log('PRODUCTS: ' + JSON.stringify(products));

const dateCol = dc.includes('dispatch_date') ? 'd.dispatch_date' : dc.includes('date') ? 'd.date' : dc.includes('created_at') ? 'd.created_at' : "''";
const dispatchStatus = dc.includes('status') ? ', d.status' : '';
const dispatchJoin = dic.includes('dispatch_id') && dc.includes('id') ? ' JOIN dispatches d ON d.id = di.dispatch_id' : '';
for (const p of products) {
  console.log('\nPRODUCT #' + p.id + ' ' + p.name + ' active=' + (p.active == null ? 1 : p.active));
  const inv = db.prepare('SELECT * FROM inventory WHERE product_id = ?').get(p.id);
  console.log('INVENTORY: ' + JSON.stringify(inv || null));
  const select = [
    'id', 'code', 'product_id', 'planned_date', 'status', 'planned_cb', 'produced_cb', 'used_cb',
    ...(bc.includes('produced_trays') ? ['produced_trays'] : []),
    ...(bc.includes('used_trays') ? ['used_trays'] : []),
    ...(bc.includes('created_at') ? ['created_at'] : []),
    ...(bc.includes('completed_at') ? ['completed_at'] : []),
  ].join(', ');
  const batches = db.prepare('SELECT ' + select + ' FROM batches WHERE product_id = ? ORDER BY COALESCE(planned_date,\'\'), id').all(p.id);
  let batchLeft = 0;
  for (const b of batches) {
    const left = n(b.produced_cb) - n(b.used_cb);
    batchLeft += String(b.status || '').toUpperCase() === 'COMPLETED' ? left : 0;
    console.log('BATCH: ' + JSON.stringify(Object.assign({}, b, { remaining_cb: left })));
  }
  console.log('SUMMARY: batch_completed_remaining=' + batchLeft + ' inventory_qty_cb=' + n(inv && inv.qty_cb) + ' unassigned_drift=' + (n(inv && inv.qty_cb) - batchLeft));

  if (dic.includes('product_id')) {
    const lineCols = ['di.id line_id', 'di.product_id', ...(dic.includes('dispatch_id') ? ['di.dispatch_id'] : []), ...(dic.includes('batch_code') ? ['di.batch_code'] : []), ...(dic.includes('cartons') ? ['di.cartons'] : []), ...(dic.includes('trays') ? ['di.trays'] : [])];
    const q = 'SELECT ' + lineCols.join(', ') + (dispatchStatus ? dispatchStatus : '') + (dispatchJoin ? ', ' + dateCol + ' dispatch_date' : '') +
      ' FROM dispatch_items di' + dispatchJoin + ' WHERE di.product_id = ? ORDER BY di.id';
    for (const row of db.prepare(q).all(p.id)) console.log('DISPATCH_LINE: ' + JSON.stringify(row));
  }
}
console.log('\nRECENT COMPLETED BATCHES (last 15 by id)');
const recent = db.prepare("SELECT id, product_id, code, planned_date, status, planned_cb, produced_cb, used_cb FROM batches ORDER BY id DESC LIMIT 15").all();
for (const r of recent) console.log('RECENT: ' + JSON.stringify(r));
console.log('\nROUTE/SCHEMA: batches=' + JSON.stringify(bc) + ' dispatches=' + JSON.stringify(dc) + ' dispatch_items=' + JSON.stringify(dic));
try { db.close(); } catch (_) {}
console.log('=== READ ONLY DONE ===');
JS
curl -s -m 6 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAILED"
echo "=== FF-CURRENTDIAG END ==="
