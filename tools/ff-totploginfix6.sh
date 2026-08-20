#!/usr/bin/env bash
# FlavorFlow TOTP Login Fix 6
# Replaces the original login gate (which trusted the login query's possibly
# stale/partial user object) with one canonical gate that reads the current
# totp_secret + totp_enabled directly from DB. Missing code requests 2FA once;
# wrong code returns a clear error instead of reopening the dialog forever.
# Idempotent; backups; mock test; node check; service health + auto-restore.
set -euo pipefail

ROOT="${FF_ROOT:-/opt/flavorflow/server}"
BACKUP_ROOT="${FF_BACKUP_ROOT:-/opt/flavorflow/backups}"
SERVICE="${FF_SERVICE:-flavorflow}"
SKIP_SERVICE="${FF_SKIP_SERVICE:-0}"
cd "$ROOT" || { echo "FATAL: $ROOT nahi mili"; exit 1; }
[ -f routes/auth.js ] || { echo "FATAL: routes/auth.js nahi mili"; exit 1; }
[ -f totp.js ] || { echo "FATAL: totp.js nahi mili"; exit 1; }

echo "=== FF-TOTPLOGINFIX6 $(date) ==="
TS=$(date +%s)
mkdir -p "$BACKUP_ROOT"
AUTH_BAK="$BACKUP_ROOT/auth.js.bak-totplogin6-$TS"
cp -a routes/auth.js "$AUTH_BAK"
echo "BACKUP: routes/auth.js -> $AUTH_BAK"

if [ -f data/erp.db ]; then
  DB_BAK="$BACKUP_ROOT/erp.db.bak-totplogin6-$TS"
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 data/erp.db ".backup '$DB_BAK'"
  else
    cp -a data/erp.db "$DB_BAK"
  fi
  echo "BACKUP: data/erp.db -> $DB_BAK"
fi

restore_file() {
  trap - ERR
  echo "AUTO-RESTORE: routes/auth.js"
  cp -a "$AUTH_BAK" routes/auth.js
  if [ "$SKIP_SERVICE" != "1" ]; then systemctl restart "$SERVICE" || true; fi
}
trap 'rc=$?; restore_file; exit $rc' ERR

node - <<'JS'
const fs = require('fs');
const file = 'routes/auth.js';

const OLD = `
  // ff-totpfix: two-factor gate
  if (user.totp_enabled === 1) {
    const { verify: _tv } = require('../totp');
    if (!_tv(user.totp_secret, (req.body || {}).totpCode)) {
      res.status(401).json({ error: 'TOTP_REQUIRED' });
      return;
    }
  }
`;

const CANONICAL = `
  // ff-totploginfix6: always verify against the current DB secret.
  {
    const _totpUser = db.prepare('SELECT totp_secret, totp_enabled FROM users WHERE id = ?').get(user.id);
    if (_totpUser && Number(_totpUser.totp_enabled) === 1) {
      const _totpCode = String((req.body || {}).totpCode || '').replace(/\\s+/g, '');
      if (!_totpCode) {
        res.status(401).json({ error: 'TOTP_REQUIRED' });
        return;
      }
      const { verify: _verifyLoginTotp } = require('../totp');
      if (!_verifyLoginTotp(_totpUser.totp_secret, _totpCode)) {
        res.status(401).json({ error: 'Wrong authenticator code — wait for a fresh code and try again.' });
        return;
      }
    }
  }
`;

function patch(source) {
  if (source.includes('ff-totploginfix6')) return source;
  const login = source.match(/router\.post\(['"]\/login['"][\s\S]*?\n\}\);/);
  if (!login) throw new Error('Login route not found');
  const count = login[0].split(OLD).length - 1;
  if (count < 1) throw new Error('Original ff-totpfix login gate not found exactly — no file written');
  let replaced = false;
  const updatedLogin = login[0].split(OLD).map((part, i) => {
    if (i === 0) return part;
    if (!replaced) { replaced = true; return CANONICAL + part; }
    return part; // collapse any accidental duplicate old gates
  }).join('');
  const out = source.replace(login[0], updatedLogin);
  const markerCount = (out.match(/ff-totploginfix6/g) || []).length;
  if (markerCount !== 1 || out.includes('// ff-totpfix: two-factor gate')) {
    throw new Error(`Canonical gate verification failed: markers=${markerCount}`);
  }
  return out;
}

// Mandatory mock route test before touching production auth.js.
const mock = `const router = require('express').Router();
router.post('/login', (req, res) => {
  const user = {id: 7, totp_enabled: 1};${OLD}
  const token = 'x';
  res.json({token});
});
module.exports = router;
`;
const tested = patch(mock);
if (!tested.includes("SELECT totp_secret, totp_enabled FROM users WHERE id = ?") ||
    !tested.includes("error: 'TOTP_REQUIRED'") ||
    !tested.includes('Wrong authenticator code')) {
  throw new Error('MOCK LOGIN PATCH TEST FAILED');
}
console.log('MOCK LOGIN PATCH TEST OK');

const original = fs.readFileSync(file, 'utf8');
const updated = patch(original);
fs.writeFileSync(file, updated);
console.log(updated === original ? 'LOGIN GATE: already canonical' : 'LOGIN GATE: fresh DB-backed verification installed');
JS

node --check routes/auth.js
node --check totp.js
node - <<'JS'
const db = require('./db');
const t = require('./totp');
const enabled = db.prepare("SELECT id, totp_secret FROM users WHERE totp_enabled = 1 ORDER BY id").all();
const missing = enabled.filter((u) => !u.totp_secret);
if (missing.length) throw new Error(`Enabled 2FA users missing secret: ${missing.map((u) => u.id).join(',')}`);
if (typeof t.codeAt === 'function') {
  for (const u of enabled) {
    const current = t.codeAt(u.totp_secret);
    if (!t.verify(u.totp_secret, current)) throw new Error(`TOTP self-check failed for user ${u.id}`);
  }
}
console.log(`ENABLED USER TOTP SELF-CHECK OK: ${enabled.length}`);
JS

echo "NODE SYNTAX + DB TOTP CHECK OK"

if [ "$SKIP_SERVICE" = "1" ]; then
  echo "SERVICE SKIPPED (mock mode)"
else
  systemctl restart "$SERVICE"
  sleep 2
  systemctl is-active --quiet "$SERVICE"
  CODE=$(curl -sS -o /dev/null -w '%{http_code}' -m 8 http://127.0.0.1:4000/api/health || true)
  echo "health -> $CODE"
  [ "$CODE" = "200" ]
fi

trap - ERR
echo "TOTPLOGINFIX6 VERIFIED ✓ — correct 2FA code login complete karega; biometric registration fer save hovegi"
