#!/usr/bin/env bash
# FlavorFlow: retire the monthly "Packing Loss %" sheet for EVERY industry.
#   The app (this branch) no longer has the screen: nav entry, route, report,
#   dashboard tile and Loss% product tag are gone client-side. This patch keeps
#   the SERVER menu honest as well:
#     rbac.js  → NAV_ITEMS entry { path: '/loss', … } removed (SaaS core + factory)
#   Left untouched on purpose (harmless, keeps old months readable via API):
#     routes /api/packing/loss*, tables loss_months/loss_values/loss_archive,
#     permissions loss.view / loss.manage (app hides them in Users → Edit).
#   Idempotent — safe to run on every boot.  FF_NO_RESTART=1 → no service restart.
set -u
echo "=== FF-LOSSRETIRE $(date) ==="
TS=$(date +%s)

retire_one() {
  local DIR="$1" SVC="$2" F
  F="$DIR/rbac.js"
  [ -f "$F" ] || { echo "SKIP: $F nahi"; return 0; }
  if ! grep -Eq "path: *['\"]/loss['\"]" "$F"; then echo "RBAC: $DIR — /loss already gone ✓"; return 0; fi
  cp -a "$F" "$F.bak-lossretire-$TS"
  node -e '
const fs = require("fs"), f = process.argv[1];
const src = fs.readFileSync(f, "utf8");
const out = src.split("\n").filter((l) => !/path:\s*[\x27"]\/loss[\x27"]/.test(l)).join("\n");
fs.writeFileSync(f, out);
console.log("RBAC: " + f + " — " + (src.split("\n").length - out.split("\n").length) + " NAV line(s) removed");
' "$F"
  if node --check "$F" 2>/dev/null; then
    echo "RBAC: $DIR NAV /loss removed ✓ (backup $F.bak-lossretire-$TS)"
    if [ "${FF_NO_RESTART:-}" != "1" ]; then systemctl restart "$SVC" 2>/dev/null && echo "SERVER: $SVC restarted ✓"; fi
  else
    cp -a "$F.bak-lossretire-$TS" "$F"
    echo "FATAL: $F syntax after edit — restored from backup, nothing changed"
  fi
}

retire_one /opt/flavorflow-saas/core flavorflow-saas
retire_one /opt/flavorflow/server flavorflow
echo "LOSSRETIRE DONE ✓ — Packing Loss % section har industry ton hat gaya (menu, dashboard, reports, permissions chips)"
