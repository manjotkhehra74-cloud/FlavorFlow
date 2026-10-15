# FlavorFlow support centre

## Current state

- `https://support.flavorflow.co.in` now serves the support centre publicly over HTTPS. The previous coming-soon placeholder was replaced by the owner-run deployment on 15 October 2026.
- Public DNS: `support.flavorflow.co.in` CNAME → `flavorflow.co.in`; observed address `34.180.13.78`. Confirm the current VM/address before changing infrastructure.
- The owner applied a dedicated Caddy hostname block with a plain `respond` placeholder and `X-Robots-Tag: noindex, nofollow`. Existing main/ERP routes were not intentionally modified by that setup.
- The support design and approved enterprise homepage are **published**. The owner ran the uploaded-release installer at 2026-10-15 06:24:03 UTC. Main/www/support HTML and listed support dependencies passed local HTTPS/content checks. The agent subsequently fetched all three public HTTPS domains and confirmed the new page content. This was not an agent-executed VM deployment.
- Mailbox `support@flavorflow.co.in` is now active on GoDaddy/Titan. An actual outbound message reached the Gmail inbox with SPF, domain-aligned DKIM and DMARC PASS; the owner confirmed receipt of the return reply on 15 October 2026. Pricing/renewal terms were not checked. Do not change the working mail DNS to another provider.
- Email CTA is live: owner activation output and a public page/config fetch confirmed `emailEnabled: true`, active mailto and unchanged phone on 15 October 2026. Backup: `/opt/flavorflow-saas/backups/support-email-20261015T093059Z-1959580`.
- Owner selected free tawk.to human live chat and supplied the embed snippet. The owner installed the click-to-load widget at 2026-10-15 13:54:26 UTC; public page/config/runtime were subsequently verified. Backup: `/opt/flavorflow-saas/backups/support-chat-20261015T135426Z-1970989`. Actual message/reply delivery has not been confirmed. The owner subsequently installed automatic opening and confirmed completion; public auto-open code/page were fetched and verified. A later report says tawk.to disconnects frequently and its launcher disappears; a resilience follow-up is prepared in source, not yet installed. See the latest section below. Earlier setup/deployment sections are historical, not instructions to repeat.

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


## tawk.to embed integration — source ready, live deployment pending

Owner explicitly requested the supplied embed code rather than a dashboard Direct Chat Link. Exact public embed: `https://embed.tawk.to/6ad0c458b841da34cc9dcaef/1k4vntur2` (from owner screenshot). No password, API key, ERP credentials, AI automation, hired agent service or paid add-on is configured.

`assets/support-chat.js` loads that exact script only when **Open live chat** is clicked. Before clicking, no tawk.to request is made. The existing card opens the widget in-page with the tawk.to show/maximize API after readiness, deduplicates loading/reopening, supports keyboard activation, and gives email/phone fallback on blocked scripts or a 15-second readiness timeout. The card discloses third-party processing before loading. Search text and company/account context are not automatically passed to tawk.to; any chat messages and technical connection data are handled by the provider. JavaScript is required for chat; articles, phone and email retain no-JS access. No online-agent or instant-response guarantee is made.

### Targeted VM install

Use `tools/ff-support-chat-enable.py` with sudo on the existing VM (default `/opt/flavorflow-saas/web`). This standalone release embeds/checksums exactly four static files: the new chat loader, config, contact runtime and support HTML. It accepts only the verified email-enabled previous release or identical new bytes; unexpected local edits/symlinks/missing required files are refused before writing. Assets are installed before HTML; all changed existing files are backed up under `backups/support-chat-<UTC>-<pid>`, and failed writes restore changes/remove newly added assets. Re-running an installed update is a no-op. It does not touch main-site HTML, DNS, Caddy, backend or company data. Email/phone remain enabled.

Do not rerun the older email-only updater or original full-site bundle after the chat update; they predate this widget and could revert chat markup/config. To deploy a future revision, build a fresh reviewed targeted update.

### Validation and acceptance

- `python3 tools/tests/support-chat-enable.test.py`: six isolated tests for exact source/release bytes, backup, idempotency, protected existing edits/missing files, symlink refusal and rollback including deletion of a newly added file.
- `tools/tests/support-chat.test.cjs`: Playwright test with intercepted/stubbed vendor script; exact embed, no pre-click vendor traffic, button/keyboard opening, reopens/deduplication, script URL allowlist, blocked-script fallback, timeout and retry; email/phone preserved.
- Existing support, landing, email activation and initial publication regression tests also pass. No real chats/messages are sent by these tests.
- After owner runs the updater, fetch public HTML/config/runtime to confirm installation. Then owner opens chat, sends a test as visitor and replies from tawk.to inbox. Only that establishes actual two-way chat delivery. Source tests are not proof of VM deployment or chat delivery.


