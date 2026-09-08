#!/usr/bin/env bash
# FlavorFlow SaaS P1a: server code PACK (factory VM te chalauni) —
#   1) /opt/flavorflow/server da CODE tar vich (data/, node_modules, backups
#      SHAMIL NAHI — factory da data factory te hi rahega)
#   2) DIAGNOSIS print karda: db.js kiven export karda, server.js listen,
#      routes list, package.json deps — taan jo multi-tenant layer asli
#      code de hisaab naal design hove
#   Tar file: ~/flavorflow-server-pack.tar.gz  → SSH "DOWNLOAD FILE" naal
#   phone te lao, fer nave VM te "UPLOAD FILE" naal charhao.
# Read-only + pack — factory server nu koi chhed-chhad NAHI.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-SAASPACK $(date) ==="

OUT="$HOME/flavorflow-server-pack.tar.gz"
[ "$HOME" = "/root" ] && OUT="/home/manjotkhehra74/flavorflow-server-pack.tar.gz"

tar czf "$OUT" \
  --exclude='./data' \
  --exclude='./node_modules' \
  --exclude='*.bak-*' \
  --exclude='./backups' \
  .
chown manjotkhehra74:manjotkhehra74 "$OUT" 2>/dev/null || true
echo "PACK -> $OUT ($(du -h "$OUT" | cut -f1))"

echo ""
echo "===== DIAGNOSIS (eh sara output copy karke bhejna) ====="
echo "--- files ---"
ls -la | grep -v '.bak-' | head -25
echo "--- routes/ ---"
ls routes/ 2>/dev/null
echo "--- package.json deps ---"
grep -A15 '"dependencies"' package.json 2>/dev/null | head -20
echo "--- db.js (pehliyan 30 lines) ---"
head -30 db.js 2>/dev/null
echo "--- db.js export ---"
grep -n "module.exports" db.js 2>/dev/null
echo "--- server.js: listen + db require + app.use lines ---"
grep -n "listen\|require('./db')\|require(\"./db\")\|app.use(" server.js 2>/dev/null | head -20
echo "--- users/auth table hint ---"
grep -rn "CREATE TABLE.*users\|companies\|tenant" *.js routes/*.js 2>/dev/null | head -5
echo ""
echo "SAASPACK VERIFIED ✓ — hun: (1) eh output copy karke agent nu bhejo,"
echo "(2) SSH toolbar 'DOWNLOAD FILE' → path: $OUT"
