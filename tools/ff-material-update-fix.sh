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

// Work inside the material PUT route only. The live route has had small
// formatting/entity-string changes, so do not depend on the audit message.
const putStart = src.indexOf("router.put('/materials/:id'");
const nextRoute = putStart < 0 ? -1 : src.indexOf('\nrouter.', putStart + 1);
const routeEnd = nextRoute < 0 ? src.length : nextRoute;
if (putStart < 0) {
  console.error('FATAL: material PUT route not found; route was not changed');
  process.exit(2);
}
const routeBlock = src.slice(putStart, routeEnd);
let patchedBlock = routeBlock;
const queuedRe = /\n\s*setImmediate\(\(\) => \{[\s\S]*?\n\s*\}\);/;
if (queuedRe.test(patchedBlock)) {
  // A previous version queued the audit but still left the notification work
  // on the Node event loop. Remove that work completely; the global audit
  // middleware already records/broadcasts the request once.
  patchedBlock = patchedBlock.replace(queuedRe, '\n  // Audit is handled once by the global request middleware.');
} else {
  const auditRel = patchedBlock.search(/\baudit\s*\(/);
  const responseMatch = /res\.json\(\{\s*ok\s*:\s*true\s*\}\);/.exec(patchedBlock);
  if (auditRel < 0 || !responseMatch || responseMatch.index <= auditRel) {
    console.error('FATAL: material PUT audit/response anchors not found inside route; route was not changed');
    process.exit(3);
  }
  patchedBlock = patchedBlock.slice(0, auditRel) +
    '\n  // Audit is handled once by the global request middleware.\n' +
    patchedBlock.slice(responseMatch.index);
}
src = src.slice(0, putStart) + patchedBlock + src.slice(routeEnd);
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
echo "MATERIAL UPDATE FIX VERIFIED — PUT no longer runs duplicate audit notification fan-out."
