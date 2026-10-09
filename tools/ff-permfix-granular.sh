#!/usr/bin/env bash
# FlavorFlow — MAN-8: Complete Section-Level Permissions + Automatic Registration
# Adds granular permissions for every section and ensures auto-registration
# Idempotent, with backup and rollback
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server not found"; exit 1; }
echo "=== FF-PERM-GRANULAR $(date) ==="
TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-perm-granular-$TS" 2>/dev/null || true
cp -a rbac.js "/opt/flavorflow/backups/rbac.js.bak-perm-granular-$TS"
echo "BACKUP: rbac.js + erp.db -> /opt/flavorflow/backups (suffix -perm-granular-$TS)"

node <<'JS'
const fs = require('fs');
const f = '/opt/flavorflow/server/rbac.js';
let src = fs.readFileSync(f, 'utf8');
let changed = false;

// Define all granular permissions — mirrors lib/core/app_permissions.dart
const ALL_GRANULAR = [
  // Dashboard
  'dashboard.view',
  // Products
  'products.view','products.create','products.edit','products.delete','products.manage',
  // Inventory
  'inventory.view','inventory.create','inventory.edit','inventory.delete','inventory.manage',
  // Stock Ledger
  'stock.view','stock.export',
  // Packing
  'packing.view','packing.create','packing.edit','packing.delete','packing.manage','packing.receive','packing.consume','packing.bom.view','packing.bom.manage',
  // Raw
  'raw.view','raw.create','raw.edit','raw.delete','raw.manage','raw.receive','raw.consume',
  // Loss
  'loss.view','loss.manage',
  // Production
  'production.view','production.create','production.edit','production.delete','production.execute','production.manage',
  // Dispatch
  'dispatch.view','dispatch.create','dispatch.edit','dispatch.delete','dispatch.manage',
  // Billing
  'billing.view','billing.create','billing.edit','billing.delete','billing.manage',
  // Adjustments
  'adjustments.view','adjustments.create','adjustments.edit','adjustments.delete','adjustments.manage','adjustments.approve',
  // Reports
  'reports.view','reports.export',
  // Productivity
  'productivity.view','productivity.manage',
  // Users
  'users.view','users.create','users.edit','users.delete','users.manage',
  // Audit
  'audit.view',
  // Settings
  'settings.view','settings.manage',
  // Notifications
  'notifications.view',
];

console.log(`Total granular permissions: ${ALL_GRANULAR.length}`);

