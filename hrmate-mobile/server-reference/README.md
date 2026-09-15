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
```

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
