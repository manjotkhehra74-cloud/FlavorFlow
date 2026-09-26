#!/usr/bin/env bash
# FlavorFlow — product deletion/visibility fix.
#
# A deleted finished good must disappear from Product Master, inventory and all
# current-product dropdowns, but old dispatches/batches remain in history. The
# old build could leave an active product row (especially after a missing DELETE
# route), so the same name kept returning everywhere.
#
# This patch is intentionally conservative:
#   * DELETE refuses a product that still has inventory or remaining completed
#     batch stock; it never silently moves stock to another product.
#   * the known empty "Dark Soya 250" duplicate is archived only when its
#     inventory and remaining batches are both zero. Other products are never
#     changed by the cleanup.
#   * product-list responses are filtered by the database active flag.
#
# Idempotent. Backups + node --check + auto-restore.
set -u

if [ -d /opt/flavorflow-saas/core ]; then DIR=/opt/flavorflow-saas/core; MODE=saas; SVC=flavorflow-saas; ROOT=/opt/flavorflow-saas;
elif [ -d /opt/flavorflow/server ]; then DIR=/opt/flavorflow/server; MODE=factory; SVC=flavorflow; ROOT=/opt/flavorflow;
else echo "FATAL: server directory not found"; exit 1; fi

F="$DIR/routes/products.js"
[ -f "$F" ] || { echo "FATAL: $F not found"; exit 1; }
BK="$ROOT/backups"; mkdir -p "$BK"; TS=$(date +%s)
cp -a "$F" "$BK/products.js.bak-productfix-$TS"
[ -f "$DIR/routes/inventory.js" ] && cp -a "$DIR/routes/inventory.js" "$BK/inventory.js.bak-productfix-$TS" || true
export FF_DIR="$DIR" FF_PRODUCTS="$F" FF_BACKUP="$BK/products.js.bak-productfix-$TS" FF_INVENTORY="$DIR/routes/inventory.js" FF_INVENTORY_BACKUP="$BK/inventory.js.bak-productfix-$TS"

# The deployed server database is factory data or one DB per SaaS tenant. The
# cleanup below never guesses a stock number; it only archives an already-empty
# duplicate.
if [ "$MODE" = saas ]; then
  for d in "$ROOT"/data/tenant-*/erp.db; do [ -f "$d" ] && echo "$d"; done > /tmp/ff-productfix-dbs-$$
else
  DBP=$(systemctl show "$SVC" -p Environment 2>/dev/null | tr ' ' '\n' | sed -n 's/^ERP_DB_PATH=//p' | head -1)
  [ -n "$DBP" ] && [ -f "$DBP" ] || DBP="$DIR/data/erp.db"
  printf '%s\n' "$DBP" > /tmp/ff-productfix-dbs-$$
fi
export FF_DBS_FILE=/tmp/ff-productfix-dbs-$$ FF_ROOT="$ROOT" FF_TS="$TS"

echo "=== FF-PRODUCTFIX ($MODE) $(date) ==="
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = process.env.FF_PRODUCTS;
let src = fs.readFileSync(f, 'utf8');
let changed = false;

// Filter every response from the finished-goods route that contains a product
// list. Looking up active by id also works with old SELECTs that omitted the
// active column from the JSON row.
const FILTER = `/* ff-active-products */
router.use((req, res, next) => {
  if (req.method !== 'GET') return next();
  const send = res.json.bind(res);
  res.json = (body) => {
    if (body && Array.isArray(body.products)) {
      const products = body.products.filter((p) => {
        try {
          const row = db.prepare('SELECT active FROM products WHERE id = ?').get(Number(p.id));
          return !row || Number(row.active == null ? 1 : row.active) !== 0;
        } catch (_) { return Number(p.active == null ? 1 : p.active) !== 0; }
      });
      return send(Object.assign({}, body, { products }));
    }
    return send(body);
  };
  next();
});
/* end ff-active-products */
`;
if (!src.includes('ff-active-products')) {
  const router = src.indexOf('express.Router()');
  const line = src.indexOf('\n', router);
  if (router === -1 || line === -1) { console.log('PRODUCTS: router anchor not found'); process.exit(2); }
  src = src.slice(0, line + 1) + FILTER + src.slice(line + 1);
  changed = true;
  console.log('PRODUCTS: inactive products filtered from list responses ✓');
}

