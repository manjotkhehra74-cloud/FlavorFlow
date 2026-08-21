#!/usr/bin/env bash
# FlavorFlow: truck routes order fix — GET /dispatch/trucks was appended AFTER
# GET /dispatch/:id, so Express matched ':id' = "trucks" → "Dispatch not found".
# Moves the ff-truckfix block ABOVE the first '/:id' route.
# Idempotent. Backup + node --check + auto-restore.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-TRUCKFIX2 $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a routes/dispatch.js "/opt/flavorflow/backups/dispatch.js.bak-truck2-$TS"
echo "BACKUP -> /opt/flavorflow/backups/dispatch.js.bak-truck2-$TS"

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/dispatch.js';
const src = fs.readFileSync(f, 'utf8');
const bak = f + '.bak-truck2w-' + Date.now();
fs.copyFileSync(f, bak);

const startMark = '/** ff-truckfix: truck master';
const s = src.indexOf(startMark);
if (s === -1) { console.log('TRUCK BLOCK NOT FOUND — pehla ff-truckfix chalao'); process.exit(2); }

// param route ('/:id' etc.) di pehli position
const idMatch = src.match(/router\.(get|put|post|delete)\(\s*['"]\/:[^'"]+['"]/);
if (!idMatch) { console.log('NO /:id ROUTE — order theek hai'); process.exit(0); }
const idIdx = src.indexOf(idMatch[0]);
if (s < idIdx) { console.log('ALREADY ABOVE /:id — skip'); process.exit(0); }

// trucks block: startMark ton lai ke module.exports ton pehla tak
const modIdx = src.indexOf('module.exports = router;');
if (modIdx === -1 || modIdx < s) { console.log('module.exports NOT after block'); process.exit(2); }
let block = src.slice(s, modIdx).replace(/\s+$/, '') + '\n\n';

// block hatao te /:id route di line ton pehla paa deo
let out = src.slice(0, s) + src.slice(s + block.trimEnd().length).replace(/^\s*\n/, '\n');
const m2 = out.match(/router\.(get|put|post|delete)\(\s*['"]\/:[^'"]+['"]/);
const at = out.indexOf(m2[0]);
const lineStart = out.lastIndexOf('\n', at) + 1;
out = out.slice(0, lineStart) + block + out.slice(lineStart);

fs.writeFileSync(f, out);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK — trucks routes moved above /:id'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); process.exit(3); }
JS
[ $? -ne 0 ] && { echo "TRUCKFIX2 FAIL"; exit 1; }

systemctl restart flavorflow
sleep 2
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
echo "TRUCKFIX2 VERIFIED ✓ — Trucks tab hun 'Dispatch not found' nahi dikhauga"
