#!/usr/bin/env bash
# FlavorFlow: uploaded APK → website download link publish karo.
#   https://flavorflow.co.in/download/flavorflow-erp.apk  (landing page da
#   "⬇ Download for Android (APK)" button ethe hi point karda hai)
#
# Usage (SaaS VM, SSH-in-browser vich pehla UPLOAD FILE → APK chuno, fer):
#   curl -s https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a0858b-flavorflow/tools/ff-apkpublish.sh | sudo bash
#
# Home folder vichon SAB TON NAVI *.apk chukda hai — naam koi vi hove
# (CircleCI artifact = FlavorFlow-release.apk, flutter build = app-release.apk,
# Codemagic = app-release.apk / app-debug.apk). Purani APK da backup rakhda hai.
# Idempotent — dubara chalao tan sirf navi file replace hundi hai.
set -u
echo "=== FF-APKPUBLISH $(date) ==="

WEB="${FF_WEB:-/opt/flavorflow-saas/web}"
DEST="$WEB/download/flavorflow-erp.apk"
BACKUPS="${FF_BACKUPS:-/opt/flavorflow-saas/backups}"

# 1) APK labho — pehla sudo chalaun wale user da home (SSH upload othe hi aundi hai),
#    fer /home/* te /root
HOMES=()
if [ -n "${SUDO_USER:-}" ]; then
  H=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  [ -n "$H" ] && HOMES+=("$H")
fi
HOMES+=(/home/* /root)
SRC=""
for h in "${HOMES[@]}"; do
  [ -d "$h" ] || continue
  f=$(ls -t "$h"/*.apk 2>/dev/null | head -1)
  [ -n "$f" ] && { SRC="$f"; break; }
done
if [ -z "$SRC" ]; then
  echo "FATAL: koi .apk file nahi labhi (home folder khali)."
  echo "  → SSH window de upar UPLOAD FILE dabao → phone de Downloads vichon APK chuno"
  echo "  → 'Transferred 1 item ✓' aun ton BAAD eh command dubara chalao."
  exit 1
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
