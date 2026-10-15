# FlavorFlow ERP website

**Latest support state (15 October 2026):** email/phone are publicly enabled. The owner-installed free tawk.to embed was publicly verified in click-to-load mode. The latest source follows the owner’s new request to automatically open chat on visiting the support page, with third-party disclosure and blocked/timeout fallback. The auto-open update is now publicly verified. A later disconnect report prompted a tested resilience update (`tools/ff-support-chat-resilience.py`), adding a vendor-independent Support / Chat launcher and handling late readiness/retry safely. This resilience VM update and actual chat message/reply confirmation are pending. Do not reinstall the historical full-site bundle. See the latest section in `docs/SUPPORT_CENTRE.md`. Older pending-service descriptions below document earlier releases.

The public website promotes FlavorFlow ERP only. Feature copy is maintained in `index.html`; the plans API supplies live prices and trial length, not marketing copy for other products. The dashboard illustration is explicitly labelled as sample data. The selected regenerated Final Flowmark logo is used in the header, footer, dashboard preview and website favicons.

## Local preview

From the repository root:

```sh
python -m http.server 3000 --bind 0.0.0.0 --directory web-landing
```

Open port 3000. This is a static preview, not a running SaaS backend. Production provides `/api/saas/plans`, `/api/saas/lead`, `/api/saas/register` . If the plans API is unavailable, the page displays its existing default pricing. Registration requires the production API. Public Android installation is Google Play-only, with a pending state until the owner supplies the approved listing URL. Demo access is an Android app workflow; the website does not claim a browser demo is available.

The homepage uses local logo assets, `assets/landing.css`, `assets/site.js` and locally hosted Inter WOFF2 fonts (OFL license included). It requires no CDN assets or build step. Serve the whole `web-landing` directory; copying only the HTML will not publish the new layout. No HRMate application or backend files are changed by this redesign.

## Browser regression test

With the static preview running, install `playwright-core` in a temporary directory and provide a Chromium executable:

```sh
npm install --prefix /tmp/flavorflow-tests --no-save playwright-core
NODE_PATH=/tmp/flavorflow-tests/node_modules \
  CHROMIUM_EXECUTABLE=/path/to/chromium \
  node tools/tests/landing.test.cjs
```

Optionally set `LANDING_URL` (default: `http://127.0.0.1:3000`). Browser shared libraries must be installed in the test environment.

The test mocks SaaS endpoints: it verifies ERP-only copy even when the plans API returns unrelated feature descriptions, live pricing/trial length, annual plan selection, modal closing, registration failure/retry/success, demo navigation, absence of JavaScript errors, and no horizontal overflow at 320, 375, 390, 580, 768, 1024, 1280 and 1440 pixels. It also checks capability-tab click/keyboard navigation, responsive tab orientation, mobile menu opening/closing, and local CSS/script/font availability. It does not register real companies or contact WhatsApp.

## Publish to the existing domain host

`tools/ff-landing-deploy.sh` is a website-only deploy helper for the existing SaaS VM. It downloads one GitHub snapshot, validates the ERP landing page, backs up existing public HTML, and atomically replaces `index.html`, `demo.html`, `privacy.html`, `admin.html` the four versioned PNGs, distribution/QR JavaScript, homepage CSS/JavaScript and fonts/license under `assets/`. Assets are installed before HTML. It also publishes the owner console HTML favicon/logo change, but does not modify owner API behaviour, databases, APIs, APKs or reverse-proxy configuration.

Run it on the hosting VM with `sudo`, optionally setting `FF_REF` to the published commit. The existing document root must already exist (default `/opt/flavorflow-saas/web`). It verifies the exact new page through local HTTPS for **both** `flavorflow.co.in` and `www.flavorflow.co.in`, without disabling certificate verification. A successful local check does not establish that external DNS or a CDN points to that VM.

If the live domain still serves a different page, inspect DNS and `/etc/caddy/Caddyfile` before changing routing. Do not replace the whole Caddyfile: it may contain unrelated HRMate and ERP application routes. Older startup/deploy scripts fetching `arena/01a003d0-flavorflow` or `arena/01a0dc70-flavorflow` can overwrite this page on subsequent runs; update the website source ref or stop the old **web** step, keeping other required startup steps intact.

## Selected payment policy

Keep the new landing layout with the original blue/green theme. Credit/debit cards are excluded. The public copy lists invoice-based NEFT, IMPS, RTGS (minimum ₹2 lakh) and cheque, with verified beneficiary instructions and payment verification rather than promised same-day activation. UPI/net banking and optional UPI AutoPay/eNACH are explicitly marked as pending provider setup; no checkout, mandates or automatic activation have been implemented. Automatic bank-payment matching remains a future backend feature. Do not advertise these online facilities as active until the selected provider, bank eligibility and customer authorisation flows are working.

## Logo assets

`assets/flavorflow-logo-v2.png` is an optimised, tightly cropped rendition of the user-selected regenerated Final Flowmark. The same mark supplies 32px/48px favicons and a 180px Apple touch icon. Versioned filenames avoid reusing cached old favicon URLs. Only website branding changes; the Android app icon and original saved design files remain untouched.

