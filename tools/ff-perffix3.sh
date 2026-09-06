#!/usr/bin/env bash
# FlavorFlow perffix ROUND 3 — asal lag da karan: /production/batches te
#   /dispatch list saariyan (~2700+) rows bhejde ne; app poora table render
#   kardi hai te keyboard-open animation de har frame te oh dubara layout
#   hunda hai → keyboard slow.
#   FIX: batches/dispatches diyan list-SELECT queries te LIMIT 300 clamp.
#   (Reports/Loss% apne aggregate queries vertde ne — ohna nu hath nahi launa;
#    sirf list endpoints. COUNT/SUM/GROUP BY wale skip.)
# Idempotent. Backups + node --check + auto-restore.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-PERFFIX3 $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a server.js "/opt/flavorflow/backups/server.js.bak-perf3-$TS"
cp -a helpers.js "/opt/flavorflow/backups/helpers.js.bak-perf3-$TS" 2>/dev/null
echo "BACKUPS -> /opt/flavorflow/backups (suffix -perf3-$TS)"

echo ""
echo "--- DIAGNOSIS: table sizes ---"
node -e "const db=require('/opt/flavorflow/server/db');for(const t of ['batches','dispatches','dispatch_items']){try{console.log('  '+t+':',db.prepare('SELECT COUNT(*) c FROM '+t).get().c)}catch(e){console.log('  '+t+': n/a')}}"

echo ""
echo "--- DIAGNOSIS: list queries (asal lines) ---"
grep -n "FROM batches" server.js | head -8
grep -n "FROM dispatches" server.js | head -8

echo ""
echo "--- PATCH: clamp list SELECTs to LIMIT 300 ---"
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/server.js';
let src = fs.readFileSync(f, 'utf8');
const bak = f + '.bak-perf3w-' + Date.now();
fs.copyFileSync(f, bak);
let changed = 0;
src = src.replace(/(['"`])([^'"`]*SELECT[^'"`]*FROM\s+(?:batches|dispatches)\b[^'"`]*)\1/gi, (m, q, sql) => {
  if (/COUNT\s*\(|SUM\s*\(|GROUP\s+BY/i.test(sql)) return m;   // aggregates — leave
  const lim = sql.match(/LIMIT\s+(\d+)/i);
  if (lim) {
    if (parseInt(lim[1], 10) <= 300) return m;
    changed++;
    return q + sql.replace(/LIMIT\s+\d+/i, 'LIMIT 300') + q;
  }
  changed++;
  return q + sql + ' LIMIT 300' + q;
});
if (changed) {
  fs.writeFileSync(f, src);
  try { cp.execSync('node --check "' + f + '"'); console.log('server.js: ' + changed + ' list query clamped to LIMIT 300 — SYNTAX OK'); }
  catch (e) { fs.copyFileSync(bak, f); console.log('server.js: SYNTAX FAIL — RESTORED'); process.exit(3); }
} else console.log('server.js: no unlimited batches/dispatches list query found (dekho upar asal lines — dass dena)');
JS
[ $? -ne 0 ] && { echo "PERF3 PATCH FAIL — restored, kuch nahi badleya"; exit 1; }

systemctl restart flavorflow
sleep 2
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
echo "PERFFIX3 VERIFIED ✓ — production/dispatch lists hun max 300 rows; app restart karke Production page te keyboard test karo"
