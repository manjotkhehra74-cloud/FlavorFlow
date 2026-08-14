#!/usr/bin/env bash
# FlavorFlow: dump diagnostics (users.js top + rbac defaults + request log +
# DB) into the web dir for the assistant. Re-runnable.
set -u
WB=/opt/flavorflow/web
TMP=/tmp/ff-dump.txt
: > "$TMP"
{
echo "=== FF-DUMP $(date) ==="
echo ""
echo "--- routes/users.js (lines 1-45: GET handler) ---"
sed -n '1,45p' /opt/flavorflow/server/routes/users.js 2>/dev/null || echo "(file nahi mili)"
echo ""
echo "--- rbac.js (role defaults) ---"
cat /opt/flavorflow/server/rbac.js 2>/dev/null || echo "(file nahi mili)"
echo ""
echo "--- systemd unit (User=) ---"
systemctl cat flavorflow 2>/dev/null | grep -iE 'User=|ExecStart|WorkingDirectory' || echo "(na mili)"
echo ""
echo "--- REQUEST LOG (last 40 lines) ---"
tail -40 "$WB/ff-requests.txt" 2>/dev/null || echo "(no log file)"
echo ""
echo "--- POST /api/users entries ---"
grep 'POST /api/users' "$WB/ff-requests.txt" 2>/dev/null | tail -6 || echo "(none)"
echo ""
echo "--- DB: last 6 users ---"
if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 /opt/flavorflow/server/data/erp.db "SELECT id,name,email,role,active,permissions FROM users ORDER BY id DESC LIMIT 6;" 2>&1
else
  node -e "const db=require('/opt/flavorflow/server/node_modules/better-sqlite3')('/opt/flavorflow/server/data/erp.db');console.log(JSON.stringify(db.prepare('SELECT id,name,email,role,active,permissions FROM users ORDER BY id DESC LIMIT 6').all(),null,1))" 2>&1
fi
} > "$TMP" 2>&1
cp "$TMP" "$WB/ff-dump.txt" && echo "SAVED -> $WB/ff-dump.txt"
curl -s -o /dev/null -w 'URL -> %{http_code}\n' -m 8 "https://flavorflow.duckdns.org/ff-dump.txt"
