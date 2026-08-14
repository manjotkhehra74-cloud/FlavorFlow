#!/usr/bin/env bash
# FlavorFlow check: installs a request logger (if missing) + dumps diagnostics
# to the web-served dir so the assistant can read them remotely.
set -u
LOG=/tmp/ff-check-report.txt
: > "$LOG"
say(){ echo "$@" | tee -a "$LOG" >&2; }

say "=== FF-CHECK $(date) ==="
say "WHOAMI: $(whoami)  HOST: $(hostname)"
cd /opt/flavorflow/server || { say "FATAL: cd fail"; exit 1; }
say "NODE: $(node -v 2>/dev/null || echo missing)"

# find web build dir (served statically at site root)
WB=$(find /opt/flavorflow /var/www /home /srv -maxdepth 6 -name main.dart.js -printf '%h\n' 2>/dev/null | head -1)
say "WEBBUILD: ${WB:-NOT FOUND}"
if [ -n "${WB:-}" ]; then
  ls -la --time-style=+%Y-%m-%d "$WB" 2>/dev/null | head -8 | tee -a "$LOG" >&2
fi

# request logger install (idempotent — safe to run again)
say "--- LOGGER ---"
node - <<'JS' 2>&1 | tee -a "$LOG" >&2
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/server.js';
if (!fs.existsSync(f)) { console.log('FATAL: server.js nahi mili'); process.exit(2); }
let src = fs.readFileSync(f, 'utf8');
if (src.includes('ff-requests.log')) { console.log('LOGGER PEHLA HI INSTALLED'); process.exit(0); }
const bak = f + '.bak-log-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);
const LINE = "app.use((req, res, next) => { try { require('fs').appendFileSync('/tmp/ff-requests.log', new Date().toISOString() + ' ' + req.method + ' ' + req.originalUrl + ' UA:' + String(req.headers['user-agent']||'').slice(0,60) + ' BODY:' + JSON.stringify(req.body).slice(0,900) + '\\n'); } catch (e) {} next(); });\n";
const lines = src.split('\n');
let idx = -1;
for (let i = 0; i < lines.length; i++) { if (/express\.json\(|bodyParser\.json\(/.test(lines[i])) idx = i; }
if (idx === -1) { for (let i = 0; i < lines.length; i++) { if (/app\.(get|post|put|delete|all|use)\(\s*['"`]\//.test(lines[i])) { idx = i - 1; break; } } }
if (idx === -1) { console.log('INSERTION POINT NAHI MILA'); process.exit(2); }
lines.splice(idx + 1, 0, LINE);
fs.writeFileSync(f, lines.join('\n'));
let ok = true;
try { cp.execSync('node --check "' + f + '"'); } catch (e) { ok = false; }
if (!ok) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — ORIGINAL RESTORE'); process.exit(3); }
try { cp.execSync('systemctl restart flavorflow'); console.log('LOGGER INSTALLED + SERVICE RESTARTED'); }
catch (e) { console.log('RESTART FAILED: ' + String(e).slice(0, 200)); process.exit(4); }
setTimeout(() => { try { console.log('HEALTH: ' + cp.execSync('curl -s -m 5 http://127.0.0.1:4000/api/health').toString().trim()); } catch (e) { console.log('HEALTH ERR'); } }, 2000);
JS

# diagnostics dump
say "--- DIAGNOSTICS ---"
{
echo "=== server.js mounts/routes ==="
grep -n "app.use\|app.post\|app.put\|app.get\|express.json\|bodyParser" server.js | head -60
echo ""
echo "=== users route candidates ==="
UFILES=$(grep -rln "users" . --include=*.js 2>/dev/null | grep -v node_modules)
echo "$UFILES"
for f in $UFILES; do
  LNS=$(grep -nE "\.(post|put)\(\s*['\"\`]/?users|\.(post|put)\(\s*['\"\`]/?api/users|INSERT INTO users|insert into users" "$f" 2>/dev/null | cut -d: -f1 | head -4)
  for ln in $LNS; do
    echo "===== $f : $ln ====="
    sed -n "$((ln>14?ln-14:1)),$((ln+60))p" "$f"
    echo ""
  done
done
echo "=== ROLES ==="
node -e "const db=require('better-sqlite3')('data/erp.db');console.log(JSON.stringify(db.prepare('SELECT * FROM roles').all(),null,1))"
echo "=== RECENT USERS ==="
node -e "const db=require('better-sqlite3')('data/erp.db');console.log(JSON.stringify(db.prepare('SELECT id,name,email,role,permissions FROM users ORDER BY id DESC LIMIT 5').all(),null,1))"
} >> "$LOG" 2>&1

# publish to web dir
if [ -n "${WB:-}" ]; then
  cp "$LOG" "$WB/ff-check-report.txt" && say "COPIED -> $WB/ff-check-report.txt"
fi
CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 8 "https://flavorflow.duckdns.org/ff-check-report.txt")
say "URL CHECK /ff-check-report.txt -> ${CODE:-ERR}"
say "=== DONE — hun app vich Add User test karo, fer 2nd command chalao ==="
