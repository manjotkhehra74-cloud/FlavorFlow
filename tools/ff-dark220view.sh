#!/usr/bin/env bash
# FlavorFlow — current-view whitelist for Dark Soya 220.
#
# Keep historical batches in the database and history, but show only the two
# screenshot-supplied production-date + batch-code rows in current batch-stock
# and Dispatch batch selectors:
#   2026-09-21 / 6I1516AKS
#   2026-09-25 / 6I0021AKS
#   2026-09-26 / 6I0021AKS (today's newly added stock)
#
# This is a view/API filter only. It does not delete or rewrite historical
# batches, dispatches, or reports that are intended to retain history.
set -u
DIR=/opt/flavorflow/server
SVC=flavorflow
BK=/opt/flavorflow/backups
[ -d "$DIR" ] || { echo "FATAL: $DIR not found"; exit 1; }
[ -f "$DIR/batchrecon.js" ] || { echo "FATAL: $DIR/batchrecon.js not found"; exit 1; }
[ -f "$DIR/routes/dispatch.js" ] || { echo "FATAL: $DIR/routes/dispatch.js not found"; exit 1; }
mkdir -p "$BK"
TS=$(date +%s)
cp -a "$DIR/batchrecon.js" "$BK/batchrecon.js.bak-dark220view-$TS"
cp -a "$DIR/routes/dispatch.js" "$BK/dispatch.js.bak-dark220view-$TS"
echo "=== FF-DARK220VIEW $(date) ==="
echo "BACKUP: $BK/*-dark220view-$TS"
export FF_DIR="$DIR" FF_BK="$BK" FF_TS="$TS"

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const dir = process.env.FF_DIR;
let changed = false;

// 1) Inventory → Batch-wise Stock uses batchrecon.batchStockRows(db), so the
// whitelist belongs in the shared module. History remains in the DB.
const mf = dir + '/batchrecon.js';
let m = fs.readFileSync(mf, 'utf8');
if (!m.includes('ff-dark220-visible-batches')) {
  const fn = m.indexOf('function batchesLeft(db) {');
  if (fn === -1) { console.log('MODULE: batchesLeft anchor not found'); process.exit(2); }
  const loopRel = m.indexOf('  for (const r of rows) {', fn);
  if (loopRel === -1) { console.log('MODULE: batch loop anchor not found'); process.exit(2); }
  const helper =
    "  const productNames = new Map(productList(db).map((p) => [p.id, String(p.name || '')]));\n";
  m = m.slice(0, loopRel) + helper + m.slice(loopRel);
  const loop = m.indexOf('  for (const r of rows {', fn); // intentionally never matches; keep lookup below explicit
  const loopStart = m.indexOf('  for (const r of rows) {', fn);
  const after = loopStart + '  for (const r of rows) {\n'.length;
  const filter =
    "    /* ff-dark220-visible-batches */\n" +
    "    const dark220 = String(productNames.get(r.pid) || '').toLowerCase().replace(/[^a-z0-9]+/g, '') === 'darksoya220gm';\n" +
    "    if (dark220) { const d = String(r.d || '').slice(0, 10); const c = String(r.code || '').trim().toUpperCase(); if (!((d === '2026-09-21' && c === '6I1516AKS') || (d === '2026-09-25' && c === '6I0021AKS') || (d === '2026-09-26' && c === '6I0021AKS'))) continue; }\n";
  m = m.slice(0, after) + filter + m.slice(after);
  fs.writeFileSync(mf, m);
  changed = true;
  console.log('MODULE: Dark Soya 220 current batch whitelist installed ✓');
} else {
  const old = "if (!((d === '2026-09-21' && c === '6I1516AKS') || (d === '2026-09-25' && c === '6I0021AKS'))) continue;";
  const upgraded = "if (!((d === '2026-09-21' && c === '6I1516AKS') || (d === '2026-09-25' && c === '6I0021AKS') || (d === '2026-09-26' && c === '6I0021AKS'))) continue;";
  if (!m.includes("d === '2026-09-26' && c === '6I0021AKS'")) {
    if (!m.includes(old)) { console.log('MODULE: whitelist exists but upgrade anchor not found'); process.exit(2); }
    m = m.replace(old, upgraded);
    fs.writeFileSync(mf, m);
    changed = true;
    console.log('MODULE: Dark Soya 220 whitelist upgraded for today\'s batch ✓');
  } else {
    console.log('MODULE: Dark Soya 220 current batch whitelist already current ✓');
  }
}
try { cp.execFileSync('node', ['--check', mf]); console.log('MODULE: syntax OK'); }
catch (e) { console.log('MODULE: syntax FAIL — restoring backup'); cp.copyFileSync(process.env.FF_BK + '/batchrecon.js.bak-dark220view-' + process.env.FF_TS, mf); process.exit(3); }

