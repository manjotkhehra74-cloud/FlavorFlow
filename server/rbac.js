/**
 * rbac.js — Single source of truth for roles, permissions and navigation.
 * The backend enforces these permissions on EVERY API request (see middleware.js).
 * The Flutter client also consumes this map via /api/meta/bootstrap to build menus,
 * but client-side checks are cosmetic — authorization only happens server-side.
 */

const ROLES = {
  super_admin:          { label: 'Super Admin',            color: '#7C3AED' },
  admin:                { label: 'Admin',                  color: '#2563EB' },
  production_manager:   { label: 'Production Manager',     color: '#0891B2' },
  production_supervisor:{ label: 'Production Supervisor',  color: '#0D9488' },
  store_manager:        { label: 'Store Manager',          color: '#D97706' },
  store_keeper:         { label: 'Store Keeper',           color: '#65A30D' },
  dispatch_manager:     { label: 'Dispatch Manager',       color: '#EA580C' },
  management_director:  { label: 'Management / Director',  color: '#475569' },
};

/** Full permission catalog (for '*' expansion and documentation). */
const ALL_PERMISSIONS = [
  'adjustments.approve',
  'adjustments.create',
  'adjustments.delete',
  'adjustments.edit',
  'adjustments.manage',
  'adjustments.view',
  'audit.view',
  'billing.create',
  'billing.delete',
  'billing.edit',
  'billing.manage',
  'billing.view',
  'dashboard.view',
  'dispatch.create',
  'dispatch.delete',
  'dispatch.edit',
  'dispatch.manage',
  'dispatch.view',
  'inventory.create',
  'inventory.delete',
  'inventory.edit',
  'inventory.manage',
  'inventory.view',
  'loss.manage',
  'loss.view',
  'notifications.view',
  'packing.bom.manage',
  'packing.bom.view',
  'packing.consume',
  'packing.create',
  'packing.delete',
  'packing.edit',
  'packing.manage',
  'packing.receive',
  'packing.view',
  'production.create',
  'production.delete',
  'production.edit',
  'production.execute',
  'production.manage',
  'production.view',
  'productivity.manage',
  'productivity.view',
  'products.create',
  'products.delete',
  'products.edit',
  'products.manage',
  'products.view',
  'raw.consume',
  'raw.create',
  'raw.delete',
  'raw.edit',
  'raw.manage',
  'raw.receive',
  'raw.view',
  'reports.export',
  'reports.view',
  'settings.manage',
  'settings.view',
  'stock.export',
  'stock.view',
  'users.create',
  'users.delete',
  'users.edit',
  'users.manage',
  'users.view',
];

/**
 * Role → permission map. Everything is denied unless listed here.
 * management_director is intentionally READ-ONLY (view permissions only).
 */
const ROLE_PERMISSIONS = {
  super_admin: ['*'],

  admin: [
    'dashboard.view',
    'products.view', 'products.manage',
    'inventory.view', 'inventory.manage',
    'packing.view', 'packing.manage', 'raw.view', 'raw.manage', 'loss.view', 'loss.manage',
    'adjustments.view', 'adjustments.create', 'adjustments.approve',
    'production.view', 'production.manage', 'production.execute',
      'dispatch.view', 'dispatch.manage', 'billing.view', 'billing.manage',
    'reports.view',
    'users.view', 'users.manage',
    'audit.view',
  ],

  production_manager: [
    'dashboard.view',
    'products.view',
    'inventory.view',
    'packing.view', 'raw.view', 'loss.view',
    'production.view', 'production.manage', 'production.execute',
    'reports.view',
  ],

  production_supervisor: [
    'dashboard.view',
    'products.view',
    'inventory.view',
    'packing.view', 'raw.view', 'loss.view',
    'production.view', 'production.execute',
    'reports.view',
  ],

  store_manager: [
    'dashboard.view',
    'products.view', 'products.manage',
    'inventory.view', 'inventory.manage',
    'packing.view', 'packing.manage', 'raw.view', 'raw.manage', 'loss.view', 'loss.manage',
    'adjustments.view', 'adjustments.create', 'adjustments.approve',
    'dispatch.view', 'billing.view',
    'reports.view',
  ],

  store_keeper: [
    'dashboard.view',
    'products.view',
    'inventory.view',
    'packing.view', 'packing.manage', 'raw.view', 'raw.manage', 'loss.view', 'loss.manage',
    'adjustments.view', 'adjustments.create',
    'dispatch.view', 'billing.view',
    'reports.view',
  ],

  dispatch_manager: [
    'dashboard.view',
    'products.view',
    'inventory.view',
    'packing.view', 'raw.view', 'loss.view',
    'production.view',
    'dispatch.view', 'dispatch.manage', 'billing.view', 'billing.manage',
    'reports.view',
  ],

  management_director: [
    // READ ONLY — deliberately no create/manage/approve/execute rights.
    'dashboard.view',
    'products.view',
    'inventory.view',
    'packing.view', 'raw.view', 'loss.view',
    'adjustments.view',
    'production.view',
    'dispatch.view', 'billing.view',
    'reports.view',
    'audit.view',
  ],
};

