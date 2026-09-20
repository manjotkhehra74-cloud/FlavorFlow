#!/usr/bin/env bash
# FlavorFlow ERP — full stack restart + diagnosis (nginx + node + TLS).
# Use when the API does not answer at all (port 443/80 dead, not a 500).
# Safe to re-run. Touches no data.
set -u
echo "=== FF-SERVER-FIX2 $(date) ==="

echo "--- 1. box ---"
uptime
df -h / | tail -1
free -m | head -2

echo "--- 2. nginx ---"
systemctl is-active --quiet nginx && echo "nginx: running" || { echo "nginx: DOWN -> restart"; systemctl restart nginx || true; sleep 2; }
systemctl is-active --quiet nginx && echo "nginx: RUNNING now" || echo "nginx: STILL DOWN"
nginx -t 2>&1 | tail -2

echo "--- 3. flavorflow node ---"
systemctl restart flavorflow || true
sleep 4
systemctl is-active --quiet flavorflow && echo "flavorflow: RUNNING" || echo "flavorflow: STILL DOWN"
ss -ltnp 2>/dev/null | grep -E ':4000|:80 |:443 ' || echo "NO ports 4000/80/443 listening"

echo "--- 4. local health ---"
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "LOCAL HEALTH FAIL"

echo "--- 5. external health (through nginx) ---"
curl -s -m 8 -o /dev/null -w "https local->ext: HTTP:%{http_code}\n" https://flavorflow.duckdns.org/api/health || true

if ! systemctl is-active --quiet flavorflow; then
  echo "--- 6. node logs ---"
  journalctl -u flavorflow -n 25 --no-pager
fi
if ! systemctl is-active --quiet nginx; then
  echo "--- 7. nginx logs ---"
  journalctl -u nginx -n 15 --no-pager
  tail -5 /var/log/nginx/error.log 2>/dev/null
fi
echo "=== DONE ==="
