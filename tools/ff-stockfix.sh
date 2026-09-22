#!/usr/bin/env bash
# FlavorFlow ERP — "dispatched stock still shows" FIX (batch-wise stock).
#
# WHY: the batch register shows  produced_cb - used_cb.  used_cb is meant to
#   grow with every dispatch, but a dispatch line that carries NO batch_code
#   can never be attributed to a batch — its stock is taken out of
#   `inventory` yet the batch keeps showing the full quantity forever.
#
# WHAT THIS DOES (data only, no route changes):
#   1. FIFO-attribute every dispatch line to COMPLETED batches
#      (lines with a batch_code first — by planned_date/id — then lines with
#      no code, filling whatever capacity is left).
#   2. Stamp the chosen batch code back into dispatch_items for the code-less
#      lines, so from now on they are attributed (and traceable).
#   3. batches.used_cb / used_trays = exactly what dispatch consumed
#      (capped at produced; a batch whose usage cannot be explained by
#      dispatch is left alone — never silently freed).
#   Idempotent — re-run safe. Full DB backup first.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-STOCKFIX $(date) ==="
DB=/opt/flavorflow/server/data/erp.db
[ -f "$DB" ] || { echo "FATAL: DB nahi mili: $DB"; exit 1; }

cp -a "$DB" "/opt/flavorflow/backups/erp.db.bak-stockfix-$(date +%s)" && echo "DB BACKUP ✓ (/opt/flavorflow/backups/)"

systemctl stop flavorflow || true
sleep 1

node - <<'JS'
const fs = require('fs');
const DB = '/opt/flavorflow/server/data/erp.db';

function openDb(p) {
  try { const M = require('better-sqlite3'); return (M.default ? new M.default(p) : new M(p)); }
  catch (e) { const { DatabaseSync } = require('node:sqlite'); return new DatabaseSync(p); }
}
const db = openDb(DB);

const bcols = () => db.prepare('PRAGMA table_info(batches)').all().map(r => r.name);
const B = bcols();
if (!B.includes('used_cb')) { console.log('batches.used_cb nahi hai — pehla ff-batchunit.sh chalao'); process.exit(2); }
const hasBTrays = B.includes('used_trays');
const DI = db.prepare('PRAGMA table_info(dispatch_items)').all().map(r => r.name);
const hasDITrays = DI.includes('trays');
const prodTrays = B.includes('produced_trays');

const trExpr = (tbl) => (hasDITrays && tbl === 'di') ? 'COALESCE(di.trays,0)' : '0';

const batches = db.prepare(`
  SELECT id, product_id pid, COALESCE(code,'') code, COALESCE(planned_date,'') pd,
         COALESCE(produced_cb,0) pcb, ${prodTrays ? 'COALESCE(produced_trays,0)' : '0'} ptr,
         COALESCE(used_cb,0) ucb, ${hasBTrays ? 'COALESCE(used_trays,0)' : '0'} utr
  FROM batches
  WHERE UPPER(COALESCE(status,'')) = 'COMPLETED'
  ORDER BY product_id ASC, COALESCE(planned_date,'') ASC, id ASC`).all();

const lines = db.prepare(`
  SELECT di.id, di.dispatch_id did, di.product_id pid, COALESCE(di.batch_code,'') bc,
         COALESCE(di.cartons,0) cb, ${hasDITrays ? 'COALESCE(di.trays,0)' : '0'} tr
  FROM dispatch_items di
  JOIN dispatches d ON d.id = di.dispatch_id
  WHERE UPPER(COALESCE(d.status,'DISPATCHED')) <> 'VOID'
  ORDER BY di.dispatch_id ASC, di.id ASC`).all();

const byId = new Map(batches.map(b => [b.id, b]));
const cap = new Map();          // batch id -> remaining capacity {cb, tr}
for (const b of batches) cap.set(b.id, { cb: Math.max(0, b.pcb), tr: Math.max(0, b.ptr) });
const used = new Map();         // batch id -> allocated {cb, tr}
for (const b of batches) used.set(b.id, { cb: 0, tr: 0 });

function batchesFor(pid, code) {
  return batches.filter(b => b.pid === pid && (code ? b.code === code : true));
}
function take(b, cb, tr) {
  const c = cap.get(b.id), u = used.get(b.id);
  const tCb = Math.max(0, Math.min(cb, c.cb));
  const tTr = Math.max(0, Math.min(tr, c.tr));
  c.cb -= tCb; c.tr -= tTr; u.cb += tCb; u.tr += tTr;
  return { tCb, tTr };
}

