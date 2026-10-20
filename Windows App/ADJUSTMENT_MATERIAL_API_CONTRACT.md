# Stock adjustment: finished and material hierarchy (backend prerequisite)

Selected Windows concept: `preview/windows-adjustment-form-revised-concept.png`.
The user requires a stock-type dropdown (Finished goods / Semi-finished goods),
a Finished goods SKU dropdown, or a Semi-finished material-type dropdown (Raw
Material / Packing Material) followed by the filtered material dropdown. The
latter types are represented today by the `category` of rows returned from
`GET /packing/materials` (`Raw Material` versus other packing categories).
Material quantity must use the selected material's own `unit`, not `U.cb`.
Selection and quantity must never default to another product or material.

**Current blocking API:** The checkout contains only an adjustment request
client POST of `{productId, adjType, qtyCb, reason}` and approval UI that assumes
`product_name` / `qty_cb`. There is no backend server source in this checkout,
no documented material-aware adjustment request/approval contract and no
verified API capability endpoint. Sending a material ID as `productId` could
adjust a *different finished SKU with the same integer ID*; do not do this.
Likewise, a direct material stock update would bypass the requested approval
and audit/ledger. The generated concept is a design preview, **not an
implemented material adjustment**.

A safe server change must accept an explicit discriminator (for example
`itemType: 'product' | 'material'`) and the corresponding `productId` or
`materialId`, validate the selected ID and unit against the company data,
persist the type and quantity on the pending request, and on authorized approval
atomically apply signed quantity to the correct inventory/material stock table
with insufficient-stock rules, idempotency/audit and a typed stock-ledger entry.
Reject must leave stock unchanged. List/pending/history APIs need item type,
name, code, quantity and unit for both paths; existing product requests must
continue to work unchanged. Client offline queue must not enqueue an unsupported
material request; capability/version gating is required before enabling submit.

Before implementation: obtain the actual server route/schema source or a
verified versioned material-adjustment API contract; then update server and
client together, with integration tests for overlapping product/material IDs,
IN/OUT, rejection, duplicate approvals, offline queue, company-specific units,
roles and mobile UI. No deployment or publication is authorized by this note.
