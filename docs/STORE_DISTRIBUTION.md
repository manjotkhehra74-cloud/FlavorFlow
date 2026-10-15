# FlavorFlow — store-first website distribution

## Owner decisions

- Defer Cashfree. Do not start merchant onboarding or advertise working online checkout.
- Android public installation goes through Google Play, not a direct APK link.
- The website Play button and a scannable QR must open the **same live Play Store listing**.
- Play Store publication is pending. Keep the button disabled and show a non-scannable status placeholder until the owner supplies the approved public URL.
- Keep the Windows download option on the website as coming soon. Windows app development is handled separately in another chat; this branch has no Windows build scripts or app adaptations.

## Android website wiring

Android application ID in `android/app/build.gradle.kts`: `in.flavorflow.flavorflow_erp`.

`web-landing/assets/distribution-config.js` contains blank store URLs. After Google Play approval, set `playStoreUrl` to the exact listing URL and deploy. The URL validator accepts HTTPS `play.google.com/store/apps/details` only, with the matching package ID. Do not enable a made-up/not-yet-approved listing merely because the package ID is known.

The header/footer branding remains unchanged. The download area, demo instructions and registration success instructions no longer direct customers to an APK. Both the button and QR use the configured listing URL. QR generation is local (vendored MIT `qrcode-generator`), not a third-party tracking/QR endpoint. With no live URL there is deliberately **no actual QR code** to a dead destination. Android build APKs may still exist as QA artifacts (repository access rules apply); removing public APK links does not delete existing server files or modify the native app's update policy.

### Google Play launch checklist

1. Confirm Play Console access and existing/new application registration. Never change the current application ID to create a second incompatible install.
2. Use the existing signed AAB workflow in `codemagic.yaml`. Keep the upload key; ensure version code exceeds the last uploaded release.
3. Review current target SDK/Play requirements before submission; `targetSdk` is currently 35 and must not be assumed sufficient at submission time.
4. Provide listing name, screenshots, descriptions, privacy-policy URL, support contact, content rating and accurate Data Safety declarations.
5. Review Google Play billing requirements for the actual B2B ERP subscription model and external invoice/renewal flow; do not assume an enterprise exemption without checking eligibility. Provide a dedicated reviewer/demo login and clear company-code/login instructions for this business app. Explain sensitive permission use (camera/location/notifications) and actual collection/storage; remove unneeded permissions.
6. Complete the testing/release requirements Play Console assigns to this developer account, then submit for review. Public QR/installation controls stay pending during review.
7. Verify the approved listing from an unauthenticated browser and a target-region Android phone; supply the exact URL, configure it, test button and decode QR, then publish website changes.

## Website Windows download placeholder

Keep the Windows card, icon and disabled download option on the website. No native Windows code/build workflow belongs to this website work. Once the separately developed app has an approved release URL, configure the website destination. `windowsStoreUrl` currently accepts a verified HTTPS Microsoft Store listing; if a signed installer is chosen instead, deliberately update the website URL policy for that official release host. Do not advertise a working Windows download before release.