let stamped = 0, explainable = 0;
const stamps = [];
// PASS A — lines that already carry a batch code
for (const l of lines) {
  if (!l.bc.trim()) continue;
  let cb = l.cb, tr = l.tr;
  for (const b of batchesFor(l.pid, l.bc.trim())) {
    if (cb <= 0 && tr <= 0) break;
    const t = take(b, cb, tr); cb -= t.tCb; tr -= t.tTr;
    if (t.tCb || t.tTr) explainable++;
  }
}
// PASS B — lines with no batch code: give the whole line to the first
// (oldest) batch group that still has capacity. Staying inside ONE code
// group keeps the result identical on every re-run (idempotent).
let dropped = 0;
for (const l of lines) {
  if (l.bc.trim()) continue;
  let cb = l.cb, tr = l.tr;
  if (cb <= 0 && tr <= 0) continue;
  // group = batches sharing product + code, in FIFO order
  const groups = [];
  for (const b of batchesFor(l.pid, null)) {
    let g = groups.find(x => x.code === b.code);
    if (!g) { g = { code: b.code, batches: [], cb: 0, tr: 0 }; groups.push(g); }
    g.batches.push(b);
    const c = cap.get(b.id);
    g.cb += c.cb; g.tr += c.tr;
  }
  const withRoom = groups.filter(g => (cb > 0 && g.cb > 0) || (tr > 0 && g.tr > 0));
  if (!withRoom.length) continue;
  // prefer a group that can swallow the whole line; else the roomiest one
  const fits = withRoom.find(g => g.cb >= cb && g.tr >= tr);
  const pick = fits || withRoom.slice().sort((a, b) => (b.cb + b.tr) - (a.cb + a.tr))[0];
  const first = pick.batches[0];
  for (const b of batchesFor(l.pid, first.code)) {
    if (cb <= 0 && tr <= 0) break;
    const t = take(b, cb, tr); cb -= t.tCb; tr -= t.tTr;
  }
  stamps.push({ id: l.id, code: first.code });
  stamped++;
  if (cb > 0 || tr > 0) dropped++;
}

// write back
const upd = db.prepare(hasBTrays
  ? 'UPDATE batches SET used_cb = ?, used_trays = ? WHERE id = ?'
  : 'UPDATE batches SET used_cb = ? WHERE id = ?');
const updLine = db.prepare('UPDATE dispatch_items SET batch_code = ? WHERE id = ?');
db.exec('BEGIN');
try {
  for (const s of stamps) updLine.run(s.code, s.id);
  let changed = 0;
  const before = batches.reduce((s, b) => s + Math.max(0, b.pcb - b.ucb), 0);
  const finalUsed = (b) => (used.get(b.id).cb > 0 ? used.get(b.id).cb : b.ucb);
  const after = batches.reduce((s, b) => s + Math.max(0, b.pcb - finalUsed(b)), 0);
  for (const b of batches) {
    const u = used.get(b.id);
    const newCb = u.cb > 0 ? u.cb : b.ucb;         // unexplainable usage is kept
    const newTr = (!hasBTrays) ? 0 : (u.tr > 0 ? u.tr : b.utr);
    if (newCb !== b.ucb || (hasBTrays && newTr !== b.utr)) {
      if (hasBTrays) upd.run(newCb, newTr, b.id); else upd.run(newCb, b.id);
      changed++;
    }
  }
  db.exec('COMMIT');
  console.log('dispatch lines          : ' + lines.length);
  console.log('lines stamped w/ code   : ' + stamped);
  console.log('batch allocations       : ' + explainable);
  console.log('batches updated         : ' + changed);
  console.log('batch stock BEFORE      : ' + before + ' CB');
  console.log('batch stock AFTER       : ' + after + ' CB');
  console.log("stock released (fixed)  : " + (before - after) + " CB");
  console.log("lines partly unplaced   : " + dropped);
} catch (e) {
  try { db.exec('ROLLBACK'); } catch (_) {}
  console.log('FAILED — rolled back: ' + e.message);
  process.exit(1);
}
JS
RC=$?
if [ $RC -ne 0 ]; then echo "STOCKFIX FAIL"; systemctl start flavorflow || true; exit 1; fi

systemctl start flavorflow || true
sleep 3
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAIL"
echo "STOCKFIX DONE ✓ — batch register hun dispatch de hisaab naal stock dikhayega"

echo "--- dispatch.js (batch-deduct region, for the future-proof patch) ---"
sed -n '120,205p' /opt/flavorflow/server/routes/dispatch.js
echo "=== END ==="
