#!/usr/bin/env bash
# FlavorFlow: install (or refresh) the request logger writing DIRECTLY into
# the web-served dir. v2: always restarts, resets log, fixes file ownership
# so the service user can actually append to it.
# Idempotent + re-runnable.
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
  console.log('LOGGER LINE PRESENT (line ' + (i + 1) + ')');
} else {
  let idx = -1;
  for (let j = 0; j < lines.length; j++) { if (/express\.json\(|bodyParser\.json\(/.test(lines[j])) idx = j; }
  if (idx === -1) { console.log('INSERT POINT NOT FOUND'); process.exit(2); }
  const bak = f + '.bak-live-' + Date.now();
  fs.copyFileSync(f, bak);
  console.log('LOGGER INSERTED (backup: ' + bak + ')');
  lines.splice(idx + 1, 0, NEW);
  fs.writeFileSync(f, lines.join('\n'));
}
let ok = true;
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); } catch (e) { ok = false; console.log(String(e.stderr || e).slice(0, 300)); }
if (!ok) { process.exit(3); }
try {
  fs.writeFileSync('/opt/flavorflow/web/ff-requests.txt', '');
  fs.writeFileSync('/opt/flavorflow/web/ff-live.txt', new Date().toISOString());
  cp.execSync('chown flavorflow:flavorflow /opt/flavorflow/web/ff-requests.txt /opt/flavorflow/web/ff-live.txt');
  console.log('LOG RESET + CHOWN OK');
} catch (e) { console.log('WEB WRITE FAIL: ' + e.message); }
try { cp.execSync('systemctl restart flavorflow'); console.log('SERVICE RESTARTED'); } catch (e) { console.log('RESTART FAIL: ' + e.message); process.exit(4); }
JS
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health; echo
echo "--- log test line (should be 1+) ---"
wc -l /opt/flavorflow/web/ff-requests.txt 2>/dev/null || echo "(missing)"
echo "LIVE-READY — hun app vich nava user banao (store_keeper + 2-3 chips toggle), fer ff-dump chalao"
