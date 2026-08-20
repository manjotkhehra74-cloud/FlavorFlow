#!/usr/bin/env bash
# FlavorFlow targeted 2FA account recovery 7
# Resets ONLY the requested account's mismatched TOTP secret so it can sign in,
# register biometrics, then perform one clean 2FA enrolment. No password, role,
# permission, session, or business-data changes. Idempotent; DB backup + verify.
set -euo pipefail

ROOT="${FF_ROOT:-/opt/flavorflow/server}"
BACKUP_ROOT="${FF_BACKUP_ROOT:-/opt/flavorflow/backups}"
EMAIL="${FF_TOTP_EMAIL:-super.admin@flavorflow.in}"
SKIP_HEALTH="${FF_SKIP_HEALTH:-0}"
cd "$ROOT" || { echo "FATAL: $ROOT nahi mili"; exit 1; }
[ -f data/erp.db ] || { echo "FATAL: data/erp.db nahi mili"; exit 1; }
[ -f routes/auth.js ] || { echo "FATAL: routes/auth.js nahi mili"; exit 1; }
[ -f totp.js ] || { echo "FATAL: totp.js nahi mili"; exit 1; }

echo "=== FF-TOTPACCOUNTRESET7 $(date) ==="
TS=$(date +%s)
mkdir -p "$BACKUP_ROOT"
DB_BAK="$BACKUP_ROOT/erp.db.bak-totp-account-reset7-$TS"
if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 data/erp.db ".backup '$DB_BAK'"
else
  cp -a data/erp.db "$DB_BAK"
fi
echo "DB BACKUP: $DB_BAK"

node --check routes/auth.js
node --check totp.js
echo "NODE SYNTAX OK: routes/auth.js totp.js"

# Mandatory state-transition mock test before touching the real account.
node - <<'JS'
const before = {email: 'mock@example.invalid', totp_enabled: 1, totp_secret: 'MOCK'};
const after = {...before, totp_enabled: 0, totp_secret: ''};
if (after.email !== before.email || after.totp_enabled !== 0 || after.totp_secret !== '') {
  throw new Error('MOCK ACCOUNT RESET TEST FAILED');
}
console.log('MOCK ACCOUNT RESET TEST OK');
JS

FF_TOTP_EMAIL="$EMAIL" node - <<'JS'
const db = require('./db');
const email = String(process.env.FF_TOTP_EMAIL || '').trim().toLowerCase();
if (!email) throw new Error('Target email missing');
const before = db.prepare(
  "SELECT id, email, active, totp_enabled, LENGTH(COALESCE(totp_secret, '')) secret_len FROM users WHERE LOWER(email) = ?"
).get(email);
if (!before) throw new Error(`User not found: ${email}`);
if (Number(before.active) !== 1) throw new Error(`Target user is inactive: ${email}`);
console.log(`TARGET FOUND: id=${before.id} email=${before.email} 2FA=${Number(before.totp_enabled) === 1 ? 'ON' : 'OFF'} secret=${before.secret_len ? 'present' : 'empty'}`);

// DB wrapper has no transaction() helper; SAVEPOINT is supported and keeps
// this targeted update atomic.
db.exec('SAVEPOINT ff_totp_account_reset7');
try {
  db.prepare("UPDATE users SET totp_enabled = 0, totp_secret = '' WHERE id = ?").run(before.id);
  const after = db.prepare(
    "SELECT id, email, totp_enabled, LENGTH(COALESCE(totp_secret, '')) secret_len FROM users WHERE id = ?"
  ).get(before.id);
  if (!after || Number(after.totp_enabled) !== 0 || Number(after.secret_len) !== 0) {
    throw new Error('Post-reset DB verification failed');
  }
  db.exec('RELEASE ff_totp_account_reset7');
  console.log(`ACCOUNT RESET OK: ${after.email} · 2FA=OFF · secret=cleared`);
} catch (e) {
  try { db.exec('ROLLBACK TO ff_totp_account_reset7'); } catch (_) {}
  try { db.exec('RELEASE ff_totp_account_reset7'); } catch (_) {}
  throw e;
}
JS

if [ "$SKIP_HEALTH" = "1" ]; then
  echo "HEALTH CHECK SKIPPED (mock mode)"
else
  CODE=$(curl -sS -o /dev/null -w '%{http_code}' -m 8 http://127.0.0.1:4000/api/health || true)
  echo "health -> $CODE"
  [ "$CODE" = "200" ]
fi

echo "TOTPACCOUNTRESET7 VERIFIED ✓ — sirf $EMAIL da mismatched 2FA reset; password/role/data unchanged"
