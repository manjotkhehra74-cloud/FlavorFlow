#!/usr/bin/env bash
# FlavorFlow ERP — "which batch is showing stock it no longer has?"
# Read-only. Lists every COMPLETED batch that still shows stock, OLDEST FIRST
# (the stale ones are usually old), with how many days old it is.
# Tell me (or note) the ID(s) that are physically gone — they get cleared next.
set -u
DB=/opt/flavorflow/server/data/erp.db
[ -f "$DB" ] || { echo "DB nahi mili: $DB"; exit 1; }
echo "=== FF-STOCKDIAG2 $(date) ==="

echo "--- batches still showing stock (oldest first) ---"
sqlite3 -header -column "$DB" "
SELECT b.id, b.code, substr(COALESCE(p.name,'?'),1,22) product,
       COALESCE(b.planned_date,'') planned_date,
       b.produced_cb, COALESCE(b.used_cb,0) used_cb,
       b.produced_cb - COALESCE(b.used_cb,0) left_cb,
       CAST(julianday('now') - julianday(COALESCE(b.planned_date,''))) AS INTEGER days_old
FROM batches b LEFT JOIN products p ON p.id = b.product_id
WHERE UPPER(COALESCE(b.status,''))='COMPLETED'
  AND (b.produced_cb - COALESCE(b.used_cb,0)) > 0
ORDER BY COALESCE(b.planned_date,'') ASC, b.id ASC
LIMIT 30;"

echo "--- per product: how much stock is still shown ---"
sqlite3 -header -column "$DB" "
SELECT substr(COALESCE(p.name,'?'),1,26) product,
       COUNT(*) batches_with_stock,
       SUM(b.produced_cb - COALESCE(b.used_cb,0)) left_cb
FROM batches b LEFT JOIN products p ON p.id = b.product_id
WHERE UPPER(COALESCE(b.status,''))='COMPLETED'
  AND (b.produced_cb - COALESCE(b.used_cb,0)) > 0
GROUP BY b.product_id
ORDER BY left_cb DESC LIMIT 20;"

echo "--- total still shown (all completed batches) ---"
sqlite3 "$DB" "SELECT COALESCE(SUM(produced_cb - COALESCE(used_cb,0)),0) FROM batches WHERE UPPER(COALESCE(status,''))='COMPLETED';"
echo "=== DONE ==="
