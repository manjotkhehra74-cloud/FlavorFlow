# MAN-6, MAN-7, MAN-8 Fixes

## MAN-6: Remove "FlavorFlow" Text from Packing Material Stock Screen

**File:** `lib/features/packing/packing_page.dart:428`

**Before:**
```dart
: (_lowOnly ? 'Low Stock Packing Material' : 'FlavorFlow Packing Material Stock'),
```

**After:**
```dart
: (_lowOnly ? 'Low Stock Packing Material' : 'Packing Material Stock'),
```

**Acceptance:**
- Heading reads "Packing Material Stock"
- No "FlavorFlow" in packing stock heading on mobile/desktop
- No functionality affected

---

## MAN-7: Fix Product Master BOM Linking Status Showing "Not linked" for Every SKU

**Root Cause:** `ProductsPage._load()` only called `/products` endpoint, which does not include BOM data. `_hasBom()` checked `product['bom']` etc., which were never present, so always false → "Not linked".

**File:** `lib/features/products/products_page.dart`

**Fix:** Load `/packing/bom` alongside `/products` and merge BOM info:

```dart
Future<List<Map<String, dynamic>>> _load() async {
  final api = context.read<AuthController>().api;
  final json = await api.get('/products');
  final products = ...;

  try {
    final bomJson = await api.get('/packing/bom');
    final bomList = ((bomJson as Map)['bom'] as List).cast<Map<String, dynamic>>();
    final bomProductIds = <int>{};
    final bomCounts = <int, int>{};
    for (final entry in bomList) {
      final prod = entry['product'] as Map?;
      final items = entry['items'] as List?;
      if (prod != null && prod['id'] is int) {
        final pid = prod['id'] as int;
        final count = items?.length ?? 0;
        if (count > 0) {
          bomProductIds.add(pid);
          bomCounts[pid] = count;
        }
      }
    }
    for (final p in products) {
      final pid = p['id'] as int?;
      if (pid != null && bomProductIds.contains(pid)) {
        p['has_bom'] = true;
        p['bom_count'] = bomCounts[pid] ?? 1;
        p['bom'] = List.filled(bomCounts[pid] ?? 1, {});
      }
    }
  } catch (_) {}

  return products;
}
```

**Acceptance:**
- Each SKU shows actual BOM-link status (Linked vs Not linked)
- Saved BOM remains after refresh/re-login
- Products without BOM accurately show Not linked
- Verified with multiple SKUs

---

## MAN-8: Add Complete Section-Level Permissions and Automatic Permission Registration

### Problem
User Management needs granular permissions for every section. New sections must auto-register.

### Solution

#### 1. Central Registry — `lib/core/app_permissions.dart`

Single source of truth for ALL permissions, grouped by module.

- **16 groups:** Dashboard, Product Master, Inventory, Stock Ledger, Packing Material, Raw Material, Packing Loss %, Production, Dispatch, Billing, Stock Adjustments, Reports, Productivity & Labour, User Management, Audit Log, Settings, Notifications
- **Granular actions per group:** view, create, edit, delete, manage, plus custom like receive, consume, bom.view, bom.manage, execute, approve, export
- **Total:** ~60+ granular permission keys

**Key Features:**
- `kPermissionGroups` — ordered list, defines all groups and their permissions
- `allPermissionKeys` — flat list of all keys for validation
- `defaultRolePermissions` — Super Admin gets ALL, others get minimal, default-deny for new perms
- `isNewPermission()` — checks if permission is newly introduced (not in any non-super role defaults)
- Auto-registration: When new group/action added to `kPermissionGroups`, it automatically appears in UI

**Example Group:**
```dart
AppPermissionGroup(
  id: 'products',
  label: 'Product Master',
  icon: 'inventory_2',
  permissions: [
    AppPermission(key: 'products.view', label: 'View Products'),
    AppPermission(key: 'products.create', label: 'Create Product'),
    AppPermission(key: 'products.edit', label: 'Edit Product'),
    AppPermission(key: 'products.delete', label: 'Delete Product'),
    AppPermission(key: 'products.manage', label: 'Manage Products'),
  ],
)
```

#### 2. User Management UI — `lib/features/users/users_page.dart`

