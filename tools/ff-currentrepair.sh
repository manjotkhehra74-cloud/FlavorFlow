#!/usr/bin/env bash
# FlavorFlow — targeted repair for the two current data-integrity reports.
#
# 1) Dark Soya 220: keep the supplied 21/09 and 25/09 rows plus today's
#    explicitly-created row; zero only older/non-supplied current batch
#    balances. This removes the duplicate 23/09 stock and clears the negative
#    unassigned drift without deleting history.
# 2) White Vinegar 180ml: the latest 26/09 batch 6I2601K has produced=166 but
#    used=166 despite having no non-VOID dispatch line. Restore its remaining
#    166 CB and recompute that product's inventory from completed batches.
#
# Every target is guarded by product/date/code and the no-dispatch check.
# Products not named here are never changed. Full backup + transaction.
set -u
DIR=/opt/flavorflow/server
DB="$DIR/data/erp.db"
[ -f "$DB" ] || { echo "FATAL: DB not found: $DB"; exit 1; }
BK=/opt/flavorflow/backups
TS=$(date +%s)
mkdir -p "$BK"
echo "=== FF-CURRENTREPAIR $(date) ==="
cp -a "$DB" "$BK/erp.db.bak-currentrepair-$TS" || { echo "FATAL: backup failed"; exit 1; }
echo "DB BACKUP: $BK/erp.db.bak-currentrepair-$TS"
systemctl stop flavorflow || true
sleep 1
export FF_DB="$DB" FF_TS="$TS"
node - <<'JS'
let DatabaseSync;
try { DatabaseSync = require('/opt/flavorflow/server/sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) try { DatabaseSync = require('node:sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) { console.log('FATAL: sqlite wrapper unavailable'); process.exit(1); }
const db = new DatabaseSync(process.env.FF_DB);
const n = (v) => Number(v) || 0;
const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '');
const cols = (t) => db.prepare('PRAGMA table_info(' + t + ')').all().map((r) => String(r.name));
const pc = cols('products'), bc = cols('batches'), ic = cols('inventory'), dc = cols('dispatches'), dic = cols('dispatch_items');
const active = pc.includes('active') ? ' AND COALESCE(active, 1) = 1' : '';
const product = (matcher, label) => {
  const rows = db.prepare('SELECT id, name FROM products WHERE 1=1' + active).all().filter((p) => matcher(norm(p.name)));
  if (rows.length !== 1) { console.log('TARGET ' + label + ': expected 1 active product, found ' + rows.length); return null; }
  return rows[0];
};
const dark = product((x) => /darksoya220gm/.test(x), 'Dark Soya 220gm');
const vinegar = product((x) => /whitevinegar180ml/.test(x), 'White Vinegar 180ml');
if (!dark || !vinegar) { try { db.close(); } catch (_) {} process.exit(1); }

const batchSelect = 'SELECT id, code, planned_date, status, planned_cb, produced_cb, used_cb FROM batches WHERE product_id = ? ORDER BY COALESCE(planned_date,\'\'), id';
const darkRows = db.prepare(batchSelect).all(dark.id);
const vinegarRows = db.prepare(batchSelect).all(vinegar.id);
const key = (date, code) => String(date || '').slice(0, 10) + '|' + String(code || '').trim().toUpperCase();
const keepDark = new Set(['2026-09-21|6I1516AKS', '2026-09-25|6I0021AKS', '2026-09-26|6I0021AKS']);
const darkKeep = darkRows.filter((b) => keepDark.has(key(b.planned_date, b.code)));
if (darkKeep.length !== 3) {
  console.log('DARK TARGET ABORT: expected exactly 3 current rows (21/09, 25/09, today), found ' + darkKeep.length +
    ' — ' + darkKeep.map((b) => '#' + b.id + ' ' + key(b.planned_date, b.code)).join(', '));
  try { db.close(); } catch (_) {}
  process.exit(1);
}
const todayV = vinegarRows.filter((b) => key(b.planned_date, b.code) === '2026-09-26|6I2601K');
if (todayV.length !== 1) {
  console.log('VINEGAR TARGET ABORT: expected exactly 1 row 2026-09-26 / 6I2601K, found ' + todayV.length);
  try { db.close(); } catch (_) {}
  process.exit(1);
}
const vBatch = todayV[0];