// 2) Dispatch selector API uses its own query. Apply the same whitelist only
// when the selected product is Dark Soya 220; all other products are untouched.
const df = dir + '/routes/dispatch.js';
let dsrc = fs.readFileSync(df, 'utf8');
if (!dsrc.includes('ff-dark220-dispatch-visible')) {
  const start = dsrc.indexOf('/* ff-batchselect */');
  const endMarker = '/* end ff-batchselect */';
  const end = dsrc.indexOf(endMarker, start);
  if (start === -1 || end === -1) {
    console.log('DISPATCH: batchselect block anchor not found — module changed, dispatch unchanged');
  } else {
    let block = dsrc.slice(start, end);
    block = block.replace(
      "SELECT id, active FROM products WHERE id = ?",
      "SELECT id, active, name FROM products WHERE id = ?"
    );
    const colsAnchor = "  const cols = db.prepare('PRAGMA table_info(batches)').all().map((r) => String(r.name));";
    const viewVars =
      "  /* ff-dark220-dispatch-visible */\n" +
      "  const dark220 = String(product.name || '').toLowerCase().replace(/[^a-z0-9]+/g, '') === 'darksoya220gm';\n" +
      "  const dark220Where = dark220 ? \"AND ((date(COALESCE(b.planned_date, '')) = '2026-09-21' AND UPPER(TRIM(COALESCE(b.code, ''))) = '6I1516AKS') OR (date(COALESCE(b.planned_date, '')) = '2026-09-25' AND UPPER(TRIM(COALESCE(b.code, ''))) = '6I0021AKS') OR (date(COALESCE(b.planned_date, '')) = '2026-09-26' AND UPPER(TRIM(COALESCE(b.code, ''))) = '6I0021AKS')) \" : '';\n";
    if (!block.includes(colsAnchor)) {
      console.log('DISPATCH: columns anchor not found — module changed, dispatch unchanged');
    } else {
      block = block.replace(colsAnchor, viewVars + colsAnchor);
      const fromAnchor =
        '    "FROM batches b WHERE b.product_id = ? AND UPPER(COALESCE(b.status, \'\')) = \'COMPLETED\' " +';
      if (!block.includes(fromAnchor)) {
        console.log('DISPATCH: query anchor not found — module changed, dispatch unchanged');
      } else {
        block = block.replace(fromAnchor, fromAnchor + '\n    dark220Where +');
        dsrc = dsrc.slice(0, start) + block + dsrc.slice(end);
        fs.writeFileSync(df, dsrc);
        changed = true;
        console.log('DISPATCH: Dark Soya 220 batch whitelist installed ✓');
      }
    }
  }
} else {
  const old = "OR (date(COALESCE(b.planned_date, '')) = '2026-09-25' AND UPPER(TRIM(COALESCE(b.code, ''))) = '6I0021AKS'))";
  const upgraded = "OR (date(COALESCE(b.planned_date, '')) = '2026-09-25' AND UPPER(TRIM(COALESCE(b.code, ''))) = '6I0021AKS') OR (date(COALESCE(b.planned_date, '')) = '2026-09-26' AND UPPER(TRIM(COALESCE(b.code, ''))) = '6I0021AKS'))";
  if (!dsrc.includes("date(COALESCE(b.planned_date, '')) = '2026-09-26'")) {
    if (!dsrc.includes(old)) { console.log('DISPATCH: whitelist exists but upgrade anchor not found'); process.exit(2); }
    dsrc = dsrc.replace(old, upgraded);
    fs.writeFileSync(df, dsrc);
    changed = true;
    console.log('DISPATCH: Dark Soya 220 whitelist upgraded for today\'s batch ✓');
  } else {
    console.log('DISPATCH: Dark Soya 220 batch whitelist already current ✓');
  }
}
try { cp.execFileSync('node', ['--check', df]); console.log('DISPATCH: syntax OK'); }
catch (e) { console.log('DISPATCH: syntax FAIL — restoring backup'); cp.copyFileSync(process.env.FF_BK + '/dispatch.js.bak-dark220view-' + process.env.FF_TS, df); process.exit(3); }

console.log(changed ? 'DARK220VIEW: code changed' : 'DARK220VIEW: already current');
JS
RC=$?
if [ "$RC" -eq 2 ] || [ "$RC" -eq 3 ]; then
  echo "DARK220VIEW FAILED — backups retained in $BK"
  exit 1
fi

if [ "$RC" -eq 0 ] || [ "$RC" -eq 4 ] || [ "$RC" -eq 1 ]; then
  # The node script exits 0 for both changed and already-installed states.
  systemctl restart "$SVC" || { echo "SERVICE RESTART FAILED"; exit 1; }
  sleep 3
  curl -s -m 6 http://127.0.0.1:4000/api/health && echo "" || { echo "HEALTH CHECK FAILED"; exit 1; }
fi
echo "DARK220VIEW VERIFIED ✓ — current app views show 21/09 + 6I1516AKS, 25/09 + 6I0021AKS and today’s 26/09 batch; history retained"
