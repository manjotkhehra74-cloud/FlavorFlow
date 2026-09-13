#!/usr/bin/env bash
# FlavorFlow: bring the monthly "Packing Loss %" sheet BACK on the server menu.
#   ff-lossretire (Sep 2026) stripped the NAV_ITEMS entry { path: '/loss', … }
#   from rbac.js on every server — including the food factory that lives on
#   this sheet. The section is now a per-industry / per-company feature
#   (app: Settings → Company details → Packing Loss %), so the server menu
#   simply offers it again and the APP decides who sees it.
#     rbac.js  → NAV_ITEMS entry re-inserted right after /raw (or /packing)
#                (SaaS core + factory), same object style as the file.
#   Routes /api/packing/loss*, tables loss_months/loss_values/loss_archive and
#   permissions loss.view / loss.manage were never touched — every old month
#   is still there.
#   Idempotent — safe to run on every boot.  FF_NO_RESTART=1 → no service restart.
set -u
echo "=== FF-LOSSRESTORE $(date) ==="
TS=$(date +%s)

restore_one() {
  local DIR="$1" SVC="$2" F
  F="$DIR/rbac.js"
  [ -f "$F" ] || { echo "SKIP: $F nahi"; return 0; }
  if grep -Eq "path: *['\"]/loss['\"]" "$F"; then echo "RBAC: $DIR — /loss NAV present ✓"; return 0; fi
  cp -a "$F" "$F.bak-lossrestore-$TS"
  node -e '
const fs = require("fs"), f = process.argv[1], dir = process.argv[2];
let src = fs.readFileSync(f, "utf8");
const lines = src.split("\n");
// 1) Prefer the exact line ff-lossretire removed (newest backup of that run).
let lossLine = null;
try {
  const baks = fs.readdirSync(dir).filter((n) => n.startsWith("rbac.js.bak-lossretire-")).sort();
  for (let i = baks.length - 1; i >= 0 && !lossLine; i--) {
    const b = fs.readFileSync(dir + "/" + baks[i], "utf8").split("\n");
    const hit = b.find((l) => /path:\s*[\x27"]\/loss[\x27"]/.test(l));
    if (hit && /\{[^}]*\}/.test(hit)) lossLine = hit.replace(/\s+$/, "");
  }
} catch (_) {}
// 2) Otherwise clone the /raw (or /packing) entry and rewrite its fields.
const anchorIdx = (() => {
  let i = lines.findIndex((l) => /path:\s*[\x27"]\/raw[\x27"]/.test(l));
  if (i < 0) i = lines.findIndex((l) => /path:\s*[\x27"]\/packing[\x27"]/.test(l));
  return i;
})();
if (anchorIdx < 0) { console.log("RBAC: koi /raw ya /packing NAV line nahi labhi — skipped"); process.exit(3); }
if (!lossLine) {
  lossLine = lines[anchorIdx]
    .replace(/path:\s*([\x27"])\/(raw|packing)\1/, "path: $1/loss$1")
    .replace(/label:\s*([\x27"])[^\x27"]*\1/, "label: $1Packing Loss %$1")
    .replace(/icon:\s*([\x27"])[^\x27"]*\1/, "icon: $1percent$1")
    .replace(/perm:\s*([\x27"])[^\x27"]*\1/, "perm: $1loss.view$1")
    .replace(/\s+$/, "");
  if (!/path:\s*[\x27"]\/loss[\x27"]/.test(lossLine)) { console.log("RBAC: NAV line clone failed — skipped"); process.exit(3); }
}
// trailing comma on the new line (valid even as the last array element)
if (!/,\s*$/.test(lossLine)) lossLine += ",";
// make sure the anchor line itself ends with a comma (we insert after it)
if (!/,\s*$/.test(lines[anchorIdx]) && /\}\s*$/.test(lines[anchorIdx])) lines[anchorIdx] = lines[anchorIdx].replace(/\s*$/, ",");
lines.splice(anchorIdx + 1, 0, lossLine);
fs.writeFileSync(f, lines.join("\n"));
console.log("RBAC: " + f + " — /loss NAV line inserted after line " + (anchorIdx + 1) + ": " + lossLine.trim());
' "$F" "$DIR"
  local rc=$?
  if [ $rc -ne 0 ]; then rm -f "$F.bak-lossrestore-$TS"; echo "RBAC: $DIR unchanged (rc=$rc)"; return 0; fi
  if node --check "$F" 2>/dev/null; then
    echo "RBAC: $DIR NAV /loss restored ✓ (backup $F.bak-lossrestore-$TS)"
    if [ "${FF_NO_RESTART:-}" != "1" ]; then systemctl restart "$SVC" 2>/dev/null && echo "SERVER: $SVC restarted ✓"; fi
  else
    cp -a "$F.bak-lossrestore-$TS" "$F"
    echo "FATAL: $F syntax after edit — restored from backup, nothing changed"
  fi
}

# loss.view / loss.manage must exist for the NAV entry to show (ff-permfix
# added them long ago; older factory installs fall back to packing.view).
perm_check() {
  local F="$1/rbac.js"
  [ -f "$F" ] || return 0
  if grep -q "'loss.manage'" "$F"; then echo "PERMS: $1 loss.view/loss.manage present ✓"; else echo "PERMS: $1 loss.* perms missing — app falls back to packing.view (run ff-permfix2.sh to split)"; fi
}

restore_one /opt/flavorflow-saas/core flavorflow-saas
perm_check  /opt/flavorflow-saas/core
restore_one /opt/flavorflow/server flavorflow
perm_check  /opt/flavorflow/server
echo "LOSSRESTORE DONE ✓ — Packing Loss % wapas menu vich (app industry / company switch mutabik dikhaunda: food-type ON, textile/mill/footwear/hardware OFF by default)"
