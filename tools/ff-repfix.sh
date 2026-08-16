#!/usr/bin/env bash
# FlavorFlow FIX: add a "Batch Codes" column to the Dispatch Register report
# (routes/reports.js). Shows every batch code loaded on that truck, comma-
# separated. Idempotent — safe to run twice (second run skips).
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-REPFIX $(date) ==="
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/reports.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes("'Batch Codes'")) { console.log('FIX ALREADY PRESENT — skip'); process.exit(0); }

const bak = f + '.bak-repfix-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);

// 1) columns: add "Batch Codes" after Destination (unique to dispatch-register)
const c1 = "'Destination', 'Cartons', 'Trays', 'Bottles', 'Gross kg'";
if (!src.includes(c1)) { console.log('COLUMNS ANCHOR NOT FOUND'); process.exit(2); }
src = src.replace(c1, "'Destination', 'Batch Codes', 'Cartons', 'Trays', 'Bottles', 'Gross kg'");

// 2) SQL: subquery pulling all batch codes of that dispatch (comma separated)
const c2 = 'truck_number, destination,';
if (!src.includes(c2)) { console.log('SQL ANCHOR NOT FOUND'); process.exit(2); }
src = src.replace(c2, "truck_number, destination,\n                (SELECT GROUP_CONCAT(DISTINCT di.batch_code) FROM dispatch_items di WHERE di.dispatch_id = dispatches.id AND di.batch_code IS NOT NULL AND di.batch_code != '') batch_codes,");

// 3) row mapper: emit the new column after destination
const c3 = "r.destination || '—', r.total_cartons, r.total_trays, r.total_bottles, r.gross_weight]";
if (!src.includes(c3)) { console.log('MAPPER ANCHOR NOT FOUND'); process.exit(2); }
src = src.replace(c3, "r.destination || '—', r.batch_codes || '—', r.total_cartons, r.total_trays, r.total_bottles, r.gross_weight]");

fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); process.exit(3); }
try { cp.execSync('systemctl restart flavorflow'); console.log('SERVICE RESTARTED'); } catch (e) { console.log('RESTART FAIL: ' + e.message); process.exit(4); }
setTimeout(() => {
  try { console.log('HEALTH: ' + cp.execSync('curl -s -m 5 http://127.0.0.1:4000/api/health').toString().trim()); } catch (e) { console.log('HEALTH ERR'); }
  const s2 = fs.readFileSync(f, 'utf8');
  console.log(s2.includes("'Batch Codes'") && s2.includes('GROUP_CONCAT(DISTINCT di.batch_code)') ? 'PATCH VERIFIED ✓' : 'PATCH CHECK FAILED ✗');
}, 2000);
JS
# clean up the diagnostic dump from the web dir (no longer needed)
WB=$(find /opt/flavorflow /var/www /home /srv -maxdepth 6 -name main.dart.js -printf '%h\n' 2>/dev/null | head -1)
[ -n "${WB:-}" ] && rm -f "$WB/ff-repdump.txt" && echo "ff-repdump.txt removed"
echo "REPFIX DONE — app ch Dispatch Register kholo: Batch Codes column dikhega (PDF/Excel export vich vi)"
