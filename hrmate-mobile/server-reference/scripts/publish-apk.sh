#!/usr/bin/env bash
# publish-apk.sh — put a TESTED native HRMate APK on https://hr.flavorflow.co.in/download
#
# Runs ON the VPS (hrmate-prod). No git, no image rebuild: the file is copied into the
# persistent data volume that /api/download/apk serves from.
#
#   sudo bash /opt/hrmate/scripts/publish-apk.sh ~/app-prod-release.apk 3.0.0 30
#
set -euo pipefail
APK="${1:-}"; VER="${2:-}"; BUILD="${3:-}"
if [ -z "$APK" ] || [ -z "$VER" ] || [ -z "$BUILD" ]; then
  echo "usage: sudo bash $0 <app-prod-release.apk> <version e.g. 3.0.0> <build e.g. 30>"; exit 1
fi
[ -f "$APK" ] || { echo "STOP: file not found: $APK"; exit 1; }
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "STOP: version must look like 3.0.0"; exit 1; }
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "STOP: build must be a number"; exit 1; }
CONTAINER="${HRMATE_CONTAINER:-hrmate-hrmate-1}"
docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" || { echo "STOP: container $CONTAINER is not running"; exit 1; }
# Real APK = zip with AndroidManifest.xml. (No `unzip -l | grep -q` here: with pipefail, grep
# closing the pipe early makes the check fail on big APKs.)
BYTES=$(stat -c %s "$APK")
MAGIC=$(head -c 2 "$APK" | od -An -c | tr -d ' ')
if [ "$MAGIC" != "PK" ]; then
  echo "STOP: $APK is not an APK (first bytes '$MAGIC', $BYTES bytes)."
  echo "  -> '<!' or '<h' = a web page was saved, not the APK: download again from Codemagic -> Artifacts"
  exit 1
fi
if command -v unzip >/dev/null 2>&1; then
  if ! unzip -tq "$APK" >/dev/null 2>&1; then
    echo "STOP: $APK is damaged/incomplete ($BYTES bytes): $(unzip -tq "$APK" 2>&1 | tail -1)"
    echo "  -> the upload was cut short: upload the file again and wait for the progress bar to finish"
    exit 1
  fi
  LISTING=$(unzip -Z1 "$APK" 2>/dev/null || true)
  case "$LISTING" in
    *AndroidManifest.xml*) : ;;
    *) echo "STOP: $APK has no AndroidManifest.xml — not an Android APK"; exit 1 ;;
  esac
fi
NAME="HRMate-${VER}.apk"
SIZE=$BYTES
SHA=$(sha256sum "$APK" | cut -d' ' -f1)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TMP=$(mktemp -d)
printf '{"version":"%s","build":%s,"file":"%s","sizeBytes":%s,"sha256":"%s","publishedAt":"%s"}\n' \
  "$VER" "$BUILD" "$NAME" "$SIZE" "$SHA" "$NOW" > "$TMP/apk-info.json"
docker exec -u 0 "$CONTAINER" mkdir -p /app/data/releases
docker cp "$APK" "$CONTAINER:/app/data/releases/$NAME"
docker cp "$TMP/apk-info.json" "$CONTAINER:/app/data/releases/apk-info.json"
docker exec -u 0 "$CONTAINER" chmod -R a+rX /app/data/releases
rm -rf "$TMP"
echo "PUBLISHED $NAME  ($SIZE bytes, sha256 $SHA)"
echo "--- verify"
curl -s https://hr.flavorflow.co.in/api/download/apk-info; echo
curl -s -o /dev/null -w 'download: HTTP %{http_code}, %{size_download} bytes\n' https://hr.flavorflow.co.in/api/download/apk
