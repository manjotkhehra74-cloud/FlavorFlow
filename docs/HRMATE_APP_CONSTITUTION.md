# HRMate Mobile App — Architecture Constitution (v1)

**Status: BINDING.** Read this file completely before touching the HRMate mobile app.
It applies to every session, every chat and every agent, until the owner changes this
file. If a task conflicts with this file: **STOP and ask the owner** — never deviate silently.

> Hosted in the FlavorFlow repository (sister product, same owner) so any agent can fetch it.
> Canonical copy inside the HRMate repository: `mobile/ARCHITECTURE.md` (committed verbatim).
>
> **Phase 0 is already written**: the folder `hrmate-mobile/` next to this file (FlavorFlow repo,
> branch `arena/01a0858b-flavorflow`) contains the complete foundation — app code, Android
> project, server route reference, tests, RELEASE.md. Copy it to `mobile/` as-is; do not rebuild it.

---

## 0. Why this file exists

Four earlier attempts to build the HRMate Android app restarted from scratch. Each new
session re-decided the architecture (native ↔ WebView), rewrote screens that already
worked, hit "Not authenticated" because the app tried to reuse the browser session cookie,
or lost work that was never committed. One attempt shipped 1-px text because a font
scale was derived from a stored preference.

This file fixes the decisions **once**. The app grows by small phases, each one committed,
pushed and delivered as an installable APK. Nothing is ever "started over".

---

## 1. Non-negotiable decisions

1. **Native Flutter app. No WebView of any kind.** Not `webview_flutter`, not
   `flutter_inappwebview`, not loading `hr.flavorflow.co.in` inside the app. The only web
   usage allowed is `url_launcher` to open external links (privacy policy, help) in the
   system browser.
2. **Location:** the Flutter project lives at **`mobile/`** in the HRMate repository
   (monorepo, same branch as the webapp). Never create a second Flutter project or another
   folder for the app. The existing WebView shell (v1.0.x) stays where it is, untouched and
   live on `/download`, until Phase 5 replaces it.
3. **Reference for look & feel:** the HRMate webapp as it is today. Screens are re-created
   natively with the design tokens in §4 — recognisably the same product (colours, layout,
   wording, icons), not a pixel-perfect copy.
4. **Backend:** the app talks **only** to the Mobile API (`/api/v1/mobile/*`, §5) with a
   Bearer token. It never depends on the browser session cookie and never scrapes HTML.
5. **Incremental forever.** A phase adds or fixes. It never rewrites the foundation or an
   accepted screen. "Simplify", "clean rewrite", "start fresh", "migrate to X", "switch to
   WebView for now" are forbidden unless the owner writes explicit approval in the same
   session.
6. **Every session ends with committed + pushed work and a release-signed APK** built by
   the same pipeline that produced v1.0.4. If that pipeline was a manual build, Phase 0
   documents the exact commands in `mobile/RELEASE.md` and every later phase reuses them.
   Uncommitted work is considered lost.
7. **The webapp UI is never modified** by mobile-app work. Only new files under the Mobile
   API path (§5) and one shared auth helper may be added on the webapp side.

---

## 2. Repository layout (frozen after Phase 0)

```
mobile/
  ARCHITECTURE.md            ← this file (verbatim)
  RELEASE.md                 ← how the APK is built, signed and published (Phase 0)
  pubspec.yaml               ← name: hrmate · version 2.0.0+20 for the first native build
  lib/
    main.dart                ← MultiProvider + MaterialApp.router, built ONCE; textScaler clamp
    router.dart              ← go_router; auth redirect (login ↔ shell)
    core/
      api.dart               ← ApiClient: base URL, bearer token, JSON, ApiException(status,message)
      theme.dart             ← design tokens (§4) + buildTheme()      ← FROZEN after Phase 0
      i18n.dart              ← L10n (en, pa, hi); every user-visible string via tr('key')
      format.dart            ← dates / times / durations in IST
      secure.dart            ← token store (flutter_secure_storage) + biometric unlock (local_auth)
      geo.dart               ← geofence helper (geolocator): distance to site, inside/outside
    state/
      auth.dart              ← AuthController: login / logout / me / role checks, ready flag
    ui/
      app_shell.dart         ← bottom nav: Home · Leaves · Punch · Team · More
      widgets.dart           ← shared cards, buttons, chips, Loading / Empty / ErrorRetry views
    features/
      auth/    home/    punch/    leaves/    team/    more/      ← one folder per screen group
  android/                   ← keep applicationId + keystore of v1.0.4 (see §6 Versioning)
  test/                      ← widget smoke tests: login renders, shell renders, theme loads
```

Rules: extend files, never move or rename them. A new feature = a new folder under
`features/`. Shared code goes into `core/` or `ui/`, never copy-pasted between features.

---

## 3. Package allow-list

`provider`, `go_router`, `http`, `shared_preferences`, `flutter_secure_storage`,
`local_auth`, `geolocator`, `permission_handler`, `intl`, `url_launcher`,
`connectivity_plus`, `cached_network_image`, `flutter_local_notifications`,
`firebase_core` + `firebase_messaging` (Phase 6 only), `package_info_plus`.

