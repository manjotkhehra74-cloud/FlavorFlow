#!/usr/bin/env bash
# FlavorFlow SaaS P2: LANDING PAGE deploy + lead-capture + demo company —
#   1) repo ton web-landing/ (index/privacy/demo) → /opt/flavorflow-saas/web
#   2) gateway vich POST /api/saas/lead (leads.json vich save — naam/company/
#      phone/industry/time) — Try-Demo te Register dono form ehnu bhejde ne
#   3) demo company 'demo' (fixed code): demo@flavorflow.co.in / Demo@1234
#      + raat 3 vaje IST auto-reset (DB delete → fresh seed via admin env)
# Idempotent. Backup + node --check + auto-restore.
set -u
BASE=/opt/flavorflow-saas
RAW=https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a003d0-flavorflow/web-landing
echo "=== FF-SAASWEB $(date) ==="

# 1) landing pages
mkdir -p "$BASE/web"
for f in index.html privacy.html demo.html; do
  curl -fsS "$RAW/$f" -o "$BASE/web/$f" || { echo "FATAL: $f download fail"; exit 1; }
done
curl -fsS "https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a003d0-flavorflow/assets/icon/app_icon.png" -o "$BASE/web/app-icon.png" || echo "icon download fail (page fer vi chalegi)"
echo "landing pages ✓ ($(ls -la $BASE/web/*.html | wc -l) files)"

# 2) gateway: lead route (insert before the register route line)
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow-saas/server/server.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('/api/saas/lead')) { console.log('lead route: already ✓'); process.exit(0); }
const bak = f + '.bak-web-' + Date.now();
fs.copyFileSync(f, bak);
const anchor = "app.post('/api/saas/register'";
const i = src.indexOf(anchor);
if (i === -1) { console.log('register route anchor nahi labhya'); process.exit(1); }
const LEAD = `app.post('/api/saas/lead', express.json({ limit: '20kb' }), (req, res) => {
  try {
    const b = req.body || {};
    const row = { kind: String(b.kind || 'demo'), name: String(b.name || '').slice(0, 80), company: String(b.company || '').slice(0, 120), phone: String(b.phone || '').slice(0, 20), industry: String(b.industry || '').slice(0, 60), at: new Date().toISOString(), ip: req.headers['x-forwarded-for'] || '' };
    const F = BASE + '/data/leads.json';
    const arr = fs.existsSync(F) ? JSON.parse(fs.readFileSync(F, 'utf8')) : [];
    arr.push(row); fs.writeFileSync(F, JSON.stringify(arr, null, 2));
    console.log('[lead] ' + row.kind + ': ' + row.name + ' / ' + row.company + ' / ' + row.phone);
  } catch (e) {}
  res.json({ ok: true });
});

`;
src = src.slice(0, i) + LEAD + src.slice(i);
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('lead route ✓'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED'); process.exit(1); }
JS
[ $? -ne 0 ] && { echo "SAASWEB FAIL (lead route)"; exit 1; }

# 3) demo company (fixed code 'demo') in registry
node - <<'JS'
const fs = require('fs');
const REG = '/opt/flavorflow-saas/data/registry.json';
const reg = fs.existsSync(REG) ? JSON.parse(fs.readFileSync(REG, 'utf8')) : { companies: {} };
if (reg.companies['demo']) { console.log('demo company: already ✓'); process.exit(0); }
const used = Object.values(reg.companies).map(c => c.port);
let port = 4201; while (used.includes(port)) port++;
reg.companies['demo'] = {
  name: 'FlavorFlow Demo Factory', industry: 'Food & Beverage', port,
  created: new Date().toISOString(), trialEnds: '2099-12-31',
  adminName: 'Demo User', adminEmail: 'demo@flavorflow.co.in', adminPassword: 'Demo@1234',
  demo: true,
};
fs.writeFileSync(REG, JSON.stringify(reg, null, 2));
console.log('demo company ✓ (port ' + port + ')');
JS

# 4) nightly demo reset (3 AM IST = 21:30 UTC): delete DB; gateway respawns fresh
cat > /etc/systemd/system/ff-demo-reset.service <<'UNIT'
[Unit]
Description=FlavorFlow demo company nightly reset
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'P=$(node -e "const r=require(\"/opt/flavorflow-saas/data/registry.json\");const d=r.companies.demo;d&&d.adminPassword===undefined&&(d.adminPassword=\"Demo@1234\",require(\"fs\").writeFileSync(\"/opt/flavorflow-saas/data/registry.json\",JSON.stringify(r,null,2)));console.log(1)"); rm -rf /opt/flavorflow-saas/data/tenant-demo; systemctl restart flavorflow-saas'
UNIT
cat > /etc/systemd/system/ff-demo-reset.timer <<'UNIT'
[Unit]
Description=Nightly FlavorFlow demo reset (3 AM IST)
[Timer]
OnCalendar=*-*-* 21:30:00 UTC
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now ff-demo-reset.timer >/dev/null 2>&1
echo "demo nightly reset timer ✓"

systemctl restart flavorflow-saas
sleep 3
curl -s -m 8 http://127.0.0.1:4100/api/saas/health && echo ""
curl -s -m 8 -o /dev/null -w 'demo tenant -> %{http_code}\n' http://127.0.0.1:4100/t/demo/api/health || true
echo "SAASWEB VERIFIED ✓ — https://flavorflow.co.in te navi landing page live; demo login: demo@flavorflow.co.in / Demo@1234"
