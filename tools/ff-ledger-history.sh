#!/usr/bin/env bash
# FlavorFlow — make Packing/Raw Material Ledger reports complete and chronological.
#
# The report and its XLSX export use the same server-side rows. This patch keeps
# every ledger entry (no limit is introduced) and orders the two material
# ledgers from the earliest transaction to the latest, with insertion id as a
# stable tie-breaker for entries on the same date.
#
# Read-only until this script is run on the server. It creates a route backup,
# validates JavaScript, restarts flavorflow, and checks health.
set -euo pipefail

SERVER_DIR="${FF_SERVER_DIR:-/opt/flavorflow/server}"
ROUTE="$SERVER_DIR/routes/reports.js"
BACKUP_DIR="${FF_BACKUP_DIR:-/opt/flavorflow/backups}"
TS=$(date +%Y%m%d-%H%M%S)
BACKUP="$BACKUP_DIR/reports.js.bak-ledger-history-$TS"

[ -d "$SERVER_DIR" ] || { echo "FATAL: server directory not found: $SERVER_DIR"; exit 1; }
[ -f "$ROUTE" ] || { echo "FATAL: reports route not found: $ROUTE"; exit 1; }
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
let changed = 0;

for (const key of ['packing-ledger', 'raw-material-ledger']) {
  const start = src.indexOf(`'${key}': {`);
  if (start < 0) {
    console.error(`FATAL: report '${key}' not found`);
    process.exit(2);
  }
  const next = src.indexOf("\n  '", start + 1);
  const end = next < 0 ? src.length : next;
  let block = src.slice(start, end);

  // The existing report queries are intentionally unbounded. Refuse to edit
  // if a future route adds a row limit, so this tool never claims full history
  // while silently truncating it.
  if (/\bLIMIT\s+\d+/i.test(block)) {
    console.error(`FATAL: '${key}' contains a row limit; review reports.js manually`);
    process.exit(3);
  }

  const old = 'ORDER BY t.id DESC';
  const modern = 'ORDER BY t.txn_date ASC, t.id ASC';
  if (block.includes(modern)) {
    console.log(`${key}: already earliest-to-latest`);
    continue;
  }
  if (!block.includes(old)) {
    console.error(`FATAL: '${key}' does not have the expected descending order`);
    process.exit(4);
  }
  block = block.replace(old, modern);
  src = src.slice(0, start) + block + src.slice(end);
  changed++;
  console.log(`${key}: changed to txn_date ASC, id ASC`);
}

if (!changed) {
  console.log('NO CHANGES NEEDED');
  process.exit(0);
}

fs.writeFileSync(route, src);
try {
  cp.execFileSync(process.execPath, ['--check', route], { stdio: 'inherit' });
  console.log('SYNTAX OK: reports.js');
} catch (e) {
  fs.copyFileSync(backup, route);
  console.error('SYNTAX FAILED — restored the backup');
  process.exit(5);
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
echo "LEDGER HISTORY VERIFIED — Packing and Raw Material reports/export are earliest-to-latest with full history."
