# 07/10/2026 Closing Stock Reconciliation — Packing & Raw Material

**Issue:** MAN-5 — Reconcile Packing and Raw Material Stock to 07/10/2026 Closing Count  
**Date:** 07/10/2026 (physical count)  
**Cross-check window:** 05/10/2026 → 07/10/2026 (completed production + recorded consumption)  
**Script:** `tools/ff-closing-stock-07102026.sh`  
**Data:** `tools/data/closing-stock-07102026.json`

---

## 1. Physical Stock Photos / List

> **Requirement:** Attach the 07/10/2026 physical stock photos/list.

### Photos
Place the 07/10/2026 physical count photos in this folder:

```
docs/reconciliation/assets/07102026/
  - IMG_001.jpg (packing shelf)
  - IMG_002.jpg (raw material)
  - ...
```

If photos are not available locally, they are attached to the Linear issue:
- https://linear.app/manjotsingh/issue/MAN-5/reconcile-packing-and-raw-material-stock-to-07102026-closing-count
- Screenshot: `Screenshot 2026-10-08 at 9.10.23 PM.jpg` (uploads.linear.app)

### Transcribed List (Exact Product Master Names)

The table below is transcribed from the physical count sheets. **All names match Product Master exactly** (case-sensitive). Do not use fuzzy matching.

#### Packing Material (PM)

| # | Exact Product Master Name | Unit | Physical Count 07/10/2026 | Notes |
|---|---------------------------|------|---------------------------|-------|
| 1 | Shrink Soya 740g | pcs | 418,903 | |
| 2 | Shrink White Vinegar 610ml | pcs | 436,562 | |
| 3 | Shrink Brown Vinegar 610ml | pcs | 15,265 | |
| 4 | Label Soya 1.3kg | pcs | 30,155 | |
| 5 | Label White Vinegar 1 Ltr | pcs | 67,548 | |
| 6 | Label Dark Soya 220g | pcs | 10,023 | |
| 7 | Label White Vinegar 180ml | pcs | 158,172 | |
| 8 | Hologram 65 x 65 | pcs | 171,038 | **Shared** — used for Vinegar 180ml & Dark Soya 220g (same physical pool) |
| 9 | Label White Vinegar 4 Ltr | pcs | 4,092 | |
| 10 | Label Dark Soya 4.7kg | pcs | 4,200 | |
| 11 | Cap Orange | pcs | 1,195,479 | for 610ml vinegar |
| 12 | Cap Purple | pcs | 184,785 | for 740g soya |
| 13 | Cap Red 1.3kg | pcs | 22,518 | |
| 14 | Cap Red Plastic 4gm | pcs | 135,615 | for 180ml/220g |
| 15 | Plug No 9 | pcs | 422,444 | for 180ml |
| 16 | CB 180ml / 220g | pcs | 5,151 | carton |
| 17 | CB 610ml / 740gm | pcs | 7,812 | carton |
| 18 | CB 1.3kg | pcs | 695 | carton |
| 19 | Crown Cork | pcs | 113,050 | for 220g |
| 20 | Jerry Can 4Ltr | pcs | 8,016 | **Shared pool** — see below |
| 21 | Jerry Can 4.7kg | pcs | 8,016 | **Shared pool** — same physical stock as 4Ltr |

**Shared Materials Rule:**
- `Jerry Can 4Ltr` and `Jerry Can 4.7kg` are **one physical pool** represented by two Product Master rows. The reconciliation writes the **same final balance** to both rows. It never splits 8,016 between them.
- `Hologram 65 x 65` is shared between Vinegar 180ml and Dark Soya 220g. If Product Master has a long name `Hologram 65 x 65 — shared Vinegar 180 / Dark Soya 220`, the script handles alias mapping.

#### Raw Material (RM)

| # | Exact Product Master Name | Unit | Physical Count 07/10/2026 (kg) |
|---|---------------------------|------|-------------------------------|
| 1 | Soyabean | kg | 446.30 |
| 2 | Haldi Powder | kg | 35.50 |
| 3 | Potassium Sorbate | kg | 277.46 |
| 4 | Citric Acid | kg | 623.20 |
| 5 | Ascorbic Acid | kg | 30.80 |
| 6 | Sodium Benzoate | kg | 1.16 |
| 7 | Oleoresin Garlic | kg | 29.49 |
| 8 | Oleoresin Cinnamon | kg | 28.48 |
| 9 | Oleoresin Coriander | kg | 38.79 |
| 10 | Caramel Colour E150A | kg | 4,757.50 |
| 11 | Black Salt | kg | 100.00 |

> **Note:** Water is intentionally excluded (not tracked in stock).

---

## 2. Cross-check: Production 05/10 → 07/10

The script queries:

```sql
SELECT ... FROM batches
WHERE UPPER(status)='COMPLETED'
AND planned_date > '2026-10-05' AND planned_date <= '2026-10-07'
-- or production_date if column exists
```

It prints each completed batch in the window (date, product, CB, trays) so you can verify against factory logbook.

---

## 3. Cross-check: Consumption 05/10 → 07/10

### Expected BOM consumption
Calculated from `packing_bom` × completed production in window:

