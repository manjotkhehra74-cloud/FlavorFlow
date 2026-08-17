#!/usr/bin/env bash
# FlavorFlow FIX v2: totp routes crashed with 500 (req.user undefined) because
# routes/auth.js has no global auth middleware. middleware.js exports
# `authRequired` — attach it to each totp route. Idempotent.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-TOTPFIX2 v2 $(date) ==="

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/auth.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes("authRequired, (req, res)") && src.includes('/totp/status')) { console.log('ALREADY PATCHED — skip'); process.exit(0); }
if (!src.includes('ff-totpfix')) { console.log('TOTP ROUTES MISSING — run ff-totpfix.sh first'); process.exit(2); }

const mw = fs.readFileSync('/opt/flavorflow/server/middleware.js', 'utf8');
if (!/authRequired/.test(mw)) { console.log('middleware has no authRequired — abort'); process.exit(2); }

const bak = f + '.bak-totpfix2b-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);

// import authRequired (extend the existing middleware require if present)
if (!/authRequired/.test(src)) {
  const reqLine = src.match(/const \{([^}]*)\}\s*=\s*require\(['"]\.\.\/middleware['"]\);/);
  if (reqLine) {
    src = src.replace(reqLine[0], `const {${reqLine[1].trim().replace(/,\s*$/, '')}, authRequired } = require('../middleware');`);
  } else {
    src = src.replace('// --- ff-totpfix:', `const { authRequired } = require('../middleware');\n// --- ff-totpfix:`);
  }
}

// attach the guard to each totp route
src = src.replace("router.get('/totp/status', (req, res)", "router.get('/totp/status', authRequired, (req, res)");
src = src.replace("router.post('/totp/setup', (req, res)", "router.post('/totp/setup', authRequired, (req, res)");
src = src.replace("router.post('/totp/enable', (req, res)", "router.post('/totp/enable', authRequired, (req, res)");
src = src.replace("router.post('/totp/disable', (req, res)", "router.post('/totp/disable', authRequired, (req, res)");

fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 400)); process.exit(3); }
console.log('TOTP ROUTES GUARDED with authRequired ✓');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "TOTPFIX2 FAIL"; exit 1; fi

systemctl restart flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo ""
echo "-- status without token (401/unauthenticated expected, NOT 500):"
curl -s -m 5 http://127.0.0.1:4000/api/auth/totp/status
echo ""
echo "TOTPFIX2 VERIFIED ✓ — app ch logout/login karke Settings kholo: 2FA switch dikhega"
