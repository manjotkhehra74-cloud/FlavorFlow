#!/usr/bin/env bash
# FlavorFlow: generate a NEW Google Play upload key (not the app signing key).
# Outputs a PKCS12 keystore, public PEM certificate, CircleCI Base64/credentials,
# and a ZIP in the SSH user's home. Secrets are never printed to terminal.
# Idempotent: an existing verified bundle is reused, never overwritten.
set -euo pipefail
umask 077

command -v openssl >/dev/null 2>&1 || { echo "FATAL: openssl nahi milia"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 nahi milia"; exit 1; }

OWNER="${FF_KEY_OWNER:-${SUDO_USER:-$(id -un)}}"
[ "$OWNER" != "root" ] || OWNER="manjotkhehra74"
OWNER_GROUP=$(id -gn "$OWNER")
DEFAULT_HOME=$(getent passwd "$OWNER" | cut -d: -f6)
OWNER_HOME="${FF_KEY_OUTPUT_HOME:-$DEFAULT_HOME}"
[ -n "$OWNER_HOME" ] && [ -d "$OWNER_HOME" ] || { echo "FATAL: output home for $OWNER nahi mili"; exit 1; }

OUT="$OWNER_HOME/flavorflow-new-upload-key"
ZIP="$OWNER_HOME/FlavorFlow-upload-key-reset-2026.zip"
P12="$OUT/flavorflow-upload-2026.p12"
PEM="$OUT/upload_certificate.pem"
B64="$OUT/ANDROID_KEYSTORE_BASE64.txt"
CREDS="$OUT/CircleCI-credentials.txt"
README="$OUT/README-FIRST.txt"
META="$OUT/.key-meta"
ALIAS="flavorflow-upload-2026"
TEMP_PRIVATE=""
trap 'if [ -n "${TEMP_PRIVATE:-}" ]; then rm -f "$TEMP_PRIVATE"; fi' EXIT

echo "=== FF-NEWUPLOADKEY9 $(date) ==="
echo "OWNER: $OWNER"

verify_bundle() {
  [ -s "$P12" ] && [ -s "$PEM" ] && [ -s "$B64" ] && [ -s "$CREDS" ] && [ -s "$META" ] || return 1
  # Values are generated as safe alphanumeric/hex text.
  # shellcheck disable=SC1090
  source "$META"
  [ "${KEY_ALIAS:-}" = "$ALIAS" ] || return 1
  openssl pkcs12 -in "$P12" -passin "pass:$STORE_PASSWORD" -noout >/dev/null 2>&1 || return 1
  openssl x509 -in "$PEM" -noout -checkend 86400 >/dev/null 2>&1 || return 1
  local decoded
  decoded=$(mktemp)
  base64 --decode "$B64" > "$decoded"
  cmp -s "$decoded" "$P12" || { rm -f "$decoded"; return 1; }
  rm -f "$decoded"
  return 0
}

if [ -d "$OUT" ]; then
  if verify_bundle; then
    echo "ALREADY GENERATED — verified existing upload-key bundle reuse hovega"
  else
    BACKUP="$OWNER_HOME/flavorflow-new-upload-key.partial-$(date +%Y%m%d-%H%M%S)"
    mv "$OUT" "$BACKUP"
    echo "PARTIAL OLD FOLDER BACKUP: $BACKUP"
  fi
fi

if [ ! -d "$OUT" ]; then
  mkdir -p "$OUT"
  STORE_PASSWORD=$(openssl rand -hex 16)
  TEMP_PRIVATE=$(mktemp)

  # A self-signed X.509 certificate is correct for a Google Play upload key:
  # Play registers only this public certificate; the private key stays in P12.
  openssl req -x509 -newkey rsa:4096 -sha256 -days 10000 -nodes \
    -keyout "$TEMP_PRIVATE" \
    -out "$PEM" \
    -subj "/C=IN/ST=Punjab/L=Amritsar/O=FlavorFlow/OU=FlavorFlow/CN=Manjot Singh Khehra" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "subjectKeyIdentifier=hash" >/dev/null 2>&1

  openssl pkcs12 -export \
    -out "$P12" \
    -inkey "$TEMP_PRIVATE" \
    -in "$PEM" \
    -name "$ALIAS" \
    -passout "pass:$STORE_PASSWORD" >/dev/null 2>&1

  rm -f "$TEMP_PRIVATE"
  TEMP_PRIVATE=""

  base64 -w 0 "$P12" > "$B64"
  printf '\n' >> "$B64"

  cat > "$META" <<EOF
STORE_PASSWORD=$STORE_PASSWORD
KEY_ALIAS=$ALIAS
EOF

  cat > "$CREDS" <<EOF
CONFIDENTIAL — NEVER SHARE OR ADD TO GITHUB

ANDROID_KEYSTORE_PASSWORD=$STORE_PASSWORD
ANDROID_KEY_ALIAS=$ALIAS
ANDROID_KEY_PASSWORD=$STORE_PASSWORD
ANDROID_KEYSTORE_BASE64=copy the complete single line from ANDROID_KEYSTORE_BASE64.txt
EOF

  cat > "$README" <<'EOF'
FLAVORFLOW NEW GOOGLE PLAY UPLOAD KEY

PRIVATE — keep this complete folder/ZIP in a secure personal backup.
Never upload the ZIP, P12, Base64, or credentials to GitHub/chat.

Google Play Console upload-key reset:
1. Upload ONLY upload_certificate.pem in Request upload key reset.
2. Wait until Play confirms the new upload key is active.

CircleCI Project Settings > Environment Variables:
1. Read the three short values from CircleCI-credentials.txt.
2. For ANDROID_KEYSTORE_BASE64, copy the full single line from
   ANDROID_KEYSTORE_BASE64.txt.
3. Keep the release job On Hold until Google Play approves the reset.

The .p12 is the private upload key. Losing it/password requires another reset.
This is NOT the Google Play app-signing key.
EOF
fi

verify_bundle || { echo "FATAL: generated bundle verification failed"; exit 1; }

# Public fingerprint record (contains no private key/password).
openssl x509 -in "$PEM" -noout -fingerprint -sha256 > "$OUT/upload-certificate-SHA256.txt"

rm -f "$ZIP"
OUT="$OUT" ZIP="$ZIP" python3 - <<'PY'
import os
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
out = Path(os.environ['OUT'])
zip_path = Path(os.environ['ZIP'])
names = [
    'README-FIRST.txt',
    'flavorflow-upload-2026.p12',
    'upload_certificate.pem',
    'upload-certificate-SHA256.txt',
    'CircleCI-credentials.txt',
    'ANDROID_KEYSTORE_BASE64.txt',
]
with ZipFile(zip_path, 'w', ZIP_DEFLATED) as z:
    for name in names:
        path = out / name
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f'missing output: {name}')
        z.write(path, name)
PY

chmod 700 "$OUT"
chmod 600 "$OUT"/* "$META" "$ZIP"
chown -R "$OWNER:$OWNER_GROUP" "$OUT" "$ZIP"

# Final verification after ownership/ZIP creation.
verify_bundle
python3 -m zipfile -t "$ZIP" >/dev/null

echo "PUBLIC PEM (Play Console): $PEM"
echo "PRIVATE ZIP (download + secure backup): $ZIP"
echo "Secrets terminal te print NAHI kite gaye. ZIP/credentials da screenshot NA bhejo."
echo "NEWUPLOADKEY9 VERIFIED ✓ — 4096-bit PKCS12 + PEM + CircleCI bundle ready"
