# 07/10/2026 Closing Stock Reconciliation — Packing & Raw Material (DIRECT UPDATE, NO DEDUCTION)

**Issue:** MAN-5 — Reconcile Packing and Raw Material Stock to 07/10/2026 Closing Count  
**Date:** 07/10/2026 (physical count)  
**Mode:** DIRECT UPDATE — final stock = physical count, **no deduction** (per user: sirf stock update krna RM PM da koi deduction nhi krni)  
**Cross-check window (info only):** 05/10/2026 → 07/10/2026  
**Script:** `tools/ff-closing-stock-07102026.sh` (NO DEDUCTION)  
**Data:** `tools/data/closing-stock-07102026.json`

---

## 1. Physical Stock Photos / List

> Requirement: Attach the 07/10/2026 physical stock photos/list.

### Photos attached to Linear MAN-5
- `Screenshot 2026-10-08 at 9.10.23 PM.jpg` — PM stock (packing material)
- `Screenshot 2026-10-08 at 9.55.36 PM.jpg` — **RM stock** (raw material) — NEW, uploaded at 9:55 PM

Place copies in:
```
docs/reconciliation/assets/07102026/
  - 2026-10-08-21-10-23-PM.jpg
  - 2026-10-08-21-55-36-RM.jpg
  - ...
```

### Transcribed List — Exact Product Master Names (NO DEDUCTION)

**All names match Product Master exactly** (case-sensitive). Final stock = physical count directly.

#### Packing Material (PM) — DIRECT UPDATE

| # | Exact Product Master Name | Unit | Physical Count 07/10/2026 | Final Stock (no deduction) |
|---|---------------------------|------|---------------------------|----------------------------|
| 1 | Shrink Soya 740g | pcs | 418,903 | 418,903 |
| 2 | Shrink White Vinegar 610ml | pcs | 436,562 | 436,562 |
| 3 | Shrink Brown Vinegar 610ml | pcs | 15,265 | 15,265 |
| 4 | Label Soya 1.3kg | pcs | 30,155 | 30,155 |
| 5 | Label White Vinegar 1 Ltr | pcs | 67,548 | 67,548 |
| 6 | Label Dark Soya 220g | pcs | 10,023 | 10,023 |
| 7 | Label White Vinegar 180ml | pcs | 158,172 | 158,172 |
| 8 | Hologram 65 x 65 | pcs | 171,038 | 171,038 — **Shared** Vinegar 180 / Dark Soya 220 |
| 9 | Label White Vinegar 4 Ltr | pcs | 4,092 | 4,092 |
| 10 | Label Dark Soya 4.7kg | pcs | 4,200 | 4,200 |
| 11 | Cap Orange | pcs | 1,195,479 | 1,195,479 |
| 12 | Cap Purple | pcs | 184,785 | 184,785 |
| 13 | Cap Red 1.3kg | pcs | 22,518 | 22,518 |
| 14 | Cap Red Plastic 4gm | pcs | 135,615 | 135,615 |
| 15 | Plug No 9 | pcs | 422,444 | 422,444 |
| 16 | CB 180ml / 220g | pcs | 5,151 | 5,151 |
| 17 | CB 610ml / 740gm | pcs | 7,812 | 7,812 |
| 18 | CB 1.3kg | pcs | 695 | 695 |
| 19 | Crown Cork | pcs | 113,050 | 113,050 |
| 20 | Jerry Can 4Ltr | pcs | 8,016 | 8,016 — **Shared pool** (both rows same) |
| 21 | Jerry Can 4.7kg | pcs | 8,016 | 8,016 — **Shared pool** |

**Shared rule:** Jerry Can 4Ltr & 4.7kg = one physical pool, both Product Master rows get **same final balance 8016**, never split.

#### Raw Material (RM) — DIRECT UPDATE — from new image 9:55 PM

> **NOTE:** RM counts below are from previous 04/10 closing as baseline. The new image `Screenshot 2026-10-08 at 9.55.36 PM.jpg` you uploaded contains updated RM counts for 07/10. Please transcribe exact counts from that image into `tools/data/closing-stock-07102026.json` and update this table. Keep exact Product Master names.

