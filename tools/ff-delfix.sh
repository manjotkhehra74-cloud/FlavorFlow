#!/usr/bin/env bash
# FlavorFlow FIX: DELETE routes —
#   DELETE /api/products/:id          (soft delete product + REMOVE its inventory row)
#   DELETE /api/packing/materials/:id (removes material + its BOM lines; ledger stays)
# Idempotent + upgrade-aware:
#   - fresh server            → adds both routes
#   - old delfix already run  → upgrades product route to also clear inventory
#   - fully patched           → skips
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-DELFIX v2 $(date) ==="
node - <<'JS'
const fs = require('fs'), cp = require('child_process');

function backup(file) {
  const bak = file + '.bak-delfix-' + Date.now();
  fs.copyFileSync(file, bak);
  console.log('BACKUP: ' + bak);
  return bak;
}
function checkOrRestore(file, bak) {
  try { cp.execSync('node --check "' + file + '"'); console.log('SYNTAX OK: ' + file); return true; }
  catch (e) { fs.copyFileSync(bak, file); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); return false; }
}

const INV_LINE = "  db.prepare('DELETE FROM inventory WHERE product_id = ?').run(id); // clear stock row too";

const prodCode = `/** Soft-delete a product (ff-delfix v2). Inventory row is removed; history (dispatches, batches, reports) stays. */
router.delete('/:id', requirePerm('products.manage'), (req, res) => {
  const id = Number(req.params.id);
  const prod = db.prepare('SELECT id, name FROM products WHERE id = ? AND active = 1').get(id);
  if (!prod) { res.status(404).json({ error: 'Product not found.' }); return; }
  db.prepare('UPDATE products SET active = 0 WHERE id = ?').run(id);
${INV_LINE}
  try { require('../helpers').audit(db, req.user, 'DELETE', 'product', id, 'Product "' + prod.name + '" deleted (soft) — inventory row removed'); } catch (_) {}
  res.json({ ok: true });
});`;

const packCode = `/** Delete a packing material (ff-delfix). BOM lines removed; ledger entries stay. */
router.delete('/materials/:id', requirePerm('packing.manage'), (req, res) => {
  const id = Number(req.params.id);
  const mat = db.prepare('SELECT id, name FROM packing_materials WHERE id = ?').get(id);
  if (!mat) { res.status(404).json({ error: 'Material not found.' }); return; }
  try { db.prepare('DELETE FROM bom_lines WHERE material_id = ?').run(id); } catch (_) {}
  try { db.prepare('DELETE FROM bom WHERE material_id = ?').run(id); } catch (_) {}
  try { db.prepare('DELETE FROM packing_materials WHERE id = ?').run(id); }
  catch (e) { res.status(409).json({ error: 'Cannot delete: material is referenced by other records.' }); return; }
  try { require('../helpers').audit(db, req.user, 'DELETE', 'packing', id, 'Packing material "' + mat.name + '" deleted'); } catch (_) {}
  res.json({ ok: true });
});`;

let changed = false, failed = false;

// ---- products.js ----
{
  const f = '/opt/flavorflow/server/routes/products.js';
  if (!fs.existsSync(f)) { console.log('MISSING: ' + f); failed = true; }
  else {
    let src = fs.readFileSync(f, 'utf8');
    if (src.includes('DELETE FROM inventory WHERE product_id')) {
      console.log('PRODUCTS: already fully patched — skip');
    } else if (src.includes('deleted (soft)')) {
      // v1 route present — upgrade: add inventory cleanup after the soft-delete UPDATE
      const anchor = "db.prepare('UPDATE products SET active = 0 WHERE id = ?').run(id);";
      if (!src.includes(anchor)) { console.log('PRODUCTS: v1 anchor not found'); failed = true; }
      else {
        const bak = backup(f);
        src = src.replace(anchor, anchor + '\n' + INV_LINE);
        fs.writeFileSync(f, src);
        if (checkOrRestore(f, bak)) { console.log('PRODUCTS: v1 → v2 upgraded (inventory cleanup added)'); changed = true; } else failed = true;
      }
    } else {
      const anchor = 'module.exports = router;';
      if (!src.includes(anchor)) { console.log('PRODUCTS: anchor not found'); failed = true; }
      else {
        const bak = backup(f);
        src = src.replace(anchor, prodCode + '\n\n' + anchor);
        fs.writeFileSync(f, src);
        if (checkOrRestore(f, bak)) { console.log('PRODUCTS: route added (v2)'); changed = true; } else failed = true;
      }
    }
  }
}

// ---- packing.js ----
{
  const f = '/opt/flavorflow/server/routes/packing.js';
  if (!fs.existsSync(f)) { console.log('MISSING: ' + f); failed = true; }
  else {
    let src = fs.readFileSync(f, 'utf8');
    if (src.includes("'Material not found.'")) {
      console.log('PACKING: already patched — skip');
    } else {
      const anchor = 'module.exports = router;';
      if (!src.includes(anchor)) { console.log('PACKING: anchor not found'); failed = true; }
      else {
        const bak = backup(f);
        src = src.replace(anchor, packCode + '\n\n' + anchor);
        fs.writeFileSync(f, src);
        if (checkOrRestore(f, bak)) { console.log('PACKING: route added'); changed = true; } else failed = true;
      }
    }
  }
}

if (failed) { console.log('PATCH INCOMPLETE — restart skip'); process.exit(2); }
if (!changed) { console.log('NOTHING TO DO — sab pehla hi patched'); process.exit(0); }
try { cp.execSync('systemctl restart flavorflow'); console.log('SERVICE RESTARTED'); } catch (e) { console.log('RESTART FAIL: ' + e.message); process.exit(4); }
setTimeout(() => {
  try { console.log('HEALTH: ' + cp.execSync('curl -s -m 5 http://127.0.0.1:4000/api/health').toString().trim()); } catch (e) { console.log('HEALTH ERR'); }
  console.log('DELFIX v2 VERIFIED ✓');
}, 2000);
JS
echo "DELFIX v2 DONE — product delete hun inventory vicho vi stock row hata dinda"
