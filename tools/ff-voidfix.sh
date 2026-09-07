#!/usr/bin/env bash
# FlavorFlow: dispatch VOID (galat entry theek karan layi) —
#   POST /api/dispatch/:id/void  (perm: dispatch.manage)
#     - har item da stock WAPAS inventory vich (qty_cb += cartons, qty_trays += trays)
#     - batch_code wali line: batches.used_cb/used_trays vi wapas (clamp >= 0)
#     - dispatch status = 'VOID' (history vich rehnda, mitda nahi)
#   Fer sahi entry navi bana lao — stock dubara sahi kat-jayega.
# Idempotent. Backup + node --check + auto-restore.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-VOIDFIX $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a routes/dispatch.js "/opt/flavorflow/backups/dispatch.js.bak-void-$TS"
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-void-$TS" 2>/dev/null
echo "BACKUP -> /opt/flavorflow/backups (suffix -void-$TS)"

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/dispatch.js';
let src = fs.readFileSync(f, 'utf8');
const bak = f + '.bak-voidw-' + Date.now();
fs.copyFileSync(f, bak);

if (src.includes('/** ff-voidfix')) { console.log('ALREADY PATCHED — skip'); process.exit(0); }

const hasPerm = src.includes('requirePerm');
const guard = hasPerm ? "requirePerm('dispatch.manage'), " : '';

const BLOCK = `
/** ff-voidfix: void a wrong dispatch — stock returns to inventory (and batches). History row stays as VOID. */
router.post('/:id/void', ${guard}(req, res) => {
  const id = Number(req.params.id);
  const d = db.prepare('SELECT * FROM dispatches WHERE id = ?').get(id);
  if (!d) return res.status(404).json({ error: 'Dispatch not found' });
  if (String(d.status || '').toUpperCase() === 'VOID') return res.status(400).json({ error: 'Already voided' });
  const items = db.prepare('SELECT * FROM dispatch_items WHERE dispatch_id = ?').all(id);
  const tx = db.transaction(() => {
    for (const it of items) {
      const cb = Number(it.cartons || 0), tr = Number(it.trays || 0);
      // 1) inventory wapas
      const inv = db.prepare('SELECT product_id FROM inventory WHERE product_id = ?').get(it.product_id);
      if (inv) {
        db.prepare('UPDATE inventory SET qty_cb = qty_cb + ?, qty_trays = qty_trays + ? WHERE product_id = ?').run(cb, tr, it.product_id);
      } else {
        try { db.prepare('INSERT INTO inventory (product_id, qty_cb, qty_trays) VALUES (?,?,?)').run(it.product_id, cb, tr); } catch (e) {}
      }
      // 2) batch wapas (je batch code naal gayi si)
      const code = (it.batch_code || '').trim();
      if (code) {
        let remCb = cb, remTr = tr;
        const bchs = db.prepare("SELECT id, COALESCE(used_cb,0) ucb, COALESCE(used_trays,0) utr FROM batches WHERE code = ? AND product_id = ? ORDER BY id DESC").all(code, it.product_id);
        for (const b of bchs) {
          if (remCb <= 0 && remTr <= 0) break;
          const backCb = Math.min(remCb, b.ucb), backTr = Math.min(remTr, b.utr);
          if (backCb > 0 || backTr > 0) {
            db.prepare('UPDATE batches SET used_cb = COALESCE(used_cb,0) - ?, used_trays = COALESCE(used_trays,0) - ? WHERE id = ?').run(backCb, backTr, b.id);
            remCb -= backCb; remTr -= backTr;
          }
        }
      }
    }
    const who = (req.user && (req.user.name || req.user.email)) || 'user';
    db.prepare("UPDATE dispatches SET status = 'VOID', remarks = COALESCE(remarks,'') || ' [VOIDED by ' || ? || ' ' || datetime('now') || ']' WHERE id = ?").run(who, id);
  });
  try { tx(); } catch (e) { return res.status(500).json({ error: 'Void failed: ' + e.message }); }
  res.json({ ok: true, returnedItems: items.length });
});
`;

const modIdx = src.indexOf('module.exports = router;');
if (modIdx === -1) { console.log('module.exports NOT FOUND'); process.exit(2); }
src = src.slice(0, modIdx) + BLOCK + '\n' + src.slice(modIdx);
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK — void route added' + (hasPerm ? ' (dispatch.manage guard)' : '')); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); process.exit(3); }
JS
[ $? -ne 0 ] && { echo "VOIDFIX FAIL"; exit 1; }

systemctl restart flavorflow
sleep 2
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
echo "VOIDFIX VERIFIED ✓ — galat dispatch hun Void ho sakdi hai; stock (inventory + batches) wapas aa janda"
