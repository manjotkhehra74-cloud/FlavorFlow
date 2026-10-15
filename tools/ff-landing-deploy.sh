#!/usr/bin/env bash
# Deploy FlavorFlow website HTML, styles, scripts, fonts and selected logo assets only.
# No backend, database, APK, app icon or Caddy configuration edits.
# Run on the existing SaaS VM with sudo. FF_REF can pin an immutable commit.
set -Eeuo pipefail
REF="${FF_REF:-arena/f2bca6ec-flavorflow}"
WEB="${FF_WEB:-/opt/flavorflow-saas/web}"
REPO="manjotkhehra74-cloud/FlavorFlow"
[[ "$(id -u)" == 0 ]] || { echo 'ERROR: run with sudo on the hosting VM.' >&2; exit 1; }
[[ -d "$WEB" && -f "$WEB/index.html" ]] || {
  echo "ERROR: existing website not found at $WEB; refusing an unverified location." >&2
  exit 1
}
for cmd in curl tar python3 install cmp; do
  command -v "$cmd" >/dev/null || { echo "ERROR: missing $cmd" >&2; exit 1; }
done
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ASSETS=(assets/flavorflow-logo-v2.png assets/favicon-32-v2.png assets/favicon-48-v2.png assets/apple-touch-icon-v2.png)
SCRIPTS=(assets/distribution-config.js assets/distribution.js assets/vendor/qrcode.js)
STYLES=(assets/landing.css assets/support.css)
FONTS=(assets/fonts/inter-regular.woff2 assets/fonts/inter-semibold.woff2 assets/fonts/inter-bold.woff2 assets/fonts/LICENSE.txt)
SCRIPTS+=(assets/site.js assets/support.js assets/support-contact-config.js assets/support-contacts.js)
FILES=("${ASSETS[@]}" "${SCRIPTS[@]}" "${STYLES[@]}" "${FONTS[@]}" demo.html privacy.html admin.html support/index.html index.html)
# One snapshot keeps pages and versioned logo assets consistent.
curl --fail --silent --show-error --location --max-time 120 --retry 2 \
  "https://codeload.github.com/$REPO/tar.gz/$REF" -o "$STAGE/source.tar.gz"
tar -xzf "$STAGE/source.tar.gz" --strip-components=1 -C "$STAGE" --wildcards \
  '*/web-landing/*.html' '*/web-landing/assets/*'
python3 - "$STAGE/web-landing" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
for name in ('index.html', 'demo.html', 'privacy.html', 'admin.html', 'support/index.html'):
    text = (root / name).read_text()
    if '<html' not in text.lower() or '</html>' not in text.lower():
        raise SystemExit(f'Invalid HTML: {name}')
text = (root / 'index.html').read_text()
if '<meta name="application-name" content="FlavorFlow ERP">' not in text or 'id="features"' not in text:
    raise SystemExit('Snapshot does not contain the ERP landing page.')
if 'hrmate' in text.lower() or 'integration' in text.lower():
    raise SystemExit('Refusing unrelated product promotion in public landing page.')
for name in ('distribution-config.js', 'distribution.js', 'vendor/qrcode.js', 'site.js', 'landing.css', 'support.js', 'support.css', 'support-contact-config.js', 'support-contacts.js',
             'fonts/inter-regular.woff2', 'fonts/inter-semibold.woff2', 'fonts/inter-bold.woff2'):
    if not (root / 'assets' / name).is_file():
        raise SystemExit(f'Missing website asset: {name}')
for page in ('index.html', 'demo.html'):
    if '/download/flavorflow-erp.apk' in (root / page).read_text():
        raise SystemExit(f'Public APK link still present in {page}')
for name in ('flavorflow-logo-v2.png', 'favicon-32-v2.png', 'favicon-48-v2.png', 'apple-touch-icon-v2.png'):
    data = (root / 'assets' / name).read_bytes()
    if not data.startswith(b'\x89PNG\r\n\x1a\n') or len(data) < 24:
        raise SystemExit(f'Invalid logo asset: {name}')
    if f'/assets/{name}' not in text:
        raise SystemExit(f'Landing page does not reference {name}')
PY
BACKUP="$(dirname "$WEB")/backups/landing-$(date -u +%Y%m%dT%H%M%SZ)-$$"
for file in "${FILES[@]}"; do
  mkdir -p "$BACKUP/$(dirname "$file")" "$WEB/$(dirname "$file")"
done
for file in "${FILES[@]}"; do
  [[ ! -f "$WEB/$file" ]] || cp -p "$WEB/$file" "$BACKUP/$file"
done
rollback() {
  for file in "${FILES[@]}"; do
    if [[ -f "$BACKUP/$file" ]]; then cp -p "$BACKUP/$file" "$WEB/$file";
    else rm -f "$WEB/$file"; fi
    rm -f "$WEB/$file.new"
  done
  echo "ERROR: deploy failed; restored backup $BACKUP" >&2
}
trap 'rollback' ERR
# Install assets before HTML so the new page never references missing logos.
for file in "${FILES[@]}"; do
  install -m 644 "$STAGE/web-landing/$file" "$WEB/$file.new"
  mv -f "$WEB/$file.new" "$WEB/$file"
done
trap - ERR
printf 'Website and logo updated from %s\nBackup: %s\n' "$REF" "$BACKUP"
echo 'Checking local HTTPS routing for both public domains...'
FAILED=0
for host in flavorflow.co.in www.flavorflow.co.in; do
  for file in index.html "${ASSETS[@]}" "${SCRIPTS[@]}" "${STYLES[@]}" "${FONTS[@]}"; do
    path="/$file"; [[ "$file" != index.html ]] || path=/
    if curl --fail --silent --show-error --max-time 15 \
      --resolve "$host:443:127.0.0.1" "https://$host$path?landing-check=$(date +%s)" \
      -o "$STAGE/check" && cmp -s "$WEB/$file" "$STAGE/check"; then
      echo "OK: $host serves $file."
    else
      echo "WARNING: $host/$file verification failed; check routing and DNS." >&2
      FAILED=1
    fi
  done
done
if [[ "$FAILED" == 1 ]]; then
  echo 'Files installed, but domain routing is NOT confirmed. No proxy config changed.' >&2
  exit 1
fi
echo 'Local routing verified. Check public URLs in a private window; external DNS/CDN may differ.'
