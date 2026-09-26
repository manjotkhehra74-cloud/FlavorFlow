#!/usr/bin/env bash
# FlavorFlow — read-only target batch check.
# Shows the real product/batch rows before any manual sheet correction. It does
# not stop the service and does not write anything.
set -u
DIR=/opt/flavorflow/server
DB="$DIR/data/erp.db"
[ -f "$DB" ] || { echo "DB not found: $DB"; exit 1; }
export FF_DB="$DB"
node - <<'JS'
let db;
try { db = require('/opt/flavorflow/server/db'); } catch (e) { console.log('DB OPEN FAILED: ' + e.message); process.exit(1); }
const n = (v) => Number(v) || 0;
const cols = (t) => db.prepare('PRAGMA table_info(' + t + ')').all().map((r) => String(r.name));
const pc = cols('products'), bc = cols('batches'), ic = cols('inventory');
const trays = bc.includes('produced_trays') ? ', produced_trays' : '';
const usedTrays = bc.includes('used_trays') ? ', used_trays' : '';
const active = pc.includes('active') ? ', active' : '';
console.log('=== FF-TARGETPEEK ' + new Date().toISOString() + ' ===');
const products = db.prepare('SELECT id, name' + active + ' FROM products ORDER BY id').all()
  .filter((p) => /dark\s*soya|soya\s*sauce\s*740/i.test(p.name));
for (const p of products) {
  const inv = db.prepare('SELECT * FROM inventory WHERE product_id = ?').get(p.id);
  console.log('\nPRODUCT #' + p.id + ' ' + p.name + ' active=' + (p.active == null ? 1 : p.active));
  console.log('INVENTORY: ' + JSON.stringify(inv || null));
  const rows = db.prepare("SELECT id, code, product_id, planned_date, status, planned_cb, produced_cb, used_cb" + trays + usedTrays + " FROM batches WHERE product_id = ? ORDER BY COALESCE(planned_date,''), id").all(p.id);
  for (const b of rows) console.log('BATCH: ' + JSON.stringify(Object.assign({}, b, { remaining_cb: n(b.produced_cb) - n(b.used_cb), remaining_trays: n(b.produced_trays) - n(b.used_trays) })));
}
console.log('\nCODE LOOKUP');
for (const code of ['6I1516AKS', '6I0021AKS', '6I1819AK', '6I1819BK']) {
  const rows = db.prepare("SELECT id, code, product_id, planned_date, status, planned_cb, produced_cb, used_cb FROM batches WHERE UPPER(TRIM(code)) = UPPER(?) ORDER BY product_id, id").all(code);
  console.log(code + ': ' + JSON.stringify(rows));
}
console.log('=== READ ONLY DONE ===');
try { db.close(); } catch (_) {}
JS
