# FlavorFlow Android release

## Current build identity

- Version: **1.2.4 (version code 8)** — increment the `+build` number in `pubspec.yaml` for every Play upload.
- Android application ID: `in.flavorflow.flavorflow_erp`.
- Minimum Android: API 23; target Android: API 36 (required for new Play submissions from August 31, 2026).
- The APK is for direct installation/testing. Google Play accepts the **AAB**, not the APK, for new app releases.

## CI checks and artifacts

The GitHub Actions workflow runs `flutter analyze --no-fatal-infos lib test` (errors and warnings fail; legacy info-level lint hints are non-blocking), `flutter test`, builds the web app, a release APK and a release AAB, then checks the archive/signature outputs. Pushes to `main` and the configured Arena release branches trigger the build; download the Android artifact from the completed run's **Artifacts** section. Builds run through GitHub Actions only; this repository has no CircleCI build configuration.

For a store-upload-signed build, configure these Actions secrets with the existing FlavorFlow upload key:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Never commit the keystore or passwords. If no upload key is configured, GitHub Actions explicitly labels its APK/AAB as **test-only, debug-signed**; those files must not be uploaded to Play Console. GitHub Actions is the release build system for this repository.

## Publishing

CI builds the release files but does **not** publish them to Google Play. Before uploading the AAB, confirm the package ID and signing certificate match the existing Play Console app. Then upload the AAB in Play Console's internal-testing track, complete the listing, privacy/data-safety and content-rating forms, test the internal release, and promote it only after acceptance. No Play Console service-account credential is stored in this repository.
