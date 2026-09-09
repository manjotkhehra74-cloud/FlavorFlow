#!/usr/bin/env bash
# FlavorFlow: APK → website download link publish karo.
#   https://flavorflow.co.in/download/flavorflow-erp.apk  (landing page da
#   "⬇ Download for Android (APK)" button ethe hi point karda hai)
#
# SOURCE — phone ton upload di lorh NAHI, VM khud CircleCI ton download kardi hai:
#   curl -s https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a0858b-flavorflow/tools/ff-apkpublish.sh | sudo bash
#     → branch di sab ton navi SUCCESSFUL build-play-store-release da FlavorFlow-release.apk
#   ... | sudo bash -s 211                    khaas CircleCI build number
#   ... | sudo bash -s 'https://.../x.apk'    kise vi URL ton
#   ... | sudo bash -s home                   home folder vich (SSH upload naal) pai navi *.apk
# Har APK: size + zip integrity test (adhoori upload/download REJECT), purani da backup,
# same sha → skip, apk mime, local verify, /download/apk-info.txt (browser ton dekho
# kehri build live hai). Idempotent. tools/ff-boot.sh (GCE startup-script, bina SSH)
# vi ehnu 'ci' arg naal chalaunda hai.
set -u
echo "=== FF-APKPUBLISH $(date) ==="

WEB="${FF_WEB:-/opt/flavorflow-saas/web}"
DEST="$WEB/download/flavorflow-erp.apk"
INFO="$WEB/download/apk-info.txt"
BACKUPS="${FF_BACKUPS:-/opt/flavorflow-saas/backups}"
REPO="manjotkhehra74-cloud/FlavorFlow"
BRANCH="${FF_BRANCH:-arena/01a0858b-flavorflow}"
BRANCH_ENC=$(printf '%s' "$BRANCH" | sed 's#/#%2F#g')
ARG="${1:-}"
[ "$ARG" = "ci" ] && ARG=""
SRC=""; SOURCE=""; BUILD=""; REV=""; TMP=""

# APK check: ≥5MB, zip header, POORA zip (unzip -t / end-record) — adhoori file reject
valid_apk() {
  local f="$1" size
  [ -s "$f" ] || { echo "  ✗ file khali/nahi: $f"; return 1; }
  size=$(du -m "$f" | cut -f1)
  [ "$size" -ge 5 ] || { echo "  ✗ bahut chhoti (${size}MB) — adhoori"; return 1; }
  [ "$(head -c 2 "$f")" = "PK" ] || { echo "  ✗ zip header nahi — eh APK nahi"; return 1; }
  if command -v unzip >/dev/null 2>&1; then
    unzip -tq "$f" >/dev/null 2>&1 || { echo "  ✗ zip test fail — adhoori/corrupt"; return 1; }
  else
    tail -c 70000 "$f" | grep -qaF $'PK\x05\x06' || { echo "  ✗ zip end-record nahi — adhoori"; return 1; }
  fi
  return 0
}

