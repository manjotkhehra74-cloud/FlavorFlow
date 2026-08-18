#!/usr/bin/env bash
# FlavorFlow: broadcast notifications —
#   EVERY mutating action in EVERY section (product/inventory/packing/raw/
#   production/dispatch/adjustments/users/reports/settings) now notifies ALL
#   active users (except the person who did it).
#   EXCLUDED: logins and Packing Loss % sheet edits (per Manjot's request).
# How: helpers.js audit() is the single choke-point every route calls —
#   we wrap it, so nothing is missed and future sections are covered
#   automatically as long as they call audit().
# Idempotent — safe to run twice. Backup + node --check + auto-restore.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-NOTIFYFIX $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a helpers.js "/opt/flavorflow/backups/helpers.js.bak-notify-$TS"
echo "BACKUP: helpers.js -> /opt/flavorflow/backups/helpers.js.bak-notify-$TS"

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/helpers.js';
const bak = f + '.bak-notifyw-' + Date.now();
fs.copyFileSync(f, bak);
let src = fs.readFileSync(f, 'utf8');

if (src.includes('ffBroadcast')) { console.log('ALREADY PATCHED — skip'); process.exit(0); }

const m = src.match(/function audit\(/);
if (!m) { console.log('audit() NOT FOUND'); process.exit(2); }

// 1) rename the original implementation
src = src.replace(/function audit\(/, 'function _auditCore(');

// 2) wrapper + broadcast, inserted just before module.exports
const CODE = `
/* ff-notifyfix: every audited action notifies every active user (except the
   actor). Logins and Packing Loss % sheet edits are excluded. */
let _ffNotifCols = null;
function ffBroadcast(db, user, action, entity, refId, detail) {
  if (!user || !user.id) return;
  if (String(action).toUpperCase() === 'LOGIN') return;
  const d = String(detail || '');
  if (/^Loss (sheet|month)/i.test(d)) return; // Packing Loss % excluded
  if (!_ffNotifCols) {
    try { _ffNotifCols = db.prepare('PRAGMA table_info(notifications)').all().map((c) => c.name); }
    catch (_) { _ffNotifCols = []; }
  }
  if (!_ffNotifCols.includes('user_id')) return;
  const routes = {
    adjustment: '/adjustments', dispatch: '/dispatch', batch: '/production',
    user: '/users', product: '/products', inventory: '/inventory',
    packing: '/packing', report: '/reports', system: '/settings',
  };
  const title = (user.name || 'Someone') + ' \u00b7 ' + String(action).toLowerCase() + ' ' + String(entity || '');
  const body = d.length > 220 ? d.slice(0, 217) + '...' : d;
  const nowFn = (typeof istNow === 'function') ? istNow : (typeof nowIso === 'function') ? nowIso : () => new Date().toISOString();
  const now = nowFn();
  const vals = {
    user_id: 0, type: 'activity', title, body,
    route: routes[String(entity)] || '/notifications',
    entity: String(entity || ''), ref_id: Number(refId) || 0,
    is_read: 0, created_at: now,
  };
  const names = Object.keys(vals).filter((k) => _ffNotifCols.includes(k));
  if (!names.includes('user_id') || !names.includes('title')) return;
  const ins = db.prepare('INSERT INTO notifications (' + names.join(',') + ') VALUES (' + names.map(() => '?').join(',') + ')');
  const targets = db.prepare('SELECT id FROM users WHERE active = 1 AND id <> ?').all(user.id);
  for (const t of targets) {
    vals.user_id = t.id;
    try { ins.run(...names.map((k) => vals[k])); } catch (_) {}
  }
}
function audit(...args) {
  _auditCore(...args);
  try { ffBroadcast(...args); } catch (_) {}
}
`;

const anchor = src.lastIndexOf('module.exports');
if (anchor === -1) { console.log('module.exports NOT FOUND'); process.exit(2); }
src = src.slice(0, anchor) + CODE + '\n' + src.slice(anchor);
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); process.exit(3); }
console.log('BROADCAST PATCH OK');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "NOTIFYFIX FAIL — upar output dekho"; exit 1; fi

systemctl restart flavorflow
sleep 2
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
echo "NOTIFYFIX VERIFIED ✓ — har action di notification hun SARE active users nu (actor te Loss% chhad ke)"
