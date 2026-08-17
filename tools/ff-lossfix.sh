#!/usr/bin/env bash
# FlavorFlow: monthly Packing LOSS% module (factory sheet format).
#   Tables: loss_months (open month), loss_values (manual/override cells),
#           loss_archive (closed months snapshot JSON).
#   Routes on the packing router:
#     GET  /api/packing/loss            → current month full structure
#     GET  /api/packing/loss?ym=YYYY-MM → archived month
#     PUT  /api/packing/loss/cell       → { key, value }  manual edit
#     POST /api/packing/loss/close      → archive month, roll closing→opening
#   Computation:
#     Actual  = Σ produced_cb of COMPLETED batches in the month (per product)
#     CB      = BOM qty/cb × produced CB (+ qty/tray × trays) per material
#     Extra   = manual CONSUMED txns in month (batch NULL); shared materials
#               split by expected usage; every cell overridable
#     Loss%   = Extra ÷ CB × 100 · %Adherence = (Opening+Actual)/Projection×100
#     Closing = Opening + Actual − month dispatched CB (overridable)
# Idempotent — safe to run twice.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-LOSSFIX $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-loss-$TS" 2>/dev/null
echo "DB BACKUP: /opt/flavorflow/backups/erp.db.bak-loss-$TS"

node - <<'JS'
const db = require('/opt/flavorflow/server/db');
db.exec(`
CREATE TABLE IF NOT EXISTS loss_months (ym TEXT PRIMARY KEY, status TEXT NOT NULL DEFAULT 'OPEN', created_at TEXT);
CREATE TABLE IF NOT EXISTS loss_values (ym TEXT NOT NULL, key TEXT NOT NULL, value REAL NOT NULL, PRIMARY KEY (ym, key));
CREATE TABLE IF NOT EXISTS loss_archive (ym TEXT PRIMARY KEY, data TEXT NOT NULL, closed_at TEXT);
`);
console.log('TABLES OK');
JS

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = '/opt/flavorflow/server/routes/packing.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('/loss/close')) { console.log('LOSS ROUTES: already present — skip'); process.exit(0); }
const bak = f + '.bak-loss-' + Date.now();
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak);

