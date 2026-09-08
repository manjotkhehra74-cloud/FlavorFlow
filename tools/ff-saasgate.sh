#!/usr/bin/env bash
# FlavorFlow SaaS P1b: GATEWAY (nave SaaS VM te chalauni) —
#   1) ~/flavorflow-server-pack.tar.gz → /opt/flavorflow-saas/core (unpack + npm install)
#   2) Node check: core da sqlite wrapper (DatabaseSync) je Node 22 mangda hai
#      ta Node 22 install (data-driven test, guess nahi)
#   3) server.js listen() nu PORT env respect karauna (je hardcoded hai)
#   4) Gateway (port 4100): 
#        POST /api/saas/register  → navi company: code + vakhri DB + vakhra process + 30-din trial
#        /t/<code>/api/*          → us company de process val proxy (trial-check naal)
#        GET /api/saas/health     → status
#   5) Caddy: /t/* vi proxy + reload
#   Har company = apna process + apni erp.db (data/tenant-<code>/) — poora vakhra.
# Idempotent. Backups + node --check + auto-restore.
set -u
BASE=/opt/flavorflow-saas
echo "=== FF-SAASGATE $(date) ==="

PACK="/home/manjotkhehra74/flavorflow-server-pack.tar.gz"
[ -f "$PACK" ] || PACK="$HOME/flavorflow-server-pack.tar.gz"
[ -f "$PACK" ] || { echo "FATAL: flavorflow-server-pack.tar.gz nahi labhi (~ vich pao)"; exit 1; }

# 1) unpack core
mkdir -p "$BASE/core" "$BASE/data" "$BASE/server" "$BASE/backups"
tar xzf "$PACK" -C "$BASE/core"
echo "core unpacked ✓ ($(ls $BASE/core | wc -l) items)"

# 2) npm install
cd "$BASE/core"
npm install --omit=dev >/dev/null 2>&1
echo "npm install ✓"

# 3) Node capability test (sqlite wrapper)
if ! node -e "require('$BASE/core/sqlite')" >/dev/null 2>&1; then
  echo "sqlite wrapper current Node te nahi chalda — Node 22 install..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
  apt-get install -y nodejs >/dev/null 2>&1
  node -e "require('$BASE/core/sqlite')" >/dev/null 2>&1 && echo "node $(node -v) ✓ (sqlite OK)" || { echo "FATAL: sqlite wrapper fer vi fail — output bhejo"; node -e "require('$BASE/core/sqlite')" 2>&1 | head -5; exit 1; }
else
  echo "node $(node -v) ✓ (sqlite OK)"
fi

# 4) listen() PORT patch (je hardcoded)
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow-saas/core/server.js';
let src = fs.readFileSync(f, 'utf8');
const bak = f + '.bak-gate-' + Date.now();
if (/listen\(\s*process\.env\.PORT/.test(src)) { console.log('listen: already PORT-aware ✓'); process.exit(0); }
const m = src.match(/listen\(\s*(\d+)/);
if (!m) { console.log('listen: pattern nahi labhya — eh line bhejo:'); console.log(src.split('\n').filter(l=>l.includes('listen')).join('\n')); process.exit(1); }
fs.copyFileSync(f, bak);
src = src.replace(/listen\(\s*\d+/, 'listen(process.env.PORT || ' + m[1]);
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('listen: PORT env patch ✓'); }
catch (e) { fs.copyFileSync(bak, f); console.log('listen patch SYNTAX FAIL — RESTORED'); process.exit(1); }
JS
[ $? -ne 0 ] && { echo "SAASGATE FAIL (listen patch)"; exit 1; }

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
echo "SAASGATE VERIFIED ✓ — registration test: is VM te chalao:"
echo "  curl -s -X POST https://flavorflow.co.in/api/saas/register -H 'Content-Type: application/json' -d '{\"company\":\"Test Foods\",\"industry\":\"Sauces & Condiments\"}'"