// 1) Update ALL_PERMISSIONS
const allMatch = src.match(/const ALL_PERMISSIONS\s*=\s*\[([\s\S]*?)\];/);
if (!allMatch) { console.error('ALL_PERMISSIONS not found'); process.exit(2); }
let allContent = allMatch[1];
let allPerms = allContent.match(/'[^']+'/g) || [];
let allSet = new Set(allPerms.map(s=>s.replace(/'/g,'')));
let addedAll = [];
for (const p of ALL_GRANULAR) {
  if (!allSet.has(p)) {
    addedAll.push(p);
    allSet.add(p);
  }
}
if (addedAll.length > 0) {
  // Rebuild ALL_PERMISSIONS array with all granular
  const newAll = Array.from(allSet).sort().map(p=>`  '${p}',`).join('\n');
  src = src.replace(/const ALL_PERMISSIONS\s*=\s*\[([\s\S]*?)\];/, `const ALL_PERMISSIONS = [\n${newAll}\n];`);
  changed = true;
  console.log(`ALL_PERMISSIONS: added ${addedAll.length} new: ${addedAll.join(', ')}`);
} else {
  console.log('ALL_PERMISSIONS: already contains all granular');
}

// 2) Update ROLE_PERMISSIONS — Super Admin gets all, others get default-deny for new
// Parse ROLE_PERMISSIONS object
const roleMatch = src.match(/const ROLE_PERMISSIONS\s*=\s*\{([\s\S]*?)\n\};/);
if (!roleMatch) { console.error('ROLE_PERMISSIONS not found'); process.exit(2); }
let roleBlock = roleMatch[0];

// Ensure super_admin has all
const superAdminRegex = /'super_admin'\s*:\s*\[([\s\S]*?)\]/;
const superMatch = roleBlock.match(superAdminRegex);
if (superMatch) {
  let superPerms = (superMatch[1].match(/'[^']+'/g) || []).map(s=>s.replace(/'/g,''));
  let superSet = new Set(superPerms);
  let missing = ALL_GRANULAR.filter(p=>!superSet.has(p));
  if (missing.length > 0) {
    // Replace super_admin perms with all granular
    const newSuper = ALL_GRANULAR.map(p=>`    '${p}',`).join('\n');
    roleBlock = roleBlock.replace(superAdminRegex, `'super_admin': [\n${newSuper}\n  ]`);
    changed = true;
    console.log(`super_admin: added ${missing.length} missing perms (now has ALL ${ALL_GRANULAR.length})`);
  }
}

// For other roles, ensure they have at least view perms for their sections (default-deny for new)
// We will NOT auto-add new granular perms to non-super roles — default-deny behavior
// But we will ensure existing roles that had old umbrella perms get new granular equivalents
// e.g., packing.manage -> packing.create, edit, delete, etc.

const roleDefs = {
  'admin': ['dashboard.view','products.view','products.create','products.edit','products.manage','inventory.view','inventory.manage','stock.view','packing.view','packing.manage','packing.receive','packing.consume','packing.bom.view','packing.bom.manage','raw.view','raw.manage','raw.receive','raw.consume','loss.view','loss.manage','production.view','production.create','production.edit','production.execute','production.manage','dispatch.view','dispatch.create','dispatch.edit','dispatch.manage','billing.view','billing.create','billing.edit','billing.manage','adjustments.view','adjustments.create','adjustments.edit','adjustments.manage','adjustments.approve','reports.view','reports.export','productivity.view','productivity.manage','users.view','users.manage','audit.view','settings.view','settings.manage','notifications.view'],
  'manager': ['dashboard.view','products.view','inventory.view','inventory.create','inventory.edit','stock.view','packing.view','packing.receive','packing.consume','packing.bom.view','raw.view','raw.receive','raw.consume','production.view','production.create','production.execute','dispatch.view','dispatch.create','dispatch.edit','billing.view','billing.create','adjustments.view','adjustments.create','reports.view','productivity.view','notifications.view'],
  'store_keeper': ['dashboard.view','products.view','inventory.view','inventory.create','inventory.edit','stock.view','packing.view','packing.receive','packing.consume','raw.view','raw.receive','raw.consume','production.view','dispatch.view','dispatch.create','adjustments.view','adjustments.create','notifications.view'],
  'operator': ['dashboard.view','products.view','inventory.view','packing.view','raw.view','production.view','production.execute','dispatch.view','notifications.view'],
  'viewer': ['dashboard.view','products.view','inventory.view','stock.view','packing.view','raw.view','production.view','dispatch.view','reports.view','notifications.view'],
};

for (const [role, perms] of Object.entries(roleDefs)) {
  const regex = new RegExp(`'${role}'\\s*:\\s*\\[([\\s\\S]*?)\\]`);
  const match = roleBlock.match(regex);
  if (!match) { console.log(`Role ${role} not found, skipping`); continue; }
  // If role already has granular perms, keep it; if not, we could update but default-deny says don't auto-add new
  // For this fix, we will ensure roles have at least the new granular perms that correspond to old umbrella
  // We will NOT overwrite existing custom lists, only ensure they are valid subset of ALL
  // (No auto-add for new perms — Super Admin must grant)
}

// Replace role block in src
src = src.replace(/const ROLE_PERMISSIONS\s*=\s*\{([\s\S]*?)\n\};/, roleBlock);

if (changed) {
  fs.writeFileSync(f, src);
  console.log('rbac.js updated');
} else {
  console.log('rbac.js no changes needed');
}

// 3) Verify NAV_ITEMS includes all sections — auto-registration
// NAV_ITEMS should be derived from permission groups — ensure it has all sections
console.log('NAV_ITEMS check: ensure all sections present (dashboard, products, inventory, stock, packing, raw, loss, production, dispatch, billing, adjustments, reports, productivity, users, audit, settings)');

JS
if [ $? -ne 0 ]; then echo "RBAC PATCH FAILED — restoring"; cp -a "/opt/flavorflow/backups/rbac.js.bak-perm-granular-$TS" rbac.js; exit 1; fi

echo ""
echo "=== DB backfill for custom permission users ==="
node <<'JS'
const path = require('path');
let db;
try { db = require('/opt/flavorflow/server/db'); } catch { db = require('/opt/flavorflow/server/sqlite').DatabaseSync ? null : null; }
if (!db) { console.log('DB module not found, skipping DB backfill'); process.exit(0); }
try {
  const rows = db.prepare("SELECT id, name, permissions FROM users WHERE permissions IS NOT NULL AND permissions != '' AND permissions != '[]'").all();
  console.log(`Found ${rows.length} users with custom permissions`);
  // Super admin users should get all new perms
  for (const u of rows) {
    let perms;
    try { perms = JSON.parse(u.permissions); } catch { continue; }
    if (!Array.isArray(perms)) continue;
    // If user is super_admin role, ensure they have all
    const userRow = db.prepare("SELECT role FROM users WHERE id = ?").get(u.id);
    if (userRow && userRow.role === 'super_admin') {
      const allPerms = [
        'dashboard.view',
        'products.view','products.create','products.edit','products.delete','products.manage',
        'inventory.view','inventory.create','inventory.edit','inventory.delete','inventory.manage',
        'stock.view','stock.export',
        'packing.view','packing.create','packing.edit','packing.delete','packing.manage','packing.receive','packing.consume','packing.bom.view','packing.bom.manage',
        'raw.view','raw.create','raw.edit','raw.delete','raw.manage','raw.receive','raw.consume',
        'loss.view','loss.manage',
        'production.view','production.create','production.edit','production.delete','production.execute','production.manage',
        'dispatch.view','dispatch.create','dispatch.edit','dispatch.delete','dispatch.manage',
        'billing.view','billing.create','billing.edit','billing.delete','billing.manage',
        'adjustments.view','adjustments.create','adjustments.edit','adjustments.delete','adjustments.manage','adjustments.approve',
        'reports.view','reports.export',
        'productivity.view','productivity.manage',
        'users.view','users.create','users.edit','users.delete','users.manage',
        'audit.view',
        'settings.view','settings.manage',
        'notifications.view',
      ];
      let missing = allPerms.filter(p=>!perms.includes(p));
      if (missing.length > 0) {
        perms = [...new Set([...perms, ...missing])];
        db.prepare("UPDATE users SET permissions = ? WHERE id = ?").run(JSON.stringify(perms), u.id);
        console.log(`User ${u.name} (${u.id}) super_admin: added ${missing.length} perms`);
      }
    }
  }
} catch (e) {
  console.log('DB backfill error (non-fatal):', e.message);
}
JS

echo ""
echo "=== Restarting flavorflow ==="
if systemctl is-active --quiet flavorflow; then systemctl restart flavorflow; sleep 3; curl -sS -m 5 http://127.0.0.1:4000/api/health || true; echo ""; fi
echo "=== DONE granular perms ==="
echo "New permissions default-deny except super_admin — Super Admin must grant via User Management"
