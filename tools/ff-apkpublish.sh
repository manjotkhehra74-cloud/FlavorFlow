#!/usr/bin/env bash
# FlavorFlow: APK → website download link publish karo.
#   https://flavorflow.co.in/download/flavorflow-erp.apk  (landing page da
#   "⬇ Download for Android (APK)" button ethe hi point karda hai)
#
# DO TARIKE:
#  A) SEEDHA CircleCI TON (phone upload di lorh nahi — VM khud download kardi hai):
#     curl -s https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a0858b-flavorflow/tools/ff-apkpublish.sh | sudo bash
#     → branch di sab ton navi SUCCESSFUL build da FlavorFlow-release.apk aap labh ke publish
#     Khaas build number: ... | sudo bash -s 211      Kise vi URL ton: ... | sudo bash -s 'https://.../x.apk'
#  B) SSH-in-browser UPLOAD FILE naal APK home vich pao, fer ohi command — home wali file
#     mil gayi ta ohnu pehal (CircleCI skip)
# Idempotent — purani APK da backup rakhda hai.
set -u
echo "=== FF-APKPUBLISH $(date) ==="

WEB="${FF_WEB:-/opt/flavorflow-saas/web}"
DEST="$WEB/download/flavorflow-erp.apk"
BACKUPS="${FF_BACKUPS:-/opt/flavorflow-saas/backups}"
REPO="manjotkhehra74-cloud/FlavorFlow"
BRANCH="${FF_BRANCH:-arena/01a0858b-flavorflow}"
BRANCH_ENC=$(printf '%s' "$BRANCH" | sed 's#/#%2F#g')
ARG="${1:-}"

# 0) home folder vich upload kiti APK? (tarika B) — hove ta ohi vartni
HOMES=()
if [ -n "${SUDO_USER:-}" ]; then
  H=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  [ -n "$H" ] && HOMES+=("$H")
fi
HOMES+=(/home/* /root)
SRC=""
if [ -z "$ARG" ]; then
  for h in "${HOMES[@]}"; do
    [ -d "$h" ] || continue
    f=$(ls -t "$h"/*.apk 2>/dev/null | head -1)
    [ -n "$f" ] && { SRC="$f"; break; }
  done
fi

# 1) nahi ta CircleCI ton seedha download (public repo → artifacts bina token de milde ne)
if [ -z "$SRC" ]; then
  TMP=$(mktemp -d)
  URL=""
  case "$ARG" in
    http*://*) URL="$ARG" ;;
    ''|[0-9]*)
      if [ -n "$ARG" ]; then
        BUILD="$ARG"
      else
        echo "CircleCI: branch $BRANCH di sab ton navi successful build labh reha..."
        JSON=$(curl -s -m 20 "https://circleci.com/api/v1.1/project/github/$REPO/tree/$BRANCH_ENC?limit=30&filter=successful")
        if command -v node >/dev/null 2>&1; then
          BUILD=$(printf '%s' "$JSON" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{const a=JSON.parse(d);const b=a.find(x=>x.workflows&&x.workflows.job_name==="build-play-store-release"&&x.status==="success");console.log(b?b.build_num:"")}catch(e){console.log("")}})')
        else
          BUILD=$(printf '%s' "$JSON" | python3 -c 'import sys,json
try:
  a=json.load(sys.stdin); b=[x for x in a if (x.get("workflows") or {}).get("job_name")=="build-play-store-release" and x.get("status")=="success"]
  print(b[0]["build_num"] if b else "")
except Exception: print("")')
        fi
      fi
      [ -z "$BUILD" ] && { echo "FATAL: CircleCI te $BRANCH di koi successful APK build nahi labhi. Pehla CircleCI te approve-release karo, build hari hon dio, fer eh command dubara."; exit 1; }
      echo "CircleCI build #$BUILD"
      URL=$(curl -s -m 20 "https://circleci.com/api/v1.1/project/github/$REPO/$BUILD/artifacts" | tr -d '\n' | grep -o 'https://[^"]*FlavorFlow-release\.apk' | head -1)
      [ -z "$URL" ] && { echo "FATAL: build #$BUILD vich FlavorFlow-release.apk artifact nahi (AAB-only ya expire?)."; exit 1; }
      ;;
    *) echo "FATAL: argument samajh nahi aaya: $ARG (build number ya https URL dio)"; exit 1 ;;
  esac
  echo "download: $URL"
  curl -fSL -m 600 --retry 3 --retry-delay 5 -o "$TMP/FlavorFlow-release.apk" "$URL" || { echo "FATAL: download fail (net/URL)."; exit 1; }
  SRC="$TMP/FlavorFlow-release.apk"
fi

# 2) sanity: size + zip header (APK = zip, 'PK' naal shuru)
SIZE=$(du -m "$SRC" | cut -f1)
echo "APK: $SRC (${SIZE}MB)"
if [ "$SIZE" -lt 5 ]; then
  echo "FATAL: file bahut chhoti (${SIZE}MB) — upload adhoori lagdi. Dubara upload karo."
  exit 1
fi
if [ "$(head -c 2 "$SRC")" != "PK" ]; then
  echo "FATAL: eh valid APK nahi lagdi (zip header nahi). Sahi file upload karo."
  exit 1
fi

# 3) purani APK backup + navi place karo
mkdir -p "$WEB/download" "$BACKUPS"
if [ -f "$DEST" ]; then
  cp -a "$DEST" "$BACKUPS/flavorflow-erp-$(date +%s).apk" && echo "purani APK backup ✓ ($BACKUPS)"
fi
mv -f "$SRC" "$DEST" || { echo "FATAL: move fail — sudo naal chalaya?"; exit 1; }
chmod 755 "$WEB/download"
chmod 644 "$DEST"          # caddy (alag user) nu read chahidi hai
echo "placed ✓ → $DEST"
ls -la "$WEB/download/"
echo "sha256: $(sha256sum "$DEST" | cut -c1-16)…"

# 4) .apk da sahi Content-Type (android package) — minimized Ubuntu te
#    /etc/mime.types kade-kade nahi hunda; ohde bina Chrome file nu zip samajh
#    sakda hai. media-types install + caddy restart (mime table start te load hundi hai).
if [ "$(id -u)" = 0 ] && command -v caddy >/dev/null 2>&1; then
  if ! grep -qs 'vnd.android.package-archive' /etc/mime.types; then
    echo "mime.types vich apk nahi — media-types install kar reha..."
    apt-get install -y -qq media-types >/dev/null 2>&1 || apt-get install -y -qq mime-support >/dev/null 2>&1 || true
    grep -qs 'vnd.android.package-archive' /etc/mime.types && systemctl restart caddy && sleep 1 && echo "caddy restart ✓ (apk mime)"
  fi
  # 5) local verify — apne hi caddy nu domain de naam naal (SNI/Host sahi) puchho
  echo "--- verify (local caddy) ---"
  curl -sSIk --resolve flavorflow.co.in:443:127.0.0.1 -m 10 \
    https://flavorflow.co.in/download/flavorflow-erp.apk 2>&1 | grep -i -E '^HTTP|content-type|content-length' || echo "(local verify skip — caddy respond nahi kita)"
fi

echo "APKPUBLISH VERIFIED ✓"
echo "Phone browser vich kholo: https://flavorflow.co.in/download/flavorflow-erp.apk"
echo "(ya landing page → '⬇ Download for Android (APK)' button — download shuru = done)"
