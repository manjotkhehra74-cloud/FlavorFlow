#!/usr/bin/env bash
# FlavorFlow: install (or reuse) the request logger that writes DIRECTLY into
# the web-served dir, so the assistant can fetch the log itself.
# Idempotent + re-runnable: running twice gives the same safe result.
set -u
cd /opt/flavorflow/server || { echo FATAL; exit 1; }
echo "=== FF-LIVE $(date) ==="
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/server.js';
let src = fs.readFileSync(f, 'utf8');
const NEW = "app.use((req, res, next) => { try { require('fs').appendFileSync('/opt/flavorflow/web/ff-requests.txt', new Date().toISOString() + ' ' + req.method + ' ' + req.originalUrl + ' UA:' + String(req.headers['user-agent']||'').slice(0,80) + ' BODY:' + JSON.stringify(req.body).slice(0,1200) + '\\n'); } catch (e) {} next(); });";
const lines = src.split('\n');
const i = lines.findIndex(l => l.includes('ff-requests.txt') || l.includes('ff-requests.log'));
if (i !== -1) {
  console.log('LOGGER ALREADY PRESENT (line ' + (i + 1) + ') — sirf log reset');
} else {
  let idx = -1;
  for (let j = 0; j < lines.length; j++) { if (/express\.json\(|bodyParser\.json\(/.test(lines[j])) idx = j; }
  if (idx === -1) { console.log('INSERT POINT NOT FOUND'); process.exit(2); }
  const bak = f + '.bak-live-' + Date.now();
  fs.copyFileSync(f, bak);
  lines.splice(idx + 1, 0, NEW);
  fs.writeFileSync(f, lines.join('\n'));
  console.log('LOGGER INSERTED (backup: ' + bak + ')');
  let ok = true;
  try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); } catch (e) { ok = false; }
  if (!ok) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED'); process.exit(3); }
  try { cp.execSync('systemctl restart flavorflow'); console.log('SERVICE RESTARTED'); } catch (e) { console.log('RESTART FAIL: ' + e.message); process.exit(4); }
}
try {
  fs.writeFileSync('/opt/flavorflow/web/ff-requests.txt', '');
  fs.writeFileSync('/opt/flavorflow/web/ff-live.txt', new Date().toISOString());
  console.log('LOG RESET + MARKER WRITTEN');
} catch (e) { console.log('WEB WRITE FAIL: ' + e.message); }
JS
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health; echo
echo "LIVE-READY — hun app vich Add User test karo (store_keeper + 2-3 chips toggles)"
