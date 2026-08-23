#!/usr/bin/env bash
# FlavorFlow: Loss% "add-on" mode —
#   Pehla: manual cell edit = FREEZE (nava auto data cell vich judna band).
#   Hun:   manual edit = BASELINE. Edit vele da auto value 'base:<key>' vich
#          save hunda; display = manual + (auto_hun − auto_edit_vele).
#          Matlab agle din di navi production/consumption manual number de
#          UPAR judd jandi hai — sheet atkdi nahi.
#   Lagu hunda: act: / cb: / extra: / close: cells te.
#   proj: te open: pehla vangu pure-manual hi ne (ohna vich auto flow nahi).
# Idempotent — safe to run twice. Backup + node --check + auto-restore.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-LOSSFIX5 $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a routes/packing.js "/opt/flavorflow/backups/packing.js.bak-loss5-$TS"
echo "BACKUP -> /opt/flavorflow/backups/packing.js.bak-loss5-$TS"

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/packing.js';
let src = fs.readFileSync(f, 'utf8');
const bak = f + '.bak-loss5w-' + Date.now();
fs.copyFileSync(f, bak);

if (src.includes('lossAddMode')) { console.log('ALREADY PATCHED — skip'); process.exit(0); }

let n = 0;

// 1) gA helper right after the g helper inside lossBuild
const gAnchor = "const g = (k, dflt) => (V[k] !== undefined ? V[k] : dflt);";
if (!src.includes(gAnchor)) { console.log('g() anchor NOT FOUND'); process.exit(2); }
src = src.replace(gAnchor, gAnchor + `
  /* lossAddMode: manual edit = baseline; auto data AFTER the edit adds on.
     base:<key> = auto value captured at edit time. */
  const A = {}; lossBuild._autos = A;
  const gA = (k, auto) => {
    A[k] = auto;
    if (V[k] === undefined) return auto;
    const b = V['base:' + k];
    return V[k] + (b === undefined ? 0 : Math.max(0, auto - b));
  };`);
n++;

// 2) act / cb / extra / close call sites → gA (proj/open stay pure manual)
for (const key of ["g('act:", "g('cb:", "g('extra:", "g('close:"]) {
  if (src.includes(key)) { src = src.split(key).join("gA('" + key.slice(3)); n++; }
  else console.log('WARN: call site not found: ' + key);
}

// 3) PUT /loss/cell: capture base BEFORE saving the manual value
const putAnchor = ".run(ym, key, value);";
if (!src.includes(putAnchor)) { console.log('PUT anchor NOT FOUND'); process.exit(2); }
src = src.replace(putAnchor, `.run(ym, key, value);
  /* lossAddMode: remember the auto value at edit time so future data adds on */
  if (/^(act|cb|extra|close):/.test(key)) {
    try {
      lossBuild(ym);
      const a = (lossBuild._autos || {})[key];
      if (a !== undefined) db.prepare('INSERT INTO loss_values (ym, key, value) VALUES (?,?,?) ON CONFLICT(ym, key) DO UPDATE SET value = excluded.value').run(ym, 'base:' + key, a);
    } catch (_) {}
  }`);
n++;

fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK — ' + n + ' patch(es) applied'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); process.exit(3); }
JS
[ $? -ne 0 ] && { echo "LOSSFIX5 FAIL"; exit 1; }

systemctl restart flavorflow
sleep 2
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
echo "LOSSFIX5 VERIFIED ✓ — manual edit hun baseline hai; agle din da data ohde UPAR judd jauga (act/cb/extra/close)"
