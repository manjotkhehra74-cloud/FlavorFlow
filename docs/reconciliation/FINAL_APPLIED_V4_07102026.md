# FINAL APPLIED v4 — 07/10/2026 Closing Stock — 41 Rows

**Date Applied:** 2026-10-09 10:03 IST
**Server:** manjotkhehra74@flavorflow
**Script:** `tools/ff-closing-stock-07102026-v4.sh`
**Backup:** `/opt/flavorflow/backups/erp.db.bak-closing-07102026-v4-20261009-100311`
**Mode:** DIRECT UPDATE, NO DEDUCTION — final = physical from latest screenshots
**Result:** APPLIED 41 rows, 1 shared pool, DONE

## Screenshots Provided (Latest)
- PM 07/10/2026 Balance sheet (28 items): Red Caps 174245, Crown Cork 103064, Label White 143656, Label D Soya 220 0, Hologram 747262, Plug 407847, Glass Bottles 81068, CB 180/220 4123, Cap Orange 1165805, Shrink White 406086, Shrink Brown 15265, Cap Purple 168861, Shrink Soya 402615, CB 610/740 5276, HDPE Bottles 129556, Tray Soya 18819, Tray Top 18175, Red Cap 16172, Label 1.3 30155, Label 1 Ltr 61103, Bottles 1.3 18808, CB 1.3 165, Tray 382, Tray Cap 322, Jerry Can 8016, Label vin 4092, Label Soya 5623, CB 31
- RM sheet (12 items): Molasses 59338, Soya been 2403.3, Salt 26383.5, Dhaniya 36.476, Garlic 27.176, Dalchini 27.598, Haldi 27.895, Pot Sorbeta 247.76, Acetic Acid 25598, Caramel 150A 12412.5, Caramel 150C 233, Black salt 100

## Applied Updates (Exact DB Names from --list 09:33)

### PM (29 rows including shared Jerry)
| ID | Exact Name | Was (after v2) | Now (07/10 closing) | Diff |
|----|------------|----------------|---------------------|------|
| #8 | Red Cap (180/220) | 135615 | 174245 | +38630 |
| #47 | Crown Cork (220) | 113050 | 103064 | -9986 |
| #13 | Label White (180) | 158172 | 143656 | -14516 |
| #46 | Dark S Label (220) | 159 | 0 | -159 |
| #19 | Hologram (180/220) | 171038 | 747262 | +576224 |
| #20 | Plug (180) | 422444 | 407847 | -14597 |
| #2 | Glass Bottles 180/220 | 100146 | 81068 | -19078 |
| #25 | Carton CB 180/220 | 5151 | 4123 | -1028 |
| #9 | Cap Orange (610) | 1195479 | 1165805 | -29674 |
| #21 | Shrink Sleeve White 610 | 436562 | 406086 | -30476 |
| #22 | Shrink Sleeve Brown 610 | 15265 | 15265 | 0 |
| #10 | Cap Purple (740) | 184785 | 168861 | -15924 |
| #23 | Shrink Sleeve 740 | 418903 | 402615 | -16288 |
| #26 | Carton CB (610/740) | 7812 | 5276 | -2536 |
| #3 | HDPE Bottle (610/740) | 97389* | 129556 | +32167 |
| #30 | Tray (740/610) | 18819 | 18819 | 0 |
| #32 | Tray Cap (740/610) | 18175 | 18175 | 0 |
| #11 | Red Cap (1.3 / 1 Ltr) | 22518 | 16172 | -6346 |
| #16 | Label Soya 1.3 | 30155 | 30155 | 0 |
| #17 | Label Vinegar 1 Ltr | 61260 | 61103 | -157 |
| #4 | HDPE Bottle (1.3/1 Ltr) | 15342 | 18808 | +3466 |
| #27 | Carton CB (1.3/1 Ltr) | 695 | 165 | -530 |
| #31 | Tray (1.3/1 Ltr) | 410 | 382 | -28 |
| #33 | Tray Cap (1.3/1 Ltr) | 346 | 322 | -24 |
| #5 | Jerry Can 4 Ltr | 8016 | 8016 | 0 shared |
| #6 | Jerry Can 4.7kg | 8016 | 8016 | 0 shared |
| #14 | Label Front 4 Ltr | 4092 | 4092 | 0 |
| #15 | Label Front 4.7 | 4200 | 5623 | +1423 |
| #28 | Carton CB 4.7/4 Ltr | 43* | 31 | -12 |

