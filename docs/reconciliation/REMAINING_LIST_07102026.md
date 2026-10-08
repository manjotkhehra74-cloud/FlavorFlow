# Remaining Materials Check — 07/10/2026 Closing

**Date:** 2026-10-09
**Applied so far:** 30 rows (20 PM + 10 RM) — see FINAL_APPLIED_07102026.md
**DB Total:** 49 materials (from --list on live server)
**Remaining in DB not yet updated:** 19 rows

## ✅ Updated Already (30) — DIRECT UPDATE, NO DEDUCTION

### PM (20)
1. #23 Shrink Sleeve 740 → 418903
2. #21 Shrink Sleeve White 610 → 436562
3. #22 Shrink Sleeve Brown 610 → 15265
4. #16 Label Soya 1.3 → 30155
5. #13 Label White (180) → 158172
6. #14 Label Front 4 Ltr → 4092
7. #15 Label Front 4.7 → 4200
8. #12 Dark S Label (250) → 10023
9. #19 Hologram (180/220) → 171038 (shared)
10. #9 Cap Orange (610) → 1195479
11. #10 Cap Purple (740) → 184785
12. #11 Red Cap (1.3 / 1 Ltr) → 22518
13. #8 Red Cap (180/220) → 135615
14. #20 Plug (180) → 422444
15. #47 Crown Cork (220) → 113050
16. #25 Carton CB 180/220 → 5151
17. #26 Carton CB (610/740) → 7812
18. #27 Carton CB (1.3/1 Ltr) → 695
19. #5 Jerry Can 4 Ltr → 8016 (shared=jerry-shared)
20. #6 Jerry Can 4.7kg → 8016 (shared=jerry-shared)

### RM (10) — **NOTE: These counts were from OLD baseline, NOT from new 9:55 PM RM image**
21. #35 Soyabean → 446.30 kg
22. #42 Potassium Sorbate → 277.46 kg
23. #48 Citric Acid → 623.20 kg
24. #49 Ascorbic Acid → 30.80 kg
25. #50 Sodium Benzoate → 1.16 kg
26. #38 Garlic Oleoresin → 29.49 kg
27. #37 Coriander Oleoresin → 38.79 kg (actually #37 is Coriander, #39 Cinnamon - check)
28. #39 Cinnamon Oleoresin → 28.48 kg
29. #43 Caramel Colour (E150a) → 4757.50 kg
30. #40 Black Salt → 100 kg (was 600)

## ❌ Reh gaye / Not Updated (19) — from live DB --list

These 19 exist in packing_materials but were NOT in the 30 we applied. If their physical count was in your screenshots, they are still pending.

**Confirmed missing IDs from FINAL_APPLIED notes:**
- #34 Molasses (RM)
- #36 White Salt (RM)
- #41 Turmeric Powder / Haldi Powder (RM) — we had Haldi but not Turmeric? Check exact name
- #44 Caramel Colour (E150c) (RM) — different from E150a
- #45 Acetic Acid (RM) — not in our 30 list

**Other likely missing (to reach 49 total) — run --list to confirm exact names:**
Based on typical FlavorFlow master, remaining 14 could be:
- #? Glass Bottle 180ml
- #? Glass Bottle 220ml
- #? HDPE Bottle 610ml / 740gm
- #? PET Bottle 1 Ltr / 1.3kg
- #? Shrink Sleeve for 1.3 / other variants
- #? Label White Vinegar 1 Ltr (we missed? In first version we had 67548 but not in final 20 — check)
- #? Label White Vinegar 610ml? etc.
- #? Other RM: Sugar, Soya Sauce Base, Vinegar Mother, etc.

**Exact way to get full 49 list from live server:**
```bash
sudo bash ~/ff-closing-stock-07102026.sh --list > /tmp/all-materials-07102026.txt
cat /tmp/all-materials-07102026.txt
```

This will print:
```
--- Category: packing (20+?)
#ID | "Exact Name" | stock=... | category=packing
--- Category: raw material (29?)
#ID | "Exact Name" | stock=... | category=raw material
```

## 🚨 Important — RM Image 9:55 PM

Your second screenshot `Screenshot 2026-10-08 at 9.55.36 PM.jpg` (RM stock) could NOT be auto-fetched due to Linear upload domain blocked in sandbox.

The 10 RM values we applied (446.30 etc) were from **old 04/10 baseline**, not from your new 9:55 PM photo. If that photo shows different counts for Soyabean, Black Salt, etc. OR shows additional materials like Molasses, White Salt, Turmeric, Acetic Acid, E150c — those counts are still pending.

**Action needed:**
1. Please upload both screenshots again HERE in this chat (PM 9:10 PM + RM 9:55 PM) — I can read them directly and transcribe exact counts.
2. Or run the --list command above on server and paste output here.
3. Then I will update `tools/data/closing-stock-07102026.json` with exact remaining counts and generate a new `ff-closing-stock-07102026.sh` v3 that updates ONLY the remaining 19 (or corrected RM).

## What you asked: "Sare e update krne c"

If "sare" means all 49 materials in DB should be set to physical count, then yes — 19 are still pending.

If "sare" means all materials visible in the two screenshots — then:
- PM screenshot: we did 20, but if photo had more (e.g., Glass Bottles, etc.), list them.
- RM screenshot: we need to re-transcribe because we used old numbers.

Once you re-upload images, I will:
- Transcribe exact Product Master names + counts
- Diff against already applied 30
- Create v3 script for remaining only (with backup)
- Dry-run → Apply

---
*Generated 2026-10-09*