/** Navigation menu entries shown per permission (sent to the client, grouped for the sidebar). */
const NAV_ITEMS = [
  { path: '/dashboard',   label: 'Dashboard',          icon: 'dashboard',      perm: 'dashboard.view',      group: 'Overview' },
  { path: '/products',    label: 'Product Master',     icon: 'inventory_2',    perm: 'products.view',       group: 'Operations' },
  { path: '/inventory',   label: 'Inventory',          icon: 'warehouse',      perm: 'inventory.view',      group: 'Operations' },
  { path: '/drums',       label: 'Drum Stock',         icon: 'inventory_2',    perm: 'inventory.view',      group: 'Operations' },
  { path: '/packing',     label: 'Packing Material',   icon: 'widgets',        perm: 'packing.view',        group: 'Operations' },
  { path: '/raw',         label: 'Raw Material',       icon: 'science',        perm: 'raw.view',            group: 'Operations' },
  { path: '/loss',        label: 'Packing Loss %',     icon: 'percent',        perm: 'loss.view',           group: 'Operations' },
  { path: '/production',  label: 'Production',         icon: 'manufacturing',  perm: 'production.view',     group: 'Operations' },
  { path: '/dispatch',    label: 'Dispatch',           icon: 'local_shipping', perm: 'dispatch.view',       group: 'Operations' },
  { path: '/billing',     label: 'Billing',            icon: 'receipt_long',   perm: 'billing.view',        group: 'Operations' },
  { path: '/adjustments', label: 'Stock Adjustments',  icon: 'tune',           perm: 'adjustments.view',    group: 'Stock Control' },
  { path: '/approvals',   label: 'Approvals',          icon: 'fact_check',     perm: 'adjustments.approve', group: 'Stock Control' },
  { path: '/reports',     label: 'Reports',            icon: 'bar_chart',      perm: 'reports.view',        group: 'Insights' },
  { path: '/users',       label: 'User Management',    icon: 'group',          perm: 'users.view',          group: 'Administration' },
  { path: '/audit',       label: 'Audit Log',          icon: 'history',        perm: 'audit.view',          group: 'Administration' },
  { path: '/stock', label: 'Stock Ledger', icon: 'history', perm: 'stock.view', group: 'Operations' },
  { path: '/productivity', label: 'Productivity & Labour', icon: 'analytics', perm: 'productivity.view', group: 'Insights' },
  { path: '/settings', label: 'Settings', icon: 'settings', perm: 'settings.view', group: 'Administration' },
  { path: '/notifications', label: 'Notifications', icon: 'notifications', perm: 'notifications.view', group: 'System' },
];

function permissionsForRole(role) {
  const perms = ROLE_PERMISSIONS[role];
  if (!perms) return [];
  return perms.includes('*') ? ALL_PERMISSIONS.slice() : perms.slice();
}

function hasPermission(role, perm) {
  const perms = ROLE_PERMISSIONS[role];
  if (!perms) return false;
  return perms.includes('*') || perms.includes(perm);
}

function navForRole(role) {
  return NAV_ITEMS.filter((item) => hasPermission(role, item.perm));
}

module.exports = { ROLES, ALL_PERMISSIONS, ROLE_PERMISSIONS, NAV_ITEMS, permissionsForRole, hasPermission, navForRole };
