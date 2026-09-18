# Mobile API — server reference for Phase 0

Reference implementation of the three Phase 0 endpoints (ARCHITECTURE.md §5) as
Next.js App Router handlers. Copy into the HRMate webapp repository, then wire the two
`TODO` functions in `_lib/mobileAuth.ts` to the webapp's **existing** user/password/role
model. Nothing here creates a second user table or duplicates business rules.

```
app/api/v1/mobile/
  _lib/mobileAuth.ts        ← JWT sign/verify + requireMobileUser() helper (shared by every route)
  auth/login/route.ts       ← POST {login, password, deviceId, deviceName} → {ok, token, expiresAt, user}
  auth/logout/route.ts      ← POST (bearer) → {ok:true}; revokes the device token
  me/route.ts               ← GET  (bearer) → {ok:true, user, profile}   (profile block added in Phase 5)
  attendance/today/route.ts ← Phase 1: GET → status/firstIn/lastOut/workedMinutes/shift/onLeave/holiday/geofence
  announcements/route.ts    ← Phase 1: GET → {items:[…]} (return [] if the webapp has no announcements)
  leaves/balance/route.ts   ← Phase 1: GET → {available, pending, balances:[…]}
  attendance/punch/route.ts ← Phase 2: POST {type,lat,lng,accuracyM,mocked,method,deviceId} → {punch} · 409 GEOFENCE/CONFLICT
  attendance/history/route.ts ← Phase 2: GET ?from&to → {days:[{date,status,firstIn,lastOut,workedMinutes,punches[]}]}
  _lib/leaveCodes.ts        ← Phase 3: PURE — assignCodes (unique short code per type: Earned Leave→EL), matchLeaveType, publicType
  _lib/leaveTypes.ts        ← Phase 3: WIRING — listLeaveTypes() → the webapp's [{key:"lt_earned", name:"Earned Leave", code?}]
  leaves/route.ts           ← Phase 3: GET ?status&scope=mine|team → {items:[…]} · POST {type,from,to,halfDay,reason} → {leave}
  leaves/[id]/approve/route.ts ← Phase 3: POST → {leave} (manager/HR/admin; 403 otherwise)
  leaves/[id]/reject/route.ts  ← Phase 3: POST {reason} → {leave}
  team/_shared.ts           ← Phase 4: requireTeamAccess / teamMemberIds / memberDay (wire to the webapp's reporting-line rule)
  team/today/route.ts       ← Phase 4: GET ?date → {date, counts{total,present,absent,onLeave,late}, members[]}
  team/members/route.ts     ← Phase 4: GET ?q → {items[]}
  team/members/[id]/day/route.ts ← Phase 4: GET ?date → {member, shift, day{…punches[]}}
  holidays/route.ts         ← Phase 5: GET ?year → {year, items[{date,name,type,optional}]}
  payslips/route.ts         ← Phase 5: GET → {items[{id,month,label,netPay,currency,url}]} — create ONLY if the webapp has payroll; 404 hides the tile
  devices/push-token/route.ts ← Phase 6: POST {token, platform, deviceId} → {ok} (upsert) · DELETE ?token= → {ok}
  devices/push-test/route.ts  ← Phase 6: POST → {ok, configured, tokens, inSeconds} — sends ONE real push to the caller's phones after 10 s
  prefs/notify/route.ts       ← Phase 6: GET → {enabled} · PUT {enabled} → the webapp's own user_prefs.notify_enabled
  auth/logout/route.ts        ← Phase 6: re-copy — also forgets the device's FCM tokens
lib/fcm.ts                  ← Phase 6: → src/lib/fcm.ts  FCM HTTP v1 sender (no npm dep), token table, sendFcmToUser / sendFcmAnnouncement
webapp-patches/src/lib/push.ts        ← Phase 6: → src/lib/push.ts  (the live file + FCM fan-out inside sendPushToUser — the ONLY change)
webapp-patches/src/app/api/wall/route.ts ← Phase 6: → src/app/api/wall/route.ts (the live file + push-only announcement after INSERT — the ONLY change)
```

Phase 3 note: `_lib/mobileAuth.ts` `handle()` now passes the route context through
(`handle(async (req, ctx) => …)`) so `[id]` routes can read `ctx.params.id`. Existing
one-argument handlers keep working unchanged — re-copy `_lib/mobileAuth.ts` too.

Rules that every later route must follow (copy from `me/route.ts`):

- `const user = await requireMobileUser(req)` — throws a 401 `UNAUTHENTICATED` response
  when the Bearer token is missing / invalid / revoked.
- Success → `NextResponse.json({ ok: true, ...data })`.
- Error → `NextResponse.json({ ok:false, error, code }, { status })` with
  `UNAUTHENTICATED 401 · FORBIDDEN 403 · VALIDATION 400 · GEOFENCE 409 · CONFLICT 409`.
