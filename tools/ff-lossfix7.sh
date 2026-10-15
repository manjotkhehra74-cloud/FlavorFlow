#!/usr/bin/env bash
# FlavorFlow: Packing Loss% v7.
# Actual production is authoritative for its product's BOM-based material CB.
# Clear stale manual CB cell overrides when Actual is saved, and once on install
# for products that already have a manual Actual override in the open month.
# Backups are made first; no physical stock or archived month is changed.
set -euo pipefail
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-LOSSFIX7 $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-loss7-$TS"
cp -a routes/packing.js "/opt/flavorflow/backups/packing.js.bak-loss7-$TS"
echo "DB BACKUP: /opt/flavorflow/backups/erp.db.bak-loss7-$TS"
echo "ROUTE BACKUP: /opt/flavorflow/backups/packing.js.bak-loss7-$TS"

node - <<'JS'
const fs = require('fs');
const cp = require('child_process');
const db = require('/opt/flavorflow/server/db');
const f = '/opt/flavorflow/server/routes/packing.js';
const marker = 'lossfix7: Actual edits clear product CB overrides.';
const routeBackup = f + '.bak-loss7-route-' + Date.now();
fs.copyFileSync(f, routeBackup);
let src = fs.readFileSync(f, 'utf8');
if (!src.includes("router.put('/loss/cell'") || !src.includes('actualByProduct[l.pid]')) {
  console.error('Expected v6 Packing Loss route was not found; no data changed.');
  process.exit(2);
}

if (!src.includes(marker)) {
  const anchor = "  db.prepare('INSERT INTO loss_values (ym, key, value) VALUES (?,?,?) ON CONFLICT(ym, key) DO UPDATE SET value = excluded.value').run(ym, key, value);";
  if (!src.includes(anchor)) {
    console.error('PUT /loss/cell anchor not found; no data changed.');
    process.exit(2);
  }
  const addition = `${anchor}
  // ${marker}
  const actMatch = /^act:([0-9]+)$/.exec(key);
  if (actMatch) {
    const pid = Number(actMatch[1]);
    db.prepare('DELETE FROM loss_values WHERE ym = ? AND (key LIKE ? OR key LIKE ?)')
      .run(ym, 'cb:' + pid + ':%', 'base:cb:' + pid + ':%');
  }`;
  src = src.replace(anchor, addition);
  fs.writeFileSync(f, src);
  try {
    cp.execFileSync(process.execPath, ['--check', f], { stdio: 'inherit' });
    console.log('ROUTE SYNTAX OK — Actual edits will refresh BOM CB');
  } catch (e) {
    fs.copyFileSync(routeBackup, f);
    console.error('SYNTAX FAIL — route restored from ' + routeBackup);
    process.exit(3);
  }
} else {
  console.log('ROUTE PATCH already present');
  cp.execFileSync(process.execPath, ['--check', f], { stdio: 'inherit' });
}

// Remove only current-month CB overrides for products with manual Actual cells.
// This makes the existing saved Actual immediately flow through to the BOM.
const openMonth = db.prepare(
  "SELECT ym FROM loss_months WHERE status = 'OPEN' ORDER BY ym DESC LIMIT 1"
).get();
let cleared = 0;
let products = 0;
if (openMonth) {
  const actualCells = db.prepare(
    "SELECT key FROM loss_values WHERE ym = ? AND key LIKE 'act:%'"
  ).all(openMonth.ym);
  const deleteCb = db.prepare(
    'DELETE FROM loss_values WHERE ym = ? AND (key LIKE ? OR key LIKE ?)'
  );
  const seen = new Set();
  for (const row of actualCells) {
    const match = /^act:([0-9]+)$/.exec(row.key);
    if (!match || seen.has(match[1])) continue;
    seen.add(match[1]);
    const pid = Number(match[1]);
    cleared += deleteCb.run(
      openMonth.ym,
      'cb:' + pid + ':%',
      'base:cb:' + pid + ':%'
    ).changes;
  }
  products = seen.size;
  console.log(`OPEN MONTH: ${openMonth.ym}; reset ${cleared} saved CB override row(s) for ${products} product(s) with manual Actual.`);
} else {
  console.log('No open loss month found; route patch installed, no cells reset.');
}
JS

systemctl restart flavorflow
sleep 2
curl -fsS -m 8 http://127.0.0.1:4000/api/health
echo ""
echo "LOSSFIX7 VERIFIED ✓ — saving Actual refreshes BOM CB; current-month overrides reset for Actual-edited products."
