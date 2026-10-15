# FlavorFlow support centre

## Current state

- `https://support.flavorflow.co.in` now serves the support centre publicly over HTTPS. The previous coming-soon placeholder was replaced by the owner-run deployment on 15 October 2026.
- Public DNS: `support.flavorflow.co.in` CNAME → `flavorflow.co.in`; observed address `34.180.13.78`. Confirm the current VM/address before changing infrastructure.
- The owner applied a dedicated Caddy hostname block with a plain `respond` placeholder and `X-Robots-Tag: noindex, nofollow`. Existing main/ERP routes were not intentionally modified by that setup.
- The support design and approved enterprise homepage are **published**. The owner ran the uploaded-release installer at 2026-10-15 06:24:03 UTC. Main/www/support HTML and listed support dependencies passed local HTTPS/content checks. The agent subsequently fetched all three public HTTPS domains and confirmed the new page content. This was not an agent-executed VM deployment.
- Mailbox `support@flavorflow.co.in` is now active on GoDaddy/Titan. An actual outbound message reached the Gmail inbox with SPF, domain-aligned DKIM and DMARC PASS; the owner confirmed receipt of the return reply on 15 October 2026. Pricing/renewal terms were not checked. Do not change the working mail DNS to another provider.
- Email CTA activation is prepared in source/config and tested. The live static files still require the owner to run `ff-support-email-enable.py`; do not claim the live button is enabled until public verification. Live chat remains pending.

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
- `emailAddress`: verified support mailbox. `emailEnabled` is now **true in source** after successful send/receive checks. The CTA opens the customer's email app, not a website ticket backend. The originally delivered archive remains a historical snapshot with email disabled.
- `liveChatUrl`: blank until the owner selects and activates a provider and supplies its approved HTTPS customer-chat URL. When configured, it opens the external chat page in a new tab with `noopener noreferrer`. This is not an embedded chat widget or a guarantee that an agent is online. Never put secrets/private keys into this public file.

The source now includes `tools/ff-support-publish.sh`, an uploaded-release installer for the existing VM. A prepared archive can include the approved homepage/support HTML and required assets, plus a SHA256 manifest. It does **not** overwrite demo/privacy/admin HTML, backend code or data. The helper verifies release hashes, backs up touched files and the Caddyfile, refuses unknown/duplicate support routing, validates a candidate Caddy configuration and replaces only the known placeholder or its managed support block. Installation/reload failures trigger rollback. Local HTTPS checks are not a substitute for public checks. No real deployment was executed by the agent.

`tools/tests/support-publish.test.py` covers placeholder conversion, unrelated-route preservation, idempotency, unknown/duplicate routing refusal, tampered-file refusal, mock publish success and mock install-failure rollback. Service/root/HTTPS tools are mocked in shell tests: these tests do not validate real Caddy syntax/ACME or access a VM.


## Confirmed owner deployment — 15 October 2026

- Uploaded bundle SHA256: `d6a016384688e40392d700aca4c1ac3c64b0a5b93f4f32658cf6af840690d3a6`; owner reported checksum OK.
- Delivery source: GitHub commit `71f54da4c8d3544fd3eea5ba2c36679e35fb7848`, `website-release/flavorflow-support-release.tar.gz`.
- VM backup: `/opt/flavorflow-saas/backups/support-web-20261015T062403Z-1949903`.
- Caddy candidate validation/reload succeeded. The formatting warning was non-blocking.
- Installer reported matching local HTTPS content on main/www/support and support CSS/JS/config/logo/font paths. Public fetches subsequently returned the enterprise homepage on main/www and `Support Centre | FlavorFlow ERP` on the support origin.
- Public support config was also fetched: `phoneNumber: '+919501606877'`, `emailEnabled: false`, `liveChatUrl: ''`. The public support page shows the call link and pending chat/email states. No call was placed, no mailbox was provisioned and no chat provider was activated.
- No live company registrations, payment requests or backend/data regression tests were performed during this verification.

Earlier sections describing local preview and proposed publication document the preparation phase; this confirmed deployment supersedes that phase. The noindex policy and pending service activation remain unchanged.


## Verified mailbox and targeted activation — 15 October 2026

The owner created `support@flavorflow.co.in` in GoDaddy/Titan and supplied the account screenshot. A narrow Gmail search located the owner's test message in INBOX. Google's Authentication-Results showed `spf=pass`, domain-aligned `dkim=pass` (`d=flavorflow.co.in`, selector `secureserver1`) and `dmarc=pass`. The assistant sent one verification reply in the same test thread; the owner confirmed its arrival in the Titan mailbox. No credentials were requested or stored. Mailbox health tests do not guarantee all future delivery or establish the provider's renewal price.

`tools/ff-support-email-enable.py` is a targeted owner-run updater for the existing VM. It validates the expected mailbox/config/HTML, backs up both static files, enables only the email flag and email-card markup, version-busts the config URL, and rolls back changed files on failure. Call/chat configuration remains untouched. It does not modify DNS, Caddy, backend/data or provision a mailbox. Re-running it after successful activation is a no-op. Run with sudo; default web root is `/opt/flavorflow-saas/web`.

The source page has an active mailto fallback even without JavaScript; live chat retains its pending UI. Support/landing browser suites and seven isolated activation tests passed, including rollback, refusal of unknown markup/address, duplicate flags, symlinks and idempotency. **These code tests are not a live deployment.** Await owner-run updater output/public page check before recording the live email button as enabled. Do not reinstall the original archive afterward without re-applying activation; its historical email flag is false.
