#!/usr/bin/env bash
# FlavorFlow ERP — "dispatched stock never clears from Inventory" diagnosis.
# Read-only. Prints:
#   1. the server code behind GET /inventory and PUT /inventory/stock
#      (does setting stock also clear the batch register? — the suspected bug)
#   2. per product: inventory qty vs batch-register qty (drift) + active flag
#   3. deleted (active = 0) products that still hold stock / batches
#   4. inventory rows whose product is gone
set -u
SRV=/opt/flavorflow/server
DB=$SRV/data/erp.db
[ -f "$DB" ] || { echo "DB nahi mili: $DB"; exit 1; }
echo "=== FF-INVDIAG $(date) ==="

echo "--- 1. inventory route code (GET /inventory + PUT /inventory/stock) ---"
grep -rn "inventory/stock\|'/inventory'" "$SRV"/routes/*.js 2>/dev/null | head -10
for pat in "inventory/stock" "router.get('/inventory'"; do
  grep -rn "$pat" "$SRV"/routes/*.js 2>/dev/null | cut -d: -f1,2 | while IFS=: read -r file n; do
    a=$((n-6)); [ $a -lt 1 ] && a=1
    echo "### $file around line $n"
    sed -n "${a},$((n+34))p" "$file"
  done
done

echo "--- 2. per product: inventory vs batch register (drift) ---"
sqlite3 -header -column "$DB" "
SELECT p.id, substr(p.name,1,26) name, COALESCE(p.active,1) active,
       COALESCE(i.qty_cb,0) inv_cb,
       COALESCE(b.left_cb,0) batch_left,
       COALESCE(i.qty_cb,0) - COALESCE(b.left_cb,0) drift
FROM products p
LEFT JOIN inventory i ON i.product_id = p.id
LEFT JOIN (SELECT product_id pid, SUM(produced_cb - COALESCE(used_cb,0)) left_cb
           FROM batches WHERE UPPER(COALESCE(status,''))='COMPLETED'
           GROUP BY product_id) b ON b.pid = p.id
ORDER BY (COALESCE(p.active,1)=1) DESC, COALESCE(b.left_cb,0) DESC
LIMIT 40;"

echo "--- 3. deleted (active=0) products still holding something ---"
sqlite3 -header -column "$DB" "
SELECT p.id, substr(p.name,1,26) name, COALESCE(i.qty_cb,0) inv_cb,
       COALESCE(b.left_cb,0) batch_left, COALESCE(b.n,0) completed_batches
FROM products p
LEFT JOIN inventory i ON i.product_id = p.id
LEFT JOIN (SELECT product_id pid, SUM(produced_cb - COALESCE(used_cb,0)) left_cb, COUNT(*) n
           FROM batches WHERE UPPER(COALESCE(status,''))='COMPLETED' GROUP BY product_id) b ON b.pid = p.id
WHERE COALESCE(p.active,1) = 0
ORDER BY COALESCE(b.left_cb,0) DESC LIMIT 20;"

echo "--- 4. inventory rows with no product / no batches ---"
sqlite3 -header -column "$DB" "
SELECT i.product_id, COALESCE(p.name,'(product missing)') name, i.qty_cb, i.qty_trays
FROM inventory i LEFT JOIN products p ON p.id = i.product_id
WHERE p.id IS NULL OR COALESCE(p.active,1)=0
LIMIT 20;"

echo "--- 5. health ---"
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH FAIL"
echo "=== DONE ==="
