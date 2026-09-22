#!/usr/bin/env bash
# FlavorFlow ERP — permissions + "Enter Supplier Bill" error diagnosis.
# Read-only: dumps the server's permission catalogue (from source), the
# roles/permissions tables, and the recent server errors (403 / 500).
# HOW TO USE: in the app tap the thing that errors FIRST, then run this.
set -u
echo "=== FF-PERMDIAG $(date) ==="
SRV=/opt/flavorflow/server
DB=$SRV/data/erp.db
[ -f "$DB" ] || { echo "DB nahi mili: $DB"; exit 1; }

echo "--- 1. permission keys the SERVER actually checks (requirePerm) ---"
grep -rhoE "requirePerm\('[^']+'\)" "$SRV"/routes "$SRV"/*.js 2>/dev/null | sed "s/requirePerm('//;s/')//" | sort -u | tr '\n' ' '
echo ""

echo "--- 2. tables (permissions/roles wali) ---"
sqlite3 -header -column "$DB" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;" 2>&1 | head -40

for T in roles permissions role_permissions perms; do
  N=$(sqlite3 "$DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$T';" 2>/dev/null)
  if [ "${N:-0}" != "0" ]; then
    echo "--- table: $T (schema) ---"
    sqlite3 "$DB" "PRAGMA table_info($T);" 2>&1
    echo "--- table: $T (rows) ---"
    sqlite3 -header -column "$DB" "SELECT * FROM $T;" 2>&1 | head -40
  fi
done

echo "--- 3. users (id, name, email, role) ---"
sqlite3 -header -column "$DB" "SELECT id, name, email, role FROM users ORDER BY id;" 2>&1 | head -50

echo "--- 4. server errors / 403 in last 20 min ---"
journalctl -u flavorflow --since "-20min" --no-pager 2>/dev/null | grep -iE "403|not allowed|forbidden|permission|UNIQUE|error|exception" | tail -30

echo "--- 5. last 20 raw log lines ---"
journalctl -u flavorflow -n 20 --no-pager 2>/dev/null

echo "--- 6. health ---"
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH FAIL"
echo "=== DONE ==="