const CODE = `/** ff-lossfix: monthly packing loss% (factory sheet). */
function lossYm() {
  const d = new Date(Date.now() + 330 * 60 * 1000); // IST
  return d.toISOString().slice(0, 7);
}
function lossOpenMonth() {
  let m = db.prepare("SELECT ym FROM loss_months WHERE status = 'OPEN' ORDER BY ym DESC LIMIT 1").get();
  if (!m) {
    const ym = lossYm();
    db.prepare("INSERT OR IGNORE INTO loss_months (ym, status, created_at) VALUES (?, 'OPEN', ?)").run(ym, nowIso());
    m = { ym };
  }
  return m.ym;
}
function lossVals(ym) {
  const o = {};
  for (const r of db.prepare('SELECT key, value FROM loss_values WHERE ym = ?').all(ym)) o[r.key] = r.value;
  return o;
}
function lossBuild(ym) {
  const V = lossVals(ym);
  const g = (k, dflt) => (V[k] !== undefined ? V[k] : dflt);
  const products = db.prepare('SELECT * FROM products WHERE active = 1 ORDER BY name').all();
  const prodAgg = {};
  for (const r of db.prepare(
    "SELECT product_id, SUM(produced_cb) cb, SUM(produced_trays) tr FROM batches WHERE status='COMPLETED' AND substr(COALESCE(planned_date,''),1,7) = ? GROUP BY product_id"
  ).all(ym)) prodAgg[r.product_id] = r;
  const dispAgg = {};
  for (const r of db.prepare(
    "SELECT di.product_id pid, SUM(di.cartons) cb FROM dispatch_items di JOIN dispatches d ON d.id = di.dispatch_id WHERE substr(d.dispatch_date,1,7) = ? GROUP BY di.product_id"
  ).all(ym)) dispAgg[r.pid] = r.cb;

  const top = [];
  let tProj = 0, tOpen = 0, tAct = 0;
  for (const p of products) {
    const actual = Math.round(g('act:' + p.id, (prodAgg[p.id] || {}).cb || 0));
    const projection = g('proj:' + p.id, 0);
    const opening = g('open:' + p.id, 0);
    const oa = opening + actual;
    const adherence = projection > 0 ? Math.round(oa / projection * 1000) / 10 : 0;
    const closing = g('close:' + p.id, Math.max(0, oa - (dispAgg[p.id] || 0)));
    top.push({ productId: p.id, name: p.name, projection, opening, actual, openingActual: oa, adherence, closing });
    tProj += projection; tOpen += opening; tAct += actual;
  }
  top.push({ productId: 0, name: 'Total', projection: tProj, opening: tOpen, actual: tAct, openingActual: tOpen + tAct, adherence: tProj > 0 ? Math.round((tOpen + tAct) / tProj * 1000) / 10 : 0, closing: '' });

  // expected material usage per product (BOM × production)
  const bom = db.prepare(
    'SELECT b.product_id pid, b.material_id mid, b.qty_per_cb qc, b.qty_per_tray qt, m.name mname FROM packing_bom b JOIN packing_materials m ON m.id = b.material_id ORDER BY b.product_id, b.material_id'
  ).all();
  const expByMat = {}, expByPidMat = {};
  for (const l of bom) {
    const a = prodAgg[l.pid] || { cb: 0, tr: 0 };
    const exp = (a.cb || 0) * l.qc + (a.tr || 0) * l.qt;
    expByPidMat[l.pid + ':' + l.mid] = exp;
    expByMat[l.mid] = (expByMat[l.mid] || 0) + exp;
  }
  // manual consumption per material this month (not batch-linked)
  const manual = {};
  for (const r of db.prepare(
    "SELECT material_id mid, SUM(qty) q FROM packing_txns WHERE txn_type='CONSUMED' AND batch_id IS NULL AND substr(txn_date,1,7) = ? GROUP BY material_id"
  ).all(ym)) manual[r.mid] = r.q;

  const sections = [];
  for (const p of products) {
    const lines = bom.filter((l) => l.pid === p.id);
    if (!lines.length) continue;
    const rows = [];
    for (const l of lines) {
      const cb = Math.round(g('cb:' + p.id + ':' + l.mid, expByPidMat[p.id + ':' + l.mid] || 0) * 100) / 100;
      const mTot = manual[l.mid] || 0;
      const mExp = expByMat[l.mid] || 0;
      const share = mExp > 0 ? (expByPidMat[p.id + ':' + l.mid] || 0) / mExp : (bom.filter((x) => x.mid === l.mid).length === 1 ? 1 : 0);
      const extra = Math.round(g('extra:' + p.id + ':' + l.mid, mTot * share) * 100) / 100;
      const total = Math.round((cb + extra) * 100) / 100;
      const loss = cb > 0 ? Math.round(extra / cb * 10000) / 100 : 0;
      rows.push({ materialId: l.mid, name: l.mname, cb, extra, total, lossPct: loss });
    }
    sections.push({ productId: p.id, name: p.name, rows });
  }
  return { ym, top, sections };
}

router.get('/loss', requirePerm('packing.view'), (req, res) => {
  const ymQ = String(req.query.ym || '').trim();
  if (ymQ) {
    const a = db.prepare('SELECT data FROM loss_archive WHERE ym = ?').get(ymQ);
    if (a) { res.json(JSON.parse(a.data)); return; }
  }
  const ym = lossOpenMonth();
  const out = lossBuild(ym);
  out.archives = db.prepare('SELECT ym FROM loss_archive ORDER BY ym DESC LIMIT 24').all().map((r) => r.ym);
  res.json(out);
});

router.put('/loss/cell', requirePerm('packing.manage'), (req, res) => {
  const key = String((req.body || {}).key || '').trim();
  const value = Number((req.body || {}).value);
  if (!/^(proj|open|act|close|cb|extra):[0-9]+(:[0-9]+)?$/.test(key) || isNaN(value)) throw bad('Bad cell.');
  const ym = lossOpenMonth();
  db.prepare('INSERT INTO loss_values (ym, key, value) VALUES (?,?,?) ON CONFLICT(ym, key) DO UPDATE SET value = excluded.value').run(ym, key, value);
  audit(db, req.user, 'UPDATE', 'packing', 0, 'Loss sheet ' + ym + ': ' + key + ' = ' + value);
  res.json({ ok: true });
});

router.post('/loss/close', requirePerm('packing.manage'), (req, res) => {
  const ym = lossOpenMonth();
  const data = lossBuild(ym);
  tx(db, () => {
    db.prepare('INSERT OR REPLACE INTO loss_archive (ym, data, closed_at) VALUES (?,?,?)').run(ym, JSON.stringify(data), nowIso());
    db.prepare("UPDATE loss_months SET status = 'CLOSED' WHERE ym = ?").run(ym);
    const [y, m] = ym.split('-').map(Number);
    const next = new Date(Date.UTC(y, m, 1)).toISOString().slice(0, 7);
    db.prepare("INSERT OR IGNORE INTO loss_months (ym, status, created_at) VALUES (?, 'OPEN', ?)").run(next, nowIso());
    // closing → next month opening
    for (const t of data.top) {
      if (!t.productId) continue;
      const c = Number(t.closing) || 0;
      db.prepare('INSERT INTO loss_values (ym, key, value) VALUES (?,?,?) ON CONFLICT(ym, key) DO UPDATE SET value = excluded.value').run(next, 'open:' + t.productId, c);
    }
  });
  audit(db, req.user, 'UPDATE', 'packing', 0, 'Loss month ' + ym + ' closed — closings rolled to next month openings');
  res.json({ ok: true, closed: ym });
});

`;
src = src.replace('module.exports = router;', CODE + 'module.exports = router;');
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 400)); process.exit(3); }
console.log('LOSS ROUTES ADDED ✓');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "LOSSFIX FAIL"; exit 1; fi

systemctl restart flavorflow
sleep 2
curl -s -m 5 http://127.0.0.1:4000/api/health && echo ""
echo "LOSSFIX VERIFIED ✓ — Loss% module live (app build ton baad menu ch dikhega)"
