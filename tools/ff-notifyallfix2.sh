#!/usr/bin/env bash
# FlavorFlow notification coverage fix 2
# Every audited mutation now creates a notification for EVERY active user,
# including the person who made the entry. LOGIN and Loss% remain excluded by
# the existing ff-notifyfix wrapper.
# Idempotent; helper + DB backup; patch self-test; node --check + auto-restore.
set -euo pipefail

ROOT="${FF_ROOT:-/opt/flavorflow/server}"
SKIP_SERVICE="${FF_SKIP_SERVICE:-0}"
SERVICE="${FF_SERVICE:-flavorflow}"
BACKUP_ROOT="${FF_BACKUP_ROOT:-/opt/flavorflow/backups}"

cd "$ROOT" || { echo "FATAL: $ROOT nahi mili"; exit 1; }
echo "=== FF-NOTIFYALLFIX2 $(date) ==="

[ -f helpers.js ] || { echo "FATAL: helpers.js nahi mili"; exit 1; }
TS=$(date +%s)
mkdir -p "$BACKUP_ROOT"
HELPER_BAK="$BACKUP_ROOT/helpers.js.bak-notifyall2-$TS"
cp -a helpers.js "$HELPER_BAK"
echo "BACKUP: helpers.js -> $HELPER_BAK"

# No schema change is made, but keep a consistent safety backup for every
# production server patch.
if [ -f data/erp.db ]; then
  DB_BAK="$BACKUP_ROOT/erp.db.bak-notifyall2-$TS"
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 data/erp.db ".backup '$DB_BAK'"
  else
    cp -a data/erp.db "$DB_BAK"
  fi
  echo "BACKUP: data/erp.db -> $DB_BAK"
fi

HELPER_BAK="$HELPER_BAK" node - <<'JS'
const fs = require('fs');
const cp = require('child_process');
const file = 'helpers.js';
const backup = process.env.HELPER_BAK;

function patch(source) {
  if (!source.includes('ffBroadcast')) {
    throw new Error('ffBroadcast not found — pehla ff-notifyfix.sh run karo');
  }

  // Original ff-notifyfix deliberately excluded the actor. Replace that one
  // target query only; no audit or business behaviour is changed.
  const actorExcluded = /const\s+targets\s*=\s*db\.prepare\(\s*(['"])SELECT id FROM users WHERE active = 1 AND id <> \?\1\s*\)\.all\(\s*user\.id\s*\)\s*;/;
  const allActive = "const targets = db.prepare('SELECT id FROM users WHERE active = 1').all();";

  let out = source;
  if (actorExcluded.test(out)) {
    out = out.replace(actorExcluded, allActive);
  } else if (!/SELECT id FROM users WHERE active = 1(['"])\s*\)\.all\(\s*\)/.test(out)) {
    throw new Error('notification target query da expected pattern nahi milya — no file written');
  }

  out = out
    .replace(/\(except the\s+actor\)/gi, '(including the actor)')
    .replace(/except the person who did it/gi, 'including the person who did it');

  if (!out.includes('ff-notifyallfix2')) {
    const marker = '/* ff-notifyallfix2: broadcast audited actions to ALL active users, actor included. */\n';
    const at = out.indexOf('function ffBroadcast');
    if (at < 0) throw new Error('ffBroadcast function anchor missing');
    out = out.slice(0, at) + marker + out.slice(at);
  }
  return out;
}

// Mandatory mock test before touching the real helper.
const mock = `
function ffBroadcast(db, user) {
  const targets = db.prepare('SELECT id FROM users WHERE active = 1 AND id <> ?').all(user.id);
  return targets;
}
`;
const tested = patch(mock);
if (!tested.includes("WHERE active = 1').all()") || tested.includes('id <> ?') || !tested.includes('ff-notifyallfix2')) {
  throw new Error('MOCK PATCH TEST FAILED');
}
console.log('MOCK PATCH TEST OK');

const original = fs.readFileSync(file, 'utf8');
let updated;
try {
  updated = patch(original);
} catch (e) {
  console.error('PATCH FAIL:', e.message);
  process.exit(2);
}

if (updated === original) {
  console.log('ALREADY PATCHED — actor already included');
} else {
  fs.writeFileSync(file, updated);
  console.log('PATCHED: notification targets now include actor + all active users');
}

try {
  cp.execFileSync(process.execPath, ['--check', file], {stdio: 'pipe'});
  console.log('NODE SYNTAX OK');
} catch (e) {
  fs.copyFileSync(backup, file);
  console.error('NODE SYNTAX FAIL — helpers.js AUTO-RESTORED');
  console.error(String(e.stderr || e.message).slice(0, 500));
  process.exit(3);
}

const finalSource = fs.readFileSync(file, 'utf8');
if (!finalSource.includes('ff-notifyallfix2') || finalSource.includes('WHERE active = 1 AND id <> ?')) {
  fs.copyFileSync(backup, file);
  console.error('VERIFY FAIL — helpers.js AUTO-RESTORED');
  process.exit(4);
}
console.log('FILE VERIFY OK: ALL active users targeted');
JS

if [ "$SKIP_SERVICE" = "1" ]; then
  echo "SERVICE RESTART SKIPPED (mock mode)"
else
  systemctl restart "$SERVICE"
  sleep 2
  systemctl is-active --quiet "$SERVICE" || {
    echo "SERVICE FAIL — helpers.js restore karke restart kar reha"
    cp -a "$HELPER_BAK" helpers.js
    systemctl restart "$SERVICE" || true
    exit 1
  }
  CODE=$(curl -sS -o /dev/null -w '%{http_code}' -m 8 http://127.0.0.1:4000/api/health || true)
  echo "health -> $CODE"
  [ "$CODE" = "200" ] || {
    echo "HEALTH FAIL — helpers.js restore karke restart kar reha"
    cp -a "$HELPER_BAK" helpers.js
    systemctl restart "$SERVICE" || true
    exit 1
  }
fi

echo "NOTIFYALLFIX2 VERIFIED ✓ — har audited entry actor samet SARE active users nu notify karegi"
