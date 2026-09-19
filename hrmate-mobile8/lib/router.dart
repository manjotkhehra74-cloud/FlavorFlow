import 'package:go_router/go_router.dart';

import 'features/auth/login_page.dart';
import 'features/home/home_page.dart';
import 'features/leaves/leaves_page.dart';
import 'features/more/more_page.dart';
import 'features/punch/punch_page.dart';
import 'features/team/team_page.dart';
import 'state/auth.dart';
import 'ui/app_shell.dart';

/// Built ONCE in main.dart (ARCHITECTURE.md §2). Auth redirects: not signed
/// in → /login, signed in on /login → /home. New screens = new GoRoute
/// inside the shell — the shell itself is never rewritten.
GoRouter buildRouter(AuthController auth) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: auth,
    redirect: (context, state) {
      final atLogin = state.matchedLocation == '/login';
      if (!auth.isLoggedIn) return atLogin ? null : '/login';
      if (atLogin) return '/home';
      if (state.matchedLocation.startsWith('/team') && !(auth.user?.isManager ?? false)) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginPage()),
      ShellRoute(
        builder: (c, s, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', pageBuilder: (c, s) => const NoTransitionPage(child: HomePage())),
          GoRoute(path: '/leaves', pageBuilder: (c, s) => const NoTransitionPage(child: LeavesPage())),
          GoRoute(path: '/punch', pageBuilder: (c, s) => const NoTransitionPage(child: PunchPage())),
          GoRoute(path: '/team', pageBuilder: (c, s) => const NoTransitionPage(child: TeamPage())),
          GoRoute(path: '/more', pageBuilder: (c, s) => const NoTransitionPage(child: MorePage())),
        ],
      ),
    ],
  );
}
