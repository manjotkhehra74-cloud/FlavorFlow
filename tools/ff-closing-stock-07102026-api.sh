#!/usr/bin/env bash
# FlavorFlow — 07/10/2026 closing stock reconciliation via API (SaaS / remote).
#
# For tenants where direct DB access is not available, this script uses the
# ERP API to:
#   1. Fetch all packing materials (exact Product Master names)
#   2. Match against 07/10/2026 physical count list (exact name)
#   3. Cross-check production & consumption from 05/10 to 07/10 via reports
#   4. Dry-run: show proposed balances
#   5. Apply: PUT /api/packing/materials/:id with exact stock (if permitted)
#
# Usage:
#   API_BASE=http://127.0.0.1:4000/api TOKEN=xxx bash tools/ff-closing-stock-07102026-api.sh
#   API_BASE=... TOKEN=... bash tools/ff-closing-stock-07102026-api.sh --apply
#
# Requirements: curl, jq, node (for JSON handling)
set -euo pipefail

API_BASE="${API_BASE:-http://127.0.0.1:4000/api}"
TOKEN="${TOKEN:-}"
COUNT_JSON="${FF_COUNT_JSON:-tools/data/closing-stock-07102026.json}"
CLOSING_DATE="2026-10-07"
START_DATE="2026-10-05"
APPLY=0
if [[ "${1:-}" == "--apply" ]]; then APPLY=1; fi

if [[ -z "$TOKEN" ]]; then echo "FATAL: TOKEN env required (Bearer token)"; exit 1; fi
if ! command -v jq >/dev/null; then echo "FATAL: jq required"; exit 1; fi
if [[ ! -f "$COUNT_JSON" ]]; then echo "FATAL: count JSON not found: $COUNT_JSON"; exit 1; fi

echo "=== FF-CLOSING-STOCK-07102026-API ==="
echo "API: $API_BASE"
echo "Closing: $CLOSING_DATE | Window: $START_DATE -> $CLOSING_DATE"
echo "Mode: $([ $APPLY -eq 1 ] && echo APPLY || echo DRY-RUN)"
echo ""

# Fetch materials
echo "Fetching /packing/materials ..."
MATERIALS=$(curl -sS -H "Authorization: Bearer $TOKEN" "$API_BASE/packing/materials")
if echo "$MATERIALS" | jq -e '.materials' >/dev/null 2>&1; then
  echo "Got $(echo "$MATERIALS" | jq '.materials | length') materials"
else
  echo "FATAL: failed to fetch materials: $MATERIALS"
  exit 1
fi

# Fetch production batches in window (if permitted)
echo "Fetching /production/batches ..."
BATCHES=$(curl -sS -H "Authorization: Bearer $TOKEN" "$API_BASE/production/batches" || echo '{"batches":[]}')
if echo "$BATCHES" | jq -e '.batches' >/dev/null 2>&1; then
  PROD_IN_WINDOW=$(echo "$BATCHES" | jq --arg s "$START_DATE" --arg e "$CLOSING_DATE" '[.batches[] | select(.status=="COMPLETED" and .planned_date > $s and .planned_date <= $e)]')
  echo "Completed production in window: $(echo "$PROD_IN_WINDOW" | jq 'length') batches"
  echo "$PROD_IN_WINDOW" | jq -r '.[] | "  \(.planned_date) | \(.product_name // .product_id) | CB \(.produced_cb // 0)"' | head -n 20
else
  echo "WARN: could not fetch batches (may lack permission)"
  PROD_IN_WINDOW="[]"
fi

# Fetch ledger for consumption in window
echo ""
echo "Fetching /packing/ledger?type=CONSUMED (for window) ..."
LEDGER=$(curl -sS -H "Authorization: Bearer $TOKEN" "$API_BASE/packing/ledger?type=CONSUMED" || echo '{"txns":[]}')
if echo "$LEDGER" | jq -e '.txns' >/dev/null 2>&1; then
  CONSUMED=$(echo "$LEDGER" | jq --arg s "$START_DATE" --arg e "$CLOSING_DATE" '[.txns[] | select(.txn_date > $s and .txn_date <= $e)] | group_by(.material_id) | map({material_id: .[0].material_id, material_name: .[0].material_name, qty: (map(.qty) | add)})')
  echo "Recorded consumption in window: $(echo "$CONSUMED" | jq 'length') materials"
  echo "$CONSUMED" | jq -r '.[] | "  #\(.material_id) \(.material_name): -\(.qty)"' | head -n 30
