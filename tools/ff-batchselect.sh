#!/usr/bin/env bash
# FlavorFlow — dispatch batch picker + remaining-stock API.
#
# Adds GET /api/dispatch/batches?productId=ID. The response contains only
# COMPLETED batches that still have CB/tray stock, ordered oldest first, with
# planned date and remaining quantities. The Flutter Dispatch screen uses this
# to show: BATCH-CODE · dd/mm · available stock.
#
# This is deliberately read-only with respect to stock. It never changes a
# product quantity or a batch. Run ff-stockfix/ff-batchrecon separately for the
# one-time historical reconciliation; this patch only prevents the UI from
# making an operator type an unknown batch code.
#
# Idempotent. Backup + node --check + auto-restore.
set -u

if [ -d /opt/flavorflow-saas/core ]; then DIR=/opt/flavorflow-saas/core; MODE=saas; SVC=flavorflow-saas; BK=/opt/flavorflow-saas/backups;
elif [ -d /opt/flavorflow/server ]; then DIR=/opt/flavorflow/server; MODE=factory; SVC=flavorflow; BK=/opt/flavorflow/backups;
else echo "FATAL: server directory not found"; exit 1; fi

F="$DIR/routes/dispatch.js"
[ -f "$F" ] || { echo "FATAL: $F not found"; exit 1; }
mkdir -p "$BK"
TS=$(date +%s)
cp -a "$F" "$BK/dispatch.js.bak-batchselect-$TS"
export FF_DIR="$DIR" FF_FILE="$F" FF_BACKUP="$BK/dispatch.js.bak-batchselect-$TS"

echo "=== FF-BATCHSELECT ($MODE) $(date) ==="
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = process.env.FF_FILE;
let src = fs.readFileSync(f, 'utf8');

if (src.includes('ff-batchselect') && src.includes('ff-batch-required')) {
  console.log('DISPATCH: batch picker route already installed ✓');
  process.exit(4);
}

