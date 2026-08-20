#!/usr/bin/env bash
# FlavorFlow per-account 2FA hardening 8
# Every user gets an isolated pending secret. Starting/retrying setup cannot
# overwrite an already-enabled login secret; the pending secret is promoted
# atomically only after that same user enters a valid code.
# Idempotent; DB/file backup; mock patch; node check + auto-restore.
set -euo pipefail

ROOT="${FF_ROOT:-/opt/flavorflow/server}"
BACKUP_ROOT="${FF_BACKUP_ROOT:-/opt/flavorflow/backups}"
SERVICE="${FF_SERVICE:-flavorflow}"
SKIP_SERVICE="${FF_SKIP_SERVICE:-0}"
cd "$ROOT" || { echo "FATAL: $ROOT nahi mili"; exit 1; }
[ -f routes/auth.js ] || { echo "FATAL: routes/auth.js nahi mili"; exit 1; }
[ -f data/erp.db ] || { echo "FATAL: data/erp.db nahi mili"; exit 1; }

echo "=== FF-TOTPACCOUNTS8 $(date) ==="
TS=$(date +%s)
mkdir -p "$BACKUP_ROOT"
AUTH_BAK="$BACKUP_ROOT/auth.js.bak-totpaccounts8-$TS"
DB_BAK="$BACKUP_ROOT/erp.db.bak-totpaccounts8-$TS"
cp -a routes/auth.js "$AUTH_BAK"
if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 data/erp.db ".backup '$DB_BAK'"
else
  cp -a data/erp.db "$DB_BAK"
fi
echo "BACKUP: routes/auth.js -> $AUTH_BAK"
echo "BACKUP: data/erp.db -> $DB_BAK"

restore_auth() {
  trap - ERR
  echo "AUTO-RESTORE: routes/auth.js"
  cp -a "$AUTH_BAK" routes/auth.js
  if [ "$SKIP_SERVICE" != "1" ]; then systemctl restart "$SERVICE" || true; fi
}
trap 'rc=$?; restore_auth; exit $rc' ERR

# Additive schema change first; harmless if a later file check fails.
node - <<'JS'
const db = require('./db');
const cols = db.prepare('PRAGMA table_info(users)').all().map((c) => c.name);
if (!cols.includes('totp_pending_secret')) {
  db.exec("ALTER TABLE users ADD COLUMN totp_pending_secret TEXT NOT NULL DEFAULT ''");
  console.log('DB COLUMN ADDED: users.totp_pending_secret');
} else {
  console.log('DB COLUMN: users.totp_pending_secret already present');
}
JS

node - <<'JS'
const fs = require('fs');
const file = 'routes/auth.js';

function patch(source) {
  if (source.includes('ff-totpaccounts8')) return source;

  const setupOld = "db.prepare('UPDATE users SET totp_secret = ?, totp_enabled = 0 WHERE id = ?').run(secret, req.user.id);";
  const setupNew = "db.prepare('UPDATE users SET totp_pending_secret = ? WHERE id = ?').run(secret, req.user.id); // ff-totpaccounts8";

  const enableOld = `  const u = db.prepare('SELECT totp_secret FROM users WHERE id = ?').get(req.user.id);
  if (!u || !u.totp_secret) { res.status(400).json({ error: 'Run setup first.' }); return; }
  if (!_totpVerify(u.totp_secret, (req.body || {}).code)) { res.status(400).json({ error: 'Wrong code — check the app and try again.' }); return; }
  db.prepare('UPDATE users SET totp_enabled = 1 WHERE id = ?').run(req.user.id);`;
  const enableNew = `  const u = db.prepare('SELECT totp_secret, totp_pending_secret FROM users WHERE id = ?').get(req.user.id);
  const candidate = u && (u.totp_pending_secret || u.totp_secret);
  if (!candidate) { res.status(400).json({ error: 'Run setup first.' }); return; }
  if (!_totpVerify(candidate, (req.body || {}).code)) { res.status(400).json({ error: 'Wrong code — check the app and try again.' }); return; }
  db.prepare("UPDATE users SET totp_secret = ?, totp_pending_secret = '', totp_enabled = 1 WHERE id = ?").run(candidate, req.user.id);`;

  const disableOld = `db.prepare("UPDATE users SET totp_enabled = 0, totp_secret = '' WHERE id = ?").run(req.user.id);`;
  const disableNew = `db.prepare("UPDATE users SET totp_enabled = 0, totp_secret = '', totp_pending_secret = '' WHERE id = ?").run(req.user.id);`;

  if (!source.includes(setupOld)) throw new Error('TOTP setup update line not found');
  if (!source.includes(enableOld)) throw new Error('TOTP enable block not found');
  if (!source.includes(disableOld)) throw new Error('TOTP disable update line not found');

  const out = source
    .replace(setupOld, setupNew)
    .replace(enableOld, enableNew)
    .replace(disableOld, disableNew);
  if (!out.includes('ff-totpaccounts8') || !out.includes('totp_pending_secret')) {
    throw new Error('Per-account patch verification failed');
  }
  return out;
}

