# FlavorFlow backend

This directory contains the versioned Node.js API source. It requires Node.js 24 or newer and uses SQLite through `node:sqlite`.

## Local checks

```sh
npm ci
npm test
npm start
```

Set `ERP_DB_PATH` to a disposable database for local development and tests. Runtime data under `data/`, environment files, SQLite files, backups, installed dependencies, and `.jwt-secret` are deliberately ignored by Git.

## Secrets and initial users

JWT signing uses `JWT_SECRET` (at least 32 characters) or the protected `.jwt-secret` file. The production GitHub Actions deployment creates that file on the VPS if it is missing; it is never included in the source artifact.

A fresh, empty database creates no built-in accounts. To bootstrap one administrator, set `FLAVORFLOW_BOOTSTRAP_EMAIL` and a `FLAVORFLOW_BOOTSTRAP_PASSWORD` of at least 12 characters in the server's protected environment before its first start. Existing user databases are not changed by this bootstrap behavior.

## Drum traceability

Drum inventory is stored separately from bottled/carton finished-goods inventory. A filled drum receives a unique sequential fill/sticker number within its plant; empty iron drums are reusable, while historic fill records remain. Gross weight includes the iron drum. Outbound drum dispatches are recorded only at the source plant; no Neemrana receiving workflow is provided.

The 22 October 2026 report is loaded as product-level aggregate opening stock. Partial aggregate dispatches record a product, drum count, and operator-entered total kg, then decrement the remaining opening balance; they do not create or infer individual drum IDs or weights. Individually recorded fills continue to use the per-drum dispatch workflow.
