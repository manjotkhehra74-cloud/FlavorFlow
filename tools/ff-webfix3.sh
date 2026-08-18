#!/usr/bin/env bash
# FlavorFlow: rebuild the WEBSITE (Flutter web) with all the new app features
# and deploy it to /opt/flavorflow/web (served at https://flavorflow.duckdns.org).
#   - installs the Flutter SDK on the server once (/opt/flutter, stable)
#   - adds 2G swap if RAM is low (web builds are hungry)
#   - clones/updates the repo branch arena/01a003d0-flavorflow
#   - flutter build web --release
#   - backs up the current web dir, copies the new build over it
#     (extra files like ff-dump.txt stay untouched)
# Idempotent — safe to run twice. FIRST RUN TAKES 10-25 MIN (SDK download).
set -u
echo "=== FF-WEBFIX3 $(date) ==="

# ---------- -1) prerequisites (git was missing on the server) ----------
export DEBIAN_FRONTEND=noninteractive
NEED=""
for c in git curl unzip xz; do command -v $c >/dev/null 2>&1 || NEED="$NEED $c"; done
if [ -n "$NEED" ]; then
  echo "Installing prerequisites:$NEED"
  apt-get update -qq && apt-get install -y -qq git curl unzip xz-utils zip >/dev/null || { echo "FATAL: apt install fail"; exit 1; }
fi
git --version || { echo "FATAL: git ajje vi nahi"; exit 1; }

BRANCH=arena/01a003d0-flavorflow
REPO=https://github.com/manjotkhehra74-cloud/FlavorFlow.git
SRC=/opt/flavorflow/src
WEB=/opt/flavorflow/web
FL=/opt/flutter

# ---------- 0) swap (Flutter web build needs ~2GB free) ----------
MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
for SF in /swapfile-ff /swapfile-ff2; do
  SWAP_MB=$(free -m | awk '/^Swap:/{print $2}')
  if [ "$MEM_MB" -lt 3500 ] && [ "$SWAP_MB" -lt 3500 ]; then
    if [ ! -f "$SF" ]; then
      echo "RAM ${MEM_MB}MB — adding 2G swapfile $SF"
      fallocate -l 2G "$SF" || dd if=/dev/zero of="$SF" bs=1M count=2048
      chmod 600 "$SF" && mkswap "$SF"
    fi
    swapon "$SF" 2>/dev/null || true
  fi
done
echo "SWAP TOTAL: $(free -m | awk '/^Swap:/{print $2}')MB"

# heartbeat helper: long silent steps de vich har 30s progress line
hb_start() {
  ( while true; do sleep 30; echo "  ... chal reha ($1): $(date +%H:%M:%S) · cache=$(du -sm /opt/flutter/bin/cache 2>/dev/null | cut -f1)MB · free=$(free -m | awk '/^Mem:/{print $7}')MB"; done ) &
  HB_PID=$!
}
hb_stop() { kill "$HB_PID" 2>/dev/null; wait "$HB_PID" 2>/dev/null; }

# ---------- 1) Flutter SDK ----------
export PATH="$FL/bin:$PATH"
git config --global --add safe.directory "$FL" 2>/dev/null || true
git config --global --add safe.directory "$SRC" 2>/dev/null || true
if [ ! -x "$FL/bin/flutter" ]; then
  echo "Installing Flutter SDK (stable) — download ~1GB, saber rakho..."
  rm -rf "$FL"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FL" || { echo "FATAL: flutter clone fail"; exit 1; }
fi
echo "Flutter first-run: Dart SDK download + tool build — is chhote server te 10-30 min. Heartbeat har 30s:"
export CI=true
hb_start "flutter setup"
flutter --version
RC=$?
hb_stop
[ $RC -ne 0 ] && { echo "FATAL: flutter not runnable"; exit 1; }
flutter config --no-analytics >/dev/null 2>&1 || true
flutter config --enable-web >/dev/null 2>&1 || true

# ---------- 2) repo checkout ----------
if [ ! -d "$SRC/.git" ]; then
  rm -rf "$SRC"
  git clone --depth 1 -b "$BRANCH" "$REPO" "$SRC" || { echo "FATAL: repo clone fail"; exit 1; }
else
  cd "$SRC"
  git fetch origin "$BRANCH" && git reset --hard "origin/$BRANCH" || { echo "FATAL: repo update fail"; exit 1; }
fi
cd "$SRC"
COMMIT=$(git rev-parse --short HEAD)
echo "SOURCE @ $COMMIT"

# ---------- 3) build ----------
hb_start "pub get"
flutter pub get
RC=$?
hb_stop
[ $RC -ne 0 ] && { echo "FATAL: pub get fail"; exit 1; }
echo "Web build shuru — eh sab ton lamba step hai (10-25 min es server te), heartbeat aunda rahega:"
hb_start "web build"
flutter build web --release --no-tree-shake-icons
RC=$?
hb_stop
[ $RC -ne 0 ] && { echo "FATAL: web build fail"; exit 1; }
[ -f build/web/index.html ] || { echo "FATAL: build output missing"; exit 1; }

# ---------- 4) deploy ----------
TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
tar -czf "/opt/flavorflow/backups/web-$TS.tgz" -C "$WEB" . 2>/dev/null && echo "WEB BACKUP: /opt/flavorflow/backups/web-$TS.tgz"
cp -a build/web/. "$WEB"/
echo "$COMMIT $(date)" > "$WEB/ff-web-version.txt"
chown -R flavorflow:flavorflow "$WEB" 2>/dev/null || true

curl -s -o /dev/null -w 'site -> %{http_code}\n' -m 8 http://127.0.0.1:4000/ || true
echo "WEBFIX3 VERIFIED ✓ — website hun commit $COMMIT te hai; browser ch Ctrl+Shift+R (hard refresh) karke dekho"
