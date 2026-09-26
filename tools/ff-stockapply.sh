#!/usr/bin/env bash
# FlavorFlow — apply the two stock corrections explicitly supplied by the
# factory sheet. This is intentionally NOT a generic stock reset.
#
# Targeted values only:
#   Dark Soya 220gm: 6I1516AKS = 110 CB, 6I0021AKS = 257 CB (total 367)
#   Soya Sauce 740gm: 6I1819AK = 330 CB, 6I1819BK = 87 CB (total 417)
#
# Products not listed above are not changed. The script will not create a
# missing batch or guess when a code is ambiguous. It updates a batch's used_cb
# so its remaining balance equals the supplied sheet, and sets inventory only
# for these two named products to the same supplied total.
#
# Use FF_DRY_RUN=1 to inspect without writing.
set -u
DIR=/opt/flavorflow/server
DB="$DIR/data/erp.db"
[ -f "$DB" ] || { echo "FATAL: DB not found: $DB"; exit 1; }
BK=/opt/flavorflow/backups
TS=$(date +%s)
mkdir -p "$BK"
echo "=== FF-STOCKAPPLY (targeted sheet values) $(date) ==="

if [ "${FF_DRY_RUN:-0}" != 1 ]; then
  cp -a "$DB" "$BK/erp.db.bak-stockapply-$TS" || { echo "FATAL: backup failed"; exit 1; }
  echo "DB BACKUP: $BK/erp.db.bak-stockapply-$TS"
  systemctl stop flavorflow || true
  sleep 1
fi

export FF_DB="$DB" FF_DRY_RUN="${FF_DRY_RUN:-0}" FF_TS="$TS"
node - <<'JS'
const fs = require('fs');
const dbPath = process.env.FF_DB;
let DatabaseSync;
try { DatabaseSync = require('/opt/flavorflow/server/sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) try { DatabaseSync = require('node:sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) { console.log('FATAL: server sqlite wrapper not available'); process.exit(1); }
const db = new DatabaseSync(dbPath);
const n = (v) => Number(v) || 0;
const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '');
const cols = (t) => db.prepare('PRAGMA table_info(' + t + ')').all().map((r) => String(r.name));
const pc = cols('products'), bc = cols('batches'), ic = cols('inventory');
for (const required of ['id', 'name']) if (!pc.includes(required)) { console.log('FATAL: products.' + required + ' missing'); process.exit(1); }
for (const required of ['id', 'product_id', 'code', 'produced_cb', 'used_cb', 'status']) if (!bc.includes(required)) { console.log('FATAL: batches.' + required + ' missing'); process.exit(1); }
if (!ic.includes('product_id') || !ic.includes('qty_cb')) { console.log('FATAL: inventory columns missing'); process.exit(1); }

const targets = [
  { label: 'Dark Soya 220gm', product: (name) => /darksoya220/.test(norm(name)), rows: [['6I1516AKS', 110], ['6I0021AKS', 257]] },
  { label: 'Soya Sauce 740gm', product: (name) => /soyasauce740/.test(norm(name)), rows: [['6I1819AK', 330], ['6I1819BK', 87]] },
];
const activeExpr = pc.includes('active') ? ' AND COALESCE(active, 1) = 1' : '';
const plan = [];
let failed = false;
for (const t of targets) {
  const products = db.prepare('SELECT id, name FROM products WHERE 1=1' + activeExpr).all().filter((p) => t.product(p.name));
  if (products.length !== 1) {
    console.log('TARGET ' + t.label + ': expected exactly 1 active product, found ' + products.length + (products.length ? ' (' + products.map((p) => '#' + p.id + ' ' + p.name).join(' / ') + ')' : ''));
    failed = true;
    continue;
  }
  const p = products[0];
  const actions = [];
  for (const [code, desired] of t.rows) {
    const rows = db.prepare("SELECT id, code, produced_cb, used_cb, planned_date FROM batches WHERE product_id = ? AND UPPER(TRIM(code)) = UPPER(?) AND UPPER(COALESCE(status,'')) = 'COMPLETED' ORDER BY id").all(p.id, code);
    if (rows.length !== 1) {
      console.log('TARGET ' + t.label + ' #' + p.id + ' ' + code + ': expected exactly 1 completed batch, found ' + rows.length + ' — unchanged');
      failed = true;
      continue;
    }
    const b = rows[0];
    if (n(b.produced_cb) < desired) {
      console.log('TARGET ' + t.label + ' ' + code + ': produced ' + b.produced_cb + ' is below supplied balance ' + desired + ' — unchanged');
      failed = true;
      continue;
    }
    actions.push({ product: p, batch: b, code, desired, used: n(b.produced_cb) - desired });
  }
  if (actions.length !== t.rows.length) continue;
  const inv = db.prepare('SELECT qty_cb' + (ic.includes('qty_trays') ? ', qty_trays' : '') + ' FROM inventory WHERE product_id = ?').get(p.id);
  const total = t.rows.reduce((s, r) => s + r[1], 0);
  plan.push({ target: t, product: p, actions, inv, total });
  console.log('PLAN ' + t.label + ' #' + p.id + ': ' + t.rows.map((r) => r[0] + ' → ' + r[1] + ' CB').join(', ') + ' · inventory → ' + total + ' CB');
}
if (failed) {
  console.log('STOCKAPPLY ABORTED — missing/ambiguous supplied batch data; no target was changed.');
  try { db.close(); } catch (_) {}
  process.exit(2);
}
if (process.env.FF_DRY_RUN === '1') {
  console.log('DRY RUN — no database writes.');
  try { db.close(); } catch (_) {}
  process.exit(0);
}
try {
  db.exec('BEGIN');
  const updBatch = db.prepare('UPDATE batches SET used_cb = ? WHERE id = ?');
  const updInv = db.prepare('UPDATE inventory SET qty_cb = ? WHERE product_id = ?');
  const insInv = db.prepare('INSERT INTO inventory (product_id, qty_cb' + (ic.includes('qty_trays') ? ', qty_trays' : '') + ') VALUES (?, ?' + (ic.includes('qty_trays') ? ', 0' : '') + ')');
  for (const p of plan) {
    for (const a of p.actions) {
      updBatch.run(a.used, a.batch.id);
      console.log('FIXED ' + p.product.name + ' · ' + a.code + ': remaining ' + a.desired + ' CB (used_cb → ' + a.used + ')');
    }
    if (p.inv) updInv.run(p.total, p.product.id);
    else insInv.run(p.product.id, p.total);
    console.log('INVENTORY ' + p.product.name + ': qty_cb → ' + p.total);
  }
  db.exec('COMMIT');
  console.log('STOCKAPPLY VERIFIED — only the two supplied products changed.');
} catch (e) {
  try { db.exec('ROLLBACK'); } catch (_) {}
  console.log('STOCKAPPLY FAILED — rolled back: ' + e.message);
  process.exit(1);
} finally { try { db.close(); } catch (_) {} }
JS
RC=$?
if [ "${FF_DRY_RUN:-0}" != 1 ]; then
  systemctl start flavorflow || true
  sleep 3
  curl -s -m 6 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAILED"
fi
if [ "$RC" -eq 0 ]; then echo "FF-STOCKAPPLY DONE"; else echo "FF-STOCKAPPLY STOPPED (code $RC)"; fi
exit "$RC"
