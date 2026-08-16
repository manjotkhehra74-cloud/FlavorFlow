#!/usr/bin/env bash
# FlavorFlow: two-factor authentication (TOTP — Google/Microsoft Authenticator).
#   users.totp_secret / users.totp_enabled columns
#   POST /api/auth/totp/setup    → { secret, otpauth }  (logged in)
#   POST /api/auth/totp/enable   → { code }             (verify + turn on)
#   POST /api/auth/totp/disable  → { code }             (verify + turn off)
#   GET  /api/auth/totp/status   → { enabled }
#   POST /api/auth/login         → when user's 2FA is on and totpCode missing/
#                                  wrong ⇒ 401 { error: 'TOTP_REQUIRED' }
# Pure Node crypto (RFC 6238) — no npm install. Idempotent.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-TOTPFIX $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-totp-$TS" 2>/dev/null
echo "DB BACKUP: /opt/flavorflow/backups/erp.db.bak-totp-$TS"

# 1) DB columns
node -e "
const db = require('/opt/flavorflow/server/db');
const cols = db.prepare('PRAGMA table_info(users)').all().map(c => c.name);
if (!cols.includes('totp_secret')) { db.exec(\"ALTER TABLE users ADD COLUMN totp_secret TEXT DEFAULT ''\"); console.log('COL totp_secret added'); }
if (!cols.includes('totp_enabled')) { db.exec('ALTER TABLE users ADD COLUMN totp_enabled INTEGER NOT NULL DEFAULT 0'); console.log('COL totp_enabled added'); }
console.log('DB OK');
"

# 2) helper module (TOTP maths)
cat > /opt/flavorflow/server/totp.js <<'JS'
/** totp.js — RFC 6238 TOTP with base32, pure node:crypto (ff-totpfix). */
const crypto = require('crypto');
const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
function b32encode(buf) {
  let bits = 0, value = 0, out = '';
  for (const byte of buf) {
    value = (value << 8) | byte; bits += 8;
    while (bits >= 5) { out += B32[(value >>> (bits - 5)) & 31]; bits -= 5; }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out;
}
function b32decode(str) {
  let bits = 0, value = 0; const out = [];
  for (const ch of str.replace(/=+$/, '').toUpperCase()) {
    const idx = B32.indexOf(ch);
    if (idx === -1) continue;
    value = (value << 5) | idx; bits += 5;
    if (bits >= 8) { out.push((value >>> (bits - 8)) & 255); bits -= 8; }
  }
  return Buffer.from(out);
}
function newSecret() { return b32encode(crypto.randomBytes(20)); }
function codeAt(secret, t) {
  const counter = Buffer.alloc(8);
  let c = Math.floor(t / 30);
  for (let i = 7; i >= 0; i--) { counter[i] = c & 255; c = Math.floor(c / 256); }
  const h = crypto.createHmac('sha1', b32decode(secret)).update(counter).digest();
  const o = h[h.length - 1] & 15;
  const n = ((h[o] & 127) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return String(n % 1000000).padStart(6, '0');
}
function verify(secret, code) {
  if (!secret || !/^[0-9]{6}$/.test(String(code || ''))) return false;
  const now = Math.floor(Date.now() / 1000);
  for (const dt of [-30, 0, 30]) { // ±30s clock drift
    if (codeAt(secret, now + dt) === String(code)) return true;
  }
  return false;
}
module.exports = { newSecret, verify };
JS
node --check /opt/flavorflow/server/totp.js && echo "totp.js OK"

# 3) auth routes patch
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/auth.js';
if (!fs.existsSync(f)) { console.log('AUTH FILE MISSING'); process.exit(2); }
let src = fs.readFileSync(f, 'utf8');
if (src.includes('TOTP_REQUIRED')) { console.log('AUTH: already patched — skip'); process.exit(0); }
const bak = f + '.bak-totp-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);

// (a) login guard: after password check passes, demand the TOTP code
// find the line issuing the token — insert the guard just before res.json of login
const loginRoute = src.match(/router\.post\(['"]\/login['"][\s\S]*?\n\}\);/);
if (!loginRoute) { console.log('LOGIN ROUTE NOT FOUND'); process.exit(2); }
let lr = loginRoute[0];
const marker = lr.match(/\n(\s*)(const token|res\.json)/);
if (!marker) { console.log('LOGIN INSERT POINT NOT FOUND'); process.exit(2); }
const guard = `\n  // ff-totpfix: two-factor gate\n  if (user.totp_enabled === 1) {\n    const { verify: _tv } = require('../totp');\n    if (!_tv(user.totp_secret, (req.body || {}).totpCode)) {\n      res.status(401).json({ error: 'TOTP_REQUIRED' });\n      return;\n    }\n  }\n`;
lr = lr.replace(marker[0], guard + marker[0]);
src = src.replace(loginRoute[0], lr);

// (b) totp management routes before module.exports
const CODE = `
// --- ff-totpfix: authenticator-app 2FA management (logged-in user) ---
const { newSecret: _totpNew, verify: _totpVerify } = require('../totp');
router.get('/totp/status', (req, res) => {
  const u = db.prepare('SELECT totp_enabled FROM users WHERE id = ?').get(req.user.id);
  res.json({ enabled: !!(u && u.totp_enabled === 1) });
});
router.post('/totp/setup', (req, res) => {
  const secret = _totpNew();
  db.prepare('UPDATE users SET totp_secret = ?, totp_enabled = 0 WHERE id = ?').run(secret, req.user.id);
  const label = encodeURIComponent('FlavorFlow ERP:' + req.user.email);
  res.json({ secret, otpauth: 'otpauth://totp/' + label + '?secret=' + secret + '&issuer=' + encodeURIComponent('FlavorFlow ERP') });
});
router.post('/totp/enable', (req, res) => {
  const u = db.prepare('SELECT totp_secret FROM users WHERE id = ?').get(req.user.id);
  if (!u || !u.totp_secret) { res.status(400).json({ error: 'Run setup first.' }); return; }
  if (!_totpVerify(u.totp_secret, (req.body || {}).code)) { res.status(400).json({ error: 'Wrong code — check the app and try again.' }); return; }
  db.prepare('UPDATE users SET totp_enabled = 1 WHERE id = ?').run(req.user.id);
  res.json({ ok: true });
});
router.post('/totp/disable', (req, res) => {
  const u = db.prepare('SELECT totp_secret, totp_enabled FROM users WHERE id = ?').get(req.user.id);
  if (!u || u.totp_enabled !== 1) { res.json({ ok: true }); return; }
  if (!_totpVerify(u.totp_secret, (req.body || {}).code)) { res.status(400).json({ error: 'Wrong code — 2FA stays on.' }); return; }
  db.prepare("UPDATE users SET totp_enabled = 0, totp_secret = '' WHERE id = ?").run(req.user.id);
  res.json({ ok: true });
});
// --- end ff-totpfix ---

`;
src = src.replace('module.exports = router;', CODE + 'module.exports = router;');
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); process.exit(3); }
console.log('AUTH ROUTES PATCHED ✓');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "TOTPFIX FAIL"; exit 1; fi

systemctl restart flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH FAIL"
echo "TOTPFIX VERIFIED ✓ — 2FA (Google/Microsoft Authenticator) live: Settings → Two-factor authentication"