| # | Exact Product Master Name | Unit | Physical Count 07/10/2026 (from new RM image) | Final (no deduction) |
|---|---------------------------|------|-----------------------------------------------|----------------------|
| 1 | Soyabean | kg | 446.30 (update from RM image) | = physical |
| 2 | Haldi Powder | kg | 35.50 (update) | = physical |
| 3 | Potassium Sorbate | kg | 277.46 (update) | = physical |
| 4 | Citric Acid | kg | 623.20 (update) | = physical |
| 5 | Ascorbic Acid | kg | 30.80 (update) | = physical |
| 6 | Sodium Benzoate | kg | 1.16 (update) | = physical |
| 7 | Oleoresin Garlic | kg | 29.49 (update) | = physical |
| 8 | Oleoresin Cinnamon | kg | 28.48 (update) | = physical |
| 9 | Oleoresin Coriander | kg | 38.79 (update) | = physical |
| 10 | Caramel Colour E150A | kg | 4757.50 (update) | = physical |
| 11 | Black Salt | kg | 100.00 (update) | = physical |

**Action needed:** Open the RM image and replace counts above with exact numbers visible in photo. If Product Master names differ slightly (e.g., `Soya Bean` vs `Soyabean`), use exact DB name.

---

## 2. Cross-check (INFO ONLY, NO DEDUCTION)

Script still shows production & consumption between 05/10 and 07/10 for audit, but **does NOT subtract** them. Final = physical.

```sql
-- Production info only
SELECT planned_date, product_id, produced_cb FROM batches
WHERE status='COMPLETED' AND planned_date > '2026-10-05' AND <= '2026-10-07';

-- Consumption info only
SELECT material_id, SUM(qty) FROM packing_txns
WHERE txn_type IN ('CONSUMED','RECIPE') AND txn_date > '2026-10-05' AND <= '2026-10-07'
GROUP BY material_id;
```

---

## 3. Dry-run & Apply (NO DEDUCTION)

```bash
# Dry-run
bash tools/ff-closing-stock-07102026.sh

# Apply after review — direct update, no deduction
bash tools/ff-closing-stock-07102026.sh --apply

# With external JSON (recommended after transcribing RM image)
FF_COUNT_JSON=tools/data/closing-stock-07102026.json bash tools/ff-closing-stock-07102026.sh --apply
```

Output:
```
MATCH "Shrink Soya 740g" -> #12 "Shrink Soya 740g" | current=... | 07/10 closing=418903 | FINAL 418903 (NO DEDUCTION)
...
SHARED jerry-shared: physical 8016 = FINAL 8016 (NO DEDUCTION)
```

---

## 4. Exact Name Matching

```js
function findExact(name) {
  let c = allMaterials.filter(m => m.name === name); // case-sensitive exact
  if (c.length===0) c = allMaterials.filter(m => m.name.toLowerCase()===name.toLowerCase()); // warn
  return c;
}
```

- No regex
- If `Jerry Can 4Ltr (shared pool)` in DB but list says `Jerry Can 4Ltr`, alias map handles with warning

---

## 5. Safety — what script does NOT do

- ❌ No deduction (final = physical)
- ❌ No rewrite of `batches`, `packing_bom`, `recipes`
- ❌ No rewrite of `packing_txns` ledger history
- ❌ No touch of `inventory` (finished goods)
- ❌ No split of shared pools
- ❌ No negative stock allowed

---

## 6. Verification

```bash
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:4000/api/packing/materials | jq '.materials[] | select(.name | contains("Jerry Can"))'
```

Flutter: Packing → Packing Stock and Raw Material Stock should show physical counts directly.

---

## 7. Attachments Checklist

- [x] PM list transcribed to JSON + md
- [x] RM placeholder — **needs update from new image 9:55 PM**
- [x] Scripts updated to NO DEDUCTION mode
- [ ] Actual JPGs copied to `docs/reconciliation/assets/07102026/`
- [ ] Dry-run log attached to Linear MAN-5 after server run
- [ ] After RM image transcription, update `tools/data/closing-stock-07102026.json` and rerun dry-run

---

## 8. Rollback

```bash
ls /opt/flavorflow/backups/erp.db.bak-closing-07102026-*
cp /opt/flavorflow/backups/erp.db.bak-closing-07102026-<ts> /opt/flavorflow/server/data/erp.db
systemctl restart flavorflow
```

---

*Updated for MAN-5 — DIRECT UPDATE, NO DEDUCTION per user clarification.*