## Follow-up: automatic opening — source ready, VM update pending

The owner explicitly changed click-to-load behaviour: the chat window should show as soon as the support page opens. `support-chat.js` now loads the same approved embed and calls show/maximize on vendor readiness without waiting for a click. It starts only once per page visit; it does not force the widget to reopen after the customer closes/minimizes it. The existing Open live chat control still reopens it manually. Main-site pages do not include the loader. The third-party notice now accurately says chat loads automatically; technical connection data may reach tawk.to on visiting the support page, not only after clicking. No company/account context or search query is passed to the provider. The 15-second fallback/retry and no-JavaScript phone/email access remain unchanged.

`tools/ff-support-chat-autostart.py` is the standalone targeted update for the already-installed `56da7a3` widget. Run with sudo on the existing VM. It changes only `assets/support-chat.js` and `support/index.html`, with known-previous checksums, backup under `backups/support-chat-auto-<UTC>-<pid>`, atomic writes, rollback and idempotency. Config, contact runtime, phone/email, main-site HTML, Caddy and backend are untouched. Do not rerun the older click-only updater afterward. Public installation still requires owner output and a public page check; real chat delivery still needs a message/reply test.

Validation: five isolated auto-update tests, the original six release tests pinned to their immutable source, existing email/publication tests, and support/chat/landing browser suites. Chat tests stub the vendor: opening without interaction, manual reopen, no forced reopen/duplicate script, blocked/timeout/retry, keyboard access and no provider loading on the main website. They do not send real messages.


## Disconnect/vanishing launcher report — resilience fix ready, VM install pending

The owner reports frequent tawk.to disconnects and a missing chat button. This is not proof of a global provider outage: `https://status.tawk.to/` reported All Systems Operational and no incident on 15 October 2026 when checked. The exact user-side cause (network, blocked vendor requests, dashboard/agent status, or provider connection) remains unconfirmed. No real customer messages were sent for diagnosis.

A concrete local defect was found: the old 15-second readiness watchdog cleared the `loading` flag and removed the script, while `onLoad` ignored callbacks when `loading` was false. A slow widget could therefore finish after timeout but never auto-open. The new loader keeps the in-flight embed/callback after timeout, accepts late readiness, and does not insert a second embed for an initialization retry. A true script error clears that failed script and permits a fresh manual retry; generation guards reject stale callbacks. Browser offline/online events show accurate fallback guidance, delay initial requests while offline, and allow a user-requested socket restart with the documented `Tawk_API.start({showWidget:true})` method. An online browser event does not force a ready/closed widget open. There is no aggressive polling, fake online-agent status, shutdown loop, or claim that messages were delivered.

A native first-party **Support / Chat** launcher sits at bottom-left, independent of tawk.to assets/readiness. Its details panel always offers email, phone and support-option links, including without JavaScript or with the chat loader blocked. When the loader is available it also offers **Open / retry chat** and mirrored status feedback. The provider widget remains auto-opening on initial visits when ready; it can still fail when the provider/network is unavailable. The persistent local launcher is a fallback, not a replacement chat backend.

Deploy using the standalone `tools/ff-support-chat-resilience.py` on the existing auto-open VM. It updates only `assets/support-chat.js`, `assets/support.css` and `support/index.html`, with cache-busted URLs, known-previous checksums, idempotency, backup under `backups/support-chat-resilience-<UTC>-<pid>`, atomic writes and rollback. Contact config/runtime, email/phone settings, main-site HTML, DNS, Caddy and backend/data are untouched. Do not rerun older installers afterward.

Validation: five isolated release safety tests; prior immutable updater tests remain pinned to their own release bytes. Playwright vendor-stub tests cover readiness after timeout, no duplicate injection during retry, offline initial visit/recovery, loaded-connection restart on explicit click, missing/throwing APIs, blocked local loader, persistent fallback with no JavaScript, keyboard use and responsive widths. No real tawk.to message/reply delivery or global reliability guarantee follows from stub tests. After owner installation, publicly verify the new code, then test with the user's network/browser; if disconnect persists ask whether the error appears in the visitor widget or agent dashboard and obtain a redacted screenshot.

API reference checked: `https://developer.tawk.to/jsapi/` — onLoad is rendering readiness, `start` starts the socket, and onStatusChange online/away/offline is page status (not definitive socket-disconnect telemetry). Do not interpret offline-agent status as evidence the vendor server is down.
