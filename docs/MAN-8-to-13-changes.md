# MAN-8 → MAN-13: what changed

Branch: `arena/fc479533-flavorflow`

| Issue | Status | What changed (app) | Needs on the server / by hand |
|---|---|---|---|
| MAN-8 Section-level permissions | Done | Granular permission registry (`lib/core/app_permissions.dart`), grouped matrix in Users, router guards, API `requirePerm` guards (server). | Nothing new. |
| MAN-9 Soya Sauce 740gm productivity | Code fixed, confirm on live data | `_batchOutput()` in `productivity_labour_page.dart`: trays (`produced_trays`) now count as CB equivalents (`trays × bottles_per_tray ÷ bottles_per_cb`) and KG = CB × net kg per CB. The with-carton weight is never read. | Check October 2026 Soya 740gm on the Productivity screen against the batch register. SKUs with tray production (Soya 740 / 1.3, Vinegar 610 / 1.0) also change if they had trays — intended. |
| MAN-10 Daily reminder hour + minute | Done | Settings → Daily entry reminder opens a clock picker (hour and minute), shows the time, reschedules with the same alarm id (no duplicates), re-schedules on app start. `AppSettings.dailyReminderMinute`. | Nothing. |
| MAN-11 Remove HRMate | Done in app | HRMate section, connect dialog, dashboard strip, batch labour row, provider and client code removed. | Optional: `sudo bash tools/ff-remove-hrmate.sh` on the server removes the server-side HRMate routes and the stored `hrmate` setting (backups first). `hrmate-mobile/` and `hrmate-mobile8/` are separate apps in this repo and were left untouched. |
| MAN-12 Notifications | Partly (closed-app limit) | One phone notification per event: alerts are fingerprinted (title + body + route) and not shown twice within 24 h; the notification id comes from the fingerprint. Polling also runs when the app returns to the front. Settings shows the phone notification permission and opens phone settings when blocked. | Closed-app delivery needs a push service (FCM) — not set up. Server duplicates (several writers) can still store extra rows; `tools/ff-notifdedup.sh` is the existing server cleanup. |
| MAN-13 Offline entry + sync | Done for the listed entries | `lib/core/offline_queue.dart`: entries that cannot reach the server are kept in encrypted storage and sent once each with an `Idempotency-Key`; oldest first; retried every 20 s, on app resume and on "Sync now"; rejected entries show "Needs review" with Retry / Discard; each entry belongs to the account that captured it. Status banner under the app bar and the "Offline entries" page (Settings). | **Run `sudo bash tools/ff-idempotency.sh` on the server** before relying on offline entries (it makes a repeated key return the first saved reply). Covered: Dispatch, Production batch (create), Packing receive/consume, Stock receipt, Stock count (set-to-count), Stock adjustment request. Online-only by design: billing invoices/purchases/payments (GST numbering), products and packing master data, recipes, users/roles/2FA, approvals, cancel/void, batch start/complete/edit, loss sheet, labour sheet. |

## Test checklist (manual)
- Turn Wi-Fi and mobile data off → save a dispatch / receipt / stock count → banner says "Offline — … saved on this phone".
- Close and reopen the app while still offline → entry is still listed under Settings → Offline entries.
- Turn the network on → entry moves to "Synced" without re-entering it; the server has exactly one record.
- Send the same entry again (Sync now) → still one record on the server.
- A rejected entry (for example stock rule or a duplicate batch code) → "Needs review" with the server message; Retry works after the cause is fixed.
- Settings → Daily entry reminder → pick a time 2–3 minutes ahead → notification arrives at that minute; change the time → only one reminder.
- Phone notifications blocked → Settings shows OFF; tapping it opens the permission request or the phone's app settings.

## Conflict policy (MAN-13)
- Offline entries are **new records** (a dispatch, a receipt, a stock count, an adjustment request). A phone never edits an existing record offline, so it cannot overwrite another device's change.
- A **stock count** is set-to-count (absolute quantity, no deduction). It is applied when it syncs; the stock ledger shows it like any other count.
- If the server rejects an entry when it syncs (for example a duplicate batch code, a stock rule, or missing permission), it is kept as **Needs review** with the server message. Nothing is retried automatically after a rejection; the person decides Retry or Discard.
- A repeated send of the same entry never creates a second record when `tools/ff-idempotency.sh` is installed.

## Decision to confirm (MAN-9)
- `docs/PRODUCTIVITY_LABOUR_API.md` says CB = sum of `produced_cb`. This change counts tray production as CB equivalents (`produced_trays × bottles_per_tray ÷ bottles_per_cb`), because MAN-9 asks that KG and CB match the pack configuration and trays are real production. If the API doc is the rule, the tray conversion must be reverted.
- The conversion uses `bottles_per_tray` and `bottles_per_cb` from Products. Check those values for Soya Sauce 740gm before comparing totals.
