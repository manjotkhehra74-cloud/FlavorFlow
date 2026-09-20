#!/usr/bin/env bash
# FlavorFlow ERP — server-down repair.
#   1) restores routes/production.js from the newest backup
#      (bak-batchunit2-* = last known-good v3, then bak-batchunit-* = v2)
#   2) node --check
#   3) restarts the flavorflow service
#   4) local health check + prints logs if still down
# Safe to re-run. Does not touch the database.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-SERVER-FIX $(date) ==="

F=routes/production.js
echo "--- current state ---"
node --check "$F" >/dev/null 2>&1 && echo "SYNTAX OK (as-is)" || echo "SYNTAX BROKEN (as-is)"
systemctl is-active --quiet flavorflow && echo "service: running" || echo "service: NOT running"

# newest backup = highest mtime
BAK=$(ls -1t ${F}.bak-batchunit2-* ${F}.bak-batchunit-* 2>/dev/null | head -1 || true)
if [ -z "${BAK:-}" ]; then
  echo "NO BACKUP FOUND — production.js left untouched"
else
  echo "--- restoring: $BAK ---"
  cp -a "$BAK" "$F"
  node --check "$F" && echo "SYNTAX OK after restore" || { echo "SYNTAX STILL BAD — STOPPING"; exit 1; }
fi

echo "--- restarting ---"
systemctl restart flavorflow || true
sleep 4
systemctl is-active --quiet flavorflow && echo "service: RUNNING" || echo "service: STILL DOWN"

echo "--- health ---"
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAIL"

if ! systemctl is-active --quiet flavorflow; then
  echo "--- last 30 log lines ---"
  journalctl -u flavorflow -n 30 --no-pager
  echo "--- port 4000 ---"
  ss -ltnp 2>/dev/null | grep 4000 || echo "nothing listening on 4000"
fi
echo "=== DONE ==="
