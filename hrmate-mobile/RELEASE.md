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

## Toolchain pin (do not "upgrade" casually)

Gradle **8.10.2** · AGP **8.7.3** · Kotlin **2.1.0** · Java 17 — compatible with Flutter 3.27 → 3.35
(Codemagic image uses 3.29; CircleCI uses stable). Gradle 9 / AGP 9 break Flutter ≤3.35's
gradle plugin (`groovy.xml.QName` error at `:gradle:compileGroovy`).

## Versioning

`pubspec.yaml` `version: <major.minor.patch>+<build>` — bump the build number (+1) in every
phase commit; minor per phase (2.1.0 P1 … 2.4.0 P4); **3.0.0 at Phase 5** = first public
release of the native app (the WebView shell was 1.x, so 3.0.0 is guaranteed higher than any
installed `versionCode`/`versionName`). After P5: 3.0.x for fixes, 3.1.0 P6 push, 3.2.0 P7.
The About row in More shows `version (build)` from `package_info_plus`, so a screenshot
proves which build runs. Actual history: 2.0.0+20 P0 · 2.1.0+21 P1 · 2.2.0+22 P2 ·
2.3.0+24 P3 · 2.4.0+27 P4 · **3.0.0+28 P5 (prod)**.

## Phase 5 (release track) checklist

1. Obtain the v1.0.4 upload keystore + passwords from wherever the WebView shell was built;
   add them in Codemagic as `HRMATE_KEYSTORE_BASE64 / HRMATE_KEYSTORE_PASSWORD /
   HRMATE_KEY_ALIAS / HRMATE_KEY_PASSWORD` (secure group `hrmate_release`), and in the
   workflow, before the build step, write `android/key.properties`:
   ```bash
   echo "$HRMATE_KEYSTORE_BASE64" | base64 --decode > "$CM_BUILD_DIR/mobile/android/app/upload.keystore"
   cat > "$CM_BUILD_DIR/mobile/android/key.properties" <<EOF2
   storeFile=upload.keystore
   storePassword=$HRMATE_KEYSTORE_PASSWORD
   keyAlias=$HRMATE_KEY_ALIAS
   keyPassword=$HRMATE_KEY_PASSWORD
   EOF2
   ```
   (`storeFile` is resolved relative to `android/app/`.) If the keystore is lost, say so
   explicitly: users uninstall the shell once; the download page must explain it.
2. Build `flutter build apk --release --flavor prod` → `app-prod-release.apk`. Verify with
   `apksigner verify --print-certs app-prod-release.apk`: the SHA-256 must equal the shell's
   certificate; `aapt dump badging … | grep package` → `name='in.flavorflow.hrmate'
   versionCode='28' versionName='3.0.0'`. Only then does it install OVER the shell as an update.
3. Publish on `hr.flavorflow.co.in/download` as `HRMate-3.0.0.apk` (+ `apk-info.txt`: version,
   build, commit, date) and update the page copy: "HRMate 3.0.0 — native app; fingerprint punch,
   leaves, team, holidays, payslips". Keep the beta build installable side-by-side (different id)
   until testers have moved; then stop building `beta`.
4. From now on every phase commit is built with `--flavor prod` (3.0.x / 3.1.0 …). The beta
   flavor stays in the Gradle file for internal test builds only.
