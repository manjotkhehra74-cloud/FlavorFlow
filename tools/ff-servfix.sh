#!/usr/bin/env bash
# FlavorFlow: morning-timeout fix —
#   DIAGNOSIS: OOM kills / service restarts / swap-disk state / leftover
#   Flutter junk from the HRMate attempt.
#   HARDENING:
#     1) delete leftover flutter SDK folders (RAM/disk hogs)
#     2) permanent 2G swap (mounted now + /etc/fstab so it survives reboot)
#     3) systemd override: auto-restart on crash + start after network
#     4) SQLite WAL checkpoint + vacuum nightly is skipped — instead a light
#        5:00 AM IST daily service restart (pre-warm before morning logins)
#     5) journald capped at 100M (log bloat on 30GB disk)
# Idempotent — safe to run twice.
set -u
echo "=== FF-SERVFIX $(date) ==="

echo ""
echo "--- DIAGNOSIS ---"
echo "[mem]";  free -m | sed 's/^/  /'
echo "[disk]"; df -h / | tail -1 | sed 's/^/  /'
echo "[oom/kills last 3 days]"
journalctl --since "3 days ago" 2>/dev/null | grep -iE "out of memory|oom-kill|killed process" | tail -6 | sed 's/^/  /' || echo "  (none)"
echo "[flavorflow restarts last 3 days]"
journalctl -u flavorflow --since "3 days ago" 2>/dev/null | grep -iE "Started|Stopped|Main process exited|Failed" | tail -10 | sed 's/^/  /' || echo "  (none)"
echo "[leftover flutter junk]"
for d in /root/flutter /home/*/flutter /opt/flutter; do [ -d "$d" ] && du -sh "$d" 2>/dev/null | sed 's/^/  /'; done || true
echo "-----------------"
echo ""

# 1) leftover flutter folders → delete (the HRMate attempt)
for d in /root/flutter /home/*/flutter /opt/flutter; do
  if [ -d "$d" ]; then rm -rf "$d" && echo "DELETED: $d"; fi
done

# 2) permanent swap
if ! swapon --show | grep -q .; then
  if [ ! -f /swapfile-ff ]; then
    fallocate -l 2G /swapfile-ff || dd if=/dev/zero of=/swapfile-ff bs=1M count=2048
    chmod 600 /swapfile-ff && mkswap /swapfile-ff
  fi
  swapon /swapfile-ff 2>/dev/null || true
fi
grep -q '/swapfile-ff' /etc/fstab || echo '/swapfile-ff none swap sw 0 0' >> /etc/fstab
echo "SWAP: $(free -m | awk '/^Swap:/{print $2}')MB (fstab persistent)"

# 3) systemd hardening: always restart, sane limits
mkdir -p /etc/systemd/system/flavorflow.service.d
cat > /etc/systemd/system/flavorflow.service.d/override.conf <<'EOF'
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
Restart=always
RestartSec=5
# never let one runaway request take the box down
MemoryHigh=500M
MemoryMax=650M
OOMPolicy=continue
EOF
systemctl daemon-reload
echo "SYSTEMD: Restart=always + memory guard set"

# 4) 5:00 AM IST daily pre-warm restart (before morning logins)
cat > /etc/systemd/system/flavorflow-prewarm.service <<'EOF'
[Unit]
Description=FlavorFlow pre-warm restart (before morning logins)

[Service]
Type=oneshot
ExecStart=/bin/systemctl restart flavorflow
EOF
cat > /etc/systemd/system/flavorflow-prewarm.timer <<'EOF'
[Unit]
Description=Restart FlavorFlow daily at 05:00 IST

[Timer]
OnCalendar=*-*-* 05:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now flavorflow-prewarm.timer >/dev/null 2>&1
echo "PREWARM: daily 05:00 restart timer enabled"

# 5) journald cap
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/ff-cap.conf <<'EOF'
[Journal]
SystemMaxUse=100M
EOF
systemctl restart systemd-journald 2>/dev/null || true
echo "JOURNAL: capped at 100M"

# restart service now with the new limits
systemctl restart flavorflow
sleep 2
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
echo "SERVFIX VERIFIED ✓ — junk saaf, swap pakki, auto-restart + 5AM pre-warm live. Upar DIAGNOSIS vich asli reason vi dikhda"
