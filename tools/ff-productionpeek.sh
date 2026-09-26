#!/usr/bin/env bash
# Read-only: show the live production completion route and DB triggers related
# to produced/used stock. No database or server changes.
set -u
DIR=/opt/flavorflow/server
DB="$DIR/data/erp.db"
[ -d "$DIR" ] || { echo "FATAL: server directory missing"; exit 1; }
[ -f "$DB" ] || { echo "FATAL: database missing"; exit 1; }
echo "=== FF-PRODUCTIONPEEK $(date) ==="
for f in "$DIR/routes/production.js" "$DIR/routes/inventory.js" "$DIR/batchrecon.js"; do
  [ -f "$f" ] || continue
  echo "--- $f: production/complete + produced/used/inventory references ---"
  grep -n -E "complete|produced_cb|used_cb|producedCb|inventory|qty_cb" "$f" | head -160 || true
done
echo "--- SQLite triggers touching batches/inventory ---"
if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "$DB" "SELECT name, sql FROM sqlite_master WHERE type='trigger' AND (lower(sql) LIKE '%batches%' OR lower(sql) LIKE '%inventory%');"
else
  node - <<'JS'
let db;
try { db = require('/opt/flavorflow/server/db'); } catch (e) { console.log('DB OPEN FAILED: ' + e.message); process.exit(1); }
for (const r of db.prepare("SELECT name, sql FROM sqlite_master WHERE type='trigger' AND (lower(sql) LIKE '%batches%' OR lower(sql) LIKE '%inventory%')").all()) console.log(JSON.stringify(r));
try { db.close(); } catch (_) {}
JS
fi
echo "--- health ---"
curl -s -m 6 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAILED"
echo "=== READ ONLY DONE ==="
