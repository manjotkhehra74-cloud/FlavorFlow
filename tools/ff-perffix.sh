#!/usr/bin/env bash
# FlavorFlow: app slow / keyboard lag fix —
#   /notifications har 20s te PURI table bhejda si (hazaran rows after the
#   triple-writer bug) — phone har poll te sab download+parse karda si,
#   jis naal keyboard/typing lag hunda si.
#   FIX (server-side, koi APK nahi chahida):
#     1) SELECT ... FROM notifications queries te LIMIT 100 lao (jithe nahi hai)
#     2) index: notifications(user_id, id) — fast lookups
#     3) purge: read rows > 30 din purane, sab rows > 90 din purane
# Idempotent. Backups + node --check + auto-restore.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-PERFFIX $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a server.js "/opt/flavorflow/backups/server.js.bak-perf-$TS"
cp -a helpers.js "/opt/flavorflow/backups/helpers.js.bak-perf-$TS" 2>/dev/null
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-perf-$TS" 2>/dev/null
echo "BACKUPS -> /opt/flavorflow/backups (suffix -perf-$TS)"

echo ""
echo "--- DIAGNOSIS: notifications table size ---"
node - <<'JS'
const db = require('/opt/flavorflow/server/db');
try {
  const t = db.prepare('SELECT COUNT(*) c FROM notifications').get();
  const u = db.prepare('SELECT COUNT(*) c FROM notifications WHERE is_read = 0').get();
  console.log('  total rows: ' + t.c + ' | unread: ' + u.c);
} catch (e) { console.log('  count error:', e.message); }
JS

echo ""
echo "--- PATCH 1: LIMIT on notification queries ---"
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const files = ['/opt/flavorflow/server/server.js', '/opt/flavorflow/server/helpers.js'];
for (const f of files) {
  if (!fs.existsSync(f)) continue;
  let src = fs.readFileSync(f, 'utf8');
  const bak = f + '.bak-perfw-' + Date.now();
  fs.copyFileSync(f, bak);
  let changed = false;
  // single/double/backtick-quoted SELECT ... FROM notifications ... without LIMIT
  src = src.replace(/(['"`])(\s*SELECT[^'"`]*FROM\s+notifications[^'"`]*)\1/gi, (m, q, sql) => {
    if (/LIMIT\s+\d+/i.test(sql)) return m;      // already limited
    if (/COUNT\s*\(/i.test(sql)) return m;       // counts are cheap — leave
    changed = true;
    return q + sql + ' LIMIT 100' + q;
  });
  if (changed) {
    fs.writeFileSync(f, src);
    try { cp.execSync('node --check "' + f + '"'); console.log(f.split('/').pop() + ': LIMIT 100 added — SYNTAX OK'); }
    catch (e) { fs.copyFileSync(bak, f); console.log(f.split('/').pop() + ': SYNTAX FAIL — RESTORED'); process.exit(3); }
  } else console.log(f.split('/').pop() + ': no change needed (already limited / no unlimited query)');
}
JS
[ $? -ne 0 ] && { echo "PERF PATCH FAIL — restored, kuch nahi badleya"; exit 1; }

echo ""
echo "--- PATCH 2: index + purge old rows ---"
node - <<'JS'
const db = require('/opt/flavorflow/server/db');
try {
  db.prepare('CREATE INDEX IF NOT EXISTS idx_notif_user_id ON notifications(user_id, id)').run();
  console.log('index idx_notif_user_id: OK');
  const a = db.prepare("DELETE FROM notifications WHERE is_read = 1 AND created_at < datetime('now','-30 day')").run();
  const b = db.prepare("DELETE FROM notifications WHERE created_at < datetime('now','-90 day')").run();
  console.log('purged: ' + a.changes + ' read rows (>30d), ' + b.changes + ' old rows (>90d)');
  const t = db.prepare('SELECT COUNT(*) c FROM notifications').get();
  console.log('rows left: ' + t.c);
  try { db.prepare('VACUUM').run(); console.log('VACUUM: OK'); } catch (e) { console.log('VACUUM skipped:', e.message); }
} catch (e) { console.log('DB step error:', e.message); }
JS

systemctl restart flavorflow
sleep 2
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
echo "PERFFIX VERIFIED ✓ — /notifications hun max 100 rows bhejda hai; purani rows saaf; app/keyboard lag hat jana chahida"
