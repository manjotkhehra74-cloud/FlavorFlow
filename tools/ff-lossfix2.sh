#!/usr/bin/env bash
# FlavorFlow: Loss% sheet — Extra (and CB) columns in WHOLE numbers.
#   Shared materials' manual consumption is split across products by expected
#   usage; the split produced decimals (6 CB → 3.4 + 2.6). Packing material
#   is counted in pieces, so every auto figure now rounds to whole numbers
#   (largest-remainder so the split still adds up to the recorded total).
# Idempotent — safe to run twice.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-LOSSFIX2 $(date) ==="

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/packing.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('lossWholeSplit')) { console.log('ALREADY PATCHED — skip'); process.exit(0); }
if (!src.includes('ff-lossfix')) { console.log('loss module missing — run ff-lossfix.sh first'); process.exit(2); }
const bak = f + '.bak-lossfix2-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);

// helper: split a total into whole numbers by weights (largest remainder)
const HELPER = `function lossWholeSplit(total, weights) {
  const sumW = weights.reduce((a, b) => a + b, 0);
  if (sumW <= 0 || total <= 0) return weights.map(() => 0);
  const raw = weights.map((w) => total * w / sumW);
  const base = raw.map(Math.floor);
  let left = Math.round(total) - base.reduce((a, b) => a + b, 0);
  const order = raw.map((v, i) => [v - base[i], i]).sort((a, b) => b[0] - a[0]);
  for (let k = 0; k < order.length && left > 0; k++, left--) base[order[k][1]] += 1;
  return base;
}
`;
src = src.replace('/** ff-lossfix: monthly packing loss% (factory sheet). */',
  '/** ff-lossfix: monthly packing loss% (factory sheet). */\n' + HELPER);

// per-section rows: precompute whole-number splits per material, then use them
const OLD = `    const rows = [];
    for (const l of lines) {
      const cb = Math.round(g('cb:' + p.id + ':' + l.mid, expByPidMat[p.id + ':' + l.mid] || 0) * 100) / 100;
      const mTot = manual[l.mid] || 0;
      const mExp = expByMat[l.mid] || 0;
      const share = mExp > 0 ? (expByPidMat[p.id + ':' + l.mid] || 0) / mExp : (bom.filter((x) => x.mid === l.mid).length === 1 ? 1 : 0);
      const extra = Math.round(g('extra:' + p.id + ':' + l.mid, mTot * share) * 100) / 100;`;
const NEW = `    const rows = [];
    for (const l of lines) {
      const cb = Math.round(g('cb:' + p.id + ':' + l.mid, expByPidMat[p.id + ':' + l.mid] || 0));
      const mTot = manual[l.mid] || 0;
      // whole-number split of the recorded manual total across the products
      // sharing this material (largest remainder — parts always sum to total)
      const shares = bom.filter((x) => x.mid === l.mid);
      const weights = shares.map((x) => expByPidMat[x.pid + ':' + l.mid] || 0);
      const parts = weights.some((w) => w > 0)
        ? lossWholeSplit(mTot, weights)
        : shares.map((x, i) => (i === 0 ? Math.round(mTot) : 0));
      const myIdx = shares.findIndex((x) => x.pid === p.id);
      const extra = Math.round(g('extra:' + p.id + ':' + l.mid, myIdx >= 0 ? parts[myIdx] : 0));`;
if (!src.includes(OLD)) { console.log('ANCHOR NOT FOUND'); process.exit(2); }
src = src.replace(OLD, NEW);

// totals stay whole too
src = src.replace("const total = Math.round((cb + extra) * 100) / 100;", "const total = cb + extra;");

fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 400)); process.exit(3); }
console.log('WHOLE-NUMBER SPLIT ✓');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "LOSSFIX2 FAIL"; exit 1; fi

systemctl restart flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo ""
echo "LOSSFIX2 VERIFIED ✓ — Extra/CB/Total hun poore ank ch (6 CB → 4 + 2, na ki 3.4 + 2.6)"
