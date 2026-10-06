# Productivity & Labour API contract

The Flutter module in `lib/features/reports/productivity_labour_page.dart` consumes the following tenant-scoped API. These endpoints are intentionally separate from inventory, dispatch, and planned-production reports.

## Product weight configuration

`POST /products` and `PUT /products/:id` accept the existing `weightWithoutCb` field and the explicit productivity fields below:

```json
{
  "netWeightPerCb": 4.32,
  "netWeightEffectiveFrom": "2026-01-01",
  "netWeightEffectiveTo": null
}
```

`weightWithoutCb` remains a backwards-compatible alias for `netWeightPerCb`. `weightPerCb` / with-CB weight is reference data only and must never be used by productivity.

When a completed batch is reported for a date, resolve the effective net weight for that product and production date. Do not silently fall back to with-CB/carton weight. A product with no valid effective net weight should be rejected from productivity aggregation and surfaced as a configuration error.

## Daily labour

`POST /labour/daily` stores one line-level row for each date, production line, and shift. Worker count does not change when the product or production batch on that line changes:

```json
{
  "date": "2026-10-06",
  "shift": "Day",
  "line": "Line 2",
  "workerCount": 8,
  "actualHours": 8,
  "supervisor": "Supervisor name",
  "remarks": ""
}
```

Required values are `date`, `shift` (`Day` or `Night`), `line`, positive `workerCount`, and positive `actualHours`. There is deliberately no overtime, product, or batch-code field in this line-level labour entry. The uniqueness key is `date + line + shift`; the API should reject an accidental duplicate instead of overwriting it. Product and batch production remain authoritative in the Production register.

`PUT /labour/daily/:id` accepts the same body and updates a saved manual row; the UI exposes this as **Edit Entry**. `GET /labour/daily?from=YYYY-MM-DD&to=YYYY-MM-DD&line=Line%201&shift=Day` returns `{ "rows": [...] }`. Omit `shift` for combined reporting.

Line/SKU configuration used by Production and the reports:

- **Line 2:** Soya Sauce 740, Soya Sauce 1.3, White Vinegar 610, Brown Vinegar 610, Vinegar 1.0.
- **Line 3:** Dark Soya 220, White Vinegar 180, Soya Sauce 4.7, White Vinegar 4.0 for packing and labelling.

Production/report aggregation must validate these mappings when a completed record has a line and SKU; a Line 2 or Line 3 record outside its configured family must be rejected or surfaced as a reconciliation/configuration error, not silently reassigned. Other lines can have their own configured SKU list. The line-level labour row is not duplicated when the product or batch code changes.

## Productivity summary

`GET /reports/productivity` accepts date/month, SKU, line, and shift filters. It does not need a batch-code filter: completed production is read automatically from the Production register. It must aggregate only completed production records:

- sum `produced_cb` from completed batches;
- aggregate all rows for the same batch code without counting a source row twice;
- never read planned CB, inventory CB, dispatch stock, or screenshot totals;
- calculate `netKg = producedCb * effectiveNetWeightKgPerCb`;
- calculate `cbPerHead = producedCb / aggregatedManpower`;
- calculate `kgPerHead = netKg / aggregatedManpower`.

The response is shaped for the existing table and remains grouped by SKU plus production line. The same SKU on different lines is represented by separate rows; White Vinegar 610 and Brown Vinegar 610 are grouped only within the same line in the Productivity summary:

```json
{
  "columns": ["SKU", "LINE", "MANPOWER", "PROD. IN KG", "PROD. IN CB", "PRODUCTIVITY IN KG/HEAD", "PRODUCTIVITY IN CB/HEAD"],
  "rows": [["Vinegar 180", "Line 1", 8, 43.2, 10, 5.4, 1.25]],
  "totals": {"cb": 10, "kg": 43.2, "manpower": 8, "kgPerHead": 5.4, "cbPerHead": 1.25}
}
```

