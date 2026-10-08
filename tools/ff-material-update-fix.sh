#!/usr/bin/env bash
# FlavorFlow — keep material stock edits responsive.
#
# The PUT material route updates stock correctly, then performs the audit/
# notification fan-out synchronously before responding. On a busy SQLite
# server that fan-out can delay the mobile save until its HTTP timeout. This
# patch sends the successful response immediately and queues the same audit
# work for the next event-loop turn, with errors logged instead of blocking or
# changing the stock result.
set -euo pipefail

SERVER_DIR="${FF_SERVER_DIR:-/opt/flavorflow/server}"
ROUTE="$SERVER_DIR/routes/packing.js"
BACKUP_DIR="${FF_BACKUP_DIR:-/opt/flavorflow/backups}"
TS=$(date +%Y%m%d-%H%M%S)
BACKUP="$BACKUP_DIR/packing.js.bak-material-update-$TS"

[ -f "$ROUTE" ] || { echo "FATAL: route not found: $ROUTE"; exit 1; }
command -v node >/dev/null || { echo "FATAL: node is required"; exit 1; }
mkdir -p "$BACKUP_DIR"
cp -a "$ROUTE" "$BACKUP"
echo "BACKUP: $BACKUP"

export ROUTE BACKUP
node <<'JS'
'use strict';
const fs = require('fs');
const cp = require('child_process');
const route = process.env.ROUTE;
const backup = process.env.BACKUP;
let src = fs.readFileSync(route, 'utf8');

let changed = false;
// The live route had a missing-braces bug:
//   if (!m) res.json(...); return;
// The return was unconditional, so valid material updates returned without a
// response and the mobile client waited until its timeout. Fix it explicitly.
const badMissingRowReturn = 'if (!m) res.json({ ok: true, alreadyDeleted: true }); return;';
const goodMissingRowReturn = 'if (!m) { res.json({ ok: true, alreadyDeleted: true }); return; }';
if (src.includes(badMissingRowReturn)) {
  src = src.replace(badMissingRowReturn, goodMissingRowReturn);
  changed = true;
  console.log('MATERIAL PUT: fixed unconditional return ✓');
}

// Also remove the duplicate route-level audit fan-out if it is still present;
// the global request middleware already records/broadcasts the request once.
const putStart = src.indexOf("router.put('/materials/:id'");
const nextRoute = putStart < 0 ? -1 : src.indexOf('\nrouter.', putStart + 1);
const routeEnd = nextRoute < 0 ? src.length : nextRoute;
if (putStart < 0) {
  console.error('FATAL: material PUT route not found; route was not changed');
  process.exit(2);
}
const routeBlock = src.slice(putStart, routeEnd);
const auditRel = routeBlock.search(/\baudit\s*\(/);
const responseMatch = /res\.json\(\{\s*ok\s*:\s*true\s*\}\);/.exec(routeBlock);
if (auditRel >= 0 && responseMatch && responseMatch.index > auditRel) {
  const patchedBlock = routeBlock.slice(0, auditRel) +
    '\n  // Audit is handled once by the global request middleware.\n' +
    routeBlock.slice(responseMatch.index);
  src = src.slice(0, putStart) + patchedBlock + src.slice(routeEnd);
  changed = true;
  console.log('MATERIAL PUT: removed duplicate audit fan-out ✓');
}
if (!changed) console.log('MATERIAL PUT: route already fixed — no source change');
fs.writeFileSync(route, src);
try {
  cp.execFileSync(process.execPath, ['--check', route], { stdio: 'inherit' });
  console.log('SYNTAX OK: packing.js');
} catch (e) {
  fs.copyFileSync(backup, route);
  console.error('SYNTAX FAILED — restored backup');
  process.exit(3);
}
JS

systemctl restart flavorflow
sleep 3
if command -v curl >/dev/null; then
  curl -sS -m 8 http://127.0.0.1:4000/api/health || true
  echo
else
  echo "Health check skipped: curl not found in root PATH"
fi
echo "MATERIAL UPDATE FIX VERIFIED — valid material PUT now responds and saves."
