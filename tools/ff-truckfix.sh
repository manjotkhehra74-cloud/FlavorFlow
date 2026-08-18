#!/usr/bin/env bash
# FlavorFlow: truck master —
#   dispatch_trucks table (number + destination + active) and routes:
#     GET    /api/dispatch/trucks            → { trucks: [...] } (active only)
#     POST   /api/dispatch/trucks            → { number, destination } (upsert)
#     DELETE /api/dispatch/trucks/:id        → deactivate
#   Dispatch Entry vich destination chunn ke usde trucks di dropdown aaugi.
# Idempotent — safe to run twice. Backup + node --check + auto-restore.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-TRUCKFIX $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-truck-$TS" 2>/dev/null
cp -a routes/dispatch.js "/opt/flavorflow/backups/dispatch.js.bak-truck-$TS"
echo "BACKUPS -> /opt/flavorflow/backups (suffix -truck-$TS)"

node - <<'JS'
const db = require('/opt/flavorflow/server/db');
db.exec(`CREATE TABLE IF NOT EXISTS dispatch_trucks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  number TEXT NOT NULL UNIQUE,
  destination TEXT NOT NULL DEFAULT 'NEEMRANA',
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT ''
)`);
console.log('TABLE dispatch_trucks OK');
JS
[ $? -ne 0 ] && { echo "TABLE FAIL"; exit 1; }

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/dispatch.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('/trucks')) { console.log('ROUTES: already present — skip'); process.exit(0); }
const bak = f + '.bak-truckw-' + Date.now();
fs.copyFileSync(f, bak);

const CODE = `/** ff-truckfix: truck master — number + destination (route). */
router.get('/trucks', requirePerm('dispatch.view'), (req, res) => {
  const trucks = db.prepare('SELECT * FROM dispatch_trucks WHERE active = 1 ORDER BY destination, number').all();
  res.json({ trucks });
});

router.post('/trucks', requirePerm('dispatch.manage'), (req, res) => {
  const b = req.body || {};
  const number = String(b.number || '').trim().toUpperCase();
  const destination = String(b.destination || 'NEEMRANA').trim().toUpperCase();
  if (!number) throw bad('Truck number is required.');
  const now = (typeof nowIso === 'function') ? nowIso() : new Date().toISOString();
  const ex = db.prepare('SELECT id FROM dispatch_trucks WHERE number = ?').get(number);
  if (ex) db.prepare('UPDATE dispatch_trucks SET destination = ?, active = 1 WHERE id = ?').run(destination, ex.id);
  else db.prepare('INSERT INTO dispatch_trucks (number, destination, active, created_at) VALUES (?,?,1,?)').run(number, destination, now);
  try { audit(db, req.user, ex ? 'UPDATE' : 'CREATE', 'dispatch', ex ? ex.id : 0, 'Truck ' + number + ' -> ' + destination); } catch (_) {}
  res.json({ ok: true });
});

router.delete('/trucks/:id', requirePerm('dispatch.manage'), (req, res) => {
  const id = Number(req.params.id);
  const t = db.prepare('SELECT * FROM dispatch_trucks WHERE id = ?').get(id);
  if (!t) throw bad('Truck not found.', 404);
  db.prepare('UPDATE dispatch_trucks SET active = 0 WHERE id = ?').run(id);
  try { audit(db, req.user, 'DELETE', 'dispatch', id, 'Truck ' + t.number + ' removed'); } catch (_) {}
  res.json({ ok: true });
});

`;
const anchor = 'module.exports = router;';
if (!src.includes(anchor)) { console.log('ANCHOR NOT FOUND'); process.exit(2); }
// make sure audit/nowIso are importable — they may already be imported
if (!/require\('\.\.\/helpers'\)/.test(src)) {
  src = src.replace(/(const db = require\('\.\.\/db'\);)/, "$1\nconst { audit, nowIso } = require('../helpers');");
} else {
  const hm = src.match(/const \{([^}]*)\} = require\('\.\.\/helpers'\);/);
  if (hm) {
    const have = hm[1].split(',').map((s) => s.trim()).filter(Boolean);
    const need = ['audit', 'nowIso'].filter((n) => !have.includes(n));
    if (need.length) src = src.replace(hm[0], `const { ${have.concat(need).join(', ')} } = require('../helpers');`);
  }
}
src = src.replace(anchor, CODE + anchor);
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK — trucks routes added'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); process.exit(3); }
JS
[ $? -ne 0 ] && { echo "TRUCKFIX FAIL"; exit 1; }

systemctl restart flavorflow
sleep 2
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
echo "TRUCKFIX VERIFIED ✓ — truck master live (destination-wise dropdown hun app vich)"
