#!/usr/bin/env bash
# FlavorFlow: dump diagnostics (request log + GET/POST users handler code +
# DB state) into the web dir for the assistant to fetch. Re-runnable.
set -u
WB=/opt/flavorflow/web
TMP=/tmp/ff-dump.txt
: > "$TMP"
{
echo "=== FF-DUMP $(date) ==="
echo ""
echo "--- routes/users.js (FULL — GET/POST/PUT/DELETE) ---"
wc -l /opt/flavorflow/server/routes/users.js 2>/dev/null || echo "(file nahi mili)"
cat /opt/flavorflow/server/routes/users.js 2>/dev/null
echo ""
echo "--- REQUEST LOG (last 60 lines) ---"
tail -60 "$WB/ff-requests.txt" 2>/dev/null || echo "(no log file)"
echo ""
echo "--- POST /api/users entries ---"
grep 'POST /api/users' "$WB/ff-requests.txt" 2>/dev/null | tail -10 || echo "(none)"
echo ""
echo "--- DB: last 5 users + roles ---"
NMDIR=$(find /opt/flavorflow /usr/lib/node_modules /usr/local/lib/node_modules /root -maxdepth 5 -type d -name better-sqlite3 2>/dev/null | head -1)
echo "NMDIR: ${NMDIR:-NOTFOUND}"
if [ -n "$NMDIR" ]; then
  node -e "const db=require(process.argv[1])(process.argv[2]);console.log(JSON.stringify(db.prepare('SELECT id,name,email,role,active,permissions FROM users ORDER BY id DESC LIMIT 5').all(),null,1));console.log('ROLES:'+JSON.stringify(db.prepare('SELECT id,permissions FROM roles').all()));" "$NMDIR" /opt/flavorflow/server/data/erp.db
else
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 /opt/flavorflow/server/data/erp.db "SELECT id,name,email,role,active,permissions FROM users ORDER BY id DESC LIMIT 5; SELECT '---'; SELECT id,permissions FROM roles;"
  else
    echo "(no better-sqlite3 module, no sqlite3 CLI)"
  fi
fi
echo ""
echo "--- WEB BUILD INFO (Chrome app version) ---"
ls -la --time-style=+%Y-%m-%d "$WB" 2>/dev/null | head -8
cat "$WB/version.json" 2>/dev/null || echo "(no version.json)"
} > "$TMP" 2>&1
sudo cp "$TMP" "$WB/ff-dump.txt" && echo "SAVED -> $WB/ff-dump.txt"
curl -s -o /dev/null -w 'URL -> %{http_code}\n' -m 8 "https://flavorflow.duckdns.org/ff-dump.txt"
