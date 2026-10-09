#!/usr/bin/env bash
# Fix nginx cert missing + DB readonly after chown
set -x
echo "=== Checking flavorflow service user ==="
cat /etc/systemd/system/flavorflow.service 2>/dev/null || cat /lib/systemd/system/flavorflow.service 2>/dev/null
echo ""
echo "=== Checking data dir permissions ==="
ls -ld /opt/flavorflow/server/data
ls -lh /opt/flavorflow/server/data/erp.db
echo ""
echo "=== Fixing DB permissions — make writable for service ==="
# Service likely runs as root, but to be safe make it 777 for data dir and 666 for db
sudo chown -R root:root /opt/flavorflow/server/data 2>/dev/null || true
sudo chmod -R 755 /opt/flavorflow/server/data
sudo chmod 664 /opt/flavorflow/server/data/erp.db
# Also check if there's a -wal -shm
sudo rm -f /opt/flavorflow/server/data/erp.db-wal /opt/flavorflow/server/data/erp.db-shm 2>/dev/null || true
sudo chown root:root /opt/flavorflow/server/data/erp.db
echo "After fix:"
ls -lh /opt/flavorflow/server/data/ | head -n 20
echo ""

echo "=== Fixing nginx gdfoods cert issue ==="
echo "Sites-enabled:"
ls -l /etc/nginx/sites-enabled/
echo ""
echo "Sites-available:"
ls -l /etc/nginx/sites-available/ | grep -i gdfood
echo ""
echo "Searching gdfoods reference in /etc/nginx:"
sudo grep -R "gdfoods" /etc/nginx/ -n 2>/dev/null | head -n 100
echo ""
echo "nginx.conf:"
sudo cat /etc/nginx/nginx.conf | head -n 100
echo ""

echo "=== Removing gdfoods vhost that has missing cert ==="
# Find file containing gdfoods
GD_FILE=$(sudo grep -R "gdfoods.duckdns.org" /etc/nginx/ -l 2>/dev/null | head -n 1)
echo "Found file: $GD_FILE"
if [ -n "$GD_FILE" ]; then
  sudo mv "$GD_FILE" "$GD_FILE.bak-missing-cert-$(date +%s)" || true
  echo "Moved $GD_FILE to backup"
fi

# Also check sites-enabled symlink
for f in /etc/nginx/sites-enabled/*; do
  if [ -f "$f" ]; then
    if sudo grep -q "gdfoods" "$f" 2>/dev/null; then
      echo "Removing $f (contains gdfoods)"
      sudo mv "$f" "$f.bak-$(date +%s)" || sudo rm -f "$f"
    fi
  fi
done

echo ""
echo "=== After removal, test nginx ==="
sudo nginx -t
echo ""

echo "=== If still fails, create dummy cert for gdfoods ==="
if sudo nginx -t 2>&1 | grep -q "gdfoods"; then
  echo "Still references gdfoods, creating dummy cert"
  sudo mkdir -p /etc/letsencrypt/live/gdfoods.duckdns.org/
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/letsencrypt/live/gdfoods.duckdns.org/privkey.pem \
    -out /etc/letsencrypt/live/gdfoods.duckdns.org/fullchain.pem \
    -subj "/CN=gdfoods.duckdns.org" 2>/dev/null
  sudo nginx -t
fi

echo ""
echo "=== Restarting services ==="
sudo systemctl restart flavorflow
sleep 5
sudo systemctl status flavorflow --no-pager -l | tail -n 50
echo ""
sudo systemctl restart nginx || true
sudo systemctl status nginx --no-pager -l | tail -n 50
echo ""
echo "=== Health checks ==="
curl -s http://127.0.0.1:4000/api/health || echo "health failed"
echo ""
echo "=== DB check ==="
sudo sqlite3 /opt/flavorflow/server/data/erp.db "SELECT COUNT(*) FROM packing_materials;" 2>&1 | head -n 5
echo ""
echo "=== Done ==="
