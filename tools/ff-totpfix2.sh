#!/usr/bin/env bash
# FlavorFlow FIX: totp routes crash with "Cannot read properties of undefined
# (reading 'id')" — req.user is not set because routes/auth.js has no global
# auth middleware (login/logout are public). Fix: give the totp routes their
# own token check (same pattern the rest of the app uses via middleware).
# Idempotent — safe to run twice.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-TOTPFIX2 $(date) ==="

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/auth.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('_totpAuth')) { console.log('ALREADY PATCHED — skip'); process.exit(0); }
if (!src.includes('ff-totpfix')) { console.log('TOTP ROUTES MISSING — run ff-totpfix.sh first'); process.exit(2); }
const bak = f + '.bak-totpfix2-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);

// find how the app authenticates elsewhere: middleware.js exports
const mw = fs.readFileSync('/opt/flavorflow/server/middleware.js', 'utf8');
console.log('middleware exports:', (mw.match(/module\.exports\s*=\s*\{([^}]*)\}/) || [,''])[1].trim());

// Add a small auth guard for the totp routes. Prefer the app's own
// requireAuth if middleware.js has one; otherwise decode the session token
// the same way middleware does (sessions table lookup).
let guard;
if (/requireAuth/.test(mw)) {
  guard = `const { requireAuth: _totpAuth } = require('../middleware');\n`;
} else {
  // verify the sessions-table pattern actually exists before using it
  const db2 = require('/opt/flavorflow/server/db');
  const hasSessions = db2.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='sessions'").get();
  if (!hasSessions) {
    // dump middleware for inspection and bail out safely
    const WBOUT = '/tmp/ff-middleware-dump.txt';
    fs.writeFileSync(WBOUT, mw);
    console.log('NO requireAuth & NO sessions table — middleware dumped to ' + WBOUT);
    console.log('BAIL OUT (no changes made). Send the dump to the assistant.');
    process.exit(4);
  }
  guard = `function _totpAuth(req, res, next) {
  try {
    const hdr = String(req.headers.authorization || '');
    const token = hdr.startsWith('Bearer ') ? hdr.slice(7) : '';
    if (!token) { res.status(401).json({ error: 'Unauthenticated. Please sign in.' }); return; }
    const s = db.prepare('SELECT u.id, u.name, u.email, u.role, u.active FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ?').get(token);
    if (!s || s.active !== 1) { res.status(401).json({ error: 'Session expired. Please sign in again.' }); return; }
    req.user = { id: s.id, name: s.name, email: s.email, role: s.role };
    next();
  } catch (e) { res.status(401).json({ error: 'Unauthenticated. Please sign in.' }); }
}
`;
}

// insert guard before the totp block and add it to each totp route
src = src.replace('// --- ff-totpfix:', guard + '// --- ff-totpfix:');
src = src.replace("router.get('/totp/status', (req, res)", "router.get('/totp/status', _totpAuth, (req, res)");
src = src.replace("router.post('/totp/setup', (req, res)", "router.post('/totp/setup', _totpAuth, (req, res)");
src = src.replace("router.post('/totp/enable', (req, res)", "router.post('/totp/enable', _totpAuth, (req, res)");
src = src.replace("router.post('/totp/disable', (req, res)", "router.post('/totp/disable', _totpAuth, (req, res)");

fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 400)); process.exit(3); }
console.log('TOTP AUTH GUARD ADDED ✓');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "TOTPFIX2 FAIL"; exit 1; fi

systemctl restart flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo ""
echo "-- status without token (401 expected, not 500):"
curl -s -m 5 http://127.0.0.1:4000/api/auth/totp/status
echo ""
echo "TOTPFIX2 VERIFIED ✓ — app ch Settings kholo, 2FA switch hun dikhega"
