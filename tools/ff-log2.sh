#!/usr/bin/env bash
# FlavorFlow: collect request log + publish to web dir.
set -u
WB=$(find /opt/flavorflow /var/www /home /srv -maxdepth 6 -name main.dart.js -printf '%h\n' 2>/dev/null | head -1)
echo "WEBBUILD: ${WB:-NOT FOUND}"
if [ -f /tmp/ff-requests.log ]; then
  echo "--- REQUEST LOG (last 40) ---"
  tail -40 /tmp/ff-requests.log
  echo "--- SUMMARY ---"
  echo "TOTAL LINES: $(wc -l < /tmp/ff-requests.log)"
  echo "POST /users WITH permissions body: $(grep -c 'POST /users.*permissions' /tmp/ff-requests.log || true)"
  echo "POST /users WITHOUT permissions: $(grep 'POST /users' /tmp/ff-requests.log 2>/dev/null | grep -vc permissions || true)"
  if [ -n "${WB:-}" ]; then
    cp /tmp/ff-requests.log "$WB/ff-requests.txt" && echo "COPIED -> $WB/ff-requests.txt"
  fi
  curl -s -o /dev/null -w 'URL CHECK -> %{http_code}\n' -m 8 "https://flavorflow.duckdns.org/ff-requests.txt"
else
  echo "LOG MISSING — pehla ff-check.sh chalao"
fi