// Prove the new vinegar batch has no non-VOID dispatch line before touching it.
let dispatchDemand = 0;
if (dic.includes('product_id') && dic.includes('batch_code') && dic.includes('cartons') && dic.includes('dispatch_id') && dc.includes('id')) {
  const status = dc.includes('status') ? " AND UPPER(COALESCE(d.status, '')) <> 'VOID'" : '';
  const lines = db.prepare('SELECT COALESCE(di.cartons,0) cb FROM dispatch_items di JOIN dispatches d ON d.id = di.dispatch_id WHERE di.product_id = ? AND UPPER(TRIM(di.batch_code)) = UPPER(?)' + status).all(vinegar.id, vBatch.code);
  dispatchDemand = lines.reduce((s, r) => s + n(r.cb), 0);
}
if (dispatchDemand !== 0) {
  console.log('VINEGAR TARGET ABORT: ' + vBatch.code + ' has non-VOID dispatch demand ' + dispatchDemand + ' CB');
  try { db.close(); } catch (_) {}
  process.exit(1);
}

const inventory = (pid) => db.prepare('SELECT * FROM inventory WHERE product_id = ?').get(pid);
const beforeDark = inventory(dark.id), beforeVinegar = inventory(vinegar.id);
const darkBatchBefore = darkRows.reduce((s, b) => s + (String(b.status || '').toUpperCase() === 'COMPLETED' ? n(b.produced_cb) - n(b.used_cb) : 0), 0);
const vinegarBatchBefore = vinegarRows.reduce((s, b) => s + (String(b.status || '').toUpperCase() === 'COMPLETED' ? n(b.produced_cb) - n(b.used_cb) : 0), 0);
console.log('BEFORE Dark Soya: inventory=' + n(beforeDark && beforeDark.qty_cb) + ' batch=' + darkBatchBefore + ' drift=' + (n(beforeDark && beforeDark.qty_cb) - darkBatchBefore));
console.log('BEFORE White Vinegar 180: inventory=' + n(beforeVinegar && beforeVinegar.qty_cb) + ' batch=' + vinegarBatchBefore + ' target=' + vBatch.code + ' produced=' + n(vBatch.produced_cb) + ' used=' + n(vBatch.used_cb));

try {
  db.exec('BEGIN');
  const updUsed = db.prepare('UPDATE batches SET used_cb = ? WHERE id = ?');
  for (const b of darkRows) {
    if (!keepDark.has(key(b.planned_date, b.code))) {
      updUsed.run(n(b.produced_cb), b.id);
      if (n(b.produced_cb) - n(b.used_cb) > 0) console.log('DARK ZEROED: #' + b.id + ' ' + key(b.planned_date, b.code) + ' remaining → 0');
    }
  }
  // The target batch was incorrectly marked fully used; no dispatch exists.
  updUsed.run(0, vBatch.id);
  console.log('VINEGAR RESTORED: #' + vBatch.id + ' ' + vBatch.code + ' ' + vBatch.planned_date + ' remaining → ' + n(vBatch.produced_cb) + ' CB');

  const updateInv = db.prepare('UPDATE inventory SET qty_cb = ?' + (ic.includes('qty_trays') ? ', qty_trays = 0' : '') + ' WHERE product_id = ?');
  const sumCompleted = (pid) => {
    const rows = db.prepare("SELECT produced_cb, used_cb FROM batches WHERE product_id = ? AND UPPER(COALESCE(status,'')) = 'COMPLETED'").all(pid);
    return rows.reduce((s, b) => s + Math.max(0, n(b.produced_cb) - n(b.used_cb)), 0);
  };
  const darkAfter = sumCompleted(dark.id);
  const vinegarAfter = sumCompleted(vinegar.id);
  updateInv.run(darkAfter, dark.id);
  updateInv.run(vinegarAfter, vinegar.id);
  console.log('INVENTORY Dark Soya 220 → ' + darkAfter + ' CB');
  console.log('INVENTORY White Vinegar 180 → ' + vinegarAfter + ' CB');
  db.exec('COMMIT');
  console.log('CURRENTREPAIR VERIFIED — only Dark Soya 220 and White Vinegar 180ml changed.');
} catch (e) {
  try { db.exec('ROLLBACK'); } catch (_) {}
  console.log('CURRENTREPAIR FAILED — rolled back: ' + e.message);
  process.exit(1);
} finally { try { db.close(); } catch (_) {} }
JS
RC=$?
systemctl start flavorflow || true
sleep 3
curl -s -m 6 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAILED"
if [ "$RC" -eq 0 ]; then echo "FF-CURRENTREPAIR DONE"; else echo "FF-CURRENTREPAIR STOPPED (code $RC)"; fi
exit "$RC"
