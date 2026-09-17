# HRMate native app — Phase 0 foundation (ready to adopt)

This folder is the **complete Phase 0** of the HRMate native Flutter app, built on the same
architecture that keeps the FlavorFlow app stable (`core/ · state/ · ui/ · features/`,
provider + go_router + http, server is the authority). It is native Flutter — **no WebView**.

Binding rules: [`../docs/HRMATE_APP_CONSTITUTION.md`](../docs/HRMATE_APP_CONSTITUTION.md)
(commit it into the HRMate repo as `mobile/ARCHITECTURE.md`).

## What is here

```
lib/main.dart                 provider + MaterialApp.router (router built once), textScaler clamp, navy splash (icon + spinner, no text)
lib/router.dart               /login · shell(/home /leaves /punch /team /more); auth redirects; Team hidden for non-managers
lib/core/api.dart             ApiClient → /api/v1/mobile (Bearer token, ApiException{status,code,data}, 401 → session drop)
lib/core/secure.dart          token in device keystore + fingerprint unlock (local_auth)
lib/core/theme.dart           HRMate design tokens (#1E6FE0 · #F4F7FB · #0B1633 …) — FROZEN
lib/core/i18n.dart            tr('…') with en / pa / hi dictionaries
lib/core/format.dart          IST times, dates, durations, greeting, initials
lib/state/auth.dart           AuthController: restore / login / biometric unlock / logout; HrUser
lib/state/push.dart           PushController (Phase 6): FCM token → POST devices/push-token, foreground display, tap → screen; off when google-services.json is absent
lib/ui/app_shell.dart         bottom nav Home · Leaves · Punch(centre) · Team · More + PhasePlaceholder
lib/ui/widgets.dart           LoadingView · EmptyView · ErrorRetryView · HrCard · StatusPill · Avatar · showErr/showOk
lib/features/auth/            LoginPage (code/email + password, fingerprint unlock, language)
lib/features/home/            HomePage — signed-in employee header + card (Phase 1 adds today card etc.)
lib/features/more/            MorePage — Profile · My attendance (calendar) · Holidays · Payslips tiles (Phase 5), language, fingerprint toggle, Notifications switch + test (Phase 6), About (version), sign out
lib/features/{punch,leaves,team}/  placeholders replaced in Phases 2–4
android/                      applicationId in.flavorflow.hrmate, flavors beta(.beta, "HRMate Beta") / prod, minSdk 26, FlutterFragmentActivity, navy launch window; Phase 6: google-services plugin (applied only if android/app/google-services.json exists), POST_NOTIFICATIONS, channel hrmate_default, ic_notification
server-reference/             Next.js handlers per phase (see server-reference/README.md); Phase 6: lib/fcm.ts + devices/push-token · devices/push-test · prefs/notify + webapp-patches (push.ts, wall route)
test/smoke_test.dart          theme tokens + splash-has-no-text
RELEASE.md                    build/sign/publish, versioning, Phase 5 checklist
```

## Adopting it in the HRMate repository (Phase 0 prompt)

1. Copy this folder to `mobile/` in the HRMate repo (keep every path). Copy
   `docs/HRMATE_APP_CONSTITUTION.md` to `mobile/ARCHITECTURE.md`.
2. Add the three server routes from `server-reference/app/api/v1/mobile/` to the webapp and
   implement the two `TODO`s in `_lib/mobileAuth.ts` against the **existing** user model.
   Set `MOBILE_JWT_SECRET`. Prove with the `curl` calls in `server-reference/README.md`.
3. `cd mobile && flutter pub get && flutter analyze && flutter test`
4. `flutter build apk --release --flavor beta` → install `app-beta-release.apk` on a phone,
   sign in with a real account, screenshot: splash, login, Home (name + role), More (version).
5. Commit + push. Reply with: Changed files · Commit · APK · Screenshots · Deviations (none).

Do **not** restructure, rename, "simplify" or replace anything in this folder. Phases 1–7 add
files under `features/` and routes under `/api/v1/mobile/`; the foundation stays.