- Never read or set the browser session cookie in `/api/v1/mobile/*`.

## Environment

`MOBILE_JWT_SECRET` — long random string (reuse the webapp's existing auth secret if
there is one). Tokens are valid 30 days; `mobile_devices` (or an equivalent JSON/table the
webapp already has) stores `{userId, deviceId, deviceName, tokenId, createdAt, revokedAt}`
so logout revokes one device.

## Verify (must be in the Phase 0 reply)

```bash
# login
curl -s https://hr.flavorflow.co.in/api/v1/mobile/auth/login \
  -H 'content-type: application/json' \
  -d '{"login":"WKH00416","password":"<pw>","deviceId":"curl-1","deviceName":"curl"}'
# → {"ok":true,"token":"eyJ…","expiresAt":"2026-10-15T…","user":{"id":"…","code":"WKH00416","name":"…","role":"superadmin",…}}

# me
curl -s https://hr.flavorflow.co.in/api/v1/mobile/me -H 'authorization: Bearer eyJ…'
# → {"ok":true,"user":{…}}

# no token
curl -s -o /dev/null -w '%{http_code}\n' https://hr.flavorflow.co.in/api/v1/mobile/me   # → 401
```

## Phase 1 verify

```bash
T=<token from login>
curl -s https://hr.flavorflow.co.in/api/v1/mobile/attendance/today -H "authorization: Bearer $T"
# → {"ok":true,"status":"in","firstIn":"2026-09-16T03:32:00.000Z","lastOut":null,"workedMinutes":142,"shift":{"name":"General","start":"09:00","end":"18:00"},"onLeave":false,"holiday":false,"holidayName":null,"geofence":{"lat":31.42225,"lng":75.08436,"radiusM":150}}
curl -s https://hr.flavorflow.co.in/api/v1/mobile/announcements -H "authorization: Bearer $T"      # → {"ok":true,"items":[…]}
curl -s https://hr.flavorflow.co.in/api/v1/mobile/leaves/balance -H "authorization: Bearer $T"     # → {"ok":true,"available":12,"pending":1,"balances":[…]}
```

## Phase 2 verify

```bash
T=<token>
# today's punches (empty list before the first punch)
curl -s "https://hr.flavorflow.co.in/api/v1/mobile/attendance/history?from=$(date +%F)&to=$(date +%F)" -H "authorization: Bearer $T"
# punch from OUTSIDE the geofence → must be 409 GEOFENCE
curl -s -w '\n%{http_code}\n' -X POST https://hr.flavorflow.co.in/api/v1/mobile/attendance/punch -H "authorization: Bearer $T" -H 'content-type: application/json' \
  -d '{"type":"in","lat":31.63,"lng":74.87,"accuracyM":10,"mocked":false,"method":"biometric","deviceId":"curl-1"}'
# punch from INSIDE (site centre) → 200 {"ok":true,"punch":{…}}; a second identical call → 409 CONFLICT
curl -s -w '\n%{http_code}\n' -X POST https://hr.flavorflow.co.in/api/v1/mobile/attendance/punch -H "authorization: Bearer $T" -H 'content-type: application/json' \
  -d '{"type":"in","lat":31.4222459,"lng":75.0843618,"accuracyM":8,"mocked":false,"method":"biometric","deviceId":"curl-1"}'
# the punch must now appear in the webapp's attendance page too (same store) — screenshot it
```

## Phase 3 verify

```bash
T=<token>
# balance per type (already live from Phase 1) and my requests
curl -s https://hr.flavorflow.co.in/api/v1/mobile/leaves/balance -H "authorization: Bearer $T"
curl -s "https://hr.flavorflow.co.in/api/v1/mobile/leaves" -H "authorization: Bearer $T"
# apply (a date a few days ahead) → 200 {"ok":true,"leave":{…,"status":"pending"}}
curl -s -w '\n%{http_code}\n' -X POST https://hr.flavorflow.co.in/api/v1/mobile/leaves -H "authorization: Bearer $T" -H 'content-type: application/json' \
  -d '{"type":"EL","from":"2026-09-25","to":"2026-09-25","halfDay":false,"reason":"Family function"}'
# same dates again → 409 CONFLICT (overlap); missing reason → 400 VALIDATION
# team scope (manager) → the request above must appear
curl -s "https://hr.flavorflow.co.in/api/v1/mobile/leaves?scope=team&status=pending" -H "authorization: Bearer $T"
# approve / reject (use the id from the create response)
curl -s -X POST https://hr.flavorflow.co.in/api/v1/mobile/leaves/<id>/approve -H "authorization: Bearer $T"
curl -s -X POST https://hr.flavorflow.co.in/api/v1/mobile/leaves/<id>/reject -H "authorization: Bearer $T" -H 'content-type: application/json' -d '{"reason":"Peak season"}'
# → after approve, leaves/balance must show used +1 / available -1 and the webapp Leaves page shows the same request
```

