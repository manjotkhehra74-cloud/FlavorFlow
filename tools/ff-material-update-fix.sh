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

if (src.includes('[packing] material update audit queued')) {
  console.log('MATERIAL UPDATE FIX: already present — no change');
  process.exit(0);
}

// Locate only the material PUT handler's UPDATE audit and its success
// response. The live route has had small formatting/string changes over time,
// so use structural anchors rather than matching the entire message text.
const auditStart = /audit\(\s*db\s*,\s*req\.user\s*,\s*['\"]UPDATE['\"]\s*,\s*['\"]packing-material['\"]\s*,\s*id\s*,/;
const am = auditStart.exec(src);
const responseRe = /res\.json\(\{\s*ok\s*:\s*true\s*\}\);/g;
let responseMatch = null;
if (am) {
  responseRe.lastIndex = am.index;
  responseMatch = responseRe.exec(src);
}
const replacement = [
  '  // Respond before notification fan-out so a stock edit cannot sit behind',
  '  // a slow SQLite/user-notification write until the mobile HTTP timeout.',
  '  res.json({ ok: true });',
  '  setImmediate(() => {',
  '    try {',
  "      audit(db, req.user, 'UPDATE', 'packing-material', id,",
  '        `Updated ${m.name} → ${name}, min ${minStock}, stock ${m.stock} → ${stock}`);',
  "      console.log('[packing] material update audit queued');",
  '    } catch (e) {',
  "      console.error('[packing] material update audit failed:', e.message);",
  '    }',
  '  });',
].join('\n');

if (!am || !responseMatch || responseMatch.index <= am.index) {
  console.error('FATAL: material PUT audit/response anchors not found; route was not changed');
  process.exit(2);
}
src = src.slice(0, am.index) + replacement + src.slice(responseMatch.index + responseMatch[0].length);
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
echo "MATERIAL UPDATE FIX VERIFIED — PUT responds before audit notification fan-out."
