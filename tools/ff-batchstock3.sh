#!/usr/bin/env bash
# FlavorFlow: Batch-wise Stock — non-tray products (Dark Soya 250gm,
# White Vinegar 180ml, 4.7/4L…) show "—" in the Trays column instead of 0;
# their trays are excluded from TOTAL/GRAND TOTAL maths too (they're always 0
# anyway, but the dash makes the sheet read like the factory register).
# Idempotent — safe to run twice.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-BATCHSTOCK3 $(date) ==="

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/reports.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('hasTray ?')) { console.log('ALREADY PATCHED — skip'); process.exit(0); }
if (!src.includes('GRAND TOTAL')) { console.log('grouped batch-stock missing — run ff-batchstock2.sh first'); process.exit(2); }
const bak = f + '.bak-batchstock3-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);

// 1) pull bottles_per_tray into the query
const q1 = `SELECT p.name, COALESCE(date(b.planned_date), '—') d, b.code,`;
const q2 = `SELECT p.name, p.bottles_per_tray bpt, COALESCE(date(b.planned_date), '—') d, b.code,`;
if (!src.includes(q1)) { console.log('QUERY ANCHOR NOT FOUND'); process.exit(2); }
src = src.replace(q1, q2);

// 2) per-batch row: dash for non-tray products
src = src.replace(
  "rows.push([r.d, r.code, r.cbLeft, r.trLeft]);",
  "const hasTray = (r.bpt || 0) > 0;\n        rows.push([r.d, r.code, r.cbLeft, hasTray ? r.trLeft : '—']);\n        if (r.name !== undefined) { /* keep flow */ }");

// 3) product TOTAL rows: dash when the product has no trays.
//    track per-product tray-ness alongside subtotals
src = src.replace(
  "let cur = null, subCb = 0, subTr = 0, totCb = 0, totTr = 0;",
  "let cur = null, subCb = 0, subTr = 0, totCb = 0, totTr = 0, curHasTray = false;");
src = src.replace(
  "if (cur !== null) { rows.push(['TOTAL', '', subCb, subTr]); rows.push(['', '', '', '']); }\n          cur = r.name; subCb = 0; subTr = 0;",
  "if (cur !== null) { rows.push(['TOTAL', '', subCb, curHasTray ? subTr : '—']); rows.push(['', '', '', '']); }\n          cur = r.name; subCb = 0; subTr = 0; curHasTray = (r.bpt || 0) > 0;");
src = src.replace(
  "if (cur !== null) { rows.push(['TOTAL', '', subCb, subTr]); rows.push(['', '', '', '']); }\n      rows.push(['GRAND TOTAL', '', totCb, totTr]);",
  "if (cur !== null) { rows.push(['TOTAL', '', subCb, curHasTray ? subTr : '—']); rows.push(['', '', '', '']); }\n      rows.push(['GRAND TOTAL', '', totCb, totTr]);");

fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 400)); process.exit(3); }
console.log('TRAY DASH ✓');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "BATCHSTOCK3 FAIL"; exit 1; fi

systemctl restart flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo ""
echo "BATCHSTOCK3 VERIFIED ✓ — non-tray products hun Trays column ch '—' dikhaunde"
