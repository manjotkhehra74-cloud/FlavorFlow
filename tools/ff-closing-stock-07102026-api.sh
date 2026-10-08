#!/usr/bin/env bash
# FlavorFlow — 07/10/2026 closing stock reconciliation via API — DIRECT UPDATE, NO DEDUCTION.
# Final stock = physical count, no subtraction. Cross-check info only.
set -euo pipefail

API_BASE="${API_BASE:-http://127.0.0.1:4000/api}"
TOKEN="${TOKEN:-}"
COUNT_JSON="${FF_COUNT_JSON:-tools/data/closing-stock-07102026.json}"
CLOSING_DATE="2026-10-07"
START_DATE="2026-10-05"
APPLY=0
if [[ "${1:-}" == "--apply" ]]; then APPLY=1; fi

if [[ -z "$TOKEN" ]]; then echo "FATAL: TOKEN env required"; exit 1; fi
if ! command -v jq >/dev/null; then echo "FATAL: jq required"; exit 1; fi
if [[ ! -f "$COUNT_JSON" ]]; then echo "FATAL: count JSON not found: $COUNT_JSON"; exit 1; fi

echo "=== FF-CLOSING-STOCK-07102026-API (DIRECT UPDATE, NO DEDUCTION) ==="
echo "API: $API_BASE"
echo "Closing: $CLOSING_DATE | Window (info only): $START_DATE -> $CLOSING_DATE"
echo "Mode: $([ $APPLY -eq 1 ] && echo APPLY || echo DRY-RUN) — NO DEDUCTION"
echo ""

echo "Fetching /packing/materials ..."
MATERIALS=$(curl -sS -H "Authorization: Bearer $TOKEN" "$API_BASE/packing/materials")
if ! echo "$MATERIALS" | jq -e '.materials' >/dev/null 2>&1; then echo "FATAL: $MATERIALS"; exit 1; fi
echo "Got $(echo "$MATERIALS" | jq '.materials | length') materials"

echo "Fetching /production/batches (info only) ..."
BATCHES=$(curl -sS -H "Authorization: Bearer $TOKEN" "$API_BASE/production/batches" || echo '{"batches":[]}')
if echo "$BATCHES" | jq -e '.batches' >/dev/null 2>&1; then
  PROD=$(echo "$BATCHES" | jq --arg s "$START_DATE" --arg e "$CLOSING_DATE" '[.batches[] | select(.status=="COMPLETED" and .planned_date > $s and .planned_date <= $e)]')
  echo "Completed production in window (info only): $(echo "$PROD" | jq 'length')"
  echo "$PROD" | jq -r '.[] | "  \(.planned_date) | \(.product_name // .product_id) | CB \(.produced_cb // 0)"' | head -n 20
fi

echo ""
echo "Fetching /packing/ledger?type=CONSUMED (info only) ..."
LEDGER=$(curl -sS -H "Authorization: Bearer $TOKEN" "$API_BASE/packing/ledger?type=CONSUMED" || echo '{"txns":[]}')
if echo "$LEDGER" | jq -e '.txns' >/dev/null 2>&1; then
  CONS=$(echo "$LEDGER" | jq --arg s "$START_DATE" --arg e "$CLOSING_DATE" '[.txns[] | select(.txn_date > $s and .txn_date <= $e)] | group_by(.material_id) | map({material_id: .[0].material_id, material_name: .[0].material_name, qty: (map(.qty) | add)})')
  echo "Recorded consumption in window (info only, NOT deducted): $(echo "$CONS" | jq 'length')"
  echo "$CONS" | jq -r '.[] | "  #\(.material_id) \(.material_name): -\(.qty) (info only)"' | head -n 30
fi

echo ""
echo "=== MATCHING EXACT NAMES — DIRECT UPDATE ==="
echo "$MATERIALS" | jq -r '.materials[] | "\(.id)|\(.name)|\(.stock)|\(.category)|\(.unit)"' > /tmp/materials.txt

jq -c '.[]' "$COUNT_JSON" | while read -r row; do
  NAME=$(echo "$row" | jq -r '.name')
  COUNT=$(echo "$row" | jq -r '.count')
  KIND=$(echo "$row" | jq -r '.kind // ""')
  SHARED=$(echo "$row" | jq -r '.sharedGroup // ""')
  MATCH=$(grep -F "|$NAME|" /tmp/materials.txt || true)
  if [[ -z "$MATCH" ]]; then
    MATCH=$(grep -i -F "|$NAME|" /tmp/materials.txt || true)
    if [[ -n "$MATCH" ]]; then echo "WARN case mismatch for \"$NAME\" -> $MATCH"; else echo "NOT FOUND: \"$NAME\""; continue; fi
  fi
  LINES=$(echo "$MATCH" | wc -l)
  if [[ "$LINES" -ne 1 ]]; then echo "AMBIGUOUS: \"$NAME\" $LINES matches"; continue; fi
  ID=$(echo "$MATCH" | cut -d'|' -f1)
  DB_NAME=$(echo "$MATCH" | cut -d'|' -f2)
  STOCK=$(echo "$MATCH" | cut -d'|' -f3)
  CAT=$(echo "$MATCH" | cut -d'|' -f4)
  UNIT=$(echo "$MATCH" | cut -d'|' -f5)
  if [[ "$KIND" == "raw" && "$CAT" != "Raw Material" ]]; then echo "CATEGORY MISMATCH raw: $NAME is $CAT"; continue; fi
  if [[ "$KIND" == "packing" && "$CAT" == "Raw Material" ]]; then echo "CATEGORY MISMATCH packing: $NAME is $CAT"; continue; fi
  FINAL=$COUNT
  echo "MATCH \"$NAME\" -> #$ID \"$DB_NAME\" | current=$STOCK $UNIT | physical $COUNT $UNIT | FINAL $FINAL $UNIT (NO DEDUCTION)${SHARED:+ | shared=$SHARED}"
  if [[ "$APPLY" -eq 1 ]]; then
    echo "  APPLYING PUT /packing/materials/$ID stock=$FINAL ..."
    RES=$(curl -sS -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "{\"name\":\"$DB_NAME\",\"category\":\"$CAT\",\"unit\":\"$UNIT\",\"stock\":$FINAL,\"minStock\":0}" \
      "$API_BASE/packing/materials/$ID" || echo '{"error":"curl failed"}')
    if echo "$RES" | jq -e '.error' >/dev/null 2>&1; then echo "  FAIL: $RES"; else echo "  OK: set to $FINAL"; fi
  fi
done

echo ""
if [[ "$APPLY" -eq 0 ]]; then echo "DRY RUN ONLY — NO DEDUCTION — no changes. Rerun with --apply"; else echo "APPLY DONE — direct update, no deduction."; fi
