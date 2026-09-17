# Ready-made patches for the HRMate repository

Each file is a `git format-patch` commit against the HRMate repo (`arena/01a056d6-hrmate`).
Applying it does the whole "copy these files verbatim" list of a phase in one step, so
nothing can be missed or re-typed.

```bash
cd <HRMate repo>            # branch arena/01a056d6-hrmate, clean working tree
curl -fsSL https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/<commit>/hrmate-mobile/patches/0001-phase6-push-notifications.patch -o /tmp/p6.patch
git am /tmp/p6.patch        # → one commit "feat(mobile): Phase 6 push notifications (FCM) …"
git push origin arena/01a056d6-hrmate
```

| Patch | Base (HRMate head it was made on) | Contents |
|---|---|---|
| `0001-phase6-push-notifications.patch` | `2077dae` | mobile/ app files 3.1.0+31, mobile/server-reference, mobile/ARCHITECTURE.md, scripts/publish-apk.sh, `src/lib/fcm.ts`, `src/lib/push.ts`, `src/app/api/wall/route.ts`, `src/app/api/v1/mobile/{devices/push-token,devices/push-test,prefs/notify,auth/logout}/route.ts` — 36 files, no json keys |

If `git am` reports a conflict (the HRMate branch moved on), run `git am --abort` and fall
back to the manual copy list in the phase prompt — the patch is a convenience, the FlavorFlow
tree under `hrmate-mobile/` stays the source of truth.
