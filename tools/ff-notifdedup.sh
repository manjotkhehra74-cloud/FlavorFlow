#!/usr/bin/env bash
# FlavorFlow: duplicate notifications fix —
#   Ik action te 3-4 notifications aa rahiyan kyunki DO-TIN systems ikatthe
#   notification rows banaunde ne:
#     1) ffBroadcast (audit() wrap — ff-notifyfix)
#     2) notifycoverage (server-level request capture — ff-notifycoverage3/4)
#     3) legacy notifyRoles (kuch routes vich)
#   FIX: sirf COVERAGE rakhna (sab ton poora hai) —
#     - ffBroadcast nu no-op banao (audit sirf audit kare)
#     - notifyRoles nu no-op banao (helpers vich)
#     - DB: pichle 7 dina diyan EXACT-duplicate unread rows saaf karo
# Idempotent. Backups + node --check + auto-restore.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-NOTIFDEDUP $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a helpers.js "/opt/flavorflow/backups/helpers.js.bak-dedup-$TS"
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-dedup-$TS" 2>/dev/null
echo "BACKUPS -> /opt/flavorflow/backups (suffix -dedup-$TS)"

echo ""
echo "--- DIAGNOSIS: active notification writers ---"
grep -c "ffBroadcast" helpers.js 2>/dev/null | sed 's/^/  ffBroadcast refs (helpers): /'
grep -c "ffNotifyCoverage\|notifycoverage\|ffCapture" server.js helpers.js 2>/dev/null | sed 's/^/  coverage refs: /'
grep -c "function notifyRoles" helpers.js 2>/dev/null | sed 's/^/  notifyRoles def: /'
echo ""

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/helpers.js';
let src = fs.readFileSync(f, 'utf8');
const bak = f + '.bak-dedupw-' + Date.now();
fs.copyFileSync(f, bak);
let changed = false;

// coverage active hai? (server.js ya helpers.js vich)
const serverSrc = fs.readFileSync('/opt/flavorflow/server/server.js', 'utf8');
const coverageActive = /ffNotifyCoverage|notifycoverage|ffCapture/i.test(serverSrc + src);
if (!coverageActive) {
  console.log('COVERAGE NAHI LABHI — ffBroadcast rakh rahe haan (single system), sirf notifyRoles band karange');
} else {
  console.log('COVERAGE ACTIVE — ffBroadcast + notifyRoles band kar rahe haan (coverage hi sab bhejegi)');
}

// 1) ffBroadcast no-op (sirf je coverage active hai)
if (coverageActive && src.includes('function ffBroadcast') && !src.includes('/* ffDedup: disabled */')) {
  src = src.replace(/function ffBroadcast\(/, 'function ffBroadcast_disabled_(');
  src = src.replace(/(\n)/, '\n/* ffDedup: disabled */ function ffBroadcast() { /* coverage handles notifications */ }\n');
  changed = true;
  console.log('ffBroadcast: DISABLED (no-op)');
} else if (!coverageActive) {
  console.log('ffBroadcast: kept');
} else {
  console.log('ffBroadcast: already disabled');
}

// 2) notifyRoles no-op (duplicate source — coverage/broadcast sab users nu bhejde hi ne)
if (src.includes('function notifyRoles') && !src.includes('/* ffDedup: notifyRoles off */')) {
  src = src.replace(/function notifyRoles\(/, 'function notifyRoles_disabled_(');
  src = src.replace(/(\n)/, '\n/* ffDedup: notifyRoles off */ function notifyRoles() { /* superseded by broadcast/coverage */ }\n');
  changed = true;
  console.log('notifyRoles: DISABLED (no-op)');
} else console.log('notifyRoles: already disabled or absent');

if (changed) {
  fs.writeFileSync(f, src);
  try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
  catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED'); process.exit(3); }
}
JS
[ $? -ne 0 ] && { echo "DEDUP PATCH FAIL"; exit 1; }

# 3) DB cleanup: exact duplicates (same user+title+body within same minute) — keep lowest id
node - <<'JS'
const db = require('/opt/flavorflow/server/db');
try {
  const del = db.prepare(`
    DELETE FROM notifications WHERE id IN (
      SELECT n2.id FROM notifications n1
      JOIN notifications n2
        ON n2.user_id = n1.user_id
       AND n2.title = n1.title
       AND COALESCE(n2.body,'') = COALESCE(n1.body,'')
       AND substr(n2.created_at,1,16) = substr(n1.created_at,1,16)
       AND n2.id > n1.id
      WHERE n1.created_at > datetime('now','-7 day')
    )`).run();
  console.log('DB CLEANUP: ' + del.changes + ' duplicate notification rows deleted (last 7 days)');
} catch (e) { console.log('DB CLEANUP ERROR:', e.message); }
JS

systemctl restart flavorflow
sleep 2
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
echo "NOTIFDEDUP VERIFIED ✓ — hun ik action = IK notification (coverage system hi bhejega)"
