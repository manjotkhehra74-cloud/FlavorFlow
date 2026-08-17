import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/adjustments/adjustments_page.dart';
import 'features/adjustments/approvals_page.dart';
import 'features/audit/audit_page.dart';
import 'features/auth/login_page.dart';
import 'features/auth/setup_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/dispatch/dispatch_detail_page.dart';
import 'features/dispatch/dispatch_page.dart';
import 'features/inventory/inventory_page.dart';
import 'features/notifications/notifications_page.dart';
import 'features/packing/loss_page.dart';
import 'features/packing/packing_page.dart';
import 'features/production/production_detail_page.dart';
import 'features/production/production_page.dart';
import 'features/products/products_page.dart';
import 'features/reports/reports_page.dart';
import 'features/settings/settings_page.dart';
import 'features/users/users_page.dart';
import 'state/auth.dart';
import 'ui/app_shell.dart';

/// Route → required permission. Mirrors (but never replaces) backend checks.
String? permForPath(String path) {
  if (path.startsWith('/products')) return 'products.view';
  if (path.startsWith('/inventory')) return 'inventory.view';
  if (path.startsWith('/packing')) return 'packing.view';
  if (path.startsWith('/raw')) return 'packing.view';
  if (path.startsWith('/loss')) return 'packing.view';
  if (path.startsWith('/adjustments')) return 'adjustments.view';
  if (path.startsWith('/approvals')) return 'adjustments.approve';
  if (path.startsWith('/production')) return 'production.view';
  if (path.startsWith('/dispatch')) return 'dispatch.view';
  if (path.startsWith('/reports')) return 'reports.view';
  if (path.startsWith('/users')) return 'users.view';
  if (path.startsWith('/audit')) return 'audit.view';
  return null; // dashboard & notifications are universal
}

/// Set by main() before the router is built: fresh install → one-time
/// language + industry setup screen comes before login.
bool kNeedsFirstRunSetup = false;

GoRouter buildRouter(AuthController auth) {
  return GoRouter(
    initialLocation: kNeedsFirstRunSetup ? '/setup' : '/dashboard',
    refreshListenable: auth,
    redirect: (context, state) {
      final atSetup = state.matchedLocation == '/setup';
      if (kNeedsFirstRunSetup && !atSetup) return '/setup';
      if (!kNeedsFirstRunSetup && atSetup) return '/login';
      if (atSetup) return null;
      final loggedIn = auth.isLoggedIn;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn) return atLogin ? null : '/login';
      if (atLogin) return '/dashboard';
      final perm = permForPath(state.matchedLocation);
      if (perm != null && !auth.can(perm)) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (c, s) => const SetupPage()),
      GoRoute(path: '/login', builder: (c, s) => const LoginPage()),
      ShellRoute(
        builder: (c, s, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (c, s) => const DashboardPage()),
          GoRoute(path: '/products', builder: (c, s) => const ProductsPage()),
          GoRoute(
            path: '/inventory',
            builder: (c, s) => InventoryPage(lowOnly: s.uri.queryParameters['filter'] == 'low'),
          ),
          GoRoute(
            path: '/packing',
            builder: (c, s) => PackingPage(lowOnly: s.uri.queryParameters['filter'] == 'low'),
          ),
          GoRoute(path: '/raw', builder: (c, s) => const RawMaterialPage()),
          GoRoute(path: '/loss', builder: (c, s) => const LossPage()),
          GoRoute(path: '/adjustments', builder: (c, s) => const AdjustmentsPage()),
          GoRoute(
            path: '/approvals',
            builder: (c, s) => ApprovalsPage(focusId: s.uri.queryParameters['focus']),
          ),
          GoRoute(
            path: '/production',
            builder: (c, s) => const ProductionPage(),
            routes: [
              GoRoute(
                path: 'batches/:id',
                builder: (c, s) => ProductionDetailPage(id: int.tryParse(s.pathParameters['id'] ?? '') ?? 0),
              ),
            ],
          ),
          GoRoute(
            path: '/dispatch',
            builder: (c, s) => DispatchPage(tab: s.uri.queryParameters['tab']),
            routes: [
              GoRoute(
                path: ':id',
                builder: (c, s) => DispatchDetailPage(id: int.tryParse(s.pathParameters['id'] ?? '') ?? 0),
              ),
            ],
          ),
          GoRoute(path: '/reports', builder: (c, s) => const ReportsPage()),
          GoRoute(path: '/users', builder: (c, s) => const UsersPage()),
          GoRoute(path: '/audit', builder: (c, s) => const AuditPage()),
          GoRoute(path: '/notifications', builder: (c, s) => const NotificationsPage()),
          GoRoute(path: '/settings', builder: (c, s) => const SettingsPage()),
        ],
      ),
    ],
    errorBuilder: (c, s) => Scaffold(body: Center(child: Text('Page not found: ${s.uri.path}'))),
  );
}
