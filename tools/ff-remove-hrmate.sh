#!/usr/bin/env bash
# FlavorFlow — remove the HRMate attendance bridge from the ERP server (MAN-11).
#   1) server.js: cut the ff-hrmate block (routes /api/settings/hrmate and
#      /api/hrmate/summary, added by tools/ff-hrmate.sh)
#   2) erp.db (factory) and every SaaS tenant erp.db: delete the stored 'hrmate'
#      setting from app_settings
#   The phone app no longer calls these routes (MAN-11), so nothing else changes.
#   Backups first · node --check + auto-restore · service restart.
set -u
if [ -d /opt/flavorflow-saas/core ]; then DIR=/opt/flavorflow-saas/core; SVC=flavorflow-saas; MODE=saas
elif [ -d /opt/flavorflow/server ]; then DIR=/opt/flavorflow/server; SVC=flavorflow; MODE=factory
else echo "FATAL: server folder nahi labhi"; exit 1; fi
echo "=== FF-REMOVE-HRMATE ($MODE) $(date) ==="
cd "$DIR" || exit 1
TS=$(date +%s)
mkdir -p /opt/flavorflow/backups

FF_FILE="$DIR/server.js" node <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = process.env.FF_FILE;
let src = fs.readFileSync(f, 'utf8');
const START = '// --- ff-hrmate v';
const END_RE = /\/\/ --- end ff-hrmate v[0-9]+ ---[ \t]*\n?/;
const si = src.indexOf(START);
if (si < 0) { console.log('server.js: ff-hrmate block nahi mila (pehlan hata chuka?)'); process.exit(0); }
const em = END_RE.exec(src.slice(si));
if (!em) { console.log('server.js: block da end marker nahi mila — kuch nahi badleya'); process.exit(1); }
const bak = f + '.bak-rmhrmate-' + Date.now();
fs.copyFileSync(f, bak);
const ls = src.lastIndexOf('\n', si) + 1;
src = src.slice(0, ls) + src.slice(si + em.index + em[0].length);
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SERVER: ff-hrmate block removed, syntax OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SERVER: SYNTAX FAIL — restored'); process.exit(1); }
process.exit(3);
JS
RC=$?
if [ $RC -eq 1 ]; then echo "SERVER PATCH FAILED — kuch nahi badleya"; exit 1; fi

# Stored HRMate setting (key 'hrmate') — factory DB + every SaaS tenant DB
if command -v sqlite3 >/dev/null 2>&1; then
  DBS=$(find /opt/flavorflow/server /opt/flavorflow-saas -name erp.db 2>/dev/null)
  for DB in $DBS; do
    cp -a "$DB" "/opt/flavorflow/backups/$(echo "$DB" | tr '/' '_')-bak-rmhrmate-$TS" 2>/dev/null
    N=$(sqlite3 "$DB" "SELECT COUNT(*) FROM app_settings WHERE key = 'hrmate';" 2>/dev/null)
    sqlite3 "$DB" "DELETE FROM app_settings WHERE key = 'hrmate';" 2>/dev/null
    echo "DB $DB: hrmate setting rows removed (were: ${N:-0})"
  done
else
  echo "sqlite3 CLI nahi mili — DB wali setting khud delete karo: DELETE FROM app_settings WHERE key='hrmate';"
fi

if [ $RC -eq 3 ] && [ -z "${FF_NO_RESTART:-}" ]; then
  systemctl restart "$SVC" && echo "SERVER: $SVC restarted"
  sleep 4
fi
CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 6 http://127.0.0.1:4000/api/settings/hrmate 2>/dev/null)
echo "/api/settings/hrmate -> $CODE (404 = route band ho gaya ✓)"
echo "REMOVE HRMATE DONE ✓"
