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
| `0002-phase7-polish.patch` | `cbc3e09` | webapp-faithful theme, app 3.2.0+32: `mobile/assets/fonts/` (Inter v4, 6 weights, OFL) + pubspec fonts, `lib/core/{theme,format,i18n}.dart`, `lib/ui/{app_shell,widgets}.dart`, `lib/features/{home,punch,leaves,team,more,auth}` screens, `mobile/ARCHITECTURE.md` + `mobile/RELEASE.md` + `mobile/server-reference/README.md` — 24 files, no server change, no json keys |
| `0003-phase7-analyzer-fix.patch` | `6f614a5` | fix the 15 analyze errors + 9 infos that failed the first Codemagic build on Flutter 3.29: `FontFeature('tnum')` (the `tabularNumbers()` factory does not exist there), dashed-border painter rewritten without `PathMetric.extractPoints`/`Path.addPolyline` (plain dash lines + corner arcs, same look), `Cached<Holiday?>` for the home holiday KPI, const `Text.rich`/`Column`/`Positioned` — 5 files, no visual change |
| `0004-phase7-analyze-fix2.patch` | `514f0f2` | clears the last 4 issues of the second Codemagic analyze run: home `_holiday` FIELD as `Cached<Holiday?>` (the local was fixed in 0003, the field was not — type error at the `setState` assignment), `const Expanded` in the header (the Column const was already in, the wrapper wasn't), and two now-unnecessary inner `const`s in `widgets.dart` — 3 files, no visual change |


If `git am` reports a conflict (the HRMate branch moved on), run `git am --abort` and fall
back to the manual copy list in the phase prompt — the patch is a convenience, the FlavorFlow
tree under `hrmate-mobile/` stays the source of truth.
