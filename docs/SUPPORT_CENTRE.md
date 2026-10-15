# FlavorFlow support centre

## Current state

- `https://support.flavorflow.co.in` was publicly verified over HTTPS on 14 October 2026 and returns `FlavorFlow ERP support centre — coming soon.`
- Public DNS: `support.flavorflow.co.in` CNAME → `flavorflow.co.in`; observed address `34.180.13.78`. Confirm the current VM/address before changing infrastructure.
- The owner applied a dedicated Caddy hostname block with a plain `respond` placeholder and `X-Robots-Tag: noindex, nofollow`. Existing main/ERP routes were not intentionally modified by that setup.
- The new support design is **local preview only**, at `/support/`. The live placeholder has not been replaced by this design.
- Email provider selection and mailbox activation are pending. The owner chose to prioritise the subdomain first. No domain email was reported in use and no MX answer was observed during that initial check; recheck before any mail DNS changes.

## Design and functional scope

Preserve the main website's blue/green palette, selected Flowmark logo and Inter typography. Use a simpler help-focused layout, not a separate visual brand.

The page offers six topics, 18 expandable guidance articles, local text/keyword search, topic filters, clear/no-results states, popular searches and article deep links. Native article expansion works without JavaScript. Content covers setup, trial, login/company codes/permissions, production/inventory, dispatch/PDFs, billing/payment instructions, reports and pending app releases. Guidance is deliberately general and does not fabricate unverified screen paths or recovery endpoints.

The contact section lists the **planned** `support@flavorflow.co.in` address with explicit pending labels and no mailto link. It collects no customer data, submits no tickets and sends no emails. The owner subsequently requested call, live-chat and email options. A dialler link now uses the existing published business number +91 95016 06877. No call has been placed or support availability verified; no service hours or response-time promises are invented. No WhatsApp contact is used on the support page. Main-site phone contacts remain unchanged until a replacement mailbox is genuinely usable.

Suggested future mailbox: Zoho Mail Lite; Google Workspace is an alternative. Provider and cost must be approved separately; account signup/payment has not been performed. A later helpdesk such as Zoho Desk can add genuine ticket IDs and tracking. Do not render success/ticket confirmations without an operational backend.

## Files and preview

- `web-landing/support/index.html`: support content/layout.
- `web-landing/assets/support.css`: support-specific responsive styles.
- `web-landing/assets/support.js`: client-side help search/filters, no API calls.
- Shared `landing.css`, logo/favicons and Inter fonts must be served on the support origin.
- Homepage header and footer link to the public support hostname; `site.js` maps these to `/support/` on non-production preview hosts so click-through works locally.
- `tools/tests/support.test.cjs`: browser regression test.

Serve the entire `web-landing` directory and open `/support/`. Search stays local to the browser; it is not a server-side search or a support submission.

## Publication boundary — not yet executed

The main website deploy helper now includes support HTML/CSS/JavaScript in its asset manifest. **It also deploys the main website redesign**; do not use it to publish support alone unless that combined deployment is intended and approved. No helper or VM deployment was run during this support design task.

After design approval, publish the support files and shared dependencies from a reviewed immutable snapshot. Back up existing files/config first. The existing support Caddy placeholder block must then be replaced, not duplicated. With files under the existing `/opt/flavorflow-saas/web` root, a possible scoped block is:

```caddyfile
support.flavorflow.co.in {
    root * /opt/flavorflow-saas/web
    header X-Robots-Tag "noindex, nofollow"

    @supportHome path /
    rewrite @supportHome /support/index.html

    @supportFiles path /support/* /assets/*
    handle @supportFiles {
        file_server
    }
    handle {
        respond "Not found" 404
    }
}
```

This is a proposed block, not a representation of the complete live Caddyfile. Review current imports/routes first; preserve all unrelated sites. Validate and reload Caddy with rollback available. The scoped routes do not expose the SaaS API or tenant data through the support hostname. Confirm `/`, shared assets, article links and HTTPS publicly before replacing the main footer's relative preview link with the live support subdomain URL. Do not claim publication from a local screenshot or DNS check alone.

Keep noindex during preparation. Remove it only when publication policy/content readiness is approved. Activate and send/receive-test the support mailbox before adding mailto links or removing the main site's existing contact route. Configure MX/SPF/DKIM/DMARC using provider-issued values; preserve any other legitimate senders and existing DNS records. Never request customer passwords, OTPs, recovery codes or banking credentials.


## Contact channels and release update

The latest UI adds three channel cards near the top: live chat, call support and email support. `assets/support-contact-config.js` holds public owner-managed contact values. `support-contacts.js` creates validated links and keeps unconfigured channels disabled. The call link opens the device dialler; it does not place a call automatically. No chat widget is loaded automatically and no ticket/contact form data is collected.

- `phoneNumber`: existing published business number, E.164 format.
- `emailAddress`: planned support mailbox. `emailEnabled` remains **false** until send/receive tests pass; then the CTA opens the customer's email app, not a website ticket backend.
- `liveChatUrl`: blank until the owner selects and activates a provider and supplies its approved HTTPS customer-chat URL. When configured, it opens the external chat page in a new tab with `noopener noreferrer`. This is not an embedded chat widget or a guarantee that an agent is online. Never put secrets/private keys into this public file.

The source now includes `tools/ff-support-publish.sh`, an uploaded-release installer for the existing VM. A prepared archive can include the approved homepage/support HTML and required assets, plus a SHA256 manifest. It does **not** overwrite demo/privacy/admin HTML, backend code or data. The helper verifies release hashes, backs up touched files and the Caddyfile, refuses unknown/duplicate support routing, validates a candidate Caddy configuration and replaces only the known placeholder or its managed support block. Installation/reload failures trigger rollback. Local HTTPS checks are not a substitute for public checks. No real deployment was executed by the agent.

`tools/tests/support-publish.test.py` covers placeholder conversion, unrelated-route preservation, idempotency, unknown/duplicate routing refusal, tampered-file refusal, mock publish success and mock install-failure rollback. Service/root/HTTPS tools are mocked in shell tests: these tests do not validate real Caddy syntax/ACME or access a VM.
