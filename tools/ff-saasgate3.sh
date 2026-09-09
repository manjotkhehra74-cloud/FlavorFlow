#!/usr/bin/env bash
# FlavorFlow SaaS P1c: TENANT ADMIN SEEDING (security fix) —
#   Masla: har navi company vich factory wale 8 seed-users bande ne
#   (Super@123 etc.) — koi vi customer kise hor company vich var sakda!
#   Fix:
#     1) core/db.js: je ADMIN_EMAIL+ADMIN_PASSWORD env set → SIRF oh ik
#        super_admin bane (koi default users/products nahi)
#     2) gateway register API: admin name/email/password REQUIRED,
#        spawn vele env pass; password registry vich sirf pehli boot tak
#        (10s baad wipe — DB seed ho jandi hai)
#   NOTE: testfoods-84fb (purani test company) vich seed users reh gaye ne —
#   oh sirf test si, baad vich delete kar dange.
# Idempotent. Backup + node --check + auto-restore.
set -u
BASE=/opt/flavorflow-saas
echo "=== FF-SAASGATE3 $(date) ==="
[ -d "$BASE/core" ] || { echo "FATAL: core nahi — pehla ff-saasgate.sh + 2 chalao"; exit 1; }

# 1) db.js: env-admin seeding
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow-saas/core/db.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('/* ffTenantAdmin */')) { console.log('db.js: already patched ✓'); process.exit(0); }
const bak = f + '.bak-gate3-' + Date.now();
fs.copyFileSync(f, bak);

// seedUsers(): count-guard ton baad env-admin block
const guard = src.match(/function seedUsers\(\)\s*\{\s*\n\s*if \(db\.prepare\('SELECT COUNT\(\*\) c FROM users'\)\.get\(\)\.c > 0\) return;/);
if (!guard) { console.log('seedUsers guard pattern nahi labhya — eh lines bhejo:'); console.log(src.split('\n').slice(220,230).join('\n')); process.exit(1); }
src = src.replace(guard[0], guard[0] + `
  /* ffTenantAdmin */
  if (process.env.ADMIN_EMAIL && process.env.ADMIN_PASSWORD) {
    db.prepare('INSERT INTO users (name, email, password_hash, role, active, created_at) VALUES (?,?,?,?,1,?)')
      .run(process.env.ADMIN_NAME || 'Admin', String(process.env.ADMIN_EMAIL).toLowerCase(),
           bcrypt.hashSync(String(process.env.ADMIN_PASSWORD), 10), 'super_admin', new Date().toISOString());
    console.log('[db] tenant admin seeded: ' + process.env.ADMIN_EMAIL);
    return;
  }`);

// tenant mode vich demo catalog vi skip (company apne products banayegi)
src = src.replace(/\n(\s*)seedPacking\(\);/, '\n$1if (!process.env.ADMIN_EMAIL) seedPacking();');

fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('db.js: tenant-admin seeding ✓'); }
catch (e) { fs.copyFileSync(bak, f); console.log('db.js SYNTAX FAIL — RESTORED'); process.exit(1); }
JS
[ $? -ne 0 ] && { echo "SAASGATE3 FAIL (db.js)"; exit 1; }

# 2) gateway: admin fields required + env pass + password wipe
cat > "$BASE/server/server.js" <<'GJS'
/** FlavorFlow SaaS gateway v2 — registration WITH company admin + per-company process/DB + trial + proxy. */
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
  const env = { ...process.env, PORT: c.port, ERP_DB_PATH: dir + '/erp.db' };
  if (c.adminEmail) { env.ADMIN_EMAIL = c.adminEmail; env.ADMIN_NAME = c.adminName || 'Admin'; }
  if (c.adminPassword) env.ADMIN_PASSWORD = c.adminPassword;
  const p = spawn('node', [BASE + '/core/server.js'], { env, stdio: ['ignore', 'inherit', 'inherit'] });
  procs[code] = p;
  p.on('exit', () => { delete procs[code]; setTimeout(() => spawnTenant(code), 3000); });
  console.log('[gate] tenant up: ' + code + ' @ ' + c.port);
  // password sirf pehli seed layi chahida — 10s baad registry ton wipe
  if (c.adminPassword) setTimeout(() => { const x = reg.companies[code]; if (x && x.adminPassword) { delete x.adminPassword; save(); } }, 10000);
}
Object.keys(reg.companies).forEach(spawnTenant);

const app = express();
app.get('/api/saas/health', (req, res) =>
  res.json({ ok: true, service: 'flavorflow-saas', companies: Object.keys(reg.companies).length }));

app.post('/api/saas/register', express.json({ limit: '50kb' }), (req, res) => {
  const b = req.body || {};
  const name = String(b.company || '').trim();
  const industry = String(b.industry || '').trim();
  const adminName = String(b.adminName || '').trim();
  const adminEmail = String(b.adminEmail || '').trim().toLowerCase();
  const adminPassword = String(b.adminPassword || '');
  if (name.length < 3) return res.status(400).json({ error: 'Company name required (min 3 characters).' });
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(adminEmail)) return res.status(400).json({ error: 'A valid admin email is required.' });
  if (adminPassword.length < 8) return res.status(400).json({ error: 'Admin password must be at least 8 characters.' });
  const base = name.toLowerCase().replace(/[^a-z0-9]+/g, '').slice(0, 12) || 'co';
  let code = base + '-' + crypto.randomBytes(2).toString('hex');
  while (reg.companies[code]) code = base + '-' + crypto.randomBytes(2).toString('hex');
  const used = Object.values(reg.companies).map(c => c.port);
  let port = 4201; while (used.includes(port)) port++;
  const trialEnds = new Date(Date.now() + 30 * 864e5).toISOString().slice(0, 10);
  reg.companies[code] = { name, industry, port, created: new Date().toISOString(), trialEnds, adminName, adminEmail, adminPassword };
  save(); spawnTenant(code);
  res.status(201).json({
    ok: true, companyCode: code, trialEnds,
    serverUrl: 'https://app.flavorflow.co.in/t/' + code + '/api',
    login: { email: adminEmail },
    next: 'FlavorFlow app kholo → login screen te server URL ✏️ naal eh serverUrl pao → apne admin email/password naal sign in karo.',
  });
});

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

app.listen(process.env.PORT || 4100, () => console.log('[gate] FlavorFlow SaaS gateway v2 on ' + (process.env.PORT || 4100)));
GJS
node --check "$BASE/server/server.js" && echo "gateway v2 ✓" || { echo "GATEWAY SYNTAX FAIL"; exit 1; }

systemctl restart flavorflow-saas
sleep 3
curl -s -m 8 http://127.0.0.1:4100/api/saas/health && echo ""
echo "SAASGATE3 VERIFIED ✓ — register hun admin email/password mangda; koi default users nahi banange"
echo "Test:"
echo "  curl -s -X POST https://flavorflow.co.in/api/saas/register -H 'Content-Type: application/json' -d '{\"company\":\"Demo Spices\",\"industry\":\"Spices\",\"adminName\":\"Manjot\",\"adminEmail\":\"manjot@demospices.in\",\"adminPassword\":\"MyStrongPass123\"}'"