## Phase 4 verify

```bash
T=<token of WKH00416 (super_admin → sees everyone)>
curl -s https://hr.flavorflow.co.in/api/v1/mobile/team/today -H "authorization: Bearer $T"
# → {"ok":true,"date":"2026-09-17","counts":{"total":N,"present":…,"absent":…,"onLeave":…,"late":…},"members":[{"id":"u_…","code":"WKH00418","name":"Ravinder Singh","department":"…","status":"leave","leaveType":"CL",…},…]}
curl -s "https://hr.flavorflow.co.in/api/v1/mobile/team/members?q=rav" -H "authorization: Bearer $T"          # → items: Ravinder only
curl -s "https://hr.flavorflow.co.in/api/v1/mobile/team/members/<ravinder id>/day?date=$(date +%F)" -H "authorization: Bearer $T"
# → member + shift + day.punches (today's list) — same numbers the webapp attendance page shows for him
# non-manager token (an employee login) → team/today must be 403 FORBIDDEN
```

## Phase 5 verify

```bash
T=<token>
# profile block on /me (every field may be null; the app hides null rows)
curl -s https://hr.flavorflow.co.in/api/v1/mobile/me -H "authorization: Bearer $T"
# → {"ok":true,"user":{…},"profile":{"designation":"…","joinedOn":"2021-04-01","phone":"…","manager":{"id":"u_…","name":"…"},"shift":{"name":"Season Day Shift","start":"07:00","end":"19:00"},"site":"…"}}
#   profile.shift = ASSIGNED shift only (null when the user has no shift_id) — must be the same at 8 AM and 11 PM
# holidays of this year — same list as the webapp holiday calendar
curl -s "https://hr.flavorflow.co.in/api/v1/mobile/holidays?year=$(date +%Y)" -H "authorization: Bearer $T"
# → {"ok":true,"year":2026,"items":[{"date":"2026-10-02","name":"Gandhi Jayanti","type":"public","optional":false},…]}
# a whole month of history (calendar) — Phase 2 route, ≤62 days
curl -s "https://hr.flavorflow.co.in/api/v1/mobile/attendance/history?from=$(date +%Y-%m-01)&to=$(date +%F)" -H "authorization: Bearer $T" | head -c 600; echo
# payslips: ONLY if the webapp has a payroll module. 404 = module absent (app hides the tile); [] = none for this user
curl -s -w '\n%{http_code}\n' https://hr.flavorflow.co.in/api/v1/mobile/payslips -H "authorization: Bearer $T"
# the url of one item must open in a plain browser tab WITHOUT the webapp login (signed link):
curl -s -o /dev/null -w '%{http_code} %{content_type}\n' "<url from the list>"   # → 200 application/pdf
```

## Publishing (end of Phase 5, then every release)

Files: `app/api/download/apk/route.ts`, `app/api/download/apk-info/route.ts` (replace the webapp's
old `/api/download/apk` that redirected to the WebView-shell GitHub release), `scripts/publish-apk.sh`.
The APK is NOT in git and NOT in the image — it is copied into the data volume by the script.

```bash
# owner, on the VPS, after uploading the tested APK with the SSH "UPLOAD FILE" button:
sudo bash /opt/hrmate/scripts/publish-apk.sh ~/app-prod-release.apk 3.0.0 30
# verify (anyone):
curl -s https://hr.flavorflow.co.in/api/download/apk-info
# → {"ok":true,"package":"in.flavorflow.hrmate","minAndroid":"8.0","version":"3.0.0","build":30,"file":"HRMate-3.0.0.apk","sizeBytes":…,"sha256":"…","publishedAt":"…","available":true,"url":"/api/download/apk"}
curl -s -o /dev/null -w '%{http_code} %{size_download}\n' https://hr.flavorflow.co.in/api/download/apk   # → 200 <same sizeBytes>
```

**publish-apk.sh v3 (09-18)** — added after the 3.0.0 bytes were published as "3.1.0" by mistake
(the old download was uploaded again; sha256 stayed `972f3445…`). The script now refuses to
publish unless the `versionName` inside the APK equals the version argument; if the named file
is wrong but another `*.apk` in the same directory has the right version (browsers save
re-downloads as `app-prod-release (1).apk`) it uses that one and says so; the same bytes can
never be published twice (`/app/data/releases/history.log`); it reports whether Firebase
Messaging **and** the google-services resources are inside the APK (`lib-only` = built without
`google-services.json` → push will not work); and after publishing it deletes the uploaded file
plus any previously-published leftovers from the home directory. Inspection runs with `node`
inside the container, so nothing is installed on the host. Works when piped
(`curl -fsSL <raw url> | sudo bash -s -- ~/app-prod-release.apk 3.1.0 31`).

