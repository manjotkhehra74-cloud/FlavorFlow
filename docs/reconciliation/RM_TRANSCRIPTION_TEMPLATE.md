# RM Stock Transcription — 07/10/2026 — from Screenshot 9:55 PM

**Image:** `Screenshot 2026-10-08 at 9.55.36 PM.jpg` uploaded to Linear MAN-5 at 9:55 PM

**Task:** Transcribe exact Product Master names and counts from the image into the format below, then update `tools/data/closing-stock-07102026.json`.

Because the sandbox cannot fetch `uploads.linear.app` (network restricted to github/npm/pypi), this template is provided for manual transcription.

## How to transcribe

1. Open Linear issue MAN-5: https://linear.app/manjotsingh/issue/MAN-5/reconcile-packing-and-raw-material-stock-to-07102026-closing-count
2. Open second screenshot (9:55 PM) — RM stock
3. For each line in the photo, find **exact** Product Master name in ERP (Packing → Raw Material Stock or `/api/packing/materials` filtered to Raw Material)
4. Write exact name and count below

## Template — fill from image

```
Exact Product Master Name | Physical Count 07/10/2026 | Unit | Notes
--------------------------|-----------------------------|------|------
                          |                             |      |
```

Example (from previous 04/10 baseline, replace with 07/10 values from image):
- Soyabean | 446.30 | kg |
- Haldi Powder | 35.50 | kg |
- Potassium Sorbate | 277.46 | kg |
- Citric Acid | 623.20 | kg |
- Ascorbic Acid | 30.80 | kg |
- Sodium Benzoate | 1.16 | kg |
- Oleoresin Garlic | 29.49 | kg |
- Oleoresin Cinnamon | 28.48 | kg |
- Oleoresin Coriander | 38.79 | kg |
- Caramel Colour E150A | 4757.50 | kg |
- Black Salt | 100 | kg |

If the new RM image shows different materials (e.g., Molasses, Soya Bean Extract, White Salt, etc. from recipe sheet), list them all with exact names.

## JSON format for update

After transcription, update `tools/data/closing-stock-07102026.json`:

```json
[
  {"name": "Exact Name 1", "count": 123.45, "kind": "raw", "unit": "kg"},
  {"name": "Exact Name 2", "count": 67.89, "kind": "raw", "unit": "kg"}
]
```

Keep `kind: "raw"` for raw materials, `kind: "packing"` for packing.

For shared pools, add `"sharedGroup": "jerry-shared"` and ensure both rows have identical counts.

## Then run dry-run

```bash
bash tools/ff-closing-stock-07102026.sh
```

Review MATCH lines — must be exact name, no NOT FOUND.

Then apply:

```bash
bash tools/ff-closing-stock-07102026.sh --apply
```

---

*Please paste the RM list from the image here or update the JSON directly.*