```sql
SELECT material_id, SUM(produced_cb * qty_per_cb + produced_trays * qty_per_tray)
FROM batches JOIN packing_bom ON product_id
WHERE status='COMPLETED' AND date > '2026-10-05' AND date <= '2026-10-07'
GROUP BY material_id
```

### Recorded consumption
From `packing_txns`:

```sql
SELECT material_id, SUM(qty)
FROM packing_txns
WHERE txn_type='CONSUMED' AND txn_date > '2026-10-05' AND txn_date <= '2026-10-07'
```

### Double-deduction guard
- If **recorded** exists, it is authoritative (ERP already deducted it).
- **Expected** is used only when recorded is absent.
- If both exist and differ >0.001, script **STOPS** — manual review required to avoid double-deduction.

---

## 4. Dry-run & Apply Workflow

### Dry-run (default, safe, read-only)

```bash
# On server:
bash tools/ff-closing-stock-07102026.sh

# With custom DB path:
FF_DB=/opt/flavorflow/server/data/erp.db bash tools/ff-closing-stock-07102026.sh

# With external JSON (exact names):
FF_COUNT_JSON=/opt/flavorflow/data/closing-07102026.json bash tools/ff-closing-stock-07102026.sh
```

Output shows:
- `MATCH "Exact Name" -> #id "DB Name" | current=... | 07/10 closing=...`
- `COMPLETED PRODUCTION BETWEEN 2026-10-05 AND 2026-10-07`
- `EXPECTED PACKING-BOM CONSUMPTION`
- `RECORDED CONSUMPTION`
- `PROPOSED FINAL BALANCES: physical - deduction = FINAL`

Review carefully. Check for:
- `NOT FOUND` or `AMBIGUOUS` (must be fixed to exact name)
- `MISMATCH` (recorded vs expected) — investigate before apply
- `NEGATIVE RESULT` — would create negative stock, stop

### Backup & Apply

```bash
bash tools/ff-closing-stock-07102026.sh --apply
```

Steps on apply:
1. `cp erp.db /opt/flavorflow/backups/erp.db.bak-closing-07102026-<timestamp>`
2. `systemctl stop flavorflow`
3. `BEGIN; UPDATE packing_materials SET stock = ? WHERE id = ?; COMMIT;`
4. Only `packing_materials.stock` is touched — **no** production, BOM, ledger history rewrite
5. `systemctl start flavorflow`
6. Health check `/api/health`

Stock journal triggers (if `ff-stockledger.sh` applied) will automatically create `SET_STOCK` / `SYNC` entries for audit.

---

## 5. Exact Product Master Name Matching

**Requirement:** Match all materials by exact Product Master name.

Implementation in `ff-closing-stock-07102026.sh`:

```js
function findExact(name, kind) {
  // case-sensitive exact first
  let candidates = allMaterials.filter(m => m.name === name);
  // fallback case-insensitive with warning
  if (candidates.length === 0) {
    candidates = allMaterials.filter(m => m.name.toLowerCase() === name.toLowerCase());
  }
  // category filter (raw vs packing)
  ...
  return candidates;
}
```

- No regex, no substring.
- If Product Master has `Jerry Can 4Ltr (shared pool)` but list says `Jerry Can 4Ltr`, alias map handles it but logs warning to correct master.
- If not found, script lists similar names for correction.

---

## 6. What the script does NOT do (safety)

- ❌ Does not rewrite `batches`, `packing_bom`, `recipes`, `recipe_lines`
- ❌ Does not delete or rewrite `packing_txns` ledger history
- ❌ Does not touch `inventory` (finished goods) — only PM/RM
- ❌ Does not split shared pools (Jerry Can) without confirmation — writes same balance to both rows
- ❌ Does not create negative stock

---

## 7. Verification after apply

```bash
# Check stock via API:
curl -H "Authorization: Bearer <token>" http://127.0.0.1:4000/api/packing/materials | jq

# Check ledger for the update:
curl -H "Authorization: Bearer <token>" "http://127.0.0.1:4000/api/stock/register?from=2026-10-07&to=2026-10-07"

# Check balances:
curl -H "Authorization: Bearer <token>" "http://127.0.0.1:4000/api/stock/balances?from=2026-10-05&to=2026-10-07"
```

In Flutter app: Packing → Packing Stock (and Raw Material Stock) should show updated balances; Ledger tab shows `SET_STOCK` entry.

---

## 8. Attachments Checklist (MAN-5)

- [x] Physical stock photos/list transcribed to `tools/data/closing-stock-07102026.json`
- [x] This document `docs/reconciliation/07102026_closing_count.md` with exact names
- [x] Script `tools/ff-closing-stock-07102026.sh` with dry-run, backup, exact matching, shared-pool handling, double-deduction guard
- [ ] Actual JPGs from factory floor in `docs/reconciliation/assets/07102026/` (to be added by store in-charge)
- [ ] Linear issue updated with dry-run output and final balances after review

---

## 9. Rollback

If needed:

```bash
ls /opt/flavorflow/backups/erp.db.bak-closing-07102026-*
cp /opt/flavorflow/backups/erp.db.bak-closing-07102026-<ts> /opt/flavorflow/server/data/erp.db
systemctl restart flavorflow
```

---

*Generated for MAN-5 — 07/10/2026 closing count reconciliation.*
