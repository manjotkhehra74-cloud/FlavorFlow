# HRMate native app — build & release

Same pipeline pattern as FlavorFlow (CircleCI, approval-gated). Nothing is built by hand.

## Where the APK comes from

| Track | Flavor | applicationId | Label | Signed with | Who installs |
|---|---|---|---|---|---|
| Beta (Phases 0–4) | `beta` | `in.flavorflow.hrmate.beta` | HRMate Beta | FlavorFlow upload key (CircleCI env) | owner + testers, next to the live app |
| Release (Phase 5+) | `prod` | `in.flavorflow.hrmate` | HRMate | v1.0.4 keystore (`HRMATE_KEYSTORE_*` env) | everyone via `hr.flavorflow.co.in/download` |

## Commands (what CI runs)

```bash
cd hrmate-mobile
flutter pub get
flutter analyze                       # must be clean
flutter test                          # must be green
flutter build apk --release --flavor beta \
  --dart-define=HRMATE_API=https://hr.flavorflow.co.in/api/v1/mobile
# → build/app/outputs/flutter-apk/app-beta-release.apk
```

Local dev: `flutter run --flavor beta` (points at production API by default; override with
`--dart-define=HRMATE_API=http://10.0.2.2:3000/api/v1/mobile` for a local webapp).

## CircleCI

Workflow `hrmate-beta` in `.circleci/config.yml` (this repo): push → `approve-hrmate-beta`
(manual) → `build-hrmate-beta` → artifact `HRMate-Android/HRMate-beta.apk`. Signing reuses
the existing `ANDROID_KEYSTORE_*` project variables; if they are absent the job still
produces a debug-signed APK (installable, not updatable over a release build).

## Versioning

`pubspec.yaml` `version: 2.0.0+20` — bump the build number (+1) in every phase commit;
bump minor per phase group (2.1.0 at Phase 3, 2.2.0 at Phase 5 …). The About row in More
shows `version (build)` from `package_info_plus`, so a screenshot proves which build runs.

## Phase 5 (release track) checklist

1. Obtain the v1.0.4 upload keystore + passwords from wherever the WebView shell was built;
   add them as `HRMATE_KEYSTORE_BASE64 / _PASSWORD / HRMATE_KEY_ALIAS / HRMATE_KEY_PASSWORD`.
   If the keystore is lost, say so: users uninstall the shell once, the download page explains it.
2. Build `--flavor prod`, verify `applicationId` matches the shell's (so it installs as an update).
3. Publish the APK on `hr.flavorflow.co.in/download` and update the page copy (v2.0.0, native).
