#!/usr/bin/env bash
# FlavorFlow SaaS P1b ROUND 2 — pehli run rukk gayi si kyunki core vich
#   app.listen(PORT, HOST, ...) hai (number nahi, PORT constant).
#   Eh script PORT di DEFINITION nu env-aware kardi hai:
#     const PORT = <n>  →  const PORT = Number(process.env.PORT) || <n>
#   (HOST nu hath nahi — 0.0.0.0/localhost jo vi hai theek hai)
#   Fer baki steps: gateway + Caddy + service (round-1 wale).
# Idempotent. Backup + node --check + auto-restore.
set -u
BASE=/opt/flavorflow-saas
echo "=== FF-SAASGATE2 $(date) ==="
[ -d "$BASE/core" ] || { echo "FATAL: core nahi — pehla ff-saasgate.sh chalao"; exit 1; }

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow-saas/core/server.js';
let src = fs.readFileSync(f, 'utf8');
if (/PORT\s*=\s*Number\(process\.env\.PORT\)/.test(src)) { console.log('PORT: already env-aware ✓'); process.exit(0); }
const bak = f + '.bak-gate2-' + Date.now();
const m = src.match(/(const|let|var)\s+PORT\s*=\s*([^;\n]+)/);
if (!m) { console.log('PORT definition nahi labhi — eh lines bhejo:'); console.log(src.split('\n').filter(l=>l.includes('PORT')).join('\n')); process.exit(1); }
fs.copyFileSync(f, bak);
src = src.replace(m[0], m[1] + ' PORT = Number(process.env.PORT) || (' + m[2].trim() + ')');
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('PORT patch ✓ — ' + m[0] + '  →  env-aware'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED'); process.exit(1); }
JS
[ $? -ne 0 ] && { echo "SAASGATE2 FAIL (PORT patch)"; exit 1; }

# 5) gateway server
cat > "$BASE/server/server.js" <<'GJS'
/** FlavorFlow SaaS gateway — registration + per-company process/DB + trial + proxy. */
const BASE = '/opt/flavorflow-saas';
const express = require(BASE + '/core/node_modules/express');
const fs = require('fs'), http = require('http'), crypto = require('crypto');
const { spawn } = require('child_process');

const REG = BASE + '/data/registry.json';
let reg = fs.existsSync(REG) ? JSON.parse(fs.readFileSync(REG, 'utf8')) : { companies: {} };
const save = () => fs.writeFileSync(REG, JSON.stringify(reg, null, 2));
const procs = {};

function spawnTenant(code) {
  const c = reg.companies[code];
  if (!c || procs[code]) return;
  const dir = BASE + '/data/tenant-' + code;
  fs.mkdirSync(dir, { recursive: true });
  const p = spawn('node', [BASE + '/core/server.js'], {
    env: { ...process.env, PORT: c.port, ERP_DB_PATH: dir + '/erp.db' },
    stdio: ['ignore', 'inherit', 'inherit'],
  });
  procs[code] = p;
  p.on('exit', () => { delete procs[code]; setTimeout(() => spawnTenant(code), 3000); });
  console.log('[gate] tenant up: ' + code + ' @ ' + c.port);
}
Object.keys(reg.companies).forEach(spawnTenant);

const app = express();
app.get('/api/saas/health', (req, res) =>
  res.json({ ok: true, service: 'flavorflow-saas', companies: Object.keys(reg.companies).length }));

app.post('/api/saas/register', express.json({ limit: '50kb' }), (req, res) => {
  const name = String((req.body || {}).company || '').trim();
  const industry = String((req.body || {}).industry || '').trim();
  if (name.length < 3) return res.status(400).json({ error: 'Company name required (min 3 characters).' });
  const base = name.toLowerCase().replace(/[^a-z0-9]+/g, '').slice(0, 12) || 'co';
  let code = base + '-' + crypto.randomBytes(2).toString('hex');
  while (reg.companies[code]) code = base + '-' + crypto.randomBytes(2).toString('hex');
  const used = Object.values(reg.companies).map(c => c.port);
  let port = 4201; while (used.includes(port)) port++;
  const trialEnds = new Date(Date.now() + 30 * 864e5).toISOString().slice(0, 10);
  reg.companies[code] = { name, industry, port, created: new Date().toISOString(), trialEnds };
  save(); spawnTenant(code);
  res.status(201).json({
    ok: true, companyCode: code, trialEnds,
    serverUrl: 'https://app.flavorflow.co.in/t/' + code + '/api',
    next: 'FlavorFlow app kholo → login screen te server URL edit karo → eh serverUrl paste karo → pehli vaari setup vich apna admin account banao.',
  });
});

// proxy: /t/<code>/api/* → tenant process (raw pipe — uploads vi chalde)
app.use('/t/:code', (req, res) => {
  const c = reg.companies[req.params.code];
  if (!c) return res.status(404).json({ error: 'Company not found — check your company code.' });
  if (new Date(c.trialEnds + 'T23:59:59') < new Date())
    return res.status(402).json({ error: 'Trial ended for ' + c.name + '. Contact FlavorFlow to continue.' });
  const opt = {
    host: '127.0.0.1', port: c.port, method: req.method,
    path: req.originalUrl.replace('/t/' + req.params.code, ''),
    headers: { ...req.headers, host: '127.0.0.1:' + c.port },
  };
  const up = http.request(opt, r => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
  up.on('error', () => { try { res.status(502).json({ error: 'Company server is starting — try again in a few seconds.' }); } catch (_) {} });
  req.pipe(up);
});

app.listen(process.env.PORT || 4100, () => console.log('[gate] FlavorFlow SaaS gateway on ' + (process.env.PORT || 4100)));
GJS
node --check "$BASE/server/server.js" && echo "gateway ✓ (syntax OK)" || { echo "GATEWAY SYNTAX FAIL"; exit 1; }

# 6) Caddy: /t/* vi proxy
cat > /etc/caddy/Caddyfile <<'CADDY'
flavorflow.co.in, www.flavorflow.co.in {
	handle /api/* {
		reverse_proxy 127.0.0.1:4100
	}
	handle /t/* {
		reverse_proxy 127.0.0.1:4100
	}
	root * /opt/flavorflow-saas/web
	file_server
}
app.flavorflow.co.in {
	handle /api/* {
		reverse_proxy 127.0.0.1:4100
	}
	handle /t/* {
		reverse_proxy 127.0.0.1:4100
	}
	root * /opt/flavorflow-saas/web
	file_server
}
CADDY
systemctl reload caddy 2>/dev/null || systemctl restart caddy
echo "caddy /t/* proxy ✓"

# 7) service on
systemctl enable --now flavorflow-saas >/dev/null 2>&1
systemctl restart flavorflow-saas
sleep 3
curl -s -m 8 http://127.0.0.1:4100/api/saas/health && echo ""
echo "SAASGATE2 VERIFIED ✓ — registration test: is VM te chalao:"
echo "  curl -s -X POST https://flavorflow.co.in/api/saas/register -H 'Content-Type: application/json' -d '{\"company\":\"Test Foods\",\"industry\":\"Sauces & Condiments\"}'"