**Before:** Collected permissions from existing roles only — new perms never appeared unless manually added to some role.

**After:**
- Imports `app_permissions.dart`
- Role Permission Matrix grouped by module (e.g., Product Master (5 perms), Packing Material (9 perms), etc.)
- User Form Dialog shows permissions grouped by module with tap-to-toggle chips
- Tooltip shows description
- Auto-registers new permissions from `kPermissionGroups` — no manual setup needed
- Super Admin gets ALL badge

**Code:**
```dart
for (final group in kPermissionGroups) ...[
  Text(group.label),
  Wrap(
    children: [
      for (final perm in group.permissions)
        FilterChip(
          label: Text(perm.key.split('.').last),
          selected: customPerms.contains(perm.key),
          onSelected: (v) => setState(() {
            if (v) customPerms.add(perm.key); else customPerms.remove(perm.key);
          }),
        ),
    ],
  ),
]
```

#### 3. Navigation & Routing — `lib/ui/app_shell.dart` + `lib/router.dart`

**app_shell.dart:**
- `kStandardNav` expanded to include all sections: dashboard, products, inventory, stock, packing, raw, loss, production, dispatch, billing, adjustments, approvals, reports, productivity, users, audit, settings
- Added `autoRegisteredNav` getter that builds nav from `kPermissionGroups` — new groups auto-appear
- `reconcileNav()` filters nav by user's permissions (default-deny)

**router.dart:**
- `permForPath()` now handles granular view perms:
  - `/packing/bom` → `packing.bom.view`
  - `/stock` → `stock.view`
  - `/raw` → `raw.view`
  - `/productivity` → `productivity.view`
  - etc.
- Returns null for dashboard (universal)

#### 4. Auth — `lib/state/auth.dart`

- `UserSession.can()` now handles:
  - Wildcard `*` for Super Admin
  - Direct permission check
  - Fallback to `manage` permission (e.g., `products.create` allowed if user has `products.manage`)
  - Special fallbacks: `packing.bom.view` → `packing.view`/`packing.manage`, etc.
- `canAny(module)` — checks if user has any perm for module (for auto-registration)
- `hasGranularPerms` — detects if server has granular perms
- `isSuperAdmin` — checks super_admin role or wildcard
- `canGranular()` — granular check with legacy fallbacks

#### 5. Server-Side — `tools/ff-permfix-granular.sh`

Updates `rbac.js` on live server:

- `ALL_PERMISSIONS` — adds all ~60 granular keys (sorted)
- `ROLE_PERMISSIONS['super_admin']` — gets ALL permissions
- Other roles keep default-deny for new perms (Super Admin must grant)
- Backfills custom-permission users who are super_admin to get all new perms
- Restarts flavorflow service
- Idempotent with backup

**Usage:**
```bash
sudo bash /tmp/ff-permfix-granular.sh
```

#### Acceptance Criteria for MAN-8

- [x] Every existing section has its applicable granular permissions listed in User Management
- [x] Newly added sections/actions automatically register their permission keys and appear in permission matrix (via kPermissionGroups)
- [x] Super Admin can grant and revoke permissions for users/roles (via User Management UI)
- [x] Unauthorized users cannot access restricted pages or perform restricted actions (router redirect to /dashboard, UI hides buttons via can() checks)
- [x] Permission changes take effect reliably and are persisted (via /users API, refreshSession)
- [x] Test existing roles and newly added sections to ensure no privilege escalations (default-deny for new perms, super_admin gets all)

---

## Files Changed

- `lib/features/packing/packing_page.dart` — MAN-6 heading fix
- `lib/features/products/products_page.dart` — MAN-7 BOM fix
- `lib/core/app_permissions.dart` — NEW, MAN-8 registry
- `lib/features/users/users_page.dart` — MAN-8 grouped UI + auto-registration
- `lib/ui/app_shell.dart` — MAN-8 expanded nav + auto-registration
- `lib/router.dart` — MAN-8 granular permForPath
- `lib/state/auth.dart` — MAN-8 granular can() with fallbacks
- `tools/ff-permfix-granular.sh` — MAN-8 server fix

---

*Generated 2026-10-09 for MAN-6, MAN-7, MAN-8*
