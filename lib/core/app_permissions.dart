/// FlavorFlow — Complete Section-Level Permissions Registry
/// MAN-8: Granular permissions for every section + automatic registration
///
/// This file is the SINGLE SOURCE OF TRUTH for all app permissions.
/// When a new section/module or action is added:
///   1. Add it to kPermissionGroups below
///   2. It automatically appears in User Management & Role Permission Matrix
///   3. Super Admin gets it by default (default-deny for others)
///
/// Server must mirror ALL_PERMISSIONS in rbac.js — use tools/ff-permfix-granular.sh

class AppPermission {
  final String key; // e.g., 'products.view'
  final String label; // e.g., 'View Products'
  final String description;
  const AppPermission({required this.key, required this.label, this.description = ''});
}

class AppPermissionGroup {
  final String id; // e.g., 'products'
  final String label; // e.g., 'Product Master'
  final String description;
  final String icon; // material icon name for UI
  final List<AppPermission> permissions;
  const AppPermissionGroup({
    required this.id,
    required this.label,
    this.description = '',
    this.icon = 'widgets',
    required this.permissions,
  });
}

/// All permission groups — ORDER matters for UI display
/// When you add a new module, add a new group here — it auto-registers everywhere
const List<AppPermissionGroup> kPermissionGroups = [
  AppPermissionGroup(
    id: 'dashboard',
    label: 'Dashboard',
    description: 'Overview and quick actions',
    icon: 'dashboard',
    permissions: [
      AppPermission(key: 'dashboard.view', label: 'View Dashboard', description: 'Access dashboard and overview metrics'),
    ],
  ),
  AppPermissionGroup(
    id: 'products',
    label: 'Product Master',
    description: 'Finished goods / SKUs and their specs',
    icon: 'inventory_2',
    permissions: [
      AppPermission(key: 'products.view', label: 'View Products', description: 'View product master list and details'),
      AppPermission(key: 'products.create', label: 'Create Product', description: 'Add new products/SKUs'),
      AppPermission(key: 'products.edit', label: 'Edit Product', description: 'Edit product specs, packing, rates'),
      AppPermission(key: 'products.delete', label: 'Delete Product', description: 'Delete products from master'),
      AppPermission(key: 'products.manage', label: 'Manage Products', description: 'Full product management including import, labels, BOM linking'),
    ],
  ),
  AppPermissionGroup(
    id: 'inventory',
    label: 'Inventory',
    description: 'Finished goods stock and movements',
    icon: 'warehouse',
    permissions: [
      AppPermission(key: 'inventory.view', label: 'View Inventory', description: 'View finished goods inventory'),
      AppPermission(key: 'inventory.create', label: 'Receive Stock', description: 'Receive / inward finished goods'),
      AppPermission(key: 'inventory.edit', label: 'Edit Inventory', description: 'Adjust inventory quantities'),
      AppPermission(key: 'inventory.delete', label: 'Delete Inventory Entry', description: 'Delete inventory transactions'),
      AppPermission(key: 'inventory.manage', label: 'Manage Inventory', description: 'Full inventory management'),
    ],
  ),
  AppPermissionGroup(
    id: 'stock',
    label: 'Stock Ledger',
    description: 'SAP-style stock movement register',
    icon: 'history',
    permissions: [
      AppPermission(key: 'stock.view', label: 'View Stock Ledger', description: 'View stock ledger and movements'),
      AppPermission(key: 'stock.export', label: 'Export Stock Ledger', description: 'Export stock ledger reports'),
    ],
  ),
  AppPermissionGroup(
    id: 'packing',
    label: 'Packing Material',
    description: 'Packing materials, BOM, recipes',
    icon: 'widgets',
    permissions: [
      AppPermission(key: 'packing.view', label: 'View Packing Stock', description: 'View packing material stock'),
      AppPermission(key: 'packing.create', label: 'Create Packing Material', description: 'Add new packing materials'),
      AppPermission(key: 'packing.edit', label: 'Edit Packing Material', description: 'Edit packing material details'),
      AppPermission(key: 'packing.delete', label: 'Delete Packing Material', description: 'Delete packing materials'),
      AppPermission(key: 'packing.manage', label: 'Manage Packing', description: 'Full packing management including BOM, recipes, receive/consume'),
      AppPermission(key: 'packing.receive', label: 'Receive Packing Stock', description: 'Receive packing materials'),
      AppPermission(key: 'packing.consume', label: 'Consume Packing Stock', description: 'Consume packing for production or extra consumption'),
      AppPermission(key: 'packing.bom.view', label: 'View Packing BOM', description: 'View product packing BOM'),
      AppPermission(key: 'packing.bom.manage', label: 'Manage Packing BOM', description: 'Create/edit packing BOM per product'),
    ],
  ),
  AppPermissionGroup(
    id: 'raw',
    label: 'Raw Material',
    description: 'Raw materials stock and consumption',
    icon: 'science',
    permissions: [
      AppPermission(key: 'raw.view', label: 'View Raw Material', description: 'View raw material stock'),
      AppPermission(key: 'raw.create', label: 'Create Raw Material', description: 'Add new raw materials'),
      AppPermission(key: 'raw.edit', label: 'Edit Raw Material', description: 'Edit raw material details'),
      AppPermission(key: 'raw.delete', label: 'Delete Raw Material', description: 'Delete raw materials'),
      AppPermission(key: 'raw.manage', label: 'Manage Raw Material', description: 'Full raw material management'),
      AppPermission(key: 'raw.receive', label: 'Receive Raw Stock', description: 'Receive raw materials'),
      AppPermission(key: 'raw.consume', label: 'Consume Raw Stock', description: 'Consume raw materials for production'),
    ],
  ),
  AppPermissionGroup(
    id: 'loss',
    label: 'Packing Loss %',
    description: 'Monthly packing loss analysis',
    icon: 'percent',
    permissions: [
      AppPermission(key: 'loss.view', label: 'View Loss %', description: 'View packing loss % sheet'),
      AppPermission(key: 'loss.manage', label: 'Manage Loss %', description: 'Edit loss % sheet, close periods'),
    ],
  ),
  AppPermissionGroup(
    id: 'production',
    label: 'Production',
    description: 'Batches, planning, execution',
    icon: 'manufacturing',
    permissions: [
      AppPermission(key: 'production.view', label: 'View Production', description: 'View production batches and planning'),
      AppPermission(key: 'production.create', label: 'Create Batch', description: 'Create new production batches'),
      AppPermission(key: 'production.edit', label: 'Edit Batch', description: 'Edit batch details and planning'),
      AppPermission(key: 'production.delete', label: 'Delete Batch', description: 'Delete production batches'),
      AppPermission(key: 'production.execute', label: 'Execute Production', description: 'Start, complete, or void production batches'),
      AppPermission(key: 'production.manage', label: 'Manage Production', description: 'Full production management'),
    ],
  ),
  AppPermissionGroup(
    id: 'dispatch',
    label: 'Dispatch',
    description: 'Outward dispatches and trucks',
    icon: 'local_shipping',
    permissions: [
      AppPermission(key: 'dispatch.view', label: 'View Dispatch', description: 'View dispatches and history'),
      AppPermission(key: 'dispatch.create', label: 'Create Dispatch', description: 'Create new dispatches'),
      AppPermission(key: 'dispatch.edit', label: 'Edit Dispatch', description: 'Edit dispatch details'),
      AppPermission(key: 'dispatch.delete', label: 'Delete/Void Dispatch', description: 'Void or delete dispatches'),
      AppPermission(key: 'dispatch.manage', label: 'Manage Dispatch', description: 'Full dispatch management including trucks'),
    ],
  ),
  AppPermissionGroup(
    id: 'billing',
    label: 'Billing',
    description: 'GST invoices and supplier bills',
    icon: 'receipt_long',
    permissions: [
      AppPermission(key: 'billing.view', label: 'View Billing', description: 'View invoices and bills'),
      AppPermission(key: 'billing.create', label: 'Create Invoice/Bill', description: 'Create sales invoices and purchase bills'),
      AppPermission(key: 'billing.edit', label: 'Edit Billing', description: 'Edit invoices and bills'),
      AppPermission(key: 'billing.delete', label: 'Delete/Void Billing', description: 'Void or delete invoices/bills'),
      AppPermission(key: 'billing.manage', label: 'Manage Billing', description: 'Full billing management'),
    ],
  ),
  AppPermissionGroup(
    id: 'adjustments',
    label: 'Stock Adjustments',
    description: 'Inventory adjustments and corrections',
    icon: 'tune',
    permissions: [
      AppPermission(key: 'adjustments.view', label: 'View Adjustments', description: 'View stock adjustments'),
      AppPermission(key: 'adjustments.create', label: 'Create Adjustment', description: 'Create new stock adjustments'),
      AppPermission(key: 'adjustments.edit', label: 'Edit Adjustment', description: 'Edit adjustments'),
      AppPermission(key: 'adjustments.delete', label: 'Delete Adjustment', description: 'Delete adjustments'),
      AppPermission(key: 'adjustments.manage', label: 'Manage Adjustments', description: 'Full adjustments management'),
      AppPermission(key: 'adjustments.approve', label: 'Approve Adjustments', description: 'Approve or reject stock adjustments'),
    ],
  ),
  AppPermissionGroup(
    id: 'reports',
    label: 'Reports',
    description: 'Analytics and exports',
    icon: 'bar_chart',
    permissions: [
      AppPermission(key: 'reports.view', label: 'View Reports', description: 'View all reports and analytics'),
      AppPermission(key: 'reports.export', label: 'Export Reports', description: 'Export reports to Excel/PDF'),
    ],
  ),
  AppPermissionGroup(
    id: 'productivity',
    label: 'Productivity & Labour',
    description: 'Labour tracking and productivity',
    icon: 'analytics',
    permissions: [
      AppPermission(key: 'productivity.view', label: 'View Productivity', description: 'View productivity and labour reports'),
      AppPermission(key: 'productivity.manage', label: 'Manage Productivity', description: 'Manage labour entries and productivity settings'),
    ],
  ),
  AppPermissionGroup(
    id: 'users',
    label: 'User Management',
    description: 'Users, roles, permissions',
    icon: 'group',
    permissions: [
      AppPermission(key: 'users.view', label: 'View Users', description: 'View users and roles'),
      AppPermission(key: 'users.create', label: 'Create User', description: 'Add new users'),
      AppPermission(key: 'users.edit', label: 'Edit User', description: 'Edit users, roles, permissions'),
      AppPermission(key: 'users.delete', label: 'Delete User', description: 'Delete users permanently'),
      AppPermission(key: 'users.manage', label: 'Manage Users', description: 'Full user management including permissions'),
    ],
  ),
  AppPermissionGroup(
    id: 'audit',
    label: 'Audit Log',
    description: 'System audit and activity logs',
    icon: 'history',
    permissions: [
      AppPermission(key: 'audit.view', label: 'View Audit Log', description: 'View audit logs and activity history'),
    ],
  ),
  AppPermissionGroup(
    id: 'settings',
    label: 'Settings',
    description: 'Company, system settings',
    icon: 'settings',
    permissions: [
      AppPermission(key: 'settings.view', label: 'View Settings', description: 'View company and system settings'),
      AppPermission(key: 'settings.manage', label: 'Manage Settings', description: 'Edit company details, industry, units, etc.'),
    ],
  ),
  AppPermissionGroup(
    id: 'notifications',
    label: 'Notifications',
    description: 'Alerts and notifications',
    icon: 'notifications',
    permissions: [
      AppPermission(key: 'notifications.view', label: 'View Notifications', description: 'View notifications and alerts'),
    ],
  ),
];

