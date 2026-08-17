#!/usr/bin/env bash
# FlavorFlow: redirect the request logger straight into the web-served dir
# so the assistant can fetch the log directly. Idempotent + safe.
set -u
cd /opt/flavorflow/server || { echo FATAL; exit 1; }
LOG=/tmp/ff-log3-report.txt
: > "$LOG"
say(){ echo "$@" | tee -a "$LOG" >&2; }
say "=== FF-LOG3 $(date) ==="
node - <<'JS' 2>&1 | tee -a "$LOG" >&2
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/server.js';
let src = fs.readFileSync(f, 'utf8');
const NEW = "app.use((req, res, next) => { try { require('fs').appendFileSync('/opt/flavorflow/web/ff-requests.txt', new Date().toISOString() + ' ' + req.method + ' ' + req.originalUrl + ' UA:' + String(req.headers['user-agent']||'').slice(0,80) + ' BODY:' + JSON.stringify(req.body).slice(0,1200) + '\\n'); } catch (e) {} next(); });";
const lines = src.split('\n');
const i = lines.findIndex(l => l.includes('ff-requests.log') || l.includes('ff-requests.txt'));
if (i !== -1) { lines[i] = NEW; console.log('LOGGER LINE REPLACED (line ' + (i + 1) + ')'); }
else {
  let idx = -1;
  for (let j = 0; j < lines.length; j++) { if (/express\.json\(|bodyParser\.json\(/.test(lines[j])) idx = j; }
  if (idx === -1) { console.log('INSERT POINT NOT FOUND'); process.exit(2); }
  lines.splice(idx + 1, 0, NEW);
  console.log('LOGGER INSERTED after line ' + (idx + 1));
}
const out = lines.join('\n');
const bak = f + '.bak-log3-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);
fs.writeFileSync(f, out);
let ok = true;
try { cp.execSync('node --check "' + f + '"'); } catch (e) { ok = false; }
if (!ok) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED'); process.exit(3); }
console.log('SYNTAX OK');
try { fs.writeFileSync('/opt/flavorflow/web/ff-requests.txt', ''); console.log('LOG FILE RESET'); } catch (e) { console.log('LOG RESET FAIL: ' + e.message); }
try { cp.execSync('systemctl restart flavorflow'); console.log('SERVICE RESTARTED'); } catch (e) { console.log('RESTART FAIL: ' + String(e).slice(0, 200)); process.exit(4); }
setTimeout(() => {
  try { console.log('HEALTH: ' + cp.execSync('curl -s -m 5 http://127.0.0.1:4000/api/health').toString().trim()); } catch (e) { console.log('HEALTH ERR'); }
  try { console.log('--- LOG TAIL (pipeline test) ---'); console.log(cp.execSync('tail -5 /opt/flavorflow/web/ff-requests.txt').toString()); } catch (e) { console.log('LOG TAIL ERR: ' + e.message); }
}, 2500);
JS
say "--- SYSTEM INFO ---"
{
systemctl list-units --type=service --no-pager 2>/dev/null | grep -i flavor
echo "--- ports ---"
ss -tlnp 2>/dev/null | grep -E ':400[0-9]|node' | head -10
echo "--- unit key lines ---"
systemctl cat flavorflow 2>/dev/null | grep -iE 'ExecStart|WorkingDirectory|User=|PrivateTmp|Environment' | head -10
} | tee -a "$LOG" >&2
WB=/opt/flavorflow/web
cp "$LOG" "$WB/ff-log3-report.txt" && say "COPIED -> $WB/ff-log3-report.txt"
curl -s -o /dev/null -w 'URL CHECK -> %{http_code}\n' -m 8 "https://flavorflow.duckdns.org/ff-log3-report.txt" | tee -a "$LOG" >&2
say "=== DONE — hun app vich Add User test karo (store_keeper + 2-3 chips) ==="
