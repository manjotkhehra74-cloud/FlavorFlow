#!/usr/bin/env bash
# FlavorFlow BOOT / REPAIR — VM te kamm BINA SSH DE (GCE startup-script rahin).
#
# PHONE TON (SSH-in-browser retry/expire hove ta):
#   console.cloud.google.com → Compute Engine → VM instances → VM te tap → EDIT
#   → thalle "Automation" → "Startup script" box vich eh 2 line paste:
#       #!/bin/bash
#       curl -fsSL https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a0858b-flavorflow/tools/ff-boot.sh | bash
#   → SAVE → VM page te ⋮ → RESET (STOP/START nahi — ephemeral IP badal sakdi hai)
#   → 2-3 min baad result browser vich:  https://flavorflow.co.in/download/boot-status.txt
#   (poora log: VM → "Serial port 1 (console)" ya /var/log/ff-boot.log)
#
# Steps (arg naal chuno, default sab):  fixssh industry apk
#   fixssh   — memory/OOM/swap snapshot, swap ensure, google-guest-agent + sshd restart
#              (SSH-in-browser "Connection failed… retrying" aksar guest-agent/RAM karke)
#   industry — tools/ff-saasindustry.sh (idempotent) + tenant /api/settings/company verify
#   apk      — tools/ff-apkpublish.sh ci (CircleCI di navi successful APK → website)
# SSH ton vi:  curl -fsSL .../ff-boot.sh | sudo bash -s apk
# Har boot te dubara chalna safe hai (sab idempotent). Startup script baad vich
# VM → EDIT → Startup script khali karke hata sakde ho.
set -u
main() {
  local RAW WEB LOG STATUS STEPS OUT RC code
  RAW="https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/${FF_BRANCH:-arena/01a0858b-flavorflow}/tools"
  WEB="${FF_WEB:-/opt/flavorflow-saas/web}"
  LOG=/var/log/ff-boot.log
  STATUS="$WEB/download/boot-status.txt"
  STEPS="${*:-fixssh industry apk}"
  mkdir -p "$WEB/download"
  exec > >(tee -a "$LOG") 2>&1
  : > "$STATUS"; chmod 644 "$STATUS"
  st() { echo "$*" | tee -a "$STATUS"; }
  fetch() { curl -fsSL -m 40 --retry 3 --retry-delay 5 "$1" -o "$2" </dev/null && [ -s "$2" ] && head -1 "$2" | grep -q '^#!'; }
  st "=== FF-BOOT $(date -u +%FT%TZ) host=$(hostname) steps=[$STEPS] ==="
  [ "$(id -u)" = 0 ] || st "WARN: root nahi (sudo naal chalao) — kuch steps fail honge"

  # ---------- fixssh ----------
  if [[ " $STEPS " == *" fixssh "* ]]; then
    st "[fixssh] up: $(uptime -p 2>/dev/null)  load: $(cut -d' ' -f1-3 /proc/loadavg)"
    st "[fixssh] mem: $(free -m | awk '/Mem:/{m=$3"/"$2"MB used"} /Swap:/{s="swap "$3"/"$2"MB"} END{print m", "s}')"
    st "[fixssh] disk /: $(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')"
    st "[fixssh] OOM kills (2 days): $(journalctl -k --since '2 days ago' 2>/dev/null | grep -ciE 'out of memory|oom-kill'; true)"
    st "[fixssh] top RAM: $(ps -eo rss,comm --sort=-rss | awk 'NR>1&&NR<7{printf "%s %dMB; ",$2,$1/1024}')"
    if ! swapon --show 2>/dev/null | grep -q '/swapfile'; then
      { fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none; } 2>/dev/null
      if chmod 600 /swapfile && mkswap /swapfile >/dev/null 2>&1 && swapon /swapfile; then
        grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        st "[fixssh] swap 2G created ✓"
      else st "[fixssh] swap create FAIL"; fi
    fi
    if systemctl list-unit-files 2>/dev/null | grep -q '^google-guest-agent'; then
      systemctl restart google-guest-agent </dev/null 2>/dev/null
      st "[fixssh] google-guest-agent: $(systemctl is-active google-guest-agent 2>/dev/null) (restarted)"
    else st "[fixssh] google-guest-agent: not installed?!"; fi
    systemctl restart ssh </dev/null 2>/dev/null || systemctl restart sshd </dev/null 2>/dev/null
    st "[fixssh] sshd: $(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null)  port22 listeners: $(ss -ltn 2>/dev/null | grep -c ':22 ')"
    st "[fixssh] services: caddy=$(systemctl is-active caddy 2>/dev/null) flavorflow-saas=$(systemctl is-active flavorflow-saas 2>/dev/null)"
  fi

  # service/caddy nu boot te 1 min tak time dio
  for _ in $(seq 1 20); do
    curl -s -m 4 http://127.0.0.1:4100/api/saas/health 2>/dev/null | grep -q '"ok":true' && break; sleep 3
  done
  st "[saas] health: $(curl -s -m 6 http://127.0.0.1:4100/api/saas/health 2>/dev/null | head -c 100)"

  # ---------- industry ----------
  if [[ " $STEPS " == *" industry "* ]]; then
    if [ -f /opt/flavorflow-saas/core/server.js ]; then
      st "[industry] core ffIndustrySeed before: $(grep -c 'ffIndustrySeed' /opt/flavorflow-saas/core/server.js)"
      OUT=""; RC=1
      if fetch "$RAW/ff-saasindustry.sh" /tmp/ff-saasindustry.sh; then OUT=$(bash /tmp/ff-saasindustry.sh </dev/null 2>&1); RC=$?; fi
      if [ -z "$OUT" ]; then st "[industry] script download FAIL (GitHub reach nahi hoya?)"; else
        echo "$OUT"
        echo "$OUT" | grep -E '^(GATEWAY|CORE|DISPATCH|TENANT|SYNTAX|PATCH|NOTHING|SAASINDUSTRY|FATAL)' | cut -c1-200 | sed 's/^/[industry] /' | tee -a "$STATUS"
      fi
      st "[industry] rc=$RC  core ffIndustrySeed after: $(grep -c 'ffIndustrySeed' /opt/flavorflow-saas/core/server.js)"
      sleep 3
      # jo phone dekhda hai ohi rasta: caddy → gateway → tenant
      for code in $(node -e 'try{const r=require("/opt/flavorflow-saas/data/registry.json");console.log(Object.keys(r.companies||{}).join(" "))}catch(e){}' 2>/dev/null); do
        OUT=$(curl -sk -m 8 --resolve app.flavorflow.co.in:443:127.0.0.1 -w ' [%{http_code}]' "https://app.flavorflow.co.in/t/$code/api/settings/company" 2>/dev/null)
        st "[verify] /t/$code/api/settings/company → $(echo "$OUT" | grep -o '\[[0-9]*\]$') $(echo "$OUT" | grep -o '"industry":"[^"]*"' | head -1) $(echo "$OUT" | grep -o '"error":"[^"]*"' | head -1)"
      done
    else st "[industry] /opt/flavorflow-saas/core/server.js nahi — eh SaaS VM nahi? skip"; fi
  fi

  # ---------- apk ----------
  if [[ " $STEPS " == *" apk "* ]]; then
    OUT=""; RC=1
    if fetch "$RAW/ff-apkpublish.sh" /tmp/ff-apkpublish.sh; then OUT=$(bash /tmp/ff-apkpublish.sh ci </dev/null 2>&1); RC=$?; fi
    if [ -z "$OUT" ]; then st "[apk] script download FAIL (GitHub reach nahi hoya?)"; else
      echo "$OUT"
      echo "$OUT" | grep -E 'CircleCI build|download:|APK:|✗|placed|eho APK|FATAL|VERIFIED|HTTP/' | cut -c1-200 | sed 's/^/[apk] /' | tee -a "$STATUS"
    fi
    st "[apk] rc=$RC  live: $(sed -n 's/^build: //p' "$WEB/download/apk-info.txt" 2>/dev/null)"
  fi

  st "=== FF-BOOT DONE $(date -u +%FT%TZ) ==="
  st "APK: https://flavorflow.co.in/download/flavorflow-erp.apk   info: /download/apk-info.txt"
}
main "$@"
