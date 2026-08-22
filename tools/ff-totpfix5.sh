#!/usr/bin/env bash
# FlavorFlow TOTP Fix 5
# Robust RFC-6238 implementation, explicit QR parameters, NTP check and safe
# clock-drift window. Clears only unfinished (totp_enabled=0) setup secrets so
# exposed/stale QR codes cannot be reused. Existing enabled 2FA users untouched.
# Idempotent; DB/file backups; mock-compatible; node checks + auto-restore.
set -euo pipefail

ROOT="${FF_ROOT:-/opt/flavorflow/server}"
BACKUP_ROOT="${FF_BACKUP_ROOT:-/opt/flavorflow/backups}"
SERVICE="${FF_SERVICE:-flavorflow}"
SKIP_SERVICE="${FF_SKIP_SERVICE:-0}"
cd "$ROOT" || { echo "FATAL: $ROOT nahi mili"; exit 1; }
[ -f routes/auth.js ] || { echo "FATAL: routes/auth.js nahi mili"; exit 1; }
[ -f totp.js ] || { echo "FATAL: totp.js nahi mili — pehla ff-totpfix.sh run karo"; exit 1; }

echo "=== FF-TOTPFIX5 $(date) ==="
TS=$(date +%s)
mkdir -p "$BACKUP_ROOT"
AUTH_BAK="$BACKUP_ROOT/auth.js.bak-totp5-$TS"
TOTP_BAK="$BACKUP_ROOT/totp.js.bak-totp5-$TS"
cp -a routes/auth.js "$AUTH_BAK"
cp -a totp.js "$TOTP_BAK"
echo "BACKUP: routes/auth.js -> $AUTH_BAK"
echo "BACKUP: totp.js -> $TOTP_BAK"

if [ -f data/erp.db ]; then
  DB_BAK="$BACKUP_ROOT/erp.db.bak-totp5-$TS"
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 data/erp.db ".backup '$DB_BAK'"
  else
    cp -a data/erp.db "$DB_BAK"
  fi
  echo "BACKUP: data/erp.db -> $DB_BAK"
fi

restore_files() {
  trap - ERR
  echo "AUTO-RESTORE: TOTP files"
  cp -a "$AUTH_BAK" routes/auth.js
  cp -a "$TOTP_BAK" totp.js
  if [ "$SKIP_SERVICE" != "1" ]; then systemctl restart "$SERVICE" || true; fi
}
trap 'rc=$?; restore_files; exit $rc' ERR

cat > totp.js <<'JS'
'use strict';
/** ff-totpfix5 — RFC 6238 TOTP, SHA1, 6 digits, 30-second period. */
const crypto = require('crypto');
const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function b32encode(buf) {
  let bits = 0, value = 0, out = '';
  for (const byte of buf) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += B32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
    value = bits ? value & ((1 << bits) - 1) : 0;
  }
  if (bits) out += B32[(value << (5 - bits)) & 31];
  return out;
}

function b32decode(input) {
  const text = String(input || '').toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = 0, value = 0;
  const out = [];
  for (const ch of text) {
    value = (value << 5) | B32.indexOf(ch);
    bits += 5;
    while (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
    value = bits ? value & ((1 << bits) - 1) : 0;
  }
  return Buffer.from(out);
}

function newSecret() {
  return b32encode(crypto.randomBytes(20));
}

function codeAt(secret, epochSeconds = Math.floor(Date.now() / 1000), digits = 6) {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(Number(epochSeconds) / 30)));
  const digest = crypto.createHmac('sha1', b32decode(secret)).update(counter).digest();
  const offset = digest[digest.length - 1] & 15;
  const binary = digest.readUInt32BE(offset) & 0x7fffffff;
  return String(binary % (10 ** digits)).padStart(digits, '0');
}

function verify(secret, suppliedCode) {
  const code = String(suppliedCode || '').replace(/\s+/g, '');
  if (!secret || !/^\d{6}$/.test(code)) return false;
  const now = Math.floor(Date.now() / 1000);
  // Current step plus two either side = safe ±60-second device drift.
  for (let step = -2; step <= 2; step++) {
    const expected = codeAt(secret, now + step * 30);
    if (crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(code))) return true;
  }
  return false;
}

