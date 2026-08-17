#!/usr/bin/env bash
# FlavorFlow: Batch-wise Stock report — factory-sheet layout:
#   ▶ PRODUCT NAME
#     Mfg. Date | Batch Code | CB | Trays     (oldest first — new batches
#     Mfg. Date | Batch Code | CB | Trays      append below the old balance)
#     TOTAL     |            | ΣCB| ΣTrays
#   ▶ NEXT PRODUCT ...
#   GRAND TOTAL |            | ΣCB| ΣTrays
# Idempotent — safe to run twice.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-BATCHSTOCK2 $(date) ==="

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/reports.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('GRAND TOTAL')) { console.log('ALREADY GROUPED — skip'); process.exit(0); }
if (!src.includes("'batch-stock'")) { console.log("batch-stock report missing — run ff-batchstock.sh first"); process.exit(2); }
const bak = f + '.bak-batchstock2-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);

const start = src.indexOf("  'batch-stock': {");
const end = src.indexOf("  'dispatch-register': {");
if (start === -1 || end === -1) { console.log('ANCHORS NOT FOUND'); process.exit(2); }

const NEW = `  'batch-stock': {
    title: 'Batch-wise Stock',
    desc: 'Remaining stock per production batch, grouped by product — dispatched quantities already deducted.',
    run: () => {
      const batches = db.prepare(
        \`SELECT p.name, COALESCE(date(b.planned_date), '—') d, b.code,
                b.produced_cb - COALESCE(b.used_cb, 0) cbLeft,
                b.produced_trays - COALESCE(b.used_trays, 0) trLeft
         FROM batches b JOIN products p ON p.id = b.product_id
         WHERE b.status = 'COMPLETED'
           AND (b.produced_cb - COALESCE(b.used_cb, 0) > 0 OR b.produced_trays - COALESCE(b.used_trays, 0) > 0)
         ORDER BY p.name, b.planned_date, b.id\`
      ).all();
      const rows = [];
      let cur = null, subCb = 0, subTr = 0, totCb = 0, totTr = 0;
      for (const r of batches) {
        if (r.name !== cur) {
          if (cur !== null) { rows.push(['TOTAL', '', subCb, subTr]); rows.push(['', '', '', '']); }
          cur = r.name; subCb = 0; subTr = 0;
          rows.push(['▶ ' + r.name.toUpperCase(), '', '', '']);
        }
        rows.push([r.d, r.code, r.cbLeft, r.trLeft]);
        subCb += r.cbLeft; subTr += r.trLeft; totCb += r.cbLeft; totTr += r.trLeft;
      }
      if (cur !== null) { rows.push(['TOTAL', '', subCb, subTr]); rows.push(['', '', '', '']); }
      rows.push(['GRAND TOTAL', '', totCb, totTr]);
      return { columns: ['Mfg. Date / Product', 'Batch Code', 'CB', 'Trays'], rows };
    },
  },
`;
src = src.slice(0, start) + NEW + src.slice(end);
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 400)); process.exit(3); }
console.log('GROUPED LAYOUT ✓');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "BATCHSTOCK2 FAIL"; exit 1; fi

systemctl restart flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo ""
echo "BATCHSTOCK2 VERIFIED ✓ — Reports → Batch-wise Stock hun sheet-style grouped hai (per-product TOTAL + GRAND TOTAL)"