Manpower is derived from the saved daily labour rows matching the selected date, line, and shift. A product or batch change on a line does not create another labour assignment. It must not be a product-master constant. If the API normalizes hours, use `workerCount * actualHours / configuredStandardShiftHours`; do not add overtime. The client fallback counts each date + line + shift assignment once and allocates it across multiple SKU rows by completed CB so a product change cannot duplicate the line assignment.

## Analysis and exports

- `GET /reports/productivity/analysis` returns product-wise, line-wise, shift-wise, and period-total rows using the same filters and formulas.
- `GET /reports/productivity.xlsx` exports the filtered productivity/analysis data.
- `GET /labour/daily.xlsx` exports the filtered manual labour register.

All endpoints must enforce the existing `reports.view` / labour-management permissions and tenant isolation server-side.

## Weight examples

These are net bottle weights per CB, not carton weights:

- Vinegar 180: `24 × 0.180 = 4.32 kg/CB`
- Soya 740: `18 × 0.740 = 13.32 kg/CB`
- Soya 1.3: `12 × 1.3 = 15.6 kg/CB`
- Vinegar 250: `24 × 0.250 = 6 kg/CB`
- Vinegar 610: `18 × 0.610 = 10.98 kg/CB`

The Vinegar 180 `9.185 kg` with-CB value remains reference data and must not replace `4.32 kg/CB`.

## Productivity-only SKU grouping correction

- This rule applies **only inside the Productivity summary report**.
- In the productivity response, `White Vinegar 610` and `Brown Vinegar 610` use one report grouping/display name: **`Vinegar 610`**. Their completed production CB, net KG, and productivity totals are added together under that Productivity row.
- Product Master, Production, Inventory, Dispatch, Daily Labour entry, Labour Analysis, stock assignment, and all source/history records must continue to keep the two original product names and product IDs separately.
- Do not perform a global rename or product-master/database merge. Preserve every other original SKU name unchanged.
- A Productivity filter for `Vinegar 610` matches both source 610 Vinegar products. Labour Analysis filters and columns remain source-product-specific. Do not mix this with the unrelated White Vinegar 180 stock-assignment issue.

## Labour Analysis workbook layout

The Labour Analysis tab should follow the uploaded labour workbook's lower summary section rather than the Productivity summary table. It is a month/period matrix with three separate sections:

1. **Day Shift**
2. **Night Shift**
3. **Combined Day & Night**

Each section keeps the original source SKUs as separate columns, including `White Vinegar 610` and `Brown Vinegar 610`. Suggested row order, matching the sheet, is:

- Net weight per CB (configuration/reference row)
- CB
- Manpower
- Prod in kg
- CB/man
- Wt/man

For each source SKU and selected shift:

- `CB` = sum of completed `produced_cb` for that source product and period/shift;
- `Manpower` = aggregated matching Daily Labour rows, not a product-master constant;
- `Prod in kg` = CB × effective net bottle weight per CB;
- `CB/man` = CB ÷ Manpower;
- `Wt/man` = Prod in kg ÷ Manpower.

To use the manually entered hours in the same way as the decimal manpower values in the workbook, calculate normalized manpower as `workerCount × actualHours ÷ configuredStandardShiftHours`. No overtime column or overtime premium is introduced. If no standard shift-hours value is configured, the report must show the configuration warning instead of silently guessing.

The app should keep the workbook-style horizontal matrix for each section, with date/month, line, source SKU, and shift filters. A line filter of `All lines` gives the period matrix; selecting a line recalculates the same three sections for that line. The detailed Daily Labour tab remains row-wise and contains only date, shift, line, workers, actual hours, supervisor, and remarks; product and batch code are intentionally absent.

The analysis response can provide the three matrices as `sections.day`, `sections.night`, and `sections.combined`, each shaped as `{ "columns": ["METRIC", "740", "1.3", "White Vinegar 610", "Brown Vinegar 610", ...], "rows": [...] }`. The Flutter client renders each matrix separately and keeps a flat-response fallback for older servers.

Before marking a period as reconciled, the server should compare the completed-batch aggregation with the authoritative production register and expose a reconciliation warning/status in the response. The known 740 discrepancy must be resolved first; the UI must not label a response with an unresolved discrepancy as correct.
