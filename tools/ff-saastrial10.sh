#!/usr/bin/env bash
# FlavorFlow SaaS: trial 30 din → 10 din (user da faisla)
# Idempotent. Backup + node --check + auto-restore.
set -u
echo "=== FF-SAASTRIAL10 $(date) ==="
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow-saas/server/server.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('10 * 864e5')) { console.log('trial: already 10 din ✓'); process.exit(0); }
if (!src.includes('30 * 864e5')) { console.log('trial pattern nahi labhya — eh line bhejo:'); console.log(src.split('\n').filter(l=>l.includes('864e5')).join('\n')); process.exit(1); }
const bak = f + '.bak-trial10-' + Date.now();
fs.copyFileSync(f, bak);
src = src.replace('30 * 864e5', '10 * 864e5');
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('trial 30→10 din ✓'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED'); process.exit(1); }
JS
[ $? -ne 0 ] && { echo "TRIAL10 FAIL"; exit 1; }
systemctl restart flavorflow-saas
sleep 2
curl -s -m 8 http://127.0.0.1:4100/api/saas/health && echo ""
echo "SAASTRIAL10 VERIFIED ✓ — navi company nu hun 10 din trial milega (puraniyan te asar nahi)"
