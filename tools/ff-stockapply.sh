#!/usr/bin/env bash
# FlavorFlow — apply only the stock values supplied by the factory screenshots.
#
# IMPORTANT: the date printed before a batch code is the production date.  The
# production date is stored in batches.planned_date, so every batch target is
# matched by BOTH product + date + exact batch code.  We deliberately do not
# match by code alone because historical rows reuse some codes.
#
# Supplied screenshot targets:
#   Dark Soya 220gm:
#     2026-09-21 / 6I1516AKS = 110 CB
#     2026-09-25 / 6I0021AKS = 257 CB
#   Soya Sauce 740gm:
#     2026-09-24 / 6I1819AK  = 330 CB
#     2026-09-24 / 6I1819BK  = 87 CB
#   Soya Sauce 1.3kg: no stock = 0 CB (explicitly supplied by the user).
#
# Products not listed above are never changed. Use FF_DRY_RUN=1 to inspect the
# exact plan without writing or restarting the service.
set -u
DIR=/opt/flavorflow/server
DB="$DIR/data/erp.db"
[ -f "$DB" ] || { echo "FATAL: DB not found: $DB"; exit 1; }
BK=/opt/flavorflow/backups
TS=$(date +%s)
mkdir -p "$BK"
echo "=== FF-STOCKAPPLY (exact screenshot date + code values) $(date) ==="

if [ "${FF_DRY_RUN:-0}" != 1 ]; then
  cp -a "$DB" "$BK/erp.db.bak-stockapply-$TS" || { echo "FATAL: backup failed"; exit 1; }
  echo "DB BACKUP: $BK/erp.db.bak-stockapply-$TS"
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
for (const required of ['id', 'name']) {
  if (!pc.includes(required)) { console.log('FATAL: products.' + required + ' missing'); process.exit(1); }
}
for (const required of ['id', 'product_id', 'code', 'planned_date', 'produced_cb', 'used_cb']) {
  if (!bc.includes(required)) { console.log('FATAL: batches.' + required + ' missing'); process.exit(1); }
}
if (!ic.includes('product_id') || !ic.includes('qty_cb')) {
  console.log('FATAL: inventory columns missing'); process.exit(1);
}

const activeExpr = pc.includes('active') ? ' AND COALESCE(active, 1) = 1' : '';
const productRows = db.prepare('SELECT id, name FROM products WHERE 1=1' + activeExpr).all();
const findProduct = (label, matcher) => {
  const rows = productRows.filter((p) => matcher(norm(p.name)));
  if (rows.length !== 1) {
    console.log('TARGET ' + label + ': expected exactly 1 active product, found ' + rows.length +
      (rows.length ? ' (' + rows.map((p) => '#' + p.id + ' ' + p.name).join(' / ') + ')' : ''));
    return null;
  }
  return rows[0];
};

// The screenshot date is the production date and must be part of the key.
const exactTargets = [
  {
    label: 'Dark Soya 220gm',
    product: (name) => /darksoya220/.test(name),
    rows: [
      { date: '2026-09-21', code: '6I1516AKS', desired: 110 },
      { date: '2026-09-25', code: '6I0021AKS', desired: 257 },
    ],
  },
  {
    label: 'Soya Sauce 740gm',
    product: (name) => /soyasauce740/.test(name),
    rows: [
      { date: '2026-09-24', code: '6I1819AK', desired: 330 },
      { date: '2026-09-24', code: '6I1819BK', desired: 87 },
    ],
  },
];

const plan = [];
for (const target of exactTargets) {
  const product = findProduct(target.label, target.product);
  if (!product) continue;
  const actions = [];
  let valid = true;
  for (const wanted of target.rows) {
    const rows = db.prepare(
      "SELECT id, code, planned_date, status, planned_cb, produced_cb, used_cb " +
      "FROM batches WHERE product_id = ? AND planned_date = ? " +
      "AND UPPER(TRIM(code)) = UPPER(?) ORDER BY id"
    ).all(product.id, wanted.date, wanted.code);
    if (rows.length !== 1) {
      console.log('TARGET ' + target.label + ' #' + product.id + ' ' + wanted.date +
        ' / ' + wanted.code + ': expected exactly 1 row, found ' + rows.length + ' — unchanged');
      valid = false;
      continue;
    }
    const batch = rows[0];
    const produced = n(batch.produced_cb);
    // The user confirmed the screenshot rows are completed. If an old app row
    // still says PLANNED, make its stored production record agree with the
    // supplied screenshot rather than rejecting it on stale status alone.
    const newProduced = Math.max(produced, wanted.desired);
    const newUsed = newProduced - wanted.desired;
    actions.push({ product, batch, wanted, newProduced, newUsed });
  }
  if (valid) {
    const total = target.rows.reduce((sum, row) => sum + row.desired, 0);
    plan.push({ kind: 'exact', target, product, actions, total });
    console.log('PLAN ' + target.label + ' #' + product.id + ': ' + target.rows.map((r) =>
      r.date + ' / ' + r.code + ' → ' + r.desired + ' CB').join(', ') + ' · inventory → ' + total + ' CB');
  }
}

