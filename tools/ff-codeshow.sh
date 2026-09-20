#!/usr/bin/env bash
# FlavorFlow ERP — print the exact INSERT/UPDATE lines for batches
# (with context) so the plan_unit stamping bug can be patched precisely.
# Read-only. Prints no secrets (passwords/keys are skipped).
set -u
F=/opt/flavorflow/server/routes/production.js
[ -f "$F" ] || { echo "FILE NOT FOUND: $F"; exit 1; }
echo "=== FF-CODESHOW $(date) ==="
echo "lines: $(wc -l < "$F")"

echo "--- all lines mentioning batches/plan_unit/planUnit ---"
grep -n -E "batches|plan_unit|planUnit|plannedUnit" "$F" | head -60

echo "--- INSERT INTO batches (context +-10) ---"
grep -n "INSERT INTO batches" "$F" | cut -d: -f1 | while read -r n; do
  a=$((n-10)); [ $a -lt 1 ] && a=1; b=$((n+12))
  echo "### around line $n"
  sed -n "${a},${b}p" "$F"
done

echo "--- UPDATE batches (context +-8) ---"
grep -n "UPDATE batches" "$F" | cut -d: -f1 | while read -r n; do
  a=$((n-8)); [ $a -lt 1 ] && a=1; b=$((n+8))
  echo "### around line $n"
  sed -n "${a},${b}p" "$F"
done
echo "=== DONE ==="