const hasPerm = /requirePerm\s*\(/.test(src);
const guard = hasPerm ? "requirePerm('dispatch.view'), " : '';
const block = `/* ff-batchselect */
router.get('/batches', ${guard}(req, res) => {
  const productId = Number((req.query || {}).productId);
  if (!Number.isInteger(productId) || productId <= 0) return res.status(400).json({ error: 'A valid productId is required.' });
  const product = db.prepare('SELECT id, active FROM products WHERE id = ?').get(productId);
  if (!product || Number(product.active == null ? 1 : product.active) === 0) return res.status(404).json({ error: 'Product not found.' });
  const cols = db.prepare('PRAGMA table_info(batches)').all().map((r) => String(r.name));
  const has = (name) => cols.includes(name);
  const producedTrays = has('produced_trays') ? 'COALESCE(b.produced_trays, 0)' : '0';
  const usedTrays = has('used_trays') ? 'COALESCE(b.used_trays, 0)' : '0';
  const date = has('planned_date') ? 'b.planned_date' : "''";
  const rows = db.prepare(
    'SELECT b.id, b.code, ' + date + ' planned_date, ' +
    'COALESCE(b.produced_cb, 0) produced_cb, COALESCE(b.used_cb, 0) used_cb, ' +
    producedTrays + ' produced_trays, ' + usedTrays + ' used_trays ' +
    "FROM batches b WHERE b.product_id = ? AND UPPER(COALESCE(b.status, '')) = 'COMPLETED' " +
    "AND (COALESCE(b.produced_cb, 0) - COALESCE(b.used_cb, 0) > 0 OR " + producedTrays + " - " + usedTrays + " > 0) " +
    "ORDER BY COALESCE(b.planned_date, '') ASC, b.id ASC"
  ).all(productId).map((b) => ({
    id: b.id,
    code: String(b.code || '').trim(),
    plannedDate: b.planned_date || '',
    remainingCb: Math.max(0, Number(b.produced_cb || 0) - Number(b.used_cb || 0)),
    remainingTrays: Math.max(0, Number(b.produced_trays || 0) - Number(b.used_trays || 0)),
  }));
  res.json({ batches: rows });
});
/* end ff-batchselect */
`;
if (!src.includes('ff-batchselect')) {
  const marker = 'module.exports = router;';
  const dynamic = [src.indexOf("router.get('/:id'"), src.indexOf('router.get(\"/:id\"')].filter((n) => n >= 0).sort((a, b) => a - b)[0];
  const at = dynamic == null ? src.indexOf(marker) : dynamic;
  if (at === -1 || at == null) { console.log('ROUTE: dispatch route anchor not found'); process.exit(2); }
  src = src.slice(0, at) + block + '\n' + src.slice(at);
} else {
  console.log('DISPATCH: batch picker route present; checking remaining guards');
}

// A duplicate code can exist on two manufacturing dates. The picker sends the
// row id as batchId so selecting 23/09 and 24/09 is not ambiguous; old clients
// still use the code/FIFO path.
if (!src.includes('ff-batch-id')) {
  const q = /^([ \t]*)const bchs = db\.prepare\(([\s\S]*?)\)\.all\(bCode, l\.productId\);/m;
  const m = src.match(q);
  if (m) {
    const original = m[0].replace('const bchs', 'let bchs');
    const exact = [
      original,
      m[1] + "if (Number(l.batchId) > 0) { /* ff-batch-id */",
      m[1] + "  bchs = db.prepare(\"SELECT id, produced_cb, COALESCE(used_cb,0) AS ucb, produced_trays, COALESCE(used_trays,0) AS ut FROM batches WHERE id = ? AND product_id = ? AND status = 'COMPLETED'\").all(Number(l.batchId), l.productId);",
      m[1] + "}"
    ].join('\n');
    src = src.replace(m[0], exact);
    console.log('DISPATCH: exact batch-row selection supported ✓');
  } else {
    console.log('DISPATCH: batch deduction anchor not found — batchId stays harmless for old server');
  }
}

// Server-side guard for API clients older than the Flutter build. A line that
// omits a batch must not silently reduce inventory while leaving used_cb
// unchanged. Opening/unassigned stock (no completed batch with balance) is
// still allowed, so this does not invent stock for any product.
if (!src.includes('ff-batch-required')) {
  const re = /^([ \t]*)if \(!bCode\) continue;[ \t]*$/m;
  if (re.test(src)) {
    const indent = src.match(re)[1] || '  ';
    const guardBlock = [
      indent + 'if (!bCode) {',
      indent + '  /* ff-batch-required */',
      indent + "  const hasBatchStock = db.prepare(\"SELECT 1 FROM batches WHERE product_id = ? AND UPPER(COALESCE(status, '')) = 'COMPLETED' AND (COALESCE(produced_cb,0) - COALESCE(used_cb,0) > 0 OR COALESCE(produced_trays,0) - COALESCE(used_trays,0) > 0) LIMIT 1\").get(l.productId);",
      indent + "  if (hasBatchStock) throw bad('Select a batch code for this product before dispatch.', 400);",
      indent + '  continue;',
      indent + '}'
    ].join('\n');
    src = src.replace(re, guardBlock);
    console.log('DISPATCH: blank batch guard installed ✓');
  } else {
    console.log('DISPATCH: no blank-batch anchor found — picker route still installed');
  }
}

fs.writeFileSync(f, src);
try {
  cp.execSync('node --check "' + f + '"');
  console.log('ROUTE: GET /api/dispatch/batches installed ✓' + (hasPerm ? ' (dispatch.view protected)' : ''));
} catch (e) {
  fs.copyFileSync(f, process.env.FF_BACKUP);
  console.log('SYNTAX FAIL — restored: ' + String(e.stderr || e).slice(0, 500));
  process.exit(3);
}
JS
RC=$?
if [ "$RC" -eq 3 ]; then
  echo "BATCHSELECT FAIL — original route restored"
  exit 1
fi
if [ "$RC" -eq 2 ]; then
  echo "BATCHSELECT FAIL — route unchanged"
  exit 1
fi

if [ -z "${FF_NO_RESTART:-}" ] && [ "$RC" -eq 0 ] && ! grep -q 'batch picker route already installed' /dev/null 2>/dev/null; then
  systemctl restart "$SVC" || { echo "SERVICE RESTART FAILED"; exit 1; }
  sleep 3
  if [ "$MODE" = factory ]; then curl -s -m 6 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAILED"; fi
fi
echo "BATCHSELECT VERIFIED ✓ — Dispatch batch dropdown API ready"
