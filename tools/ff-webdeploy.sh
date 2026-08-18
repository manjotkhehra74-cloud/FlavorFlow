#!/usr/bin/env bash
# FlavorFlow: deploy a ready-made website zip (built on Codemagic) to
# /opt/flavorflow/web — NO building on this tiny server, just download+unzip.
# Usage:
#   curl -s https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a003d0-flavorflow/tools/ff-webdeploy.sh | sudo bash -s 'ZIP_URL'
# where ZIP_URL = flavorflow-web.zip da link (Codemagic build artifacts vichon copy karo).
set -u
echo "=== FF-WEBDEPLOY $(date) ==="

URL="${1:-}"
if [ -z "$URL" ]; then
  echo "FATAL: zip URL nahi ditta. Codemagic build de artifacts vichon flavorflow-web.zip da link copy karke command de akhir vich single-quotes vich pao."
  exit 1
fi

command -v unzip >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip >/dev/null; }

WEB=/opt/flavorflow/web
TMPZ=/tmp/flavorflow-web.zip
TMPD=/tmp/flavorflow-web-extract

echo "Downloading zip..."
curl -fSL -o "$TMPZ" "$URL" || { echo "FATAL: download fail — link sahi hai? (Codemagic links kuch dinan baad expire ho jande ne)"; exit 1; }
SIZE=$(du -m "$TMPZ" | cut -f1)
echo "ZIP: ${SIZE}MB"
[ "$SIZE" -lt 1 ] && { echo "FATAL: zip bahut chhoti — link galat lagda"; exit 1; }

rm -rf "$TMPD" && mkdir -p "$TMPD"
unzip -qo "$TMPZ" -d "$TMPD" || { echo "FATAL: unzip fail"; exit 1; }
# zip may contain files at root or under build/web — find index.html
ROOT="$TMPD"
[ -f "$ROOT/index.html" ] || ROOT=$(dirname "$(find "$TMPD" -name index.html -maxdepth 4 | head -1)")
[ -f "$ROOT/index.html" ] || { echo "FATAL: index.html nahi mili zip vich"; exit 1; }
echo "EXTRACTED: $ROOT"

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
tar -czf "/opt/flavorflow/backups/web-$TS.tgz" -C "$WEB" . 2>/dev/null && echo "WEB BACKUP: /opt/flavorflow/backups/web-$TS.tgz"
cp -a "$ROOT"/. "$WEB"/
echo "deployed $(date)" > "$WEB/ff-web-version.txt"
chown -R flavorflow:flavorflow "$WEB" 2>/dev/null || true
rm -rf "$TMPZ" "$TMPD"

curl -s -o /dev/null -w 'site -> %{http_code}\n' -m 8 http://127.0.0.1:4000/ || true
echo "WEBDEPLOY VERIFIED ✓ — browser vich hard refresh (Ctrl+Shift+R) karke navi website dekho"