// Mandatory mock test before production auth.js is written.
const mock = `router.post('/totp/setup', authRequired, (req, res) => {
  const secret = _totpNew();
  db.prepare('UPDATE users SET totp_secret = ?, totp_enabled = 0 WHERE id = ?').run(secret, req.user.id);
});
router.post('/totp/enable', authRequired, (req, res) => {
  const u = db.prepare('SELECT totp_secret FROM users WHERE id = ?').get(req.user.id);
  if (!u || !u.totp_secret) { res.status(400).json({ error: 'Run setup first.' }); return; }
  if (!_totpVerify(u.totp_secret, (req.body || {}).code)) { res.status(400).json({ error: 'Wrong code — check the app and try again.' }); return; }
  db.prepare('UPDATE users SET totp_enabled = 1 WHERE id = ?').run(req.user.id);
});
db.prepare("UPDATE users SET totp_enabled = 0, totp_secret = '' WHERE id = ?").run(req.user.id);`;
const tested = patch(mock);
if (!tested.includes('totp_pending_secret = ? WHERE id = ?') ||
    !tested.includes("totp_pending_secret = '', totp_enabled = 1")) {
  throw new Error('MOCK PER-ACCOUNT PATCH TEST FAILED');
}
console.log('MOCK PER-ACCOUNT PATCH TEST OK');

const original = fs.readFileSync(file, 'utf8');
const updated = patch(original);
fs.writeFileSync(file, updated);
console.log(updated === original ? 'AUTH ROUTES: already hardened' : 'AUTH ROUTES: isolated pending-secret flow installed');
JS

node --check routes/auth.js
node --check totp.js
echo "NODE SYNTAX OK: routes/auth.js totp.js"

if [ "$SKIP_SERVICE" = "1" ]; then
  echo "SERVICE/MIGRATION SKIPPED (mock mode)"
else
  systemctl restart "$SERVICE"
  sleep 2
  systemctl is-active --quiet "$SERVICE"
  CODE=$(curl -sS -o /dev/null -w '%{http_code}' -m 8 http://127.0.0.1:4000/api/health || true)
  echo "health -> $CODE"
  [ "$CODE" = "200" ]

  # Move only old unfinished setup secrets. Enabled users keep their active
  # secret exactly as-is. Every row remains isolated by its own user id.
  node - <<'JS'
const db = require('./db');
const result = db.prepare(`UPDATE users
  SET totp_pending_secret = totp_secret, totp_secret = ''
  WHERE totp_enabled = 0
    AND COALESCE(totp_secret, '') <> ''
    AND COALESCE(totp_pending_secret, '') = ''`).run();
const bad = db.prepare("SELECT COUNT(*) n FROM users WHERE totp_enabled = 1 AND COALESCE(totp_secret, '') = ''").get().n;
if (Number(bad) !== 0) throw new Error(`Enabled 2FA users without active secret: ${bad}`);
console.log(`OLD UNFINISHED SETUPS MIGRATED: ${result.changes || 0}`);
console.log('ACCOUNT ISOLATION VERIFY OK');
JS
fi

trap - ERR
echo "TOTPACCOUNTS8 VERIFIED ✓ — har account da apna pending/active secret; ik user duje nu affect nahi karega"
