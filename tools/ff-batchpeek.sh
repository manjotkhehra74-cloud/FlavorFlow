#!/usr/bin/env bash
# FlavorFlow ERP — show what is actually stored for a batch code.
# Prints every BATCHES row for the code plus the last 10 planned batches,
# so we can see the real plan_unit / planned_date values (no guessing).
# Usage:  ... | sudo bash -s -- 610910BK
set -u
CODE="${1:-610910BK}"
echo "=== FF-BATCHPEEK $(date) code=$CODE ==="
DB=/opt/flavorflow/server/data/erp.db
[ -f "$DB" ] || { echo "DB nahi mili: $DB"; exit 1; }

run_sql () {
  local sql="$1"
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 -header -column "$DB" "$sql" 2>&1 | head -40
  else
    node -e '
      const p = process.argv[1], sql = process.argv[2];
      let db;
      for (const m of ["better-sqlite3","sqlite3","node:sqlite"]) {
        try { const M = require(m); db = M.default ? new M.default(p) : new M(p); break; } catch (e) {}
      }
      if (!db) { console.log("NO SQLITE DRIVER"); process.exit(0); }
      try { for (const r of db.prepare(sql).all()) console.log(JSON.stringify(r)); }
      catch (e) { console.log("SQL ERROR: " + e.message); }
    ' "$DB" "$sql"
  fi
}

echo "--- schema (batches) ---"
run_sql "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='batches';"
run_sql "PRAGMA table_info(batches);"

echo "--- rows for code $CODE ---"
run_sql "SELECT id, code, product_id, planned_date, plan_unit, planned_cb, planned_trays, status FROM batches WHERE code = '$CODE' ORDER BY id;"

echo "--- last 10 planned batches ---"
run_sql "SELECT id, code, product_id, planned_date, plan_unit, planned_cb, planned_trays FROM batches ORDER BY id DESC LIMIT 10;"
echo "=== DONE ==="
