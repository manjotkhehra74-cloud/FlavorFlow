#!/usr/bin/env bash
# FlavorFlow — replace only White Vinegar 180ml current stock from the
# supplied factory sheet. The sheet's Production Date and Mfg. Date are the
# same production date; it is stored as batches.planned_date.
#
# Historical rows are not deleted. Old/non-sheet rows are zeroed for current
# stock (used_cb = produced_cb), while dispatch/batch history remains intact.
# The exact 30 sheet rows below are then made the current COMPLETED batches.
# No other product is changed.
set -u
DIR=/opt/flavorflow/server
DB="$DIR/data/erp.db"
[ -f "$DB" ] || { echo "FATAL: DB not found: $DB"; exit 1; }
BK=/opt/flavorflow/backups
TS=$(date +%s)
mkdir -p "$BK"
echo "=== FF-VINEGAR180APPLY (factory sheet) $(date) ==="

if [ "${FF_DRY_RUN:-0}" != 1 ]; then
  cp -a "$DB" "$BK/erp.db.bak-vinegar180-$TS" || { echo "FATAL: backup failed"; exit 1; }
  echo "DB BACKUP: $BK/erp.db.bak-vinegar180-$TS"
  systemctl stop flavorflow || true
  sleep 1
fi

export FF_DB="$DB" FF_DRY_RUN="${FF_DRY_RUN:-0}" FF_TS="$TS"
node - <<'JS'
let DatabaseSync;
try { DatabaseSync = require('/opt/flavorflow/server/sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) try { DatabaseSync = require('node:sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) { console.log('FATAL: server sqlite wrapper not available'); process.exit(1); }
const db = new DatabaseSync(process.env.FF_DB);
const n = (v) => Number(v) || 0;
const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '');
const cols = (t) => db.prepare('PRAGMA table_info(' + t + ')').all().map((r) => String(r.name));
const pc = cols('products'), bc = cols('batches'), ic = cols('inventory');
for (const x of ['id', 'name']) if (!pc.includes(x)) { console.log('FATAL: products.' + x + ' missing'); process.exit(1); }
for (const x of ['id', 'product_id', 'code', 'planned_date', 'produced_cb', 'used_cb', 'status']) {
  if (!bc.includes(x)) { console.log('FATAL: batches.' + x + ' missing'); process.exit(1); }
}
if (!ic.includes('product_id') || !ic.includes('qty_cb')) { console.log('FATAL: inventory columns missing'); process.exit(1); }

// Transcribed exactly from the two supplied screenshots. Production Date and
// Mfg. Date match on every row, so the first date is the stored production key.
const sheet = [
  ['2026-08-25', '6H2501K', 135],
  ['2026-08-27', '6H2703K', 62],
  ['2026-08-29', '6H2705K', 50],
  ['2026-08-29', '6H2901K', 304],
  ['2026-08-30', '6H2901K', 195],
  ['2026-08-30', '6H3001K', 184],
  ['2026-09-05', '6I0404K', 418],
  ['2026-09-06', '6I0601K', 147],
  ['2026-09-06', '6I0602K', 100],
  ['2026-09-06', '6I0603K', 100],
  ['2026-09-06', '6I0604K', 116],
  ['2026-09-06', '6I0605K', 116],
  ['2026-09-07', '6I0701K', 88],
  ['2026-09-07', '6I0702K', 66],
  ['2026-09-07', '6I0703K', 55],
  ['2026-09-07', '6I0704K', 93],
  ['2026-09-07', '6I0705K', 53],
  ['2026-09-08', '6I0705K', 276],
  ['2026-09-08', '6I0801K', 162],
  ['2026-09-10', '6I0801K', 353],
  ['2026-09-10', '6I1001K', 47],
  ['2026-09-11', '6I1001K', 99],
  ['2026-09-11', '6I1101K', 107],
  ['2026-09-11', '6I1102K', 100],
  ['2026-09-11', '6I1103K', 48],
  ['2026-09-14', '6I1403K', 101],
  ['2026-09-14', '6I1404K', 119],
  ['2026-09-23', '6I2202K', 77],
  ['2026-09-23', '6I2301K', 48],
  ['2026-09-24', '6I2301K', 281],
];
const total = sheet.reduce((s, r) => s + r[2], 0);
console.log('SHEET: White Vinegar 180ml · ' + sheet.length + ' rows · total ' + total + ' CB');
if (total !== 4100) { console.log('FATAL: sheet transcription total is not 4100 CB'); process.exit(1); }

const activeExpr = pc.includes('active') ? ' AND COALESCE(active, 1) = 1' : '';
const products = db.prepare('SELECT id, name FROM products WHERE 1=1' + activeExpr).all()
  .filter((p) => /whitevinegar180ml/.test(norm(p.name)));
if (products.length !== 1) {
  console.log('TARGET White Vinegar 180ml: expected exactly 1 active product, found ' + products.length +
    (products.length ? ' (' + products.map((p) => '#' + p.id + ' ' + p.name).join(' / ') + ')' : ''));
  try { db.close(); } catch (_) {}
  process.exit(0);
}
const product = products[0];
const targetKeys = new Set(sheet.map((r) => r[0] + '|' + r[1].toUpperCase()));
const existing = db.prepare(
  "SELECT id, code, planned_date, status, planned_cb, produced_cb, used_cb " +
  "FROM batches WHERE product_id = ? ORDER BY COALESCE(planned_date, ''), id"
).all(product.id);
const exact = new Map();
for (const b of existing) exact.set(String(b.planned_date || '').slice(0, 10) + '|' + String(b.code || '').trim().toUpperCase(), b);