Anything else: list it at the **top** of the reply with a one-line justification and wait
for approval. `webview_*` / `*inappwebview*` are never allowed.

---

## 4. Design tokens (taken from the live webapp)

| Token | Value |
|---|---|
| Primary blue | `#1E6FE0` (deep `#1556B8`, container `#E7F1FF`) |
| Success green | `#16B878` · Danger `#E5484D` · Warning `#F5A524` |
| Page background | `#F4F7FB` · Card `#FFFFFF` · Border `#DDE6EF` |
| Ink | `#172334` · Sub-ink `#617083` · Navy (splash, dark bars) `#0B1633` |
| Radius | 16 cards · 12 inputs & buttons · pill chips |
| Shadow | `0 2 8 rgba(16,24,40,0.06)` |
| Type | system font (Roboto); sizes 12 / 14 / 16 / 20 / 24; weights 400 / 600 / 700 |
| Icons | Material rounded icons |

- **Text scale is clamped in `main.dart`:**
  `MediaQuery.of(context).textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3)`.
  Never derive a text scale from a preference value; never multiply font sizes by a stored
  number. (This exact mistake produced the 1-px text build.)
- **Bottom nav:** 5 items — Home, Leaves, **Punch** (centre, elevated blue circle), Team,
  More; labels always visible; Team hidden for roles without a team.
- **Splash:** opaque navy `#0B1633`, centred app icon + white spinner, **no text**. The
  router replaces it as soon as `AuthController.ready` is true (hard cap 3 s).
- **Login:** logo, title "HRMate", company line "GD Foods Mfg. (I) Pvt. Ltd. · Workforce
  Portal", employee-code-or-email + password, "Unlock with fingerprint" once a token
  exists, language selector (English / ਪੰਜਾਬੀ / हिन्दी).
- Light theme only for Phases 0–5; dark theme is Phase 7.

---

## 5. Mobile API contract (webapp side, same repository)

All routes under **`/api/v1/mobile/`**, JSON in/out, `Authorization: Bearer <jwt>` on
everything except `auth/login`. Errors: `{ ok:false, error:"human message",
code:"UNAUTHENTICATED"|"FORBIDDEN"|"VALIDATION"|"GEOFENCE"|"CONFLICT" }` with the matching
HTTP status (401 / 403 / 400 / 409). The JWT is signed with the server's existing secret,
valid 30 days, revocable per device. Auth is implemented once in a shared helper
(`lib/mobileAuth.ts` or equivalent) that reuses the webapp's **existing** user, role and
permission model — no second user table, no duplicated business rules.

| Route | Purpose |
|---|---|
| `POST auth/login {login, password, deviceId, deviceName}` | → `{ok, token, expiresAt, user:{id, code, name, email, role, department, avatarUrl, permissions[]}}` |
| `POST auth/logout` · `POST auth/refresh` · `GET me` | session lifecycle |
| `GET attendance/today` | `{status:"in"\|"out"\|"none", firstIn, lastOut, workedMinutes, shift{name,start,end}, geofence{lat,lng,radiusM}}` |
| `POST attendance/punch {type:"in"\|"out", lat, lng, accuracyM, method:"biometric"\|"password", deviceId}` | 200 record · 409 `GEOFENCE` with `distanceM` |
| `GET attendance/history?from&to` | day rows for calendar / list |
| `GET leaves/balance` · `GET leaves?status=&scope=mine\|team` · `POST leaves {type, from, to, halfDay, reason}` | employee leaves (`scope=team` = requests the caller may approve) |
| `POST leaves/:id/approve` · `POST leaves/:id/reject {reason}` | manager actions |
| `GET team/today` · `GET team/members?q=` · `GET team/members/:id/day?date=` | manager views |
| `GET me` (+`profile{designation,joinedOn,phone,manager,shift,site}`) · `GET holidays?year=` · `GET announcements` · `GET payslips` (create ONLY if the webapp has payroll; 404 hides the tile) | More tab |
| `POST devices/push-token {token, platform}` | Phase 6 |

Rule: **build the endpoint on the webapp first** (reply includes a working `curl` example
against `https://hr.flavorflow.co.in`), then build the screen that uses it.

---

## 6. Coding rules

- The server is the authority. The app renders what the API returns — no local attendance
  or leave business rules.
- Every screen has **loading, empty and error-with-retry** states from `ui/widgets.dart`.
- Offline: the last successful GET per endpoint is cached (`shared_preferences`) and shown
  with an "offline · last updated hh:mm" chip. Punches are **not** queued offline.
- i18n: no hard-coded user-visible strings; add en / pa / hi keys to `core/i18n.dart` in the
  same commit.
- No `setState` during build; controllers are read with `context.watch`; the router is
  built once.
- Android: `minSdk 26`, latest stable `targetSdk`; permissions declared only for features
  that exist (internet, fine location, biometric, notifications from Phase 6).
