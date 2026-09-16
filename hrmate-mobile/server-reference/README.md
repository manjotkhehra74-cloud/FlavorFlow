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
  me/route.ts               ← GET  (bearer) → {ok:true, user}
  attendance/today/route.ts ← Phase 1: GET → status/firstIn/lastOut/workedMinutes/shift/onLeave/holiday/geofence
  announcements/route.ts    ← Phase 1: GET → {items:[…]} (return [] if the webapp has no announcements)
  leaves/balance/route.ts   ← Phase 1: GET → {available, pending, balances:[…]}
  attendance/punch/route.ts ← Phase 2: POST {type,lat,lng,accuracyM,mocked,method,deviceId} → {punch} · 409 GEOFENCE/CONFLICT
  attendance/history/route.ts ← Phase 2: GET ?from&to → {days:[{date,status,firstIn,lastOut,workedMinutes,punches[]}]}
  _lib/leaveTypes.ts        ← Phase 3: internal key ("EARNED") ⇄ short code ("EL") — shortCode/matchLeaveType/publicType
  leaves/route.ts           ← Phase 3: GET ?status&scope=mine|team → {items:[…]} · POST {type,from,to,halfDay,reason} → {leave}
  leaves/[id]/approve/route.ts ← Phase 3: POST → {leave} (manager/HR/admin; 403 otherwise)
  leaves/[id]/reject/route.ts  ← Phase 3: POST {reason} → {leave}
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
