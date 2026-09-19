# HRMate Mobile — Architecture (Phase 8, series 4.x)

**This file is the constitution. Every phase obeys it. No phase rewrites
what an earlier phase delivered — it REPLACES a file or ADDS a file inside
the fixed structure below.**

## 1. Mission

A premium, native (Flutter, **no WebView**) Android app for the HRMate
Workforce Portal at `gdfoods.duckdns.org` (moved off hr.flavorflow.co.in on 09-19). The live webapp is the source of
truth for WHAT the app looks like and does; this app must look recognisably
like the same product and behave like it — but with native polish on top.

**The no-dummies rule:** every section and every option visible in the UI
works. A control that does not work yet does not exist yet — the screen
shows an honest "Coming in Phase N" instead of a fake, dead, or decorative
UI. Fake data is never rendered, anywhere, in any phase.

## 2. Fixed stack (do not add packages without a phase note)

| Concern     | Choice                                             |
| ----------- | -------------------------------------------------- |
| State       | `provider` (ChangeNotifier)                        |
| Navigation  | `go_router` — router built ONCE in `main.dart`     |
| Network     | `http` via `core/api.dart` (ONE `ApiClient`)       |
| Persistence | `shared_preferences` (cache, lang) · `flutter_secure_storage` (token+user) |
| Text        | `intl` via `core/format.dart`                      |
| UI          | Material 3 + the tokens in `core/theme.dart`       |
| Version     | `package_info_plus`                                |

`local_auth` is in the base stack (biometric session unlock, `core/secure.dart`).
Phase 3 (punch) adds: `geolocator`, `permission_handler`.
Phase 5 (push) adds: `firebase_core`, `firebase_messaging`,
`flutter_local_notifications`. Anything else = write a note here first.

## 3. Fixed structure

```
lib/
  main.dart              # providers + MaterialApp.router + splash (never grows big)
  router.dart            # ALL routes. New screen = one new GoRoute.
  core/                  # api · cache · theme · i18n · format · secure
  state/auth.dart        # AuthController (session, user, 401 handling)
  ui/
    app_shell.dart       # header + bottom nav (the webapp chrome)
    widgets.dart         # shared components — screens COMPOSE these
  features/
    auth/login_page.dart
    home/home_page.dart  home_models.dart
    leaves/  punch/  team/  more/
test/render_test.dart    # the CI gate (§8)
```

`features/<name>/` files are the ONLY files a phase may replace. `core/`,
`state/`, `ui/` change only when a phase note in this file says so.

## 4. Phase map (one phase = one reviewable build)

| Phase | Ships                                            | Replaces / adds                                  |
| ----- | ------------------------------------------------ | ------------------------------------------------ |
| 8.0   | foundation: login (real), shell, home (real), offline+refresh, i18n, render gate, codemagic | this tree |
| 8.1   | webapp-UI pass: login + home pixel-matched to screenshots | `login_page.dart`, `home_page.dart`, `theme.dart` tokens |
| 2     | Leaves: balance, types, apply, history, approve (managers) | `leaves/` (2–3 files) |
| 3     | Punch: live clock ring, in/out (GPS where configured), history | `punch/` + `home` navy card deep-link |
| 4     | Team: today board, members, member day (managers) | `team/` |
| 5     | More: profile, ID card, holidays, payslips, settings, language, notifications, push | `more/` + state additions |
| 6     | Polish: onboarding-free polish, haptics, dark (if webapp gets one), publish | anywhere, additive |

## 5. Design system — one source of truth

All colours, radii, shadows, motion durations live in `core/theme.dart`
(`HrBrand`). Screens reference tokens, never raw values. The shared
components in `ui/widgets.dart` (`HrCard`, `HrGradientButton`, `QuickTile`,
`KpiTile`, `PhaseScreen`, `Avatar`, `OfflineChip`, …) are the only way a
screen gets cards/buttons/tiles. If a screen needs something new, it goes
into `widgets.dart` first, then the screen uses it.

Motion: `HrBrand.fast` (140 ms) for press feedback, `HrBrand.base` (220 ms)
for state changes, `HrBrand.slow` (320 ms) for layout changes.

## 6. Data rules — the server is the authority

- Every fact on screen comes from `GET /api/v1/mobile/*` (see P6 endpoint
  list). The app never invents or persists business data.
- Reads go through `cachedFetch`: network first, on failure the last good
  value with an "Offline · last updated hh:mm" chip. No cache at all →
  `ErrorRetryView` with a working Retry.
- Writes (punch, apply leave, approve) are fire-and-forget with a server
  response toast; failures show the server's message. Nothing is queued
  offline. Punches are NEVER queued — a punch is a moment.
- 401 anywhere → session dropped → router returns to `/login`
  (one place: `AuthController`).
- Roles: the server decides. The app only hides the Team tab for
  non-managers as a courtesy.

## 7. Safety rules (learned the hard way in series 3.x — these are law)

1. **Never** `Padding`/`margin` with negative values → `padding.isNonNegative`
   assertion crash. A raised element = `Stack` + `Positioned(top: -x)`
   with `clipBehavior: Clip.none` (see the centre Punch button in `app_shell.dart`).
2. **Never** `Container(color: …)` together with `Container(decoration: …)`
   → `Decoration detected on the RenderPadding` error. Pick one.
3. `const` only where the whole subtree is const-constructible.
4. Flutter **3.29.0** safe API set only: no `PathMetric`, no
   `Canvas.addPolyline` for arcs (use `drawArc`/`CustomPainter` with
   `Path.arcTo`), no `FontFeature.tabularNumbers()` (use
   `FontFeature('tnum')` — see `kTnum`).
5. Text scale comes from `MediaQuery.textScaler` (clamped 0.9–1.3 in
   `main.dart`) — never from a stored preference value.
6. No `pumpAndSettle` in tests — Home's 1 s clock ticker and repeating
   shimmer mean the tree never settles.
7. One `ApiClient` per `AuthController`; screens read `auth.api` (tests
   inject an offline fake — §8).

## 8. The render gate (non-negotiable)

`test/render_test.dart` pumps the REAL router + shell + every tab with an
offline (throwing) API and asserts the header, nav, and page body actually
exist on screen. **Codemagic blocks the build when `flutter test` fails —
this stays that way.** Every phase adds the tabs/screens it ships to this
test in the SAME commit. A build that passes analysis+tests+build is the
only build the user runs.

## 9. Build & release

- Codemagic, Flutter 3.29.0, Java 17. Flavors: `beta` (auto on push) and
  `prod` (manual, `hrmate_release` group).
- Both workflows: `flutter pub get` → `flutter analyze` → `flutter test`
  → build.
- `--dart-define=HRMATE_API=https://gdfoods.duckdns.org/api/v1/mobile`
  (prod flavor; the code default already points there).
- Version = `pubspec` (series 4.x). Publishing the APK to the website:
  `publish-apk.sh` (v3) after the FINAL Phase 8 build.

## 10. Change log (phase notes live here)

| Date     | Phase | Note                                                        |
| -------- | ----- | ----------------------------------------------------------- |
| 2026-09-19 | 8.0 | Tree created: foundation, real login+home, shell, i18n, render gate. |
