# v3 Correction — 07/10/2026 Closing — From Latest Screenshots (2026-10-09)

**Date:** 2026-10-09
**Previous v2 applied:** 30 rows (2026-10-09 00:39 IST) with old counts (e.g., Shrink 418903, Hologram 171038)
**New screenshots uploaded:** 2026-10-09  (PM 28 items + RM 12 items = 40 physical counts)
**Issue:** v2 counts were from older transcription / baseline, not from latest 07/10/2026 Balance sheet. Need to correct to latest.

## Transcribed from Images (exact as in photo)

### RM — 12 items (first image)
| Image Name | Count | Mapped Exact DB Name |
|------------|-------|----------------------|
| Molasses | 59338 | Molasses |
| Soya been | 2403.3 | Soyabean |
| Salt | 26383.5 | White Salt (alt: Salt) |
| Dhaniya ole. | 36.476 | Coriander Oleoresin |
| Garlic ole | 27.176 | Garlic Oleoresin |
| Dalchini ole | 27.598 | Cinnamon Oleoresin |
| Haldi | 27.895 | Turmeric Powder (alt Haldi) |
| Pot. Sorbeta | 247.76 | Potassium Sorbate |
| Acetic Acid | 25598 | Acetic Acid |
| Caramel 150 A | 12412.5 | Caramel Colour (E150a) |
| Caramel 150 C | 233 | Caramel Colour (E150c) |
| Black salt | 100 | Black Salt |

### PM — 28 items (second image, 07/10/2026 Balance)
| Image Name | Count | Mapped Exact DB Name | Previous v2 Count | Diff |
|------------|-------|----------------------|-------------------|------|
| Red Caps 180/220 | 174245 | Red Cap (180/220) | 135615 | +38630 |
| Crown Cork 220 | 103064 | Crown Cork (220) | 113050 | -9986 |
| Label White vin 180 | 143656 | Label White (180) | 158172 | -14516 |
| Label D Soya 220 | 0 | Dark S Label (250) | 10023 | -10023 (now 0) |
| Hologram 180/220 | 747262 | Hologram (180/220) | 171038 | +576224 |
| Plug 180 | 407847 | Plug (180) | 422444 | -14597 |
| Glass Bottles 180/220 | 81068 | Glass Bottles 180/220 | NOT UPDATED BEFORE | new |
| CB 180/220 | 4123 | Carton CB 180/220 | 5151 | -1028 |
| Cap Orange 610 | 1165805 | Cap Orange (610) | 1195479 | -29674 |
| Shrink White Vin 610 | 406086 | Shrink Sleeve White 610 | 436562 | -30476 |
| Shrink Vin Brown 610 | 15265 | Shrink Sleeve Brown 610 | 15265 | 0 same |
| Cap Purple 740 | 168861 | Cap Purple (740) | 184785 | -15924 |
| Shrink Soya 740 | 402615 | Shrink Sleeve 740 | 418903 | -16288 |
| CB 610/740 | 5276 | Carton CB (610/740) | 7812 | -2536 |
| HDPE Bottles | 129556 | HDPE Bottles | NOT UPDATED | new |
| Tray Soya | 18819 | Tray Soya | NOT UPDATED | new |
| Tray Top | 18175 | Tray Top | NOT UPDATED | new |
| Red Cap | 16172 | Red Cap (1.3 / 1 Ltr) | 22518 | -6346 |
| Label 1.3 | 30155 | Label Soya 1.3 | 30155 | 0 same |
| Label 1 Ltr | 61103 | Label White (1 Ltr) | NOT UPDATED? | new (prev Label White 1 Ltr 67548?) |
| Bottles 1.3 | 18808 | Bottles 1.3 | NOT UPDATED | new |
| CB 1.3 | 165 | Carton CB (1.3/1 Ltr) | 695 | -530 |
| Tray | 382 | Tray | NOT UPDATED | new |
| Tray Cap | 322 | Tray Cap | NOT UPDATED | new |
| Jerry Can | 8016 | Jerry Can 4 Ltr + 4.7kg shared | 8016 | 0 same |
| Label vin | 4092 | Label Front 4 Ltr | 4092 | 0 same |
| Label Soya | 5623 | Label Front 4.7 | 4200 (prev) | +1423 |
| CB | 31 | Carton CB 4 Ltr (or CB) | NOT UPDATED | new |

**Total v3 targets:** 40 physical rows → 41 DB rows (Jerry Can shared counts as 2)

## What was wrong in v2?
- Used old baseline counts from 04/10 or intermediate transcription
- Missed new materials: Glass Bottles, HDPE Bottles, Tray Soya, Tray Top, Bottles 1.3, Tray, Tray Cap, Label 1 Ltr, CB 31, Molasses, White Salt, Acetic Acid, E150c, Turmeric
- RM counts outdated: Soya been 446 → now 2403.3, Salt 26383.5 not set, Caramel 150A 4757 → 12412.5, etc.

## v3 Script

- `tools/ff-closing-stock-07102026-v3.sh` — DIRECT UPDATE, NO DEDUCTION, final = physical from latest screenshots
- `tools/data/closing-stock-07102026-v3.json` — 41 rows with alt_names for lenient matching
- Supports --list to dump exact DB names
- Backup before apply: `/opt/flavorflow/backups/erp.db.bak-closing-07102026-v3-<ts>`

### Dry-run

```bash
sudo curl -fsSL -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/fc479533-flavorflow/tools/ff-closing-stock-07102026-v3.sh?v=$(date +%s)" -o /tmp/ff-closing-stock-07102026-v3.sh
chmod +x /tmp/ff-closing-stock-07102026-v3.sh
sudo bash /tmp/ff-closing-stock-07102026-v3.sh
# If NOT FOUND, run:
sudo bash /tmp/ff-closing-stock-07102026-v3.sh --list > /tmp/all.txt && cat /tmp/all.txt
```

### Apply (after dry-run shows all MATCH)

```bash
sudo bash /tmp/ff-closing-stock-07102026-v3.sh --apply
```

## Remaining after v3

If --list shows 49 total and we update 41, remaining 8 will be:
- Citric Acid, Ascorbic Acid, Sodium Benzoate (not in latest RM screenshot — were in v2 but not in new image)
- Possibly others like "Glass Bottle 180/220" vs "Glass Bottles 180/220" duplicate, etc.
- Those should be left as is unless you have their 07/10 counts.

If you want ALL 49 set, provide counts for remaining 8.

## Safety

- NO DEDUCTION — final = physical directly
- Only packing_materials.stock updated
- Shared Jerry Can remains shared
- Backup created
- Dry-run first

---
*Generated 2026-10-09 from latest screenshots*
