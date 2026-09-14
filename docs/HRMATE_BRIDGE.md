# FlavorFlow ↔ HRMate — read-only attendance bridge (Phase 2)

FlavorFlow (ERP) **reads** the day's head-count from HRMate and shows it on the
dashboard and on each production batch. Nothing is written back to HRMate.
The bridge is configured **per device** in FlavorFlow → Settings → *HRMATE
(ATTENDANCE)* → Connect HRMate (address + optional API key + optional average
daily wage). If HRMate is not configured, unreachable, slow (> 8 s) or answers
in an unknown shape, FlavorFlow simply hides the HRMate tiles — the ERP never
breaks because of HR.

## What FlavorFlow calls

```
GET {HRMATE_BASE}/api/v1/attendance/summary?date=YYYY-MM-DD
Accept: application/json
Authorization: Bearer <api key>          (only when a key is set in Settings)
```

* `HRMATE_BASE` default: `https://hr.flavorflow.co.in` (user can type any
  address, e.g. `https://gdfoods.duckdns.org`).
* `date` is the factory's local date (IST). Dashboard asks for today; a batch
  asks for its `planned_date`.
* Timeout 8 s. Cached 3 min per date; after a failure FlavorFlow waits 45 s
  before retrying — HRMate is never polled aggressively.

## Recommended reply (HRMate side)

```json
{
  "date": "2026-09-14",
  "present": 42,
  "absent": 5,
  "on_leave": 3,
  "late": 2,
  "half_day": 1,
  "total": 50,
  "updated_at": "2026-09-14T10:32:11+05:30"
}
```

Only `present` is strictly required — the others are optional. FlavorFlow is
tolerant about naming (snake_case or camelCase, e.g. `presentCount`,
`on_leave`/`onLeave`, `total_employees`/`headcount`) and about envelopes
(`{ "data": {...} }`, `{ "summary": {...} }`). It also understands a list of
employee rows with a `status` field (`present` / `absent` / `leave` / `late` /
`half_day`) and counts them itself. A reply that carries a bare `date` for a
different day is ignored (treated as "no data").

Errors: `401`/`403` → "HRMate rejected the API key"; `404` → "HRMate summary
API not found — update HRMate"; anything else / timeout → tile hidden.

## CORS (needed for the FlavorFlow **web** build only)

The Android APK talks to HRMate directly; the browser build needs CORS on the
summary route:

```
Access-Control-Allow-Origin: https://app.flavorflow.co.in   (echo the request Origin from an allow-list)
Access-Control-Allow-Headers: Authorization, Accept
Access-Control-Allow-Methods: GET, OPTIONS
```

Allow-list: `https://app.flavorflow.co.in`, `https://flavorflow.co.in`,
`https://flavorflow.duckdns.org` (and `http://localhost:*` for dev). Answer
the `OPTIONS` pre-flight with `204` + the same headers.

## Auth suggestion

A per-company read-only API key issued in HRMate (Settings → Integrations →
"FlavorFlow key"), sent as `Authorization: Bearer <key>`. The key only unlocks
the summary route. Phase 3 (SSO / one company code) replaces this.

## Where it shows in FlavorFlow

* Dashboard → "PRESENT TODAY · HRMATE" card: present / total, %, absent /
  on-leave / late / half-day pills, "Updated … ago". Tap → opens HRMate.
* Production → batch detail → "Workers (HRMate)" row: `38 / 45 present ·
  2 on leave` for the planned date; with an average daily wage set, an
  approximate **labour cost per carton** (`wage × present ÷ planned qty`).
* Settings → HRMATE (ATTENDANCE): Connect / Test connection / Disconnect,
  Open HRMate.
* Website footer: link "HRMate — Attendance & Leaves" → https://hr.flavorflow.co.in

## Client files

`lib/core/hrmate.dart` (client + tolerant parser + cache),
`lib/features/hrmate/hrmate_widgets.dart` (dashboard card, batch row, open
HRMate), `lib/core/open_url.dart` (url_launcher), Settings dialog in
`lib/features/settings/settings_page.dart`. Prefs: `set_hrmate_base`,
`set_hrmate_token`, `set_hrmate_wage`.
