#!/usr/bin/env bash
# FlavorFlow cleanup: remove the diagnostic request logger from server.js,
# restore from the clean backup, restart the service, verify health.
# Run via: curl -s .../tools/ff-clean.sh -o /tmp/ff-clean.sh && sudo bash /tmp/ff-clean.sh
set -u
cd /opt/flavorflow/server || { echo FATAL; exit 1; }

echo "--- logger lines in server.js now ---"
grep -c 'ff-requests' server.js 2>/dev/null || echo "0 (no logger)"
echo "--- backups present ---"
ls -1 server.js.bak-* db.js.bak-* 2>/dev/null || echo "none"

CLEAN=$(ls -tr server.js.bak-log-* 2>/dev/null | head -1)
echo "CLEAN BACKUP CANDIDATE: ${CLEAN:-NONE}"
if [ -n "$CLEAN" ] && ! grep -q 'ff-requests' "$CLEAN"; then
  cp "$CLEAN" server.js && node --check server.js && echo "RESTORED FROM: $CLEAN (SYNTAX OK)"
else
  echo "NO CLEAN BACKUP — removing logger lines from server.js directly"
  node -e "const fs=require('fs');let s=fs.readFileSync('server.js','utf8');s=s.split('\n').filter(l=>!l.includes('ff-requests')).join('\n');fs.writeFileSync('server.js',s);"
  node --check server.js || { echo SYNTAX-FAIL; exit 1; }
  echo "LOGGER-REMOVED (SYNTAX OK)"
fi

echo "--- final check: logger lines ---"
grep -c 'ff-requests' server.js 2>/dev/null || echo "0 — clean"

systemctl restart flavorflow && echo SERVICE-RESTARTED
sleep 2
echo "--- health ---"
curl -s -m 5 http://127.0.0.1:4000/api/health; echo

rm -f server.js.bak-log-* server.js.bak-log3-* db.js.bak-*
rm -f /opt/flavorflow/web/ff-*.txt
echo "CLEANUP-DONE"
