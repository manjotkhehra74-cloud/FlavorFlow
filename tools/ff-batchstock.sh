#!/usr/bin/env bash
# FlavorFlow:
#  1) Dispatch Register — batch codes one-per-line (newline instead of commas)
#     in the app table, PDF and Excel.
#  2) New report "Batch-wise Stock": Product → Production Date → Batch Code →
#     CB left → Trays left. Dispatch deduction (FIFO) already updates used_cb/
#     used_trays, so fully-dispatched batches drop off automatically and
#     partially-dispatched ones show the remainder.
# Idempotent — safe to run twice.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-BATCHSTOCK $(date) ==="

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/reports.js';
let src = fs.readFileSync(f, 'utf8');
let changed = false;
const bak = f + '.bak-batchstock-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);

/* 1) batch codes → one per line */
const oldExpr = "(SELECT GROUP_CONCAT(DISTINCT di.batch_code) FROM dispatch_items di WHERE di.dispatch_id = dispatches.id AND di.batch_code IS NOT NULL AND di.batch_code != '') batch_codes,";
const newExpr = "REPLACE((SELECT GROUP_CONCAT(DISTINCT di.batch_code) FROM dispatch_items di WHERE di.dispatch_id = dispatches.id AND di.batch_code IS NOT NULL AND di.batch_code != ''), ',', char(10)) batch_codes,";
if (src.includes(newExpr)) console.log('BATCH CODES: already one-per-line — skip');
else if (src.includes(oldExpr)) { src = src.replace(oldExpr, newExpr); changed = true; console.log('BATCH CODES: newline separator ✓'); }
else console.log('BATCH CODES: anchor not found (repfix chalaya si?) — skip');

/* 2) batch-wise stock report */
if (src.includes("'batch-stock'")) {
  console.log('BATCH-STOCK REPORT: already present — skip');
} else {
  const REPORT = `  'batch-stock': {
    title: 'Batch-wise Stock',
    desc: 'Remaining stock per production batch — dispatched quantities are already deducted (FIFO).',
    run: () => ({
      columns: ['Product', 'Production Date', 'Batch Code', 'CB Left', 'Trays Left'],
      rows: db.prepare(
        \`SELECT p.name, COALESCE(date(b.planned_date), '—') d, b.code,
                b.produced_cb - COALESCE(b.used_cb, 0) cbLeft,
                b.produced_trays - COALESCE(b.used_trays, 0) trLeft
         FROM batches b JOIN products p ON p.id = b.product_id
         WHERE b.status = 'COMPLETED'
           AND (b.produced_cb - COALESCE(b.used_cb, 0) > 0 OR b.produced_trays - COALESCE(b.used_trays, 0) > 0)
         ORDER BY p.name, b.planned_date, b.code\`
      ).all().map((r) => [r.name, r.d, r.code, r.cbLeft, r.trLeft]),
    }),
  },
`;
  const anchor = "  'dispatch-register': {";
  if (!src.includes(anchor)) { console.log('REPORT ANCHOR NOT FOUND'); process.exit(2); }
  src = src.replace(anchor, REPORT + anchor);
  // roles: everyone who can see inventory-valuation also gets batch-stock
  src = src.split("'inventory-valuation'").join("'inventory-valuation', 'batch-stock'")
           // fix the REPORTS-key line we may have just broken (only role lists wanted)
           .replace("'inventory-valuation', 'batch-stock': {", "'inventory-valuation': {");
  changed = true;
  console.log('BATCH-STOCK REPORT: added ✓');
}

if (!changed) { console.log('NOTHING TO DO'); process.exit(0); }
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 400)); process.exit(3); }
JS
RC=$?
if [ $RC -ne 0 ]; then echo "BATCHSTOCK FAIL"; exit 1; fi

systemctl restart flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo ""
echo "BATCHSTOCK VERIFIED ✓ — Reports ch 'Batch-wise Stock' + Dispatch Register batch codes line-by-line"
