#!/usr/bin/env bash
# FlavorFlow ERP — charge dispatches OLDEST-BATCH-FIRST (product FIFO).
#
# WHY: dispatch lines carry whatever batch code the operator typed, so the
#   quantity is charged to THAT code. In the register the old batches
#   (Aug / early Sep) still show their full stock while newer ones are
#   already consumed — the stock is real, it just sits on the wrong batch,
#   which is why "goods dispatched long ago" keep showing on the screen.
#
# WHAT THIS DOES (data only):
#   For every product: take the total dispatched (dispatch_items of all
#   non-VOID dispatches) and charge it to that product's COMPLETED batches
#   oldest-first (planned_date, id). The per-product total stock does NOT
#   change — only WHICH batch carries it (old ones empty out, recent ones
#   keep it), which is how a FIFO store actually behaves.
#   Idempotent — re-run safe. Full DB backup first.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-STOCKFIX3 (product FIFO) $(date) ==="
DB=/opt/flavorflow/server/data/erp.db
[ -f "$DB" ] || { echo "FATAL: DB nahi mili: $DB"; exit 1; }

cp -a "$DB" "/opt/flavorflow/backups/erp.db.bak-stockfix3-$(date +%s)" && echo "DB BACKUP ✓ (/opt/flavorflow/backups/)"
systemctl stop flavorflow || true
sleep 1

node - <<'JS'
function openDb(p) {
  try { const M = require('better-sqlite3'); return (M.default ? new M.default(p) : new M(p)); }
  catch (e) { const { DatabaseSync } = require('node:sqlite'); return new DatabaseSync(p); }
}
const db = openDb('/opt/flavorflow/server/data/erp.db');

const B = db.prepare('PRAGMA table_info(batches)').all().map(r => r.name);
if (!B.includes('used_cb')) { console.log('batches.used_cb nahi hai — pehla ff-batchunit.sh chalao'); process.exit(2); }
const bTrays = B.includes('used_trays'), pTrays = B.includes('produced_trays');
const DI = db.prepare('PRAGMA table_info(dispatch_items)').all().map(r => r.name);
const dTrays = DI.includes('trays');

const prod = db.prepare(`SELECT id, name FROM products ORDER BY name`).all();
const nameOf = new Map(prod.map(p => [p.id, p.name]));

const disp = db.prepare(`
  SELECT di.product_id pid, SUM(COALESCE(di.cartons,0)) cb, ${dTrays ? 'SUM(COALESCE(di.trays,0))' : '0'} tr
  FROM dispatch_items di JOIN dispatches d ON d.id = di.dispatch_id
  WHERE UPPER(COALESCE(d.status,'DISPATCHED')) <> 'VOID'
  GROUP BY di.product_id`).all();
const dispMap = new Map(disp.map(r => [r.pid, { cb: r.cb || 0, tr: r.tr || 0 }]));

const batches = db.prepare(`
  SELECT id, product_id pid, COALESCE(code,'') code, COALESCE(planned_date,'') pd,
         COALESCE(produced_cb,0) pcb, ${pTrays ? 'COALESCE(produced_trays,0)' : '0'} ptr,
         COALESCE(used_cb,0) ucb, ${bTrays ? 'COALESCE(used_trays,0)' : '0'} utr
  FROM batches WHERE UPPER(COALESCE(status,'')) = 'COMPLETED'
  ORDER BY product_id ASC, COALESCE(planned_date,'') ASC, id ASC`).all();

const byPid = new Map();
for (const b of batches) { if (!byPid.has(b.pid)) byPid.set(b.pid, []); byPid.get(b.pid).push(b); }

const upd = db.prepare(bTrays ? 'UPDATE batches SET used_cb = ?, used_trays = ? WHERE id = ?' : 'UPDATE batches SET used_cb = ? WHERE id = ?');
db.exec('BEGIN');
try {
  let changed = 0, emptied = 0, dropped = 0;
  const rows = [];
  for (const [pid, list] of byPid) {
    const d = dispMap.get(pid) || { cb: 0, tr: 0 };
    let remCb = d.cb, remTr = d.tr;
    for (const b of list) {
      const takeCb = Math.max(0, Math.min(remCb, b.pcb));
      const takeTr = bTrays ? Math.max(0, Math.min(remTr, b.ptr)) : 0;
      remCb -= takeCb; remTr -= takeTr;
      const newCb = takeCb, newTr = (bTrays && takeTr > 0) ? takeTr : b.utr;
      if (newCb !== b.ucb || (bTrays && newTr !== b.utr)) {
        if (bTrays) upd.run(newCb, newTr, b.id); else upd.run(newCb, b.id);
        changed++;
        if (newCb >= b.pcb && b.pcb - b.ucb > 0) emptied++;
      }
    }
    if (remCb > 0 || remTr > 0) dropped++;
    const produced = list.reduce((s, b) => s + b.pcb, 0);
    rows.push({
      product: (nameOf.get(pid) || ('#' + pid)).slice(0, 24),
      batches: list.length,
      produced,
      dispatched: d.cb,
      left: Math.max(0, produced - d.cb),
      over: Math.max(0, d.cb - produced)
    });
  }
  db.exec('COMMIT');
  console.log('batches updated   : ' + changed + '  (fully emptied: ' + emptied + ')');
  console.log('products dispatched more than produced (extra ignored): ' + dropped);
  console.log('');
  console.log('product                  batches  produced  dispatched   left   over');
  for (const r of rows) {
    if (!r.produced && !r.dispatched) continue;
    console.log(
      r.product.padEnd(24) +
      String(r.batches).padStart(6) +
      String(r.produced).padStart(10) +
      String(r.dispatched).padStart(12) +
      String(r.left).padStart(7) +
      String(r.over).padStart(7));
  }
} catch (e) {
  try { db.exec('ROLLBACK'); } catch (_) {}
  console.log('FAILED — rolled back: ' + e.message);
  process.exit(1);
}
JS
RC=$?
if [ $RC -ne 0 ]; then echo "STOCKFIX3 FAIL"; systemctl start flavorflow || true; exit 1; fi

systemctl start flavorflow || true
sleep 3
curl -s -m 5 http://127.0.0.1:4000/api/health && echo "" || echo "HEALTH CHECK FAIL"
echo "STOCKFIX3 DONE ✓ — purani batches khali, bacha hoya stock navian batches te"
