#!/usr/bin/env bash
# Apply an uploaded static website/support release on the existing SaaS VM.
# No git access, backend/API/database edits, email provisioning or chat signup.
# This publishes the approved enterprise homepage as well as support.
set -Eeuo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run with sudo on the existing hosting VM.' >&2; exit 1; }
SOURCE=${1:?Provide the extracted release web-landing directory}
SOURCE=$(realpath "$SOURCE")
WEB=/opt/flavorflow-saas/web
CFG=/etc/caddy/Caddyfile
[[ -f "$WEB/index.html" && -f "$CFG" ]] || { echo 'Existing website/Caddyfile missing; no changes made.' >&2; exit 1; }
for cmd in python3 caddy systemctl install cmp curl; do command -v "$cmd" >/dev/null; done
systemctl is-active --quiet caddy
FILES=(
  assets/flavorflow-logo-v2.png assets/favicon-32-v2.png assets/favicon-48-v2.png assets/apple-touch-icon-v2.png
  assets/fonts/inter-regular.woff2 assets/fonts/inter-semibold.woff2 assets/fonts/inter-bold.woff2 assets/fonts/LICENSE.txt
  assets/landing.css assets/site.js assets/distribution-config.js assets/distribution.js assets/vendor/qrcode.js assets/vendor/LICENSE
  assets/support.css assets/support.js assets/support-contact-config.js assets/support-chat.js assets/support-contacts.js
  support/index.html index.html
)
STAGE=$(mktemp -d)
CANDIDATE="${CFG}.support-candidate-$$"
trap 'rm -rf "$STAGE"; rm -f "$CANDIDATE"' EXIT
# Only replace the known placeholder or our previously managed block.
# Keep all other hostnames, imports, API routes and services untouched.
cp -p "$CFG" "$CANDIDATE"
python3 - "$SOURCE" "$CANDIDATE" "${FILES[@]}" <<'PY'
import hashlib, json, re, sys
from pathlib import Path
source = Path(sys.argv[1])
manifest = json.loads((source / 'release-manifest.json').read_text())
for name in sys.argv[3:]:
    file = source / name
    if file.is_symlink() or not file.is_file():
        raise SystemExit(f'Missing/unsafe release file: {name}')
    if hashlib.sha256(file.read_bytes()).hexdigest() != manifest.get(name):
        raise SystemExit(f'Release checksum mismatch: {name}')
home = (source / 'index.html').read_text()
support = (source / 'support/index.html').read_text()
if 'content="FlavorFlow ERP"' not in home or 'data-support-link' not in home:
    raise SystemExit('Expected ERP homepage/support links not found.')
for marker in ('id="live-chat-link"', 'id="support-call-link"', 'id="support-email-link"'):
    if marker not in support:
        raise SystemExit(f'Missing support option: {marker}')
if re.search(r'hrmate|integrations?', home + support, re.I):
    raise SystemExit('Unrelated product promotion detected.')
file = Path(sys.argv[2])
text = file.read_text()
pattern = re.compile(r'^support\.flavorflow\.co\.in[ \t]*\{[ \t]*\n.*?^\}', re.M | re.S)
matches = list(pattern.finditer(text))
if len(matches) != 1:
    raise SystemExit('Expected exactly one dedicated support hostname block. No changes made; review current Caddy configuration.')
old = matches[0].group()
if 'FlavorFlow ERP support centre' not in old and '# FlavorFlow managed support web' not in old:
    raise SystemExit('Unknown support routing; refusing to overwrite it.')
new = '''support.flavorflow.co.in {
    # FlavorFlow managed support web
    root * /opt/flavorflow-saas/web
    header X-Robots-Tag "noindex, nofollow"
    @supportHome path /
    rewrite @supportHome /support/index.html
    @supportFiles path /support/* /assets/*
    handle @supportFiles {
        file_server
    }
    handle {
        respond "Not found" 404
    }
}'''
file.write_text(text[:matches[0].start()] + new + text[matches[0].end():])
PY
caddy validate --config "$CANDIDATE" --adapter caddyfile
BACKUP="/opt/flavorflow-saas/backups/support-web-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$BACKUP"
cp -p "$CFG" "$BACKUP/Caddyfile"
for file in "${FILES[@]}"; do
  [[ ! -L "$WEB/$file" ]] || { echo "Refusing symlink: $WEB/$file" >&2; exit 1; }
  mkdir -p "$BACKUP/web/$(dirname "$file")"
  [[ ! -f "$WEB/$file" ]] || cp -p "$WEB/$file" "$BACKUP/web/$file"
done
rollback() {
  trap - ERR
  for file in "${FILES[@]}"; do
    if [[ -f "$BACKUP/web/$file" ]]; then cp -p "$BACKUP/web/$file" "$WEB/$file";
    else rm -f "$WEB/$file"; fi
    rm -f "$WEB/$file.new"
  done
  cp -p "$BACKUP/Caddyfile" "$CFG"
  systemctl reload caddy || echo 'WARNING: Caddy reload failed after restore; inspect service.' >&2
  echo "Publish failed. Restored backup: $BACKUP" >&2
  exit 1
}
trap rollback ERR
# Shared assets first, support HTML second, homepage last.
for file in "${FILES[@]}"; do
  mkdir -p "$WEB/$(dirname "$file")"
  install -m 644 "$SOURCE/$file" "$WEB/$file.new"
  mv -f "$WEB/$file.new" "$WEB/$file"
done
cp -p "$CANDIDATE" "$CFG"
systemctl reload caddy
trap - ERR
printf 'Static website/support published. Backup: %s\n' "$BACKUP"
# This checks local HTTPS/certificates/content, not external DNS/CDN routing.
FAILED=0
verify() {
  local host=$1 path=$2 file=$3
  if curl --fail --silent --show-error --max-time 15 --resolve "$host:443:127.0.0.1" "https://$host$path" -o "$STAGE/check" && cmp -s "$WEB/$file" "$STAGE/check"; then
    echo "OK: https://$host$path"
  else
    echo "WARNING: verification failed: https://$host$path" >&2
    FAILED=1
  fi
}
verify flavorflow.co.in / index.html
verify www.flavorflow.co.in / index.html
verify support.flavorflow.co.in / support/index.html
for file in assets/support.css assets/support.js assets/support-contact-config.js assets/support-chat.js assets/support-contacts.js assets/landing.css assets/flavorflow-logo-v2.png assets/fonts/inter-regular.woff2; do
  verify support.flavorflow.co.in "/$file" "$file"
done
[[ "$FAILED" == 0 ]] || { echo 'Files installed, but HTTPS routing not fully confirmed. Inspect Caddy; do not claim successful public launch.' >&2; exit 1; }
echo 'Local HTTPS checks passed. Confirm the public domains in a private browser window.'
echo 'Contact links/widgets require configured services and real delivery checks; no agent availability is guaranteed.'