/// Flat list of all permission keys — for validation, auto-registration, Super Admin
List<String> get allPermissionKeys {
  final keys = <String>[];
  for (final g in kPermissionGroups) {
    for (final p in g.permissions) {
      keys.add(p.key);
    }
  }
  return keys;
}

/// All permissions grouped map: groupId -> permissions
Map<String, List<AppPermission>> get permissionsByGroup {
  final map = <String, List<AppPermission>>{};
  for (final g in kPermissionGroups) {
    map[g.id] = g.permissions;
  }
  return map;
}

/// Find group for a permission key
AppPermissionGroup? groupForPermission(String key) {
  for (final g in kPermissionGroups) {
    if (g.permissions.any((p) => p.key == key)) return g;
  }
  return null;
}

/// Default permissions for roles — Super Admin gets ALL, others get minimal
/// New permissions default to DENY except for Super Admin (default-deny behavior)
Map<String, List<String>> get defaultRolePermissions {
  final all = allPermissionKeys;
  return {
    // Super Admin — ALL permissions
    'super_admin': all,
    'admin': [
      'dashboard.view',
      'products.view', 'products.create', 'products.edit', 'products.manage',
      'inventory.view', 'inventory.manage',
      'stock.view',
      'packing.view', 'packing.manage', 'packing.receive', 'packing.consume', 'packing.bom.view', 'packing.bom.manage',
      'raw.view', 'raw.manage', 'raw.receive', 'raw.consume',
      'loss.view', 'loss.manage',
      'production.view', 'production.create', 'production.edit', 'production.execute', 'production.manage',
      'dispatch.view', 'dispatch.create', 'dispatch.edit', 'dispatch.manage',
      'billing.view', 'billing.create', 'billing.edit', 'billing.manage',
      'adjustments.view', 'adjustments.create', 'adjustments.edit', 'adjustments.manage', 'adjustments.approve',
      'reports.view', 'reports.export',
      'productivity.view', 'productivity.manage',
      'users.view', 'users.manage',
      'audit.view',
      'settings.view', 'settings.manage',
      'notifications.view',
    ],
    'manager': [
      'dashboard.view',
      'products.view',
      'inventory.view', 'inventory.create', 'inventory.edit',
      'stock.view',
      'packing.view', 'packing.receive', 'packing.consume', 'packing.bom.view',
      'raw.view', 'raw.receive', 'raw.consume',
      'production.view', 'production.create', 'production.execute',
      'dispatch.view', 'dispatch.create', 'dispatch.edit',
      'billing.view', 'billing.create',
      'adjustments.view', 'adjustments.create',
      'reports.view',
      'productivity.view',
      'notifications.view',
    ],
    'store_keeper': [
      'dashboard.view',
      'products.view',
      'inventory.view', 'inventory.create', 'inventory.edit',
      'stock.view',
      'packing.view', 'packing.receive', 'packing.consume',
      'raw.view', 'raw.receive', 'raw.consume',
      'production.view',
      'dispatch.view', 'dispatch.create',
      'adjustments.view', 'adjustments.create',
      'notifications.view',
    ],
    'operator': [
      'dashboard.view',
      'products.view',
      'inventory.view',
      'packing.view',
      'raw.view',
      'production.view', 'production.execute',
      'dispatch.view',
      'notifications.view',
    ],
    'viewer': [
      'dashboard.view',
      'products.view',
      'inventory.view',
      'stock.view',
      'packing.view',
      'raw.view',
      'production.view',
      'dispatch.view',
      'reports.view',
      'notifications.view',
    ],
  };
}

/// Check if a permission is newly introduced (not in any role defaults except super_admin)
/// Used for default-deny behavior — new perms are DENY until Super Admin grants
bool isNewPermission(String key) {
  final defaults = defaultRolePermissions;
  for (final entry in defaults.entries) {
    if (entry.key == 'super_admin') continue;
    if (entry.value.contains(key)) return false;
  }
  // If no non-super role has it, it's new
  return true;
}

/// Super Admin always has all permissions, including new ones
bool isSuperAdminPermission(String role, String key) {
  if (role == 'super_admin') return true;
  return allPermissionKeys.contains(key) && defaultRolePermissions[role]?.contains(key) == true;
}
