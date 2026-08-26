#!/usr/bin/env bash
# FlavorFlow: notification diagnosis + test —
#   1) helpers.js/server.js vich broadcast patch (ffBroadcast/notifycoverage)
#      hai ya kise ne toad ditta — check
#   2) notifications table: pichle 3 dina diyan rows, kis-kis user nu baniyan
#   3) LIVE TEST: har active user nu ik test notification insert kardi —
#      app 20 second vich phone te dikha devegi (je client theek hai)
# Read-mostly — sirf test rows insert hundiyan (type='activity').
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-NOTIFDIAG $(date) ==="

echo ""
echo "--- 1) SERVER PATCH STATE ---"
grep -c "ffBroadcast" helpers.js 2>/dev/null | sed 's/^/  helpers.js ffBroadcast refs: /'
grep -c "notifycoverage\|ffNotifyCoverage\|ffCapture" server.js helpers.js 2>/dev/null | sed 's/^/  coverage refs: /'
grep -n "function audit" helpers.js | sed 's/^/  /'
echo ""

echo "--- 2) NOTIFICATIONS TABLE (last 3 days) ---"
node - <<'JS'
const db = require('/opt/flavorflow/server/db');
try {
  const cols = db.prepare('PRAGMA table_info(notifications)').all().map(c => c.name);
  console.log('  columns:', cols.join(', '));
  const cutoff = new Date(Date.now() - 3*24*3600*1000).toISOString();
  const rows = db.prepare("SELECT COUNT(*) c FROM notifications WHERE created_at > ?").get(cutoff);
  console.log('  rows created last 3 days:', rows.c);
  const byUser = db.prepare("SELECT user_id, COUNT(*) c FROM notifications WHERE created_at > ? GROUP BY user_id ORDER BY user_id").all(cutoff);
  const users = db.prepare('SELECT id, name FROM users WHERE active = 1').all();
  const nameOf = {}; for (const u of users) nameOf[u.id] = u.name;
  for (const r of byUser) console.log('   user', r.user_id, '(' + (nameOf[r.user_id] || '?') + '):', r.c, 'notifs');
  const last = db.prepare('SELECT id, user_id, title, created_at FROM notifications ORDER BY id DESC LIMIT 5').all();
  console.log('  last 5:');
  for (const n of last) console.log('   #' + n.id, 'u' + n.user_id, JSON.stringify(n.title).slice(0,60), n.created_at);
} catch (e) { console.log('  TABLE ERROR:', e.message); }
JS
echo ""

echo "--- 3) LIVE TEST INSERT (har active user nu ik test notification) ---"
node - <<'JS'
const db = require('/opt/flavorflow/server/db');
try {
  const cols = db.prepare('PRAGMA table_info(notifications)').all().map(c => c.name);
  const now = new Date(Date.now() + 330*60000).toISOString(); // IST
  const users = db.prepare('SELECT id, name FROM users WHERE active = 1').all();
  const vals = {
    user_id: 0, type: 'activity',
    title: 'Test notification — ff-notifdiag',
    body: 'Je eh phone te dikhi ta system theek hai (' + now.slice(11,16) + ')',
    route: '/notifications', entity: 'system', ref_id: 0, is_read: 0, created_at: now,
  };
  const names = Object.keys(vals).filter(k => cols.includes(k));
  const ins = db.prepare('INSERT INTO notifications (' + names.join(',') + ') VALUES (' + names.map(()=>'?').join(',') + ')');
  let n = 0;
  for (const u of users) { vals.user_id = u.id; ins.run(...names.map(k => vals[k])); n++; }
  console.log('  INSERTED test notification for', n, 'users:', users.map(u=>u.name).join(', '));
} catch (e) { console.log('  INSERT ERROR:', e.message); }
JS
echo ""
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
echo "NOTIFDIAG VERIFIED ✓ — hun 20-30 second vich app khulle phone te 'Test notification' aauni chahidi (bell vich vi dikhegi)"
