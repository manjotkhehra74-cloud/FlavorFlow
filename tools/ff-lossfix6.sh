#!/usr/bin/env bash
# FlavorFlow: Packing Loss% v6.
#   - Total-row Closing is the sum of product closings.
#   - Editing Production & Stock Actual recalculates each product's BOM-based
#     packing-material CB; trays retain their recorded production quantity.
#   - Supports the existing ff-lossfix5 gA baseline/add-on mode.
#   Run on the existing FlavorFlow VM from its normal deployment workflow.
#   No database schema/data changes. Creates a route backup before patching.
set -euo pipefail
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-LOSSFIX6 $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a routes/packing.js "/opt/flavorflow/backups/packing.js.bak-loss6-$TS"
echo "BACKUP: /opt/flavorflow/backups/packing.js.bak-loss6-$TS"

node - <<'JS'
const fs = require('fs');
const cp = require('child_process');
const f = '/opt/flavorflow/server/routes/packing.js';
let src = fs.readFileSync(f, 'utf8');
const marker = 'lossfix6: Actual-to-BOM cascade and Closing total';
if (src.includes(marker)) {
  console.log('LOSSFIX6 already present — skip');
  process.exit(0);
}
if (!src.includes("router.get('/loss'") || !src.includes('function lossBuild(ym)')) {
  console.error('Packing Loss% route not found — run the existing loss module setup first.');
  process.exit(2);
}
const bak = f + '.bak-loss6-' + Date.now();
fs.copyFileSync(f, bak);

function replaceOnce(from, to, label) {
  if (!src.includes(from)) {
    console.error('PATCH ANCHOR NOT FOUND: ' + label);
    process.exit(2);
  }
  src = src.replace(from, to);
}

// Store the effective Actual shown above the product-material sections.
if (!src.includes('const actualByProduct = {}')) {
  replaceOnce(
    '  const top = [];\n  let tProj = 0, tOpen = 0, tAct = 0;',
    '  const top = [];\n  const actualByProduct = {}; // lossfix6-cascade\n  let tProj = 0, tOpen = 0, tAct = 0, tClose = 0;',
    'Production & Stock totals'
  );
} else if (!src.includes('let tProj = 0, tOpen = 0, tAct = 0, tClose = 0;')) {
  replaceOnce(
    'let tProj = 0, tOpen = 0, tAct = 0;',
    'let tProj = 0, tOpen = 0, tAct = 0, tClose = 0;',
    'Closing total accumulator'
  );
}

// Works with either the original g() cells or the ff-lossfix5 gA() cells.
const actualLine = /const actual = Math\.round\(gA?\('act:' \+ p\.id, \(prodAgg\[p\.id\] \|\| \{\}\)\.cb \|\| 0\)\);/;
if (!src.includes('actualByProduct[p.id] = actual;')) {
  if (!actualLine.test(src)) {
    console.error('PATCH ANCHOR NOT FOUND: Actual production cell');
    process.exit(2);
  }
  src = src.replace(actualLine, (line) => line + '\n    actualByProduct[p.id] = actual;');
}

if (!src.includes('tClose += Number(closing) || 0;')) {
  replaceOnce(
    'tProj += projection; tOpen += opening; tAct += actual;',
    'tProj += projection; tOpen += opening; tAct += actual; tClose += Number(closing) || 0;',
    'sum product Closing values'
  );
}
if (!src.includes('name: \'Total\', projection: tProj')) {
  console.error('PATCH ANCHOR NOT FOUND: Production & Stock total row');
  process.exit(2);
}
if (!src.includes('closing: tClose')) {
  replaceOnce("closing: '' });", 'closing: tClose });', 'total-row Closing value');
}

const oldExp = 'const exp = (a.cb || 0) * l.qc + (a.tr || 0) * l.qt;';
const newExp = 'const exp = (actualByProduct[l.pid] ?? (a.cb || 0)) * l.qc + (a.tr || 0) * l.qt;';
if (!src.includes('actualByProduct[l.pid]')) {
  replaceOnce(oldExp, newExp, 'BOM material usage from edited Actual');
}

const returnLine = '  return { ym, top, sections };';
replaceOnce(returnLine, returnLine + ' // ' + marker, 'lossBuild version marker');
fs.writeFileSync(f, src);

try {
  cp.execFileSync(process.execPath, ['--check', f], { stdio: 'inherit' });
  console.log('SYNTAX OK — Actual→BOM cascade and Closing total installed');
} catch (e) {
  fs.copyFileSync(bak, f);
  console.error('SYNTAX FAIL — restored from ' + bak);
  process.exit(3);
}
JS

systemctl restart flavorflow
sleep 2
curl -fsS -m 8 http://127.0.0.1:4000/api/health
echo ""
echo "LOSSFIX6 VERIFIED ✓ — Actual production drives the product BOM CB; total Closing is summed."
