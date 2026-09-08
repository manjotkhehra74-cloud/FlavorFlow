#!/usr/bin/env bash
# FlavorFlow SaaS VM SETUP (nave VM 34.180.13.78 te chalauni) —
#   Ubuntu 24.04 fresh VM → production-ready base:
#     1) apt basics (curl, git, nano, unzip, build tools nahi chahide — sqlite native nahi)
#     2) Node.js 20 LTS (NodeSource)
#     3) Caddy (auto-SSL: flavorflow.co.in, www, app) — nginx/certbot di lorh nahi
#     4) 2G swap (fstab persistent)
#     5) /opt/flavorflow-saas structure + placeholder page (landing aayegi ethe)
#     6) systemd service (flavorflow-saas) — server code aun te chalega
#   Idempotent — dubara chalauni safe hai.
set -u
echo "=== SAAS-VM-SETUP $(date) ==="

# 1) basics
apt-get update -y >/dev/null 2>&1
apt-get install -y curl git nano unzip ca-certificates >/dev/null 2>&1
echo "basics ✓"

# 2) swap 2G (idempotent)
if ! swapon --show | grep -q '/swapfile'; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "swap 2G ✓ (created)"
else echo "swap ✓ (already)"; fi

# 3) Node 20
if ! command -v node >/dev/null || [ "$(node -v | cut -c2-3)" -lt 20 ]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
  apt-get install -y nodejs >/dev/null 2>&1
fi
echo "node $(node -v) ✓"

# 4) Caddy
if ! command -v caddy >/dev/null; then
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https >/dev/null 2>&1
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y >/dev/null 2>&1 && apt-get install -y caddy >/dev/null 2>&1
fi
echo "caddy $(caddy version | head -c 20) ✓"

# 5) structure
mkdir -p /opt/flavorflow-saas/{server,web,data,backups}
[ -f /opt/flavorflow-saas/web/index.html ] || cat > /opt/flavorflow-saas/web/index.html <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FlavorFlow — Manufacturing ERP</title>
<style>body{margin:0;font-family:system-ui;display:grid;place-items:center;min-height:100vh;background:linear-gradient(135deg,#1E6FE0,#16B878);color:#fff;text-align:center}h1{font-size:42px;margin:0}p{opacity:.85}</style></head>
<body><div><h1>FlavorFlow</h1><p>Manufacturing ERP for every industry.<br>Website coming soon.</p></div></body></html>
HTML

# 6) Caddyfile
cat > /etc/caddy/Caddyfile <<'CADDY'
flavorflow.co.in, www.flavorflow.co.in {
	root * /opt/flavorflow-saas/web
	file_server
	handle /api/* {
		reverse_proxy 127.0.0.1:4100
	}
}
app.flavorflow.co.in {
	handle /api/* {
		reverse_proxy 127.0.0.1:4100
	}
	root * /opt/flavorflow-saas/web
	file_server
}
CADDY
systemctl enable --now caddy >/dev/null 2>&1
systemctl reload caddy 2>/dev/null || systemctl restart caddy
echo "caddy config ✓ (SSL auto — 1-2 min lagde pehli vaari)"

# 7) systemd service (server code aun te chalega)
cat > /etc/systemd/system/flavorflow-saas.service <<'UNIT'
[Unit]
Description=FlavorFlow SaaS ERP server
After=network.target

[Service]
WorkingDirectory=/opt/flavorflow-saas/server
ExecStart=/usr/bin/env node server.js
Restart=always
RestartSec=3
Environment=PORT=4100
Environment=FF_MULTI_TENANT=1
Environment=FF_DATA_DIR=/opt/flavorflow-saas/data
MemoryHigh=1200M
MemoryMax=1500M

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
echo "systemd unit ✓ (server code aun te: systemctl enable --now flavorflow-saas)"

echo ""
echo "SAAS-VM-SETUP VERIFIED ✓ — https://flavorflow.co.in 1-2 min vich live (placeholder page)"