*Note: #3 and #28 had changed from v2 due to consumption between v2 apply and v4 dry-run.

### RM (12 rows)
| ID | Exact Name | Was | Now | Diff |
|----|------------|-----|-----|------|
| #34 | Molasses | 45754 | 59338 | +13584 |
| #35 | Soyabean | 446.3 | 2403.3 | +1957 |
| #36 | White Salt | 58336.5 | 26383.5 | -31953 |
| #37 | Coriander Oleoresin | 38.79 | 36.476 | -2.314 |
| #38 | Garlic Oleoresin | 29.49 | 27.176 | -2.314 |
| #39 | Cinnamon Oleoresin | 28.48 | 27.598 | -0.882 |
| #41 | Turmeric Powder | 35.5 | 27.895 | -7.605 |
| #42 | Potassium Sorbate | 277.46 | 247.76 | -29.7 |
| #45 | Acetic Acid | 16979.82 | 25598 | +8618.18 |
| #43 | Caramel Colour (E150a) | 4757.5 | 12412.5 | +7655 |
| #44 | Caramel Colour (E150c) | 343.3 | 233 | -110.3 |
| #40 | Black Salt | 100 | 100 | 0 |

## Dry-Run Log (09:58) — All MATCH
```
MATCH 'Red Cap (180/220)' -> #8 ... current=135615 | closing=174245
MATCH 'Crown Cork (220)' -> #47 ... current=113050 | closing=103064
... 41 total
PROPOSED FINAL (NO DEDUCTION):
SHARED jerry-shared: FINAL 8016
#8: FINAL 174245 (was 135615)
...
=== DRY RUN ONLY ===
```

## Apply Log (10:03)
```
BACKUP: /opt/flavorflow/backups/erp.db.bak-closing-07102026-v4-20261009-100311
=== FlavorFlow 07/10/2026 v4 (DIRECT UPDATE, NO DEDUCTION) ===
Closing: 2026-10-07 | Mode: APPLY | DB: /opt/flavorflow/server/data/erp.db | Targets: 41
... MATCH 41 ...
APPLYING...
UPDATED #8 'Red Cap (180/220)': 174245 (was 135615)
UPDATED #47 'Crown Cork (220)': 103064 (was 113050)
...
UPDATED #40 'Black Salt': 100 (was 100)
APPLIED 41 rows, 1 shared, NO DEDUCTION. Backup v4: 20261009-100311
DONE
```

## Verification
```bash
sqlite3 /opt/flavorflow/server/data/erp.db "SELECT id, name, stock FROM packing_materials WHERE id IN (2,3,4,5,6,8,9,10,11,13,14,15,16,17,19,20,21,22,23,25,26,27,28,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47) ORDER BY id;"
```

## Remaining 8 (Not in Photos, Unchanged)
- #1 Glass Bottles 250gm | 2249
- #7 Lug Cap (250) | 2082
- #12 Dark S Label (250) | 10023
- #18 Hologram M (250) | 300093
- #24 Carton CB 250 | 288
- #48 Citric Acid | 623.2
- #49 Ascorbic Acid | 30.8
- #50 Sodium Benzoate | 1.16

If these have 07/10 counts, provide them for v5.

## Safety
- Exact name matching from live --list
- Backup before write
- Only packing_materials.stock updated
- No deduction, no BOM rewrite, no ledger rewrite
- Shared Jerry Can remains shared (both 8016)

---
*Applied 2026-10-09 10:03 IST — v4 corrects v2 wrong counts*
