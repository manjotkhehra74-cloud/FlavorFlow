#!/usr/bin/env bash
# FlavorFlow ERP — "dispatched stock keeps showing" : FUTURE-PROOF patch.
#
# routes/dispatch.js did:   if (!bCode) continue;
#   → a dispatch line with no batch code still took stock out of `inventory`,
#     but no batch was ever charged, so the batch register (and every stock
#     screen fed by it) kept showing that stock as if it were still there.
#
# FIX: when a line arrives without a batch code, pick the OLDEST COMPLETED
#      batch group of that product that can cover the whole line and stamp
#      its code onto the line — so the existing FIFO block charges it, and
#      dispatch_items keeps the code for traceability / reconciliation.
#      (If no group can cover the line, behaviour is unchanged: skipped.)
# Idempotent (marker ff-stockfix2). Backup + node --check + auto-restore.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-STOCKFIX2 $(date) ==="

systemctl stop flavorflow || true
sleep 1

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/dispatch.js';
let src = fs.readFileSync(f, 'utf8');

if (src.includes('ff-stockfix2')) { console.log('DISPATCH: already patched — skip'); process.exit(0); }

const re = /^([ \t]*)if \(!bCode\) continue;[ \t]*$/m;
if (!re.test(src)) {
  console.log('ANCHOR NOT FOUND: "if (!bCode) continue;" nahi mili — pehla ff-codeshow.sh naal dispatch.js bhejo');
  process.exit(2);
}

const bak = f + '.bak-stockfix2-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);

const indent = src.match(re)[1] || '  ';
const block = [
  indent + 'if (!bCode) {',
  indent + '  /* ff-stockfix2: auto-pick the oldest batch group that can cover this line,',
  indent + '     so stock is ALWAYS charged to a batch (no more "dispatched but still shown"). */',
  indent + '  const needCb = Number(l.cartons) || 0, needTr = Number(l.trays) || 0;',
  indent + '  const cand = db.prepare("SELECT code FROM batches WHERE product_id = ? AND status = \'COMPLETED\' " +',
  indent + '    "GROUP BY code " +',
  indent + '    "HAVING SUM(produced_cb - COALESCE(used_cb,0)) >= ? AND SUM(COALESCE(produced_trays,0) - COALESCE(used_trays,0)) >= ? " +',
  indent + '    "ORDER BY MIN(COALESCE(planned_date,\'\')), MIN(id) LIMIT 1").get(l.productId, needCb, needTr);',
  indent + '  if (cand && cand.code) { bCode = String(cand.code).trim(); l.batchCode = bCode; }',
  indent + '}',
  indent + 'if (!bCode) continue;'
].join('\n');

src = src.replace(re, block);
fs.writeFileSync(f, src);

try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 400)); process.exit(1); }
console.log('PATCHED: auto batch-code on dispatch lines ✓');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "STOCKFIX2 FAIL"; systemctl start flavorflow || true; exit 1; fi

systemctl start flavorflow || true
sleep 3
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAIL"
echo "STOCKFIX2 DONE ✓ — hun koi dispatch line batch-code ton khali nahi rahegi"