module.exports = {newSecret, codeAt, verify};
JS

node - <<'JS'
const fs = require('fs');
const file = 'routes/auth.js';
let source = fs.readFileSync(file, 'utf8');

function patchAuth(text) {
  if (text.includes('ff-totpfix5-explicit-uri')) return text;
  const oldUri = "otpauth: 'otpauth://totp/' + label + '?secret=' + secret + '&issuer=' + encodeURIComponent('FlavorFlow ERP')";
  if (!text.includes(oldUri)) {
    throw new Error('Expected TOTP otpauth URI line not found — auth.js unchanged');
  }
  const newUri = "otpauth: 'otpauth://totp/' + label + '?secret=' + secret + '&issuer=' + encodeURIComponent('FlavorFlow ERP') + '&algorithm=SHA1&digits=6&period=30' /* ff-totpfix5-explicit-uri */";
  return text.replace(oldUri, newUri);
}

// Mandatory mock test before touching the real route file.
const mock = "res.json({ secret, otpauth: 'otpauth://totp/' + label + '?secret=' + secret + '&issuer=' + encodeURIComponent('FlavorFlow ERP') });";
const tested = patchAuth(mock);
if (!tested.includes('algorithm=SHA1&digits=6&period=30') || !tested.includes('ff-totpfix5-explicit-uri')) {
  throw new Error('MOCK AUTH PATCH TEST FAILED');
}
console.log('MOCK AUTH PATCH TEST OK');

const updated = patchAuth(source);
fs.writeFileSync(file, updated);
console.log(updated === source ? 'AUTH URI: already explicit' : 'AUTH URI: SHA1 / 6 digits / 30 seconds explicit');
JS

node --check totp.js
node --check routes/auth.js
node - <<'JS'
const t = require('./totp');
// RFC 6238 Appendix B secret at Unix time 59: 8-digit value is 94287082,
// therefore its final 6 digits must be 287082.
const known = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
if (t.codeAt(known, 59) !== '287082') throw new Error('RFC 6238 known-vector failed');
const fresh = t.newSecret();
const current = t.codeAt(fresh);
if (!t.verify(fresh, current)) throw new Error('Generated current-code verification failed');
if (t.verify(fresh, '000000') && current !== '000000') throw new Error('Wrong-code rejection failed');
console.log('RFC 6238 SELF-TEST OK');
JS

echo "NODE SYNTAX OK: totp.js routes/auth.js"

if [ "$SKIP_SERVICE" = "1" ]; then
  echo "NTP/SERVICE/DB RESET SKIPPED (mock mode)"
else
  timedatectl set-ntp true 2>/dev/null || true
  echo "TIME: $(date --iso-8601=seconds)"
  echo "NTP synchronized: $(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"

  systemctl restart "$SERVICE"
  sleep 2
  systemctl is-active --quiet "$SERVICE"
  CODE=$(curl -sS -o /dev/null -w '%{http_code}' -m 8 http://127.0.0.1:4000/api/health || true)
  echo "health -> $CODE"
  [ "$CODE" = "200" ]

  # Rotate only incomplete setup secrets (including the one exposed in the
  # screenshot). Enabled accounts remain fully untouched.
  node - <<'JS'
const db = require('./db');
const before = Number(db.prepare("SELECT COUNT(*) n FROM users WHERE totp_enabled = 0 AND COALESCE(totp_secret, '') <> ''").get().n);
db.prepare("UPDATE users SET totp_secret = '' WHERE totp_enabled = 0 AND COALESCE(totp_secret, '') <> ''").run();
console.log(`STALE/EXPOSED PENDING SECRETS CLEARED: ${before}`);
JS
fi

trap - ERR
echo "TOTPFIX5 VERIFIED ✓ — dialog band karke 2FA setup dubara kholo, nava QR scan karo"
