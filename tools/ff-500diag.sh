#!/usr/bin/env bash
# FlavorFlow ERP — catch the "Internal server error" (HTTP 500).
# HOW TO USE: in the app, do the action that shows the error FIRST,
# then run this within ~15 minutes. Prints only errors/5xx lines.
set -u
echo "=== FF-500DIAG $(date) ==="

# nginx has a broken vhost (missing gdfoods.duckdns.org cert) and is not
# the real server — Caddy holds 80/443. Just make sure it stays off.
systemctl is-active --quiet nginx && systemctl stop nginx || echo "nginx: already stopped (ok — Caddy serves 80/443)"
systemctl is-enabled --quiet nginx 2>/dev/null && systemctl disable nginx >/dev/null 2>&1 || true

echo "--- caddy: last 5xx responses ---"
journalctl -u caddy --since "-20min" --no-pager 2>/dev/null | grep -E '"status":5[0-9][0-9]|status=5[0-9][0-9]' | tail -20 || echo "(caddy journal nahi miliya)"
for L in /var/log/caddy/*.log /var/log/caddy/access.log; do
  [ -f "$L" ] && { echo "--- file: $L ---"; grep -E ' 5[0-9][0-9] ' "$L" | tail -20; }
done

echo "--- flavorflow: error lines (last 20 min) ---"
journalctl -u flavorflow --since "-20min" --no-pager | grep -iE "error|exception|unhandled|TypeError|SQLITE|rejection" | tail -40

echo "--- flavorflow: last 25 lines raw ---"
journalctl -u flavorflow -n 25 --no-pager

echo "--- node running? ---"
systemctl is-active --quiet flavorflow && echo "flavorflow: RUNNING" || echo "flavorflow: DOWN"
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "LOCAL HEALTH FAIL"
echo "=== DONE ==="