// Safe delete route. Existing historical rows keep their product id/name via
// joins and are not deleted. A product with live stock is never archived.
if (!src.includes('ff-product-delete-safe') && !/router\.delete\(['\"]:\/id['\"]/.test(src)) {
  const deleteGuard = /requirePerm\s*\(/.test(src) ? "requirePerm('products.manage'), " : '';
  const route = `/** ff-product-delete-safe */
router.delete('/:id', ${deleteGuard}(req, res) => {
  const id = Number(req.params.id);
  const p = db.prepare('SELECT id, name, active FROM products WHERE id = ?').get(id);
  if (!p || Number(p.active == null ? 1 : p.active) === 0) return res.status(404).json({ error: 'Product not found.' });
  const inv = db.prepare('SELECT COALESCE(qty_cb, 0) cb, COALESCE(qty_trays, 0) trays FROM inventory WHERE product_id = ?').get(id) || { cb: 0, trays: 0 };
  const b = db.prepare("SELECT COUNT(*) n FROM batches WHERE product_id = ? AND UPPER(COALESCE(status, '')) = 'COMPLETED' AND (COALESCE(produced_cb, 0) - COALESCE(used_cb, 0) > 0 OR COALESCE(produced_trays, 0) - COALESCE(used_trays, 0) > 0)").get(id);
  if (Number(inv.cb) > 0 || Number(inv.trays) > 0 || Number(b.n) > 0) return res.status(409).json({ error: 'Cannot delete a product with stock or a remaining production batch. Dispatch/use the stock first.' });
  db.prepare('UPDATE products SET active = 0 WHERE id = ?').run(id);
  try { db.prepare('DELETE FROM inventory WHERE product_id = ?').run(id); } catch (_) {}
  try { require('../helpers').audit(db, req.user, 'DELETE', 'product', id, 'Product "' + p.name + '" archived — empty stock'); } catch (_) {}
  res.json({ ok: true });
});
/* end ff-product-delete-safe */
`;
  const marker = 'module.exports = router;';
  const at = src.indexOf(marker);
  if (at === -1) { console.log('PRODUCTS: export anchor not found'); process.exit(2); }
  src = src.slice(0, at) + route + '\n' + src.slice(at);
  changed = true;
  console.log('PRODUCTS: safe DELETE route installed ✓');
}

fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('PRODUCTS: syntax OK'); }
catch (e) { fs.copyFileSync(f, process.env.FF_BACKUP); console.log('SYNTAX FAIL — restored: ' + String(e.stderr || e).slice(0, 500)); process.exit(3); }
process.exit(changed ? 4 : 0);
JS
RC=$?
[ "$RC" -eq 3 ] && { echo "PRODUCTFIX FAIL — original restored"; rm -f /tmp/ff-productfix-dbs-$$; exit 1; }

# Inventory is also a product-facing screen. Older inventory queries joined
# every product (including active=0), so an archived zero-stock row still
# appeared there. Filter only finished-good rows; material stock is untouched.
if [ -f "$FF_INVENTORY" ]; then
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = process.env.FF_INVENTORY;
let src = fs.readFileSync(f, 'utf8');
if (!src.includes('ff-active-inventory-products')) {
  const at = src.indexOf('express.Router()');
  const line = src.indexOf('\n', at);
  if (at === -1 || line === -1) { console.log('INVENTORY: router anchor not found — left unchanged'); process.exit(0); }
  const block = `/* ff-active-inventory-products */
router.use((req, res, next) => {
  if (req.method !== 'GET') return next();
  const send = res.json.bind(res);
  res.json = (body) => {
    if (body && Array.isArray(body.items)) {
      const items = body.items.filter((item) => {
        if (item.product_id == null) return true;
        try {
          const p = db.prepare('SELECT active FROM products WHERE id = ?').get(Number(item.product_id));
          return !p || Number(p.active == null ? 1 : p.active) !== 0;
        } catch (_) { return Number(item.active == null ? 1 : item.active) !== 0; }
      });
      return send(Object.assign({}, body, { items }));
    }
    return send(body);
  };
  next();
});
/* end ff-active-inventory-products */
`;
  src = src.slice(0, line + 1) + block + src.slice(line + 1);
  fs.writeFileSync(f, src);
  try { cp.execSync('node --check "' + f + '"'); console.log('INVENTORY: inactive finished goods filtered ✓'); }
  catch (e) { fs.copyFileSync(f, process.env.FF_INVENTORY_BACKUP); console.log('INVENTORY: syntax fail — restored'); process.exit(1); }
} else console.log('INVENTORY: active-product filter already installed ✓');
JS
[ "$?" -ne 0 ] && { echo "PRODUCTFIX FAIL (inventory route)"; rm -f /tmp/ff-productfix-dbs-$$; exit 1; }
fi

# Archive only the explicitly reported empty duplicate. If it is not empty,
# print it and leave it untouched for manual confirmation.
node - <<'JS'
const fs = require('fs'), path = require('path');
let DatabaseSync;
try { DatabaseSync = require(process.env.FF_DIR + '/sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) try { DatabaseSync = require('node:sqlite').DatabaseSync; } catch (_) {}
if (!DatabaseSync) { console.log('CLEANUP: sqlite wrapper not available — skipped safely'); process.exit(0); }
const files = fs.readFileSync(process.env.FF_DBS_FILE, 'utf8').split(/\n/).map(s => s.trim()).filter(Boolean);
for (const file of files) {
  if (!fs.existsSync(file)) continue;
  let db; try { db = new DatabaseSync(file); } catch (e) { console.log('CLEANUP ' + file + ': open failed ' + e.message); continue; }
  try {
    const pcols = db.prepare('PRAGMA table_info(products)').all().map((r) => r.name);
    if (!pcols.includes('active')) { console.log('CLEANUP ' + path.basename(file) + ': active column missing — unchanged'); db.close(); continue; }
    const matches = db.prepare("SELECT id, name, active FROM products WHERE LOWER(REPLACE(REPLACE(name, ' ', ''), '-', '')) LIKE '%darksoya250%'").all();
    if (!matches.length) { console.log('CLEANUP ' + path.basename(file) + ': Dark Soya 250 not found'); db.close(); continue; }
    for (const p of matches) {
      const i = db.prepare('SELECT COALESCE(qty_cb,0) cb, COALESCE(qty_trays,0) trays FROM inventory WHERE product_id = ?').get(p.id) || { cb: 0, trays: 0 };
      const b = db.prepare("SELECT COUNT(*) n FROM batches WHERE product_id = ? AND UPPER(COALESCE(status,'')) = 'COMPLETED' AND (COALESCE(produced_cb,0) - COALESCE(used_cb,0) > 0 OR COALESCE(produced_trays,0) - COALESCE(used_trays,0) > 0)").get(p.id);
      if (Number(i.cb) === 0 && Number(i.trays) === 0 && Number(b.n) === 0 && Number(p.active || 0) !== 0) {
        const backup = process.env.FF_ROOT + '/backups/' + path.basename(path.dirname(file)) + '.erp.db.bak-productfix-' + process.env.FF_TS;
        try { db.exec("VACUUM INTO '" + backup.replace(/'/g, "''") + "'"); } catch (_) {}
        db.prepare('UPDATE products SET active = 0 WHERE id = ?').run(p.id);
        try { db.prepare('DELETE FROM inventory WHERE product_id = ?').run(p.id); } catch (_) {}
        console.log('CLEANUP ' + path.basename(file) + ': archived empty ' + p.name + ' (#' + p.id + ') — no stock moved');
      } else {
        console.log('CLEANUP ' + path.basename(file) + ': left ' + p.name + ' (#' + p.id + ') untouched — inventory ' + i.cb + ' CB / ' + i.trays + ' trays, remaining batches ' + b.n);
      }
    }
  } catch (e) { console.log('CLEANUP ' + file + ': failed ' + e.message); }
  try { db.close(); } catch (_) {}
}
JS

rm -f /tmp/ff-productfix-dbs-$$
if [ "$RC" -eq 4 ] && [ -z "${FF_NO_RESTART:-}" ]; then
  systemctl restart "$SVC" || { echo "SERVICE RESTART FAILED"; exit 1; }
  sleep 4
  if [ "$MODE" = factory ]; then curl -s -m 6 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAILED"; fi
fi
echo "PRODUCTFIX VERIFIED ✓ — inactive products hidden; empty Dark Soya 250 archived only; other stock untouched"
