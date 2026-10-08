# FINAL APPLIED — 07/10/2026 Closing Stock Reconciliation (DIRECT UPDATE, NO DEDUCTION)

**Date Applied:** 2026-10-09 00:39 IST (screenshots 12:38, 12:39)
**Server:** manjotkhehra74@flavorflow:/opt/flavorflow/server
**Script:** `tools/ff-closing-stock-07102026.sh` (exact names version)
**Mode:** DIRECT UPDATE, NO DEDUCTION — final = physical count
**Backup:** `/opt/flavorflow/backups/erp.db.bak-closing-07102026-20261009-003734`
**Result:** 30 rows updated, 2 shared pools, DONE

## Applied Updates (from screenshots)

### Packing Materials (PM) — exact DB names

| ID | Exact Name | Was | Now (07/10 closing) | Shared |
|----|------------|-----|---------------------|--------|
| #23 | Shrink Sleeve 740 | 403045 | 418903 | |
| #21 | Shrink Sleeve White 610 | 406916 | 436562 | |
| #22 | Shrink Sleeve Brown 610 | 15265 | 15265 | |
| #16 | Label Soya 1.3 | 30155 | 30155 | |
| #13 | Label White (180) | 143796 | 158172 | |
| #14 | Label Front 4 Ltr | 4092 | 4092 | |
| #15 | Label Front 4.7 | 4200 | 4200 | |
| #12 | Dark S Label (250) | 3508 | 10023 | |
| #19 | Hologram (180/220) | 146798 | 171038 | shared=hologram-180-220 |
| #9 | Cap Orange (610) | 1165805 | 1195479 | |
| #10 | Cap Purple (740) | 168927 | 184785 | |
| #11 | Red Cap (1.3 / 1 Ltr) | 16230 | 22518 | |
| #8 | Red Cap (180/220) | 111375 | 135615 | |
| #20 | Plug (180) | 408068 | 422444 | |
| #47 | Crown Cork (220) | 103186 | 113050 | |
| #25 | Carton CB 180/220 | 4141 | 5151 | |
| #26 | Carton CB (610/740) | 5284 | 7812 | |
| #27 | Carton CB (1.3/1 Ltr) | 171 | 695 | |
| #5 | Jerry Can 4 Ltr | 8016 | 8016 | shared=jerry-shared |
| #6 | Jerry Can 4.7kg | 8016 | 8016 | shared=jerry-shared |

### Raw Materials (RM)

| ID | Exact Name | Was | Now (07/10) |
|----|------------|-----|-------------|
| #35 | Soyabean | 446.3 kg | 446.3 kg |
| #42 | Potassium Sorbate | 277.46 kg | 277.46 kg |
| #48 | Citric Acid | 623.2 kg | 623.2 kg |
| #49 | Ascorbic Acid | 30.8 kg | 30.8 kg |
| #50 | Sodium Benzoate | 1.16 kg | 1.16 kg |
| #38 | Garlic Oleoresin | 29.49 kg | 29.49 kg |
| #39 | Cinnamon Oleoresin | 28.48 kg | 28.48 kg |
| #37 | Coriander Oleoresin | 38.79 kg | 38.79 kg |
| #43 | Caramel Colour (E150a) | 4757.5 kg | 4757.5 kg |
| #40 | Black Salt | 600 kg | 100 kg |

## Cross-check (info only, NOT deducted)

- Production 05/10-07/10: WARN no such column b.product_name (query needs fix, but info only, no impact on final)
- Consumption 05/10-07/10: listed as info only, e.g., Glass Bottles 180/220 -18600, HDPE Bottle (610/740) -24048, Cap Orange -8190, etc. — NOT deducted per user requirement (sirf stock update, koi deduction nahi)

## Safety

- Exact Product Master name matching — fixed Crown Cork (220) and Jerry Can 4 Ltr (space) and Caramel Colour (E150a) case
- Only packing_materials.stock updated
- No rewrite of production, BOMs, ledger history
- Shared pools remain shared (Jerry Can 4 Ltr & 4.7kg both 8016, Hologram shared)
- Backup created before write
- Dry-run first, then apply with sudo

## Verification

```bash
sqlite3 /opt/flavorflow/server/data/erp.db "SELECT id, name, stock FROM packing_materials WHERE id IN (5,6,9,10,12,13,14,15,16,19,20,21,22,23,25,26,27,35,37,38,39,40,42,43,47,48,49,50) ORDER BY id;"
```

Flutter app: Packing → Packing Stock and Raw Material Stock should show updated 07/10 closing counts.

## Remaining (optional)

DB has 49 total materials, we updated 30 targeted from original photos. Missing raw materials not in 07/10 list: Molasses (#34), White Salt (#36), Turmeric Powder (#41), Caramel Colour (E150c) (#44), Acetic Acid (#45) — if they have 07/10 physical counts from new RM image (9:55 PM), add to JSON and rerun.

---

*Applied successfully — MAN-5 Done.*
