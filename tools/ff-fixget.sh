#!/usr/bin/env bash
# FlavorFlow FIX: GET /users must return each user's OWN permissions
# (parsed JSON array) so the client table/edit dialog can show custom perms.
# Idempotent + re-runnable: second run skips.
set -u
cd /opt/flavorflow/server || { echo FATAL; exit 1; }
echo "=== FF-FIXGET $(date) ==="
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/users.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('permissions FROM users WHERE active')) {
  console.log('FIX ALREADY PRESENT — skip');
  process.exit(0);
}
const bak = f + '.bak-get-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);
// 1) include permissions column in the GET SELECT
const a = 'SELECT id, name, email, role, active, created_at FROM users WHERE active = 1';
if (!src.includes(a)) { console.log('SELECT TEXT NOT FOUND — manual check di lod'); process.exit(2); }
src = src.replace(a, 'SELECT id, name, email, role, active, created_at, permissions FROM users WHERE active = 1');
// 2) parse the JSON string into an array right after .all()
const b = ').all();\n  res.json({';
if (!src.includes(b)) { console.log('RES.JSON ANCHOR NOT FOUND'); process.exit(2); }
src = src.replace(b, ').all();\n  for (const r of rows) {\n    try { r.permissions = JSON.parse(r.permissions || \'[]\'); } catch (_) { r.permissions = []; }\n  }\n  res.json({');
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); process.exit(3); }
try { cp.execSync('systemctl restart flavorflow'); console.log('SERVICE RESTARTED'); } catch (e) { console.log('RESTART FAIL: ' + e.message); process.exit(4); }
setTimeout(() => {
  try { console.log('HEALTH: ' + cp.execSync('curl -s -m 5 http://127.0.0.1:4000/api/health').toString().trim()); } catch (e) { console.log('HEALTH ERR'); }
  const s2 = fs.readFileSync(f, 'utf8');
  console.log((s2.includes('permissions FROM users') && s2.includes('JSON.parse(r.permissions')) ? 'PATCH VERIFIED IN FILE ✓' : 'PATCH CHECK FAILED ✗'));
}, 2000);
JS
echo "GET-FIX DONE — hun app vich users page khol ke dekhna (poorane users vi hun apni stored permissions dikhaange)"