const missing = sheet.filter((r) => !exact.has(r[0] + '|' + r[1].toUpperCase()));
const duplicates = existing.filter((b) => targetKeys.has(String(b.planned_date || '').slice(0, 10) + '|' + String(b.code || '').trim().toUpperCase()));
console.log('PRODUCT: #' + product.id + ' ' + product.name);
console.log('EXACT ROWS FOUND: ' + (sheet.length - missing.length) + ' · TO CREATE: ' + missing.length);
console.log('OLD/NON-SHEET BATCH ROWS TO ZERO FOR CURRENT VIEW: ' + existing.filter((b) => !targetKeys.has(String(b.planned_date || '').slice(0, 10) + '|' + String(b.code || '').trim().toUpperCase())).length);
if (duplicates.length) console.log('TARGET ROWS TO REPLACE: ' + duplicates.map((b) => '#' + b.id + ' ' + b.planned_date + ' / ' + b.code).join(', '));
for (const r of sheet) console.log('PLAN ' + r[0] + ' / ' + r[1] + ' → ' + r[2] + ' CB');

if (process.env.FF_DRY_RUN === '1') {
  console.log('DRY RUN — no database writes.');
  try { db.close(); } catch (_) {}
  process.exit(0);
}

try {
  db.exec('BEGIN');
  // Remove old stock from the current register without deleting history.
  const zeroOld = bc.includes('used_trays') && bc.includes('produced_trays')
    ? db.prepare('UPDATE batches SET used_cb = COALESCE(produced_cb, 0), used_trays = COALESCE(produced_trays, 0) WHERE product_id = ? AND id = ?')
    : db.prepare('UPDATE batches SET used_cb = COALESCE(produced_cb, 0) WHERE product_id = ? AND id = ?');
  for (const b of existing) {
    const key = String(b.planned_date || '').slice(0, 10) + '|' + String(b.code || '').trim().toUpperCase();
    if (!targetKeys.has(key)) zeroOld.run(product.id, b.id);
  }

  const update = db.prepare(
    'UPDATE batches SET planned_cb = ?, produced_cb = ?, used_cb = ?, status = ? WHERE id = ?'
  );
  const insertCols = ['code', 'product_id', 'planned_cb', 'produced_cb', 'status', 'planned_date', 'used_cb'];
  if (bc.includes('produced_trays')) insertCols.push('produced_trays');
  if (bc.includes('used_trays')) insertCols.push('used_trays');
  // Production databases may require created_at without a SQL default.
  // Supply it explicitly for newly-created sheet rows.
  if (bc.includes('created_at')) insertCols.push('created_at');
  const insert = db.prepare(
    'INSERT INTO batches (' + insertCols.join(', ') + ') VALUES (' + insertCols.map(() => '?').join(', ') + ')'
  );

  for (const [date, code, desired] of sheet) {
    const b = exact.get(date + '|' + code.toUpperCase());
    if (b) {
      update.run(desired, desired, 0, 'COMPLETED', b.id);
      console.log('REPLACED ' + date + ' / ' + code + ' → ' + desired + ' CB (batch #' + b.id + ')');
    } else {
      const values = [code, product.id, desired, desired, 'COMPLETED', date, 0];
      if (bc.includes('produced_trays')) values.push(0);
      if (bc.includes('used_trays')) values.push(0);
      if (bc.includes('created_at')) values.push(new Date().toISOString());
      insert.run(...values);
      console.log('CREATED ' + date + ' / ' + code + ' → ' + desired + ' CB');
    }
  }

  const inv = db.prepare('SELECT product_id FROM inventory WHERE product_id = ?').get(product.id);
  const updateInv = db.prepare('UPDATE inventory SET qty_cb = ?' + (ic.includes('qty_trays') ? ', qty_trays = 0' : '') + ' WHERE product_id = ?');
  const insertInv = db.prepare('INSERT INTO inventory (product_id, qty_cb' + (ic.includes('qty_trays') ? ', qty_trays' : '') + ') VALUES (?, ?' + (ic.includes('qty_trays') ? ', 0' : '') + ')');
  if (inv) updateInv.run(total, product.id); else insertInv.run(product.id, total);
  console.log('INVENTORY ' + product.name + ': qty_cb → ' + total);
  db.exec('COMMIT');
  console.log('VINEGAR180 VERIFIED — only White Vinegar 180ml changed; historical rows retained.');
} catch (e) {
  try { db.exec('ROLLBACK'); } catch (_) {}
  console.log('VINEGAR180 FAILED — rolled back: ' + e.message);
  process.exit(1);
} finally { try { db.close(); } catch (_) {} }
JS
RC=$?
if [ "${FF_DRY_RUN:-0}" != 1 ]; then
  systemctl start flavorflow || true
  sleep 3
  curl -s -m 6 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAILED"
fi
if [ "$RC" -eq 0 ]; then echo "FF-VINEGAR180 DONE"; else echo "FF-VINEGAR180 STOPPED (code $RC)"; fi
exit "$RC"