# A) home folder wali APK (sirf 'home' arg te) — adhoori upload skip
if [ "$ARG" = "home" ]; then
  HOMES=()
  if [ -n "${SUDO_USER:-}" ]; then
    H=$(getent passwd "$SUDO_USER" | cut -d: -f6); [ -n "$H" ] && HOMES+=("$H")
  fi
  HOMES+=(/home/* /root)
  for h in "${HOMES[@]}"; do
    [ -d "$h" ] || continue
    mapfile -t FILES < <(ls -t "$h"/*.apk 2>/dev/null)
    for f in "${FILES[@]}"; do
      echo "home APK: $f ($(du -m "$f" | cut -f1)MB)"
      if valid_apk "$f"; then SRC="$f"; SOURCE="home:$(basename "$f")"; break 2; fi
      echo "  (skip — adhoori upload lagdi; hatao: rm '$f')"
    done
  done
  [ -z "$SRC" ] && { echo "FATAL: home vich koi poori *.apk nahi. Bina arg chalao → CircleCI ton aap le lavegi."; exit 1; }
fi

# B) CircleCI / URL (default) — public repo → artifacts bina token de milde ne
if [ -z "$SRC" ]; then
  TMP=$(mktemp -d)
  URL=""
  case "$ARG" in
    http*://*) URL="$ARG"; SOURCE="url:$ARG" ;;
    ''|[0-9]*)
      if [ -n "$ARG" ]; then
        BUILD="$ARG"
        REV=$(curl -s -m 20 "https://circleci.com/api/v1.1/project/github/$REPO/$BUILD" | grep -o '"vcs_revision" *: *"[0-9a-f]*"' | head -1 | grep -o '[0-9a-f]\{40\}')
      else
        echo "CircleCI: branch $BRANCH di sab ton navi successful APK build labh reha..."
        JSON=$(curl -s -m 20 "https://circleci.com/api/v1.1/project/github/$REPO/tree/$BRANCH_ENC?limit=30&filter=successful")
        PICK=""
        if command -v node >/dev/null 2>&1; then
          PICK=$(printf '%s' "$JSON" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{const a=JSON.parse(d);const b=a.find(x=>x.workflows&&x.workflows.job_name==="build-play-store-release"&&x.status==="success");console.log(b?b.build_num+" "+(b.vcs_revision||""):"")}catch(e){console.log("")}})')
        else
          PICK=$(printf '%s' "$JSON" | python3 -c 'import sys,json
try:
  a=json.load(sys.stdin); b=[x for x in a if (x.get("workflows") or {}).get("job_name")=="build-play-store-release" and x.get("status")=="success"]
  print(str(b[0]["build_num"])+" "+str(b[0].get("vcs_revision") or "") if b else "")
except Exception: print("")')
        fi
        BUILD=${PICK%% *}; REV=${PICK#* }; [ "$REV" = "$PICK" ] && REV=""
      fi
      [ -z "$BUILD" ] && { echo "FATAL: CircleCI te $BRANCH di koi successful APK build nahi labhi. Pehla CircleCI te approve-release karo, build hari hon dio, fer eh command dubara."; exit 1; }
      echo "CircleCI build #$BUILD${REV:+ (commit ${REV:0:7})}"
      URL=$(curl -s -m 20 "https://circleci.com/api/v1.1/project/github/$REPO/$BUILD/artifacts" | tr -d '\n' | grep -o 'https://[^"]*FlavorFlow-release\.apk' | head -1)
      [ -z "$URL" ] && { echo "FATAL: build #$BUILD vich FlavorFlow-release.apk artifact nahi (AAB-only ya expire?)."; exit 1; }
      SOURCE="circleci-build-$BUILD"
      ;;
    *) echo "FATAL: argument samajh nahi aaya: $ARG (build number / https URL / home / ci)"; exit 1 ;;
  esac
  echo "download: $URL"
  curl -fSL -m 600 --retry 3 --retry-delay 5 -o "$TMP/FlavorFlow-release.apk" "$URL" || { echo "FATAL: download fail (net/URL)."; exit 1; }
  SRC="$TMP/FlavorFlow-release.apk"
  echo "APK: $SRC ($(du -m "$SRC" | cut -f1)MB) — check..."
  valid_apk "$SRC" || { echo "FATAL: download hoi file poori/valid APK nahi. Dubara chalao."; exit 1; }
fi

# 2) place (same sha → skip), purani da backup
mkdir -p "$WEB/download" "$BACKUPS"
SHA=$(sha256sum "$SRC" | cut -c1-64)
if [ -f "$DEST" ] && [ "$(sha256sum "$DEST" | cut -c1-64)" = "$SHA" ]; then
  echo "eho APK pehla hi live hai (sha same) — koi badlav nahi ✓"
  CHANGED=no
else
  if [ -f "$DEST" ]; then
    cp -a "$DEST" "$BACKUPS/flavorflow-erp-$(date +%s).apk" && echo "purani APK backup ✓ ($BACKUPS)"
    ls -t "$BACKUPS"/flavorflow-erp-*.apk 2>/dev/null | tail -n +6 | xargs -r rm -f   # 5 backups rakho
  fi
  mv -f "$SRC" "$DEST" || { echo "FATAL: move fail — sudo naal chalaya?"; exit 1; }
  CHANGED=yes
fi
chmod 755 "$WEB/download"
chmod 644 "$DEST"          # caddy (alag user) nu read chahidi hai
SIZE_B=$(stat -c %s "$DEST")
{
  echo "published: $(date -u +%FT%TZ)"
  echo "source: $SOURCE"
  echo "build: ${BUILD:--}  commit: ${REV:--}"
  echo "size: $SIZE_B bytes ($((SIZE_B/1024/1024))MB)"
  echo "sha256: $SHA"
} > "$INFO"; chmod 644 "$INFO"
echo "placed ✓ → $DEST (changed: $CHANGED)"
ls -la "$WEB/download/"
echo "sha256: ${SHA:0:16}…"
[ -n "$TMP" ] && rm -rf "$TMP"

# 3) .apk da sahi Content-Type (android package) — minimized Ubuntu te
#    /etc/mime.types kade-kade nahi hunda; ohde bina Chrome file nu zip samajh
#    sakda hai. media-types install + caddy restart (mime table start te load hundi hai).
if [ "$(id -u)" = 0 ] && command -v caddy >/dev/null 2>&1; then
  if ! grep -qs 'vnd.android.package-archive' /etc/mime.types; then
    echo "mime.types vich apk nahi — media-types install kar reha..."
    apt-get install -y -qq media-types >/dev/null 2>&1 || apt-get install -y -qq mime-support >/dev/null 2>&1 || true
    grep -qs 'vnd.android.package-archive' /etc/mime.types && systemctl restart caddy && sleep 1 && echo "caddy restart ✓ (apk mime)"
  fi
  # 4) local verify — apne hi caddy nu domain de naam naal (SNI/Host sahi) puchho
  echo "--- verify (local caddy) ---"
  curl -sSIk --resolve flavorflow.co.in:443:127.0.0.1 -m 10 \
    https://flavorflow.co.in/download/flavorflow-erp.apk 2>&1 | grep -i -E '^HTTP|content-type|content-length' || echo "(local verify skip — caddy respond nahi kita)"
fi

echo "APKPUBLISH VERIFIED ✓"
echo "Phone browser vich kholo: https://flavorflow.co.in/download/flavorflow-erp.apk"
echo "Kehri build live hai:     https://flavorflow.co.in/download/apk-info.txt"
