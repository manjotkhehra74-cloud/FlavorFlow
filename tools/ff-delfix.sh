#!/usr/bin/env bash
# FlavorFlow FIX: add DELETE routes —
#   DELETE /api/products/:id          (soft delete: active = 0; history stays)
#   DELETE /api/packing/materials/:id (removes material + its BOM lines; ledger stays)
# Idempotent — safe to run twice (second run skips each file).
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-DELFIX $(date) ==="
node - <<'JS'
const fs = require('fs'), cp = require('child_process');

function patch(file, marker, code) {
  if (!fs.existsSync(file)) { console.log('MISSING: ' + file); return false; }
  let src = fs.readFileSync(file, 'utf8');
  if (src.includes(marker)) { console.log('ALREADY PATCHED: ' + file); return true; }
  const anchor = 'module.exports = router;';
  if (!src.includes(anchor)) { console.log('ANCHOR NOT FOUND: ' + file); return false; }
  const bak = file + '.bak-delfix-' + Date.now();
  fs.copyFileSync(file, bak);
  console.log('BACKUP: ' + bak);
  src = src.replace(anchor, code + '\n\n' + anchor);
  fs.writeFileSync(file, src);
  try { cp.execSync('node --check "' + file + '"'); console.log('SYNTAX OK: ' + file); return true; }
  catch (e) { fs.copyFileSync(bak, file); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); return false; }
}

const prodCode = `/** Soft-delete a product (ff-delfix). History (dispatches, batches, reports) stays. */
router.delete('/:id', requirePerm('products.manage'), (req, res) => {
  const id = Number(req.params.id);
  const prod = db.prepare('SELECT id, name FROM products WHERE id = ? AND active = 1').get(id);
  if (!prod) { res.status(404).json({ error: 'Product not found.' }); return; }
  db.prepare('UPDATE products SET active = 0 WHERE id = ?').run(id);
  try { require('../helpers').audit(db, req.user, 'DELETE', 'product', id, 'Product "' + prod.name + '" deleted (soft)'); } catch (_) {}
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

const ok1 = patch('/opt/flavorflow/server/routes/products.js', "'Product not found.'", prodCode);
const ok2 = patch('/opt/flavorflow/server/routes/packing.js', "'Material not found.'", packCode);
if (!ok1 || !ok2) { console.log('PATCH INCOMPLETE — kuch restart nahi kita'); process.exit(2); }
try { cp.execSync('systemctl restart flavorflow'); console.log('SERVICE RESTARTED'); } catch (e) { console.log('RESTART FAIL: ' + e.message); process.exit(4); }
setTimeout(() => {
  try { console.log('HEALTH: ' + cp.execSync('curl -s -m 5 http://127.0.0.1:4000/api/health').toString().trim()); } catch (e) { console.log('HEALTH ERR'); }
  console.log('DELFIX VERIFIED ✓');
}, 2000);
JS
echo "DELFIX DONE — app ch Product Master te Packing Material ch delete button hun kamm karega"
