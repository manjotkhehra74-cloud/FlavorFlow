# FlavorFlow ERP website

The public website promotes FlavorFlow ERP only. Feature copy is maintained in `index.html`; the plans API supplies live prices and trial length, not marketing copy for other products. The dashboard illustration is explicitly labelled as sample data.

## Local preview

From the repository root:

```sh
python -m http.server 3000 --bind 0.0.0.0 --directory web-landing
```

Open port 3000. This is a static preview, not a running SaaS backend. Production provides `/api/saas/plans`, `/api/saas/lead`, `/api/saas/register` and `/download/flavorflow-erp.apk`. If the plans API is unavailable, the page displays its existing default pricing. Registration requires the production API. Demo access is an Android app workflow; the website does not claim a browser demo is available.

The HTML is self-contained and requires no CDN assets or build step. Existing deployment scripts can continue serving the same HTML files. No HRMate application or backend files are changed by this redesign.

## Browser regression test

With the static preview running, install `playwright-core` in a temporary directory and provide a Chromium executable:

```sh
npm install --prefix /tmp/flavorflow-tests --no-save playwright-core
NODE_PATH=/tmp/flavorflow-tests/node_modules \
  CHROMIUM_EXECUTABLE=/path/to/chromium \
  node tools/tests/landing.test.cjs
```

Optionally set `LANDING_URL` (default: `http://127.0.0.1:3000`). Browser shared libraries must be installed in the test environment.

The test mocks SaaS endpoints: it verifies ERP-only copy even when the plans API returns unrelated feature descriptions, live pricing/trial length, annual plan selection, modal closing, registration failure/retry/success, demo navigation, absence of JavaScript errors, and no horizontal overflow at 320, 375, 768 and 1440 pixels. It does not register real companies or contact WhatsApp.

## Publish to the existing domain host

`tools/ff-landing-deploy.sh` is a website-only deploy helper for the existing SaaS VM. It downloads one GitHub snapshot, validates the ERP landing page, backs up existing public HTML, and atomically replaces `index.html`, `demo.html` and `privacy.html`. It does not modify admin pages, databases, APIs, APKs or reverse-proxy configuration.

Run it on the hosting VM with `sudo`, optionally setting `FF_REF` to the published commit. The existing document root must already exist (default `/opt/flavorflow-saas/web`). It verifies the exact new page through local HTTPS for **both** `flavorflow.co.in` and `www.flavorflow.co.in`, without disabling certificate verification. A successful local check does not establish that external DNS or a CDN points to that VM.

If the live domain still serves a different page, inspect DNS and `/etc/caddy/Caddyfile` before changing routing. Do not replace the whole Caddyfile: it may contain unrelated HRMate and ERP application routes. Older startup/deploy scripts fetching `arena/01a003d0-flavorflow` or `arena/01a0dc70-flavorflow` can overwrite this page on subsequent runs; update the website source ref or stop the old **web** step, keeping other required startup steps intact.
