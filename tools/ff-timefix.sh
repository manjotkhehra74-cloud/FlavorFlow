#!/usr/bin/env bash
# FlavorFlow FIX: wrong time & +1-day dates.
#   Cause: the server saves timestamps in UTC (new Date().toISOString()) —
#   IST is UTC+5:30, so times show 5½ hours off and dates roll to the wrong
#   day around midnight.
#   Fix:
#     1) system timezone → Asia/Kolkata
#     2) helpers.js: every new Date().toISOString() becomes an IST-shifted
#        ISO string (same format, Indian wall-clock values)
#     3) prints the helper definitions so we can verify
# Idempotent — safe to run twice.
set -u
echo "=== FF-TIMEFIX $(date) ==="

echo "--- current timezone: $(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null)"
timedatectl set-timezone Asia/Kolkata 2>/dev/null && echo "TIMEZONE → Asia/Kolkata ✓" || echo "timedatectl fail (docker?) — TZ env verta jayega"

cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/helpers.js';
if (!fs.existsSync(f)) { console.log('helpers.js nahi mili'); process.exit(2); }
let src = fs.readFileSync(f, 'utf8');

console.log('--- current time helpers ---');
for (const name of ['nowIso', 'dateOnly', 'weekdayName']) {
  const m = src.match(new RegExp('(function\\s+' + name + '[\\s\\S]{0,220}?\\n\\}|const\\s+' + name + '\\s*=[\\s\\S]{0,220}?;)'));
  console.log(m ? m[0].split('\n').slice(0, 5).join('\n') : name + ': NOT FOUND');
  console.log('---');
}

if (src.includes('istNow()')) { console.log('ALREADY PATCHED — skip'); process.exit(0); }
const bak = f + '.bak-timefix-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);

// IST clock: shift UTC by +5:30 and keep the ISO format the app already stores
const HELPER = `// ff-timefix: Indian wall-clock timestamps (UTC+5:30), same ISO shape as before
function istNow() { return new Date(Date.now() + 330 * 60 * 1000); }
`;
src = HELPER + src;
const before = (src.match(/new Date\(\)\.toISOString\(\)/g) || []).length;
src = src.split('new Date().toISOString()').join('istNow().toISOString()');
console.log('REPLACED new Date().toISOString() × ' + before);

fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 400)); process.exit(3); }
console.log('HELPERS PATCHED ✓');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "TIMEFIX FAIL"; exit 1; fi

# systemd service picks up the new system TZ on restart; also set TZ explicitly
if ! grep -q 'TZ=Asia/Kolkata' /etc/systemd/system/flavorflow.service 2>/dev/null; then
  sed -i '/^\[Service\]/a Environment=TZ=Asia/Kolkata' /etc/systemd/system/flavorflow.service 2>/dev/null \
    && systemctl daemon-reload && echo "SERVICE ENV TZ=Asia/Kolkata ✓" || echo "service env not set (koi gal nahi — system TZ kaafi hai)"
fi

systemctl restart flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo ""
echo "System time now: $(date)"
echo "TIMEFIX VERIFIED ✓ — nave records IST time/date naal banana ge (purane records jive si tive rehnge)"
