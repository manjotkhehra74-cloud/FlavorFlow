# HRMate native app — build & release

Same pipeline pattern as FlavorFlow (CircleCI, approval-gated). Nothing is built by hand.

## Where the APK comes from

| Track | Flavor | applicationId | Label | Signed with | Who installs |
|---|---|---|---|---|---|
| Beta (Phases 0–4) | `beta` | `in.flavorflow.hrmate.beta` | HRMate Beta | FlavorFlow upload key (CircleCI env) | owner + testers, next to the live app |
| Release (Phase 5+) | `prod` | `in.flavorflow.hrmate` | HRMate | **HRMate release key** — Codemagic env group `hrmate_release` (`HRMATE_KEYSTORE_BASE64` + `HRMATE_KEYSTORE_PASSWORD`; alias fixed `hrmate3`, key password = store password), never in git | everyone via `hr.flavorflow.co.in/download` |

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
2.3.0+24 P3 · 2.4.0+27 P4 · **3.0.0+29 P5 (prod)**.

## Phase 5 (release track) checklist

**Why the native app does NOT update the old shell.** The live WebView shell (v1.0.4/1.0.5) is
package `com.gdfoods.hrmate`, signed with `hrmate-release.keystore`. That keystore *and its
password* are committed in the public HRMate repo (root, `android/app/`, `public/` — i.e. also
downloadable from the website) and printed in `PLAYSTORE_RELEASE.md`, so the key is compromised.
Android only updates an app in place when package name **and** certificate match — neither does.
Decision: the native app is `in.flavorflow.hrmate` (product identity, not the employer's), signed
with a **new private key**; the shell is retired and users uninstall it once (a handful of staff).

1. **New key, kept only in Codemagic.** Generate once, outside any repo, never `git add` it.
   ONE password for store and key, alias fixed `hrmate3` — so the owner has only two values
   to enter:
   ```bash
   P=$(openssl rand -base64 18)     # the single password
   keytool -genkeypair -v -keystore hrmate-release-3.jks -storetype JKS -keyalg RSA -keysize 2048 \
     -validity 10000 -alias hrmate3 -storepass "$P" -keypass "$P" \
     -dname "CN=HRMate, O=FlavorFlow, L=Amritsar, C=IN"
   base64 -w0 hrmate-release-3.jks        # → HRMATE_KEYSTORE_BASE64 (one line)
   echo "$P"                              # → HRMATE_KEYSTORE_PASSWORD
   keytool -list -v -keystore hrmate-release-3.jks -alias hrmate3 -storepass "$P" | grep SHA256   # record below
   ```
   Codemagic → app → Environment variables → group **`hrmate_release`**, both *secure*:
   `HRMATE_KEYSTORE_BASE64`, `HRMATE_KEYSTORE_PASSWORD`. (Optional overrides: `HRMATE_KEY_ALIAS`
   default `hrmate3`, `HRMATE_KEY_PASSWORD` default = store password.) The owner also keeps the
   two values in a password manager — losing them means every future update is a fresh install.
2. **Prod workflow** (`flutter-android-prod`, manual start only — no push trigger):
   `environment.groups: [hrmate_release]`; steps `flutter pub get` → `flutter analyze` →
   `flutter test` → keystore step → `flutter build apk --release --flavor prod`. The keystore
   step must **fail** when `HRMATE_KEYSTORE_BASE64` is empty — no fallback to any keystore in
   the repo, no default passwords:
   ```bash
   set -e
   [ -n "$HRMATE_KEYSTORE_BASE64" ] || { echo "hrmate_release env group missing"; exit 1; }
   [ -n "$HRMATE_KEYSTORE_PASSWORD" ] || { echo "HRMATE_KEYSTORE_PASSWORD missing"; exit 1; }
   echo "$HRMATE_KEYSTORE_BASE64" | base64 --decode > "$CM_BUILD_DIR/mobile/android/app/upload.keystore"
   cat > "$CM_BUILD_DIR/mobile/android/key.properties" <<EOF2
   storeFile=upload.keystore
   storePassword=$HRMATE_KEYSTORE_PASSWORD
   keyAlias=${HRMATE_KEY_ALIAS:-hrmate3}
   keyPassword=${HRMATE_KEY_PASSWORD:-$HRMATE_KEYSTORE_PASSWORD}
   EOF2
   ```
   (`storeFile` is resolved relative to `android/app/`.)
3. **Verify the artifact** `app-prod-release.apk`: `apksigner verify --print-certs` → SHA-256 must
   equal the fingerprint recorded in step 1:
   `HRMate release key SHA-256: <written by the HRMate agent when the key is generated>`
   (alias `hrmate3`, held only in Codemagic group `hrmate_release`);
   `aapt dump badging … | grep package` →
   `name='in.flavorflow.hrmate' versionCode='29' versionName='3.0.0'`. Same check for every
   later build — a different fingerprint means the APK will not install as an update.
4. **Publish** (after the owner has tested the build on his phone). One-time server setup by the
   HRMate agent: `src/app/api/download/apk/route.ts` + `apk-info/route.ts` and
   `scripts/publish-apk.sh` from `server-reference/` (the APK lives in the data volume
   `/app/data/releases/`, never in git or the Docker image), download page reads
   `/api/download/apk-info`. Every release after that is ONE command on the VPS, run by the owner:
   ```bash
   sudo bash /opt/hrmate/scripts/publish-apk.sh ~/app-prod-release.apk 3.0.0 30
   ```
   (upload the APK first with the SSH-in-browser "UPLOAD FILE" button). Download page copy:
   "HRMate 3.0.0 — native app; fingerprint punch, leaves, team, holidays", version/build/date
   from `apk-info`, package `in.flavorflow.hrmate`, plus one line: *"Using HRMate 1.x? Uninstall
   it first, then install 3.0.0 (one time). Your data stays on the server."* QR must encode
   `https://hr.flavorflow.co.in/api/download/apk`. Stop building `beta` once testers have moved.
5. From now on every phase commit is built with `--flavor prod` (3.0.x / 3.1.0 …) and published
   with the same one command. The beta flavor stays in the Gradle file for internal test builds.