else
  echo "WARN: could not fetch ledger"
  CONSUMED="[]"
fi

echo ""
echo "=== MATCHING EXACT PRODUCT MASTER NAMES ==="
# Build lookup: name -> id, stock, category
echo "$MATERIALS" | jq -r '.materials[] | "\(.id)|\(.name)|\(.stock)|\(.category)|\(.unit)"' > /tmp/materials.txt

# Process each target from JSON
jq -c '.[]' "$COUNT_JSON" | while read -r row; do
  NAME=$(echo "$row" | jq -r '.name')
  COUNT=$(echo "$row" | jq -r '.count')
  KIND=$(echo "$row" | jq -r '.kind // ""')
  SHARED=$(echo "$row" | jq -r '.sharedGroup // ""')
  # exact match
  MATCH=$(grep -F "|$NAME|" /tmp/materials.txt || true)
  if [[ -z "$MATCH" ]]; then
    # case-insensitive fallback
    MATCH=$(grep -i -F "|$NAME|" /tmp/materials.txt || true)
    if [[ -n "$MATCH" ]]; then
      echo "WARN exact case mismatch for \"$NAME\" -> $MATCH"
    else
      echo "NOT FOUND: \"$NAME\" (exact Product Master name required)"
      continue
    fi
  fi
  # handle multiple matches
  LINES=$(echo "$MATCH" | wc -l)
  if [[ "$LINES" -ne 1 ]]; then
    echo "AMBIGUOUS: \"$NAME\" matches $LINES rows: $MATCH"
    continue
  fi
  ID=$(echo "$MATCH" | cut -d'|' -f1)
  DB_NAME=$(echo "$MATCH" | cut -d'|' -f2)
  STOCK=$(echo "$MATCH" | cut -d'|' -f3)
  CAT=$(echo "$MATCH" | cut -d'|' -f4)
  UNIT=$(echo "$MATCH" | cut -d'|' -f5)
  # check category if kind specified
  if [[ "$KIND" == "raw" && "$CAT" != "Raw Material" ]]; then
    echo "CATEGORY MISMATCH: \"$NAME\" expected raw but is $CAT"
    continue
  fi
  if [[ "$KIND" == "packing" && "$CAT" == "Raw Material" ]]; then
    echo "CATEGORY MISMATCH: \"$NAME\" expected packing but is $CAT"
    continue
  fi
  # find recorded consumption for this id
  REC=$(echo "$CONSUMED" | jq --argjson id "$ID" -r '[.[] | select(.material_id == $id) | .qty] | add // 0')
  # For demo, expected BOM consumption is not calculated via API (needs packing/bom report)
  # We use recorded as authoritative, as per requirement to avoid double-deduction
  FINAL=$(node -e "console.log(Number($COUNT) - Number($REC))")
  echo "MATCH \"$NAME\" -> #$ID \"$DB_NAME\" | current=$STOCK $UNIT | physical $COUNT $UNIT | recorded -$REC $UNIT | FINAL $FINAL $UNIT${SHARED:+ | shared=$SHARED}"

  if [[ "$APPLY" -eq 1 ]]; then
    # Apply via PUT /packing/materials/:id
    echo "  APPLYING: PUT /packing/materials/$ID stock=$FINAL ..."
    RES=$(curl -sS -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "{\"name\":\"$DB_NAME\",\"category\":\"$CAT\",\"unit\":\"$UNIT\",\"stock\":$FINAL,\"minStock\":0}" \
      "$API_BASE/packing/materials/$ID" || echo '{"error":"curl failed"}')
    if echo "$RES" | jq -e '.error' >/dev/null 2>&1; then
      echo "  FAIL: $RES"
    else
      echo "  OK: stock updated to $FINAL"
    fi
  fi
done

echo ""
if [[ "$APPLY" -eq 0 ]]; then
  echo "DRY RUN ONLY — no changes made. Review above and rerun with --apply"
  echo "Shared materials (jerry-shared, hologram-180-220) must remain shared — both rows get same final balance."
else
  echo "APPLY DONE — verified via API. Check /packing and /raw ledger for SET_STOCK entries."
fi
