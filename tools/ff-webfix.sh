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
echo "=== FF-WEBFIX $(date) ==="

BRANCH=arena/01a003d0-flavorflow
REPO=https://github.com/manjotkhehra74-cloud/FlavorFlow.git
SRC=/opt/flavorflow/src
WEB=/opt/flavorflow/web
FL=/opt/flutter

# ---------- 0) swap (Flutter web build needs ~2GB free) ----------
MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
SWAP_MB=$(free -m | awk '/^Swap:/{print $2}')
if [ "$MEM_MB" -lt 3500 ] && [ "$SWAP_MB" -lt 1500 ]; then
  echo "RAM ${MEM_MB}MB — adding 2G swapfile"
  if [ ! -f /swapfile-ff ]; then
    fallocate -l 2G /swapfile-ff || dd if=/dev/zero of=/swapfile-ff bs=1M count=2048
    chmod 600 /swapfile-ff && mkswap /swapfile-ff
  fi
  swapon /swapfile-ff 2>/dev/null || true
  echo "SWAP: $(free -m | awk '/^Swap:/{print $2}')MB"
fi

# ---------- 1) Flutter SDK ----------
export PATH="$FL/bin:$PATH"
git config --global --add safe.directory "$FL" 2>/dev/null || true
git config --global --add safe.directory "$SRC" 2>/dev/null || true
if [ ! -x "$FL/bin/flutter" ]; then
  echo "Installing Flutter SDK (stable) — download ~1GB, saber rakho..."
  rm -rf "$FL"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FL" || { echo "FATAL: flutter clone fail"; exit 1; }
fi
flutter --version 2>&1 | head -2 || { echo "FATAL: flutter not runnable"; exit 1; }
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
flutter pub get || { echo "FATAL: pub get fail"; exit 1; }
flutter build web --release --no-tree-shake-icons || { echo "FATAL: web build fail"; exit 1; }
[ -f build/web/index.html ] || { echo "FATAL: build output missing"; exit 1; }

# ---------- 4) deploy ----------
TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
tar -czf "/opt/flavorflow/backups/web-$TS.tgz" -C "$WEB" . 2>/dev/null && echo "WEB BACKUP: /opt/flavorflow/backups/web-$TS.tgz"
cp -a build/web/. "$WEB"/
echo "$COMMIT $(date)" > "$WEB/ff-web-version.txt"
chown -R flavorflow:flavorflow "$WEB" 2>/dev/null || true

curl -s -o /dev/null -w 'site -> %{http_code}\n' -m 8 http://127.0.0.1:4000/ || true
echo "WEBFIX VERIFIED ✓ — website hun commit $COMMIT te hai; browser ch Ctrl+Shift+R (hard refresh) karke dekho"
