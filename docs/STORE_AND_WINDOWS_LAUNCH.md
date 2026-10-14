# FlavorFlow — store-first distribution and Windows launch

## Owner decisions

- Defer Cashfree. Do not start merchant onboarding or advertise working online checkout.
- Android public installation goes through Google Play, not a direct APK link.
- The website Play button and a scannable QR must open the **same live Play Store listing**.
- Play Store publication is pending. Keep the button disabled and show a non-scannable status placeholder until the owner supplies the approved public URL.
- Develop Windows from the **existing Flutter ERP codebase**, not a second ERP/data model. Windows public distribution is pending; Microsoft Store is a proposed release channel, not an approved/published listing.

## Android website wiring

Android application ID in `android/app/build.gradle.kts`: `in.flavorflow.flavorflow_erp`.

`web-landing/assets/distribution-config.js` contains blank store URLs. After Google Play approval, set `playStoreUrl` to the exact listing URL and deploy. The URL validator accepts HTTPS `play.google.com/store/apps/details` only, with the matching package ID. Do not enable a made-up/not-yet-approved listing merely because the package ID is known.

The header/footer branding remains unchanged. The download area, demo instructions and registration success instructions no longer direct customers to an APK. Both the button and QR use the configured listing URL. QR generation is local (vendored MIT `qrcode-generator`), not a third-party tracking/QR endpoint. With no live URL there is deliberately **no actual QR code** to a dead destination. Android build APKs may still exist as QA artifacts (repository access rules apply); removing public APK links does not delete existing server files or modify the native app's update policy.

### Google Play launch checklist

1. Confirm Play Console access and existing/new application registration. Never change the current application ID to create a second incompatible install.
2. Use the existing signed AAB workflow in `codemagic.yaml`. Keep the upload key; ensure version code exceeds the last uploaded release.
3. Review current target SDK/Play requirements before submission; `targetSdk` is currently 35 and must not be assumed sufficient at submission time.
4. Provide listing name, screenshots, descriptions, privacy-policy URL, support contact, content rating and accurate Data Safety declarations.
5. Provide a dedicated reviewer/demo login and clear company-code/login instructions for this business app. Explain sensitive permission use (camera/location/notifications) and actual collection/storage; remove unneeded permissions.
6. Complete the testing/release requirements Play Console assigns to this developer account, then submit for review. Public QR/installation controls stay pending during review.
7. Verify the approved listing from an unauthenticated browser and a target-region Android phone; supply the exact URL, configure it, test button and decode QR, then publish website changes.

## Windows development foundation

There is no checked-in native Windows runner yet and this Linux sandbox has no Flutter toolchain. A Windows executable has **not** been smoke-tested here. Remote capability tests passed. The first runner attempt failed; Windows Server 2022 / Visual Studio 2022 was pinned. The next build identified a dependency mismatch: image 4.11.0 calls archive.decodeLazy, unavailable in the resolved archive 4.0.9 / Dart 3.9 combination. The existing lockfile-compatible image 4.9.1 is now pinned for reproducible PDF/icon decoding. A successful artifact must be confirmed before calling the build ready.

`tools/bootstrap-windows.ps1` generates a runner using the installed Flutter toolchain **in a temporary sample project**, then copies only `windows/` into this repository. It does not replace `lib/`, pubspec, assets, Android signing, or app business logic. It uses the existing app icon. If a customised Windows runner already exists, it leaves it alone.

`.github/workflows/flavorflow-windows.yml` is a Windows build workflow (session-branch app changes or manual dispatch) on Windows Server 2022 / Visual Studio 2022, pinned to Flutter 3.35.7 (compatible with the Dart 3.9 SDK constraint). It generates the runner, resolves the existing dependencies, runs platform-boundary tests, builds Windows, and packages **the complete release directory**, including DLLs and Flutter data. A ZIP preview is for controlled QA, not a signed installer/public launch. Run the workflow on the session branch; publishing is not automatic.

### Platform adaptations in this foundation

- Android/iOS camera-photo ML Kit scanning remains mobile-only.
- On Windows, the scan action uses a text dialog for manual/paste input or USB keyboard-wedge scanners; it never calls ML Kit or the mobile camera plugin.
- Mobile permission prompts, status-bar notifications/reminder scheduling and GPS dispatch stamps are skipped on desktop. Server-driven in-app notification/badge features remain shared.
- Stock-adjustment camera capture is hidden on desktop; file/gallery selection remains for testing with the desktop image-picker implementation.
- Existing company-code routing connects to the same per-company API/database. No localhost API is baked into the Windows build.

### Windows release gates

1. Run the Windows workflow and resolve compile/plugin issues. Flutter/plugin platform support is not established by website UI changes.
2. Commit the generated runner after review on this same working branch; inspect product/version resources, application icon, DPI/window sizing and runtime dependencies.
3. Smoke-test company-code login, RBAC, production, stock ledger, dispatch, GST sales/purchase, PDF printing/export, CSV/Excel paste/import, image attachments and USB scanner input.
4. Test Windows Hello/secure storage, offline session/unlock, queue replay and account logout. Confirm tenant and saved credential isolation; do not weaken authentication to bypass desktop plugin issues.
5. Test in-app notification polling; decide separately whether native Windows toast notifications are needed. Do not claim phone reminders are supported on Windows.
6. Review wide-screen layouts, keyboard navigation, dialogs, printer selection and export locations on a clean Windows machine without developer tools.
7. Choose distribution: Microsoft Store with signed MSIX and Partner Center approval, or a properly signed installer. Confirm legal publisher identity and package/certificate identity; never invent a Store ID or request signing secrets in chat.
8. Define update, uninstall and data-retention behaviour. Test an upgrade from the prior Windows version and preserve company settings securely.
9. Only after approval/tested installer publication set `windowsStoreUrl` to the verified HTTPS Microsoft Store listing. The current website validator targets `apps.microsoft.com/detail/<store-id>`; change it deliberately if another channel is chosen.

## Current status

Website wiring is ready with honest pending states. Cashfree is deferred. Android listing and QR activation require Play approval and an exact URL. Windows has a build/development path, **not a released application**. Store publication and signing require owner-controlled developer accounts.
