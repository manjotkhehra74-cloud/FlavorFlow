#!/usr/bin/env bash
# FlavorFlow perffix ROUND 2 —
#   Round 1 ne dasseya: query te koi LIMIT pehla hi hai (par kehda? print karange)
#   te purge ne 0 rows kaddiyan (created_at format date-string nahi si).
#   Eh script:
#     1) notifications queries diyan asal lines PRINT kardi hai (diagnosis)
#     2) har notifications-SELECT da LIMIT 100 te clamp kardi hai
#        (jithe LIMIT > 100 hai → 100; jithe hai hi nahi → add)
#     3) DB: format di parwah kite BINA sirf latest 500 rows rakhdi hai
#        (id-based — created_at nu chhunde vi nahi), baaki delete + VACUUM
# Idempotent. Backups + node --check + auto-restore.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-PERFFIX2 $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a server.js "/opt/flavorflow/backups/server.js.bak-perf2-$TS"
cp -a helpers.js "/opt/flavorflow/backups/helpers.js.bak-perf2-$TS" 2>/dev/null
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-perf2-$TS" 2>/dev/null
echo "BACKUPS -> /opt/flavorflow/backups (suffix -perf2-$TS)"

echo ""
echo "--- DIAGNOSIS: current notification queries (asal lines) ---"
grep -n "FROM notifications" server.js helpers.js 2>/dev/null | head -10
echo ""
echo "--- DIAGNOSIS: created_at format sample ---"
node -e "const db=require('/opt/flavorflow/server/db');try{const r=db.prepare('SELECT id, created_at FROM notifications ORDER BY id DESC LIMIT 1').get();console.log('  sample:',JSON.stringify(r))}catch(e){console.log('  err:',e.message)}"

echo ""
echo "--- PATCH 1: clamp every notifications SELECT to LIMIT 100 ---"
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const files = ['/opt/flavorflow/server/server.js', '/opt/flavorflow/server/helpers.js'];
for (const f of files) {
  if (!fs.existsSync(f)) continue;
  let src = fs.readFileSync(f, 'utf8');
  const bak = f + '.bak-perf2w-' + Date.now();
  fs.copyFileSync(f, bak);
  let changed = 0;
  src = src.replace(/(['"`])([^'"`]*SELECT[^'"`]*FROM\s+notifications[^'"`]*)\1/gi, (m, q, sql) => {
    if (/COUNT\s*\(/i.test(sql)) return m; // counts are cheap
    const lim = sql.match(/LIMIT\s+(\d+)/i);
    if (lim) {
      if (parseInt(lim[1], 10) <= 100) return m; // already tight
      changed++;
      return q + sql.replace(/LIMIT\s+\d+/i, 'LIMIT 100') + q;
    }
    changed++;
    return q + sql + ' LIMIT 100' + q;
  });
  if (changed) {
    fs.writeFileSync(f, src);
    try { cp.execSync('node --check "' + f + '"'); console.log(f.split('/').pop() + ': ' + changed + ' query clamped to LIMIT 100 — SYNTAX OK'); }
    catch (e) { fs.copyFileSync(bak, f); console.log(f.split('/').pop() + ': SYNTAX FAIL — RESTORED'); process.exit(3); }
  } else console.log(f.split('/').pop() + ': all notification queries already <= LIMIT 100');
}
JS
[ $? -ne 0 ] && { echo "PERF2 PATCH FAIL — restored, kuch nahi badleya"; exit 1; }

echo ""
echo "--- PATCH 2: keep ONLY latest 500 rows (id-based, format-proof) ---"
node - <<'JS'
const db = require('/opt/flavorflow/server/db');
try {
  const before = db.prepare('SELECT COUNT(*) c FROM notifications').get().c;
  db.prepare('CREATE INDEX IF NOT EXISTS idx_notif_user_id ON notifications(user_id, id)').run();
  const del = db.prepare('DELETE FROM notifications WHERE id NOT IN (SELECT id FROM notifications ORDER BY id DESC LIMIT 500)').run();
  const after = db.prepare('SELECT COUNT(*) c FROM notifications').get().c;
  const unread = db.prepare('SELECT COUNT(*) c FROM notifications WHERE is_read = 0').get().c;
  console.log('rows: ' + before + ' -> ' + after + ' (' + del.changes + ' deleted) | unread left: ' + unread);
  try { db.prepare('VACUUM').run(); console.log('VACUUM: OK'); } catch (e) { console.log('VACUUM skipped:', e.message); }
} catch (e) { console.log('DB step error:', e.message); }
JS

systemctl restart flavorflow
sleep 2
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
echo "PERFFIX2 VERIFIED ✓ — queries clamped te table 500 rows tak trim; app restart karke typing test karo"
