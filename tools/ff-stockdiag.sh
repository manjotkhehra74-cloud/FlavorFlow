#!/usr/bin/env bash
# FlavorFlow ERP — "stock already dispatched but still showing" diagnosis.
# Read-only. Prints:
#   1. the server code that moves stock on dispatch (used_cb / inventory)
#   2. product-level reconciliation (inventory vs dispatched vs produced/used)
#   3. batch-level reconciliation (produced − used vs dispatch_items per code)
#   4. how many dispatch rows carry no batch_code (un-attributable stock)
set -u
echo "=== FF-STOCKDIAG $(date) ==="
SRV=/opt/flavorflow/server
DB=$SRV/data/erp.db
[ -f "$DB" ] || { echo "DB nahi mili: $DB"; exit 1; }

echo "--- 1. server code: where stock moves on dispatch ---"
grep -rn "used_cb\|used_trays" "$SRV"/routes/*.js 2>/dev/null | head -25
echo "--- dispatch_items INSERT (context) ---"
grep -n "INSERT INTO dispatch_items" "$SRV"/routes/*.js 2>/dev/null | cut -d: -f1,2 | while IFS=: read -r file n; do
  a=$((n-12)); [ $a -lt 1 ] && a=1
  echo "### $file around line $n"
  sed -n "${a},$((n+10))p" "$file"
done

echo "--- 2. product reconciliation (inventory vs dispatched vs produced/used) ---"
sqlite3 -header -column "$DB" "
SELECT substr(p.name,1,28) name,
       COALESCE(i.qty_cb,0) inv_cb,
       COALESCE(i.qty_trays,0) inv_tr,
       COALESCE(ds.cb,0) disp_cb,
       COALESCE(bb.prod_cb,0) prod_cb,
       COALESCE(bb.used_cb,0) used_cb
FROM products p
LEFT JOIN inventory i ON i.product_id = p.id
LEFT JOIN (SELECT di.product_id pid, SUM(COALESCE(di.cartons,0)) cb
           FROM dispatch_items di JOIN dispatches d ON d.id = di.dispatch_id
           WHERE UPPER(COALESCE(d.status,'DISPATCHED')) <> 'VOID'
           GROUP BY di.product_id) ds ON ds.pid = p.id
LEFT JOIN (SELECT product_id pid, SUM(COALESCE(produced_cb,0)) prod_cb, SUM(COALESCE(used_cb,0)) used_cb
           FROM batches WHERE UPPER(status)='COMPLETED' GROUP BY product_id) bb ON bb.pid = p.id
WHERE COALESCE(p.active,1)=1
ORDER BY COALESCE(i.qty_cb,0) DESC LIMIT 20;"

echo "--- 3. batches that still show stock (produced - used > 0) vs dispatch for that code ---"
sqlite3 -header -column "$DB" "
SELECT b.id, b.code, b.produced_cb, COALESCE(b.used_cb,0) used_cb,
       b.produced_cb - COALESCE(b.used_cb,0) left_cb,
       COALESCE(dc.cb,0) disp_for_code
FROM batches b
LEFT JOIN (SELECT batch_code, SUM(COALESCE(cartons,0)) cb FROM dispatch_items
           WHERE batch_code IS NOT NULL AND batch_code <> '' GROUP BY batch_code) dc
       ON dc.batch_code = b.code
WHERE UPPER(b.status)='COMPLETED' AND (b.produced_cb - COALESCE(b.used_cb,0)) > 0
ORDER BY b.id DESC LIMIT 20;"

echo "--- 4. dispatch lines with NO batch code (stock that can never be deducted) ---"
sqlite3 "$DB" "SELECT COUNT(*) total_lines, SUM(CASE WHEN batch_code IS NULL OR batch_code='' THEN 1 ELSE 0 END) no_code FROM dispatch_items;"

echo "--- 5. recent dispatches ---"
sqlite3 -header -column "$DB" "SELECT id, code, date, status FROM dispatches ORDER BY id DESC LIMIT 10;"

echo "--- 6. health ---"
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH FAIL"
echo "=== DONE ==="
