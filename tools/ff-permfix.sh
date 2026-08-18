#!/usr/bin/env bash
# FlavorFlow: permissions for the new sections (Raw Material + Packing Loss %).
#   1) rbac.js: ALL_PERMISSIONS += raw.view/raw.manage/loss.view/loss.manage,
#      every role that has packing.view/manage gets the matching raw./loss. perms,
#      NAV_ITEMS += /raw (raw.view) and /loss (loss.view).
#   2) routes/packing.js: recipes & recipe-consume guarded by raw.*,
#      /loss endpoints guarded by loss.*.
#   3) DB: users with CUSTOM permission lists get raw./loss. backfilled to
#      mirror their packing. perms (so nobody loses access silently).
# Idempotent — safe to run twice. Backups + node --check + auto-restore.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-PERMFIX $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-perm-$TS" 2>/dev/null
cp -a rbac.js "/opt/flavorflow/backups/rbac.js.bak-perm-$TS"
cp -a routes/packing.js "/opt/flavorflow/backups/packing.js.bak-perm-$TS"
echo "BACKUPS: erp.db / rbac.js / packing.js -> /opt/flavorflow/backups (suffix -perm-$TS)"

# ---------- 1) rbac.js ----------
node - <<'JS'
const fs = require('fs');
const f = '/opt/flavorflow/server/rbac.js';
let src = fs.readFileSync(f, 'utf8');
let changed = false;

if (!src.includes("'raw.view'")) {
  // ALL_PERMISSIONS: insert right after the packing pair (first occurrence only).
  const allIdx = src.indexOf("const ALL_PERMISSIONS");
  const roleIdx = src.indexOf("const ROLE_PERMISSIONS");
  if (allIdx === -1 || roleIdx === -1) { console.log('rbac markers NOT FOUND'); process.exit(2); }
  let head = src.slice(0, roleIdx);
  let tail = src.slice(roleIdx);
  head = head.replace("'packing.view', 'packing.manage',",
    "'packing.view', 'packing.manage',\n  'raw.view', 'raw.manage',\n  'loss.view', 'loss.manage',");

  // ROLE_PERMISSIONS: mirror packing perms for every role.
  tail = tail.replace(/'packing\.view',(\s*'packing\.manage',)?/g, (m, mg) =>
    mg ? "'packing.view', 'packing.manage', 'raw.view', 'raw.manage', 'loss.view', 'loss.manage',"
       : "'packing.view', 'raw.view', 'loss.view',");

  src = head + tail;
  changed = true;
  console.log('rbac: permissions added (ALL + role mirrors)');
} else console.log('rbac: permissions already present');

if (!src.includes("path: '/raw'")) {
  const m = src.match(/\{ *path: *'\/packing'[^\n]*\n/);
  if (!m) { console.log('rbac NAV packing entry NOT FOUND'); process.exit(2); }
  src = src.replace(m[0], m[0] +
    "  { path: '/raw',         label: 'Raw Material',       icon: 'science',        perm: 'raw.view',            group: 'Operations' },\n" +
    "  { path: '/loss',        label: 'Packing Loss %',     icon: 'percent',        perm: 'loss.view',           group: 'Operations' },\n");
  changed = true;
  console.log('rbac: NAV /raw + /loss added');
} else console.log('rbac: NAV already present');

if (changed) fs.writeFileSync(f, src);
JS
[ $? -ne 0 ] && { echo "RBAC PATCH FAILED — restoring"; cp -a "/opt/flavorflow/backups/rbac.js.bak-perm-$TS" rbac.js; exit 1; }

# ---------- 2) routes/packing.js guards ----------
node - <<'JS'
const fs = require('fs');
const f = '/opt/flavorflow/server/routes/packing.js';
let src = fs.readFileSync(f, 'utf8');
let n = 0;
const subs = [
  [/(['"]\/recipes['"]\s*,\s*)requirePerm\(\s*'packing\.view'\s*\)/g,   "$1requirePerm('raw.view')"],
  [/(['"]\/recipes\/:id['"]\s*,\s*)requirePerm\(\s*'packing\.manage'\s*\)/g, "$1requirePerm('raw.manage')"],
  [/(['"]\/recipe-consume['"]\s*,\s*)requirePerm\(\s*'packing\.manage'\s*\)/g, "$1requirePerm('raw.manage')"],
  [/(['"]\/loss['"]\s*,\s*)requirePerm\(\s*'packing\.view'\s*\)/g,      "$1requirePerm('loss.view')"],
  [/(['"]\/loss\/archives['"]\s*,\s*)requirePerm\(\s*'packing\.view'\s*\)/g, "$1requirePerm('loss.view')"],
  [/(['"]\/loss\/cell['"]\s*,\s*)requirePerm\(\s*'packing\.manage'\s*\)/g,  "$1requirePerm('loss.manage')"],
  [/(['"]\/loss\/close['"]\s*,\s*)requirePerm\(\s*'packing\.manage'\s*\)/g, "$1requirePerm('loss.manage')"],
];
for (const [re, rep] of subs) {
  const before = src;
  src = src.replace(re, rep);
  if (src !== before) n++;
}
fs.writeFileSync(f, src);
console.log(n > 0 ? `packing.js: ${n} route guard(s) switched to raw./loss.` : 'packing.js: guards already switched (or none found)');
JS
[ $? -ne 0 ] && { echo "PACKING PATCH FAILED — restoring"; cp -a "/opt/flavorflow/backups/packing.js.bak-perm-$TS" routes/packing.js; exit 1; }

# ---------- 3) DB backfill for custom-permission users ----------
node - <<'JS'
const db = require('/opt/flavorflow/server/db');
const rows = db.prepare("SELECT id, name, permissions FROM users WHERE permissions IS NOT NULL AND permissions != '' AND permissions != '[]'").all();
let updated = 0;
for (const u of rows) {
  let perms;
  try { perms = JSON.parse(u.permissions); } catch { continue; }
  if (!Array.isArray(perms) || perms.length === 0) continue;
  const before = perms.length;
  if (perms.includes('packing.view')) {
    if (!perms.includes('raw.view')) perms.push('raw.view');
    if (!perms.includes('loss.view')) perms.push('loss.view');
  }
  if (perms.includes('packing.manage')) {
    if (!perms.includes('raw.manage')) perms.push('raw.manage');
    if (!perms.includes('loss.manage')) perms.push('loss.manage');
  }
  if (perms.length !== before) {
    db.prepare('UPDATE users SET permissions = ? WHERE id = ?').run(JSON.stringify(perms.sort()), u.id);
    updated++;
    console.log(`backfilled: ${u.name} (+${perms.length - before})`);
  }
}
console.log(`DB backfill: ${updated} custom-permission user(s) updated`);
JS

# ---------- verify + restart ----------
node --check rbac.js && node --check routes/packing.js
if [ $? -ne 0 ]; then
  echo "SYNTAX FAIL — restoring backups"
  cp -a "/opt/flavorflow/backups/rbac.js.bak-perm-$TS" rbac.js
  cp -a "/opt/flavorflow/backups/packing.js.bak-perm-$TS" routes/packing.js
  exit 1
fi
systemctl restart flavorflow
sleep 2
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
grep -c "raw.view" rbac.js >/dev/null && echo "PERMFIX VERIFIED ✓ — raw.view/raw.manage/loss.view/loss.manage live; Edit User vich nave chips dikhenge"