// Explicit user instruction: Soya Sauce 1.3kg has no stock. This is the only
// zero-stock correction and it does not touch any other product.
const zeroProduct = findProduct('Soya Sauce 1.3kg — no stock', (name) =>
  /soyasauce(?:13|1[03])kg/.test(name) || /soyasauce13/.test(name));
if (zeroProduct) {
  const batches = db.prepare(
    'SELECT id, code, planned_date, status, produced_cb, used_cb FROM batches WHERE product_id = ? ORDER BY id'
  ).all(zeroProduct.id);
  plan.push({ kind: 'zero', label: 'Soya Sauce 1.3kg — no stock', product: zeroProduct, batches });
  console.log('PLAN Soya Sauce 1.3kg #' + zeroProduct.id + ': all batch remaining balances → 0 CB · inventory → 0 CB');
}

if (!plan.length) {
  console.log('STOCKAPPLY: no complete target plan found — no database rows changed.');
  try { db.close(); } catch (_) {}
  process.exit(0);
}

if (process.env.FF_DRY_RUN === '1') {
  console.log('DRY RUN — no database writes.');
  try { db.close(); } catch (_) {}
  process.exit(0);
}

try {
  db.exec('BEGIN');
  const updateBatch = bc.includes('status')
    ? db.prepare('UPDATE batches SET produced_cb = ?, used_cb = ?, status = ? WHERE id = ?')
    : db.prepare('UPDATE batches SET produced_cb = ?, used_cb = ? WHERE id = ?');
  const updateUsed = db.prepare('UPDATE batches SET used_cb = ? WHERE id = ?');
  const updateInv = db.prepare('UPDATE inventory SET qty_cb = ? WHERE product_id = ?');
  const insertInv = db.prepare(
    'INSERT INTO inventory (product_id, qty_cb' + (ic.includes('qty_trays') ? ', qty_trays' : '') +
    ') VALUES (?, ?' + (ic.includes('qty_trays') ? ', 0' : '') + ')'
  );

  for (const item of plan) {
    if (item.kind === 'exact') {
      for (const action of item.actions) {
        if (bc.includes('status')) {
          updateBatch.run(action.newProduced, action.newUsed, 'COMPLETED', action.batch.id);
        } else {
          updateBatch.run(action.newProduced, action.newUsed, action.batch.id);
        }
        console.log('FIXED ' + item.product.name + ' · ' + action.wanted.date + ' / ' +
          action.wanted.code + ': remaining ' + action.wanted.desired + ' CB' +
          ' (produced_cb → ' + action.newProduced + ', used_cb → ' + action.newUsed + ', status → COMPLETED)');
      }
      const inv = db.prepare('SELECT product_id FROM inventory WHERE product_id = ?').get(item.product.id);
      if (inv) updateInv.run(item.total, item.product.id);
      else insertInv.run(item.product.id, item.total);
      console.log('INVENTORY ' + item.product.name + ': qty_cb → ' + item.total);
    } else {
      for (const batch of item.batches) {
        const produced = n(batch.produced_cb);
        updateUsed.run(produced, batch.id);
        console.log('ZEROED ' + item.product.name + ' · ' + batch.code + ' (' + batch.planned_date +
          '): remaining 0 CB (used_cb → ' + produced + ')');
      }
      const inv = db.prepare('SELECT product_id FROM inventory WHERE product_id = ?').get(item.product.id);
      if (inv) updateInv.run(0, item.product.id);
      else insertInv.run(item.product.id, 0);
      console.log('INVENTORY ' + item.product.name + ': qty_cb → 0');
    }
  }
  db.exec('COMMIT');
  console.log('STOCKAPPLY VERIFIED — only screenshot-listed products changed.');
} catch (e) {
  try { db.exec('ROLLBACK'); } catch (_) {}
  console.log('STOCKAPPLY FAILED — rolled back: ' + e.message);
  process.exit(1);
} finally {
  try { db.close(); } catch (_) {}
}
JS
RC=$?
if [ "${FF_DRY_RUN:-0}" != 1 ]; then
  systemctl start flavorflow || true
  sleep 3
  curl -s -m 6 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAILED"
fi
if [ "$RC" -eq 0 ]; then echo "FF-STOCKAPPLY DONE"; else echo "FF-STOCKAPPLY STOPPED (code $RC)"; fi
exit "$RC"