- **Versioning & identity:** native app started at `2.0.0+20`, build number +1 per phase
  (the WebView shell was 1.x). Phases 0–4 shipped as a **beta** with `applicationIdSuffix
  ".beta"` and label "HRMate Beta" next to the live app. Phase 5 builds `--flavor prod`
  (no suffix) as **3.0.0+28**, signed with the v1.0.4 keystore so it installs as an update.
  If that keystore is not available, say so — users will then uninstall the shell once.
- Secrets (keystore, passwords, server secret) are never committed.

---

## 7. Phases — one phase = one prompt = one commit = one APK

**Definition of Done (every phase):** `flutter analyze` clean · `flutter test` green · APK
built by the pipeline and installed on a real phone · screenshots of every new/changed
screen · `git log -1` hash in the reply (pushed) · no files outside the phase's scope
changed · **Deviations: none**.

**Order inside a phase (fixed):** ① server routes → commit → deploy → curls pass ② app
files → **commit + push** (`git status` clean) ③ Codemagic build **from that pushed commit**
④ install + screenshots. An APK built from uncommitted files is invalid — the pipeline must
show the commit hash the APK was built from, and that hash must contain the phase's files.

| Phase | Scope | Done when |
|---|---|---|
| **P0 Foundation** | `mobile/` project, this file, `RELEASE.md`, theme (§4), `ApiClient`, `AuthController`, `secure.dart`, router + shell with 5 placeholder tabs, login screen, splash, Mobile API `auth/login` + `me` + `auth/logout` | real login against `hr.flavorflow.co.in` works; Home placeholder shows the logged-in user's name and role; fingerprint unlock toggle works; beta APK installs beside the live app |
| **P1 Home** | today card (status, first in / last out, worked), quick tiles, announcements, pull-to-refresh — **app code already written upstream** (`hrmate-mobile/lib/features/home/`, `core/cache.dart`); server routes in `server-reference/…/attendance/today`, `announcements`, `leaves/balance` | API `attendance/today`, `announcements`, `leaves/balance` live; offline chip works |
| **P2 Punch** | location + geofence check with distance, native biometric confirm, punch in/out, result sheet, today's punches — **app code already written upstream** (`hrmate-mobile/lib/features/punch/`, `core/geo.dart`); server routes in `server-reference/…/attendance/punch`, `attendance/history` | API `attendance/punch`, `attendance/history`; 409 GEOFENCE shown clearly; a mobile punch shows up in the webapp attendance page |
| **P3 Leaves** | balance chips, list with status filters, apply form (type, dates, half-day, reason), manager approve / reject — **app code already written upstream** (`hrmate-mobile/lib/features/leaves/`); server routes in `server-reference/…/leaves/`, `leaves/[id]/approve`, `leaves/[id]/reject` | leaves endpoints live; a request applied from the app appears on the webapp Leaves page and approving it changes `leaves/balance` |
| **P4 Team** | manager today view (present / absent / on leave / late counts as filters), member search, member day detail with date switcher — **app code already written upstream** (`hrmate-mobile/lib/features/team/`); server routes in `server-reference/…/team/` | team endpoints live; tab hidden for non-managers and 403 on the server; counts match the webapp dashboard for the same day |
| **P5 More + Release 3.0.0** | profile, holidays, attendance calendar (month grid on `attendance/history`), payslips (if any), language, biometric setting, about (version), logout — **app code already written upstream** (`hrmate-mobile/lib/features/more/`); server routes in `server-reference/…/me` (profile block), `holidays`, `payslips` · build `--flavor prod` (no `.beta`), sign with the v1.0.4 keystore, `3.0.0+28`, publish on `/download`, update download page copy | native app replaces the WebView shell: installs OVER it as an update (same applicationId + certificate) |
| **P6 Push** | FCM: punch reminders, leave decisions, announcements; `devices/push-token` | notifications arrive with the app closed |
| **P7 Polish** | dark theme, tablet layout, accessibility, crash reporting | — |

Never merge two phases into one prompt. Never begin phase N+1 with phase N unaccepted.

---

## 8. Session protocol (owner ↔ agent)

- Every owner prompt starts with:
  `Read mobile/ARCHITECTURE.md and follow it strictly. Phase N: <scope line from §7>.`
- Every agent reply ends with five headings: **Changed files** · **Commit** (hash, branch,
  pushed) · **APK** (link or pipeline status) · **Screenshots** · **Deviations** (must be
  "none" unless the owner approved one in this session).
- Forbidden replies: "I rebuilt the app", "I switched to WebView for now", "I simplified the
  architecture", "I started a fresh project", "I removed X to make it compile".
- If something cannot be done as specified: write `BLOCKED: <reason>` and stop. Do not
  substitute another approach.
- The owner's standard rejection: `REJECTED — violates mobile/ARCHITECTURE.md §<n>. Revert
  to commit <hash> and redo Phase N as an incremental change only.`
