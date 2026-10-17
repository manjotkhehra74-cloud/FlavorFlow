# Windows App handoff

This folder contains selected **concept previews** and an adjustment API-contract note, not a standalone runnable app. The main repository includes Windows-specific layouts under `lib/`. The Add/Edit User desktop form and Audit Trail read-only inspector are now implemented under `lib/features/` and copied here under `lib/` for handoff. Other selected concepts have **not** all been implemented. Selection approves visual direction, not backend capability or release.

Selected concepts under `preview/`: revised stock-adjustment form, approvals register, approval history, reports library, productivity, daily labour, labour analysis, users & roles, add/edit user, and audit trail. Preview rows and values are illustrative, not company defaults.

`ADJUSTMENT_MATERIAL_API_CONTRACT.md` documents blocked server work for material adjustments. Never submit a material ID as `productId` or bypass approval. Labour analysis in the current client contains customer-specific vinegar rules; do not promote those to universal defaults. The separate Truck Loading Calculator has been removed; dispatch entry still calculates weights. No deployment is implied by these previews.