## Phase 6 — push notifications (FCM)

**What changes on the server (all additive, no business rule touched):**

| File in the webapp | Action | Why |
|---|---|---|
| `src/lib/fcm.ts` | new (from `lib/fcm.ts`) | FCM HTTP v1 sender using the Firebase **service-account key**; signs the OAuth JWT with `node:crypto`, so **no new npm package**. Table `mobile_push_tokens`. Never throws; without a key every send is a no-op. |
| `src/lib/push.ts` | replace (from `webapp-patches/src/lib/push.ts`) | `sendPushToUser()` now also calls `sendFcmToUser()` — every existing `notify()` (morning punch nudge, leave approved / rejected, missed-punch warnings, …) reaches the phone. The `isNotifyEnabled` check stays first, so "notifications off" covers web and app alike. |
| `src/app/api/wall/route.ts` | replace (from `webapp-patches/…/wall/route.ts`) | after the wall INSERT: push-only announcement to everyone except the author (skips users with notifications off). Inbox / permissions unchanged. |
| `src/app/api/v1/mobile/devices/push-token/route.ts` | new | app registers / removes its FCM token |
| `src/app/api/v1/mobile/devices/push-test/route.ts` | new | "Send test notification" in More → the acceptance check without touching attendance/leave data |
| `src/app/api/v1/mobile/prefs/notify/route.ts` | new | Notifications switch in More = the webapp's `user_prefs.notify_enabled` |
| `src/app/api/v1/mobile/auth/logout/route.ts` | replace | logout also deletes the device's FCM tokens |

**Server key (owner does this once, outside git):** Firebase console → project **HRMate** → ⚙ Project settings →
*Service accounts* → **Generate new private key** → a `hrmate-…-firebase-adminsdk-….json` downloads. On the VPS:

```bash
# after uploading the json with the SSH "UPLOAD FILE" button (it lands in ~):
sudo docker cp ~/hrmate-*-firebase-adminsdk-*.json hrmate-hrmate-1:/app/data/fcm-service-account.json
# no restart needed — src/lib/fcm.ts re-checks the file every 30 s.  Container log shows:
sudo docker logs --since 2m hrmate-hrmate-1 2>&1 | grep '\[fcm\]'      # → [fcm] configured: project hrmate-…
```

The file lives in the `hrmate_data` volume (`/app/data`, next to `hrmate.db`), so `docker compose up -d --build`
keeps it. Optional overrides: `FCM_SERVICE_ACCOUNT_FILE=<path>` or `FCM_SERVICE_ACCOUNT_JSON=<inline json>` in
`docker-compose.yml`. **Never commit the key** — it can send notifications to every user.

**Verify (must be in the Phase 6 reply):**

```bash
T=<token from login>
# preference (same value the webapp Settings page shows)
curl -s https://hr.flavorflow.co.in/api/v1/mobile/prefs/notify -H "authorization: Bearer $T"                 # → {"ok":true,"enabled":true}
curl -s -X PUT https://hr.flavorflow.co.in/api/v1/mobile/prefs/notify -H "authorization: Bearer $T" -H 'content-type: application/json' -d '{"enabled":true}'
# token registration (validation) → 400 VALIDATION, then 200 with a dummy token
curl -s -w '\n%{http_code}\n' -X POST https://hr.flavorflow.co.in/api/v1/mobile/devices/push-token -H "authorization: Bearer $T" -H 'content-type: application/json' -d '{}'
curl -s -w '\n%{http_code}\n' -X POST https://hr.flavorflow.co.in/api/v1/mobile/devices/push-token -H "authorization: Bearer $T" -H 'content-type: application/json' -d '{"token":"curl-test-token-0123456789abcdef","platform":"android","deviceId":"curl-1"}'
curl -s -X DELETE "https://hr.flavorflow.co.in/api/v1/mobile/devices/push-token?token=curl-test-token-0123456789abcdef" -H "authorization: Bearer $T"   # → {"ok":true}
# server key status (configured:true once the json is in /app/data); tokens = phones of this user
curl -s -X POST https://hr.flavorflow.co.in/api/v1/mobile/devices/push-test -H "authorization: Bearer $T"
# → {"ok":true,"configured":true,"project":"hrmate-…","error":null,"tokens":1,"inSeconds":10}
# no token → 401
curl -s -o /dev/null -w '%{http_code}\n' https://hr.flavorflow.co.in/api/v1/mobile/prefs/notify
```

**Acceptance (owner, on the phone):** More → Notifications ON → *Send test notification* → press Home / swipe the
app away → within ~10 s the notification appears in the tray → tap opens the app. Then a real one: approve a
leave from the webapp → the employee's phone gets "Leave approved…" with the app closed.