Cashfree is deferred by the owner (not approved or enabled). See `docs/CASHFREE_ONBOARDING.md` for the written commercial-confirmation request and implementation gates. The agent has not submitted a sales request or created a merchant account. Keep online payments labelled setup pending until approval and tested integration.

## Store-first distribution and Windows

See `docs/STORE_DISTRIBUTION.md`. Both store URLs remain blank in `assets/distribution-config.js` while publication is pending. Set the exact approved Play URL to activate the Play button and its local QR; there is no public APK fallback. The Windows download option remains a coming-soon placeholder. Windows app development is handled separately in another chat; no Windows app code or build workflow is maintained here.


## Enterprise homepage design (local preview)

Reference reviewed: https://www.sap.com/products/mobile/applications.html — page text and all content chunks, not a pixel-perfect visual/device audit.

The reference uses a product-led introduction, overview/benefits, category-based capabilities, platform/download routes, customer stories, learning resources and FAQs. FlavorFlow adopts the relevant information hierarchy, not SAP branding, copy or imagery:

- Utility/header navigation and a clear product hero with desktop/phone **illustrations**, explicitly sample data rather than actual app screenshots.
- Sticky section links, three operational benefits and the existing eight-language support.
- Six accessible ERP capability panels: production, inventory, dispatch, GST billing, reporting and team controls. Desktop vertical tabs become a horizontal strip on smaller screens.
- A four-stage manufacturing workflow and industry groups based on existing company setup options.
- Existing Basic/Pro/Enterprise pricing, monthly/yearly selection, live prices/trial length and company invoice instructions.
- Google Play/button/QR pending states and the retained Windows download placeholder.
- Company database/access information, FAQs, contact CTA and a grouped footer.

Preserved: selected Flowmark logo, blue/green palette, ERP-only scope, existing API/form paths. No SAP customer logos, invented testimonials/ROI figures, AI claims or certifications are included. Online payment processing remains pending; no credit/debit card payments or public APK links. Windows native development is outside this website task.

This redesign is a **local preview**, not a VM deployment. Regression tests mock all SaaS endpoints; they do not create companies, submit real leads or initiate payments. Production API availability still needs a post-deployment check on the hosting environment. Unavailable plans APIs retain the existing fallback prices. Registration requires the SaaS backend.


## Support centre preview

Open `/support/` on the static preview. The support centre shares the selected logo, blue/green tokens, locally hosted Inter fonts and `landing.css` with the main website. Its own layout and local search are in `assets/support.css` and `assets/support.js`.

There are six topics and 18 expandable guidance articles. Search filters the local article text/keywords, works with topic filters, and supports empty states and article deep links. Native details remain usable without JavaScript. No support API, ticket submission, email sending or analytics is implemented. Search text stays in the browser. The planned `support@flavorflow.co.in` address is explicitly pending and has no mailto link. A later owner request adds call support using the existing business number, plus explicitly pending live-chat and email cards. No WhatsApp contact is used on the support page. Existing main-site contacts stay unchanged until email is activated and tested.

The homepage header and footer link to the support subdomain; non-production previews map the links to `/support/` for working local navigation. The website deployment manifest includes the support HTML/CSS/JavaScript, but publishing those files alone does not replace the support subdomain's Caddy `respond` placeholder. See `docs/SUPPORT_CENTRE.md` for the separate hosting boundary. No VM changes have been performed for this design.

Run `tools/tests/support.test.cjs` with the same `NODE_PATH`, `CHROMIUM_EXECUTABLE` and optional `LANDING_URL` variables as the landing test. Tests cover search/category filtering, clearing/no results, keyboard controls, safe query rendering, article deep links, no-JavaScript article access, responsive overflow checks, and pending email/download states. They make no support submissions or API requests.


### Contact activation and uploaded release

Public contact config is in `assets/support-contact-config.js`. Call support opens the existing business number in a dialler. Email remains disabled until the mailbox is activated/tested. Live chat remains disabled until an approved HTTPS customer-chat URL is configured; it opens the provider's external page on click and does not auto-load third-party tracking/widgets. No secrets belong in that file.

For owner-run publication without GitHub access on the VM, `tools/ff-support-publish.sh` accepts an extracted, checksummed release directory. It publishes the approved enterprise homepage/support and dependencies, backs up touched files/config, and replaces only the known support placeholder block. See `docs/SUPPORT_CENTRE.md`. Publishing files is a separate step from email/chat service activation. The agent has not run this helper on the VM.


### Verified mailbox activation (15 October 2026)

`support@flavorflow.co.in` has passed actual outbound SPF/DKIM/DMARC checks and a return-delivery test confirmed by the owner. Source now sets `emailEnabled: true` and supplies a working no-JavaScript mailto fallback; chat stays pending. This changes only the email contact link, not the gateway's transactional email behaviour or a helpdesk/ticket system. Owner-run publication is separate: `sudo python3 tools/ff-support-email-enable.py` on the VM activates the two static files with backup/rollback and a cache-busted config URL. No DNS or Caddy changes are needed.

The original downloadable website bundle predates activation; do not reinstall it as an email update. Earlier descriptions of pending email describe that initial release. `tools/tests/support-email-enable.test.py` tests the targeted updater without VM/network access.
