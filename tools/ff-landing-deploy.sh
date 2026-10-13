#!/usr/bin/env bash
# Deploy ONLY the FlavorFlow ERP public HTML; no backend, DB, APK or Caddy edits.
# Run on the existing FlavorFlow SaaS VM with sudo.
# FF_REF can pin an immutable commit. FF_WEB overrides the existing document root.
set -Eeuo pipefail

REF="${FF_REF:-arena/f2bca6ec-flavorflow}"
WEB="${FF_WEB:-/opt/flavorflow-saas/web}"
REPO="manjotkhehra74-cloud/FlavorFlow"
[[ "$(id -u)" == 0 ]] || { echo 'ERROR: run with sudo on the hosting VM.' >&2; exit 1; }
[[ -d "$WEB" && -f "$WEB/index.html" ]] || {
  echo "ERROR: existing website not found at $WEB; refusing to deploy to an unverified location." >&2
  exit 1
}
for cmd in curl tar python3 install; do command -v "$cmd" >/dev/null || { echo "ERROR: missing $cmd" >&2; exit 1; }; done
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# Download the whole snapshot once so all three public pages come from one revision.
curl --fail --silent --show-error --location --max-time 120 --retry 2 \
  "https://codeload.github.com/$REPO/tar.gz/$REF" -o "$STAGE/source.tar.gz"
tar -xzf "$STAGE/source.tar.gz" --strip-components=1 -C "$STAGE" --wildcards '*/web-landing/*.html'
python3 - "$STAGE/web-landing" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
for name in ('index.html', 'demo.html', 'privacy.html'):
    text = (root / name).read_text()
    if '<html' not in text.lower() or '</html>' not in text.lower():
        raise SystemExit(f'Invalid HTML: {name}')
text = (root / 'index.html').read_text()
if 'From factory floor' not in text or 'id="features"' not in text:
    raise SystemExit('Snapshot does not contain the new ERP landing page.')
if 'hrmate' in text.lower() or 'integration' in text.lower():
    raise SystemExit('Refusing public landing page with unrelated product promotion.')
PY

BACKUP="$(dirname "$WEB")/backups/landing-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$BACKUP"
for file in index.html demo.html privacy.html; do
  [[ ! -f "$WEB/$file" ]] || cp -p "$WEB/$file" "$BACKUP/$file"
done
# Each replacement is atomic. Roll back if any file install fails.
rollback() {
  for file in index.html demo.html privacy.html; do
    if [[ -f "$BACKUP/$file" ]]; then cp -p "$BACKUP/$file" "$WEB/$file";
    else rm -f "$WEB/$file"; fi
    rm -f "$WEB/.$file.new"
  done
  echo "ERROR: deploy failed; restored backup $BACKUP" >&2
}
trap 'rollback' ERR
for file in demo.html privacy.html index.html; do
  install -m 644 "$STAGE/web-landing/$file" "$WEB/.$file.new"
  mv -f "$WEB/.$file.new" "$WEB/$file"
done
trap - ERR
printf 'Public HTML updated from %s\nBackup: %s\n' "$REF" "$BACKUP"

echo 'Checking what Caddy serves locally for both public domain names...'
FAILED=0
for host in flavorflow.co.in www.flavorflow.co.in; do
  if curl --fail --silent --show-error --max-time 15 \
    --resolve "$host:443:127.0.0.1" "https://$host/?landing-check=$(date +%s)" \
    -o "$STAGE/$host.html" && cmp -s "$WEB/index.html" "$STAGE/$host.html"; then
    echo "OK: $host serves the new ERP landing page on this VM."
  else
    echo "WARNING: $host verification failed. Check Caddy routing and whether DNS points to this VM." >&2
    FAILED=1
  fi
done
if [[ "$FAILED" == 1 ]]; then
  echo 'HTML is installed, but live routing is NOT confirmed. No proxy config was changed.' >&2
  exit 1
fi
echo 'Local domain routing verified. Check both public URLs in a private browser window; external DNS/CDN may differ.'
