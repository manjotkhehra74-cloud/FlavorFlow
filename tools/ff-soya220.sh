#!/usr/bin/env bash
# FlavorFlow DATA FIX — Dark Soya 220 di packing BOM (factory VM · data-only · NO restart)
#
#   Dark Soya 220 ohi bottle/carton/cap… use karda hai jo (White) Vinegar 180 —
#   sirf 180 de LABEL te PLUG nahi: ohna di thaan CROWN CORK te DARK SOYA 220 LABEL.
#
#   Script ki karda hai:
#     1) products vich target ("…soya…220…") te source ("…vinegar…180…") labhda hai
#     2) source di BOM copy karda hai — label / sticker / plug wali lines chhad ke
#     3) Crown Cork line jodda hai  (qty = source de PLUG wali line; nahi ta bottles/CB)
#        Dark Soya 220 Label line   (qty = source de LABEL wali line; nahi ta bottles/CB)
#     4) target di purani BOM di thaan navi BOM likhda hai (transaction; DB backup pehlan)
#   Kuch vi ambiguous (2 products match, crown cork / label nahi labhda…) → STOP,
#   kuch nahi badalda, candidates print karda hai. Fer ID de ke dobara chalao:
#     FF_TARGET_ID / FF_SOURCE_ID / FF_CORK_ID / FF_LABEL_ID   (ya regex: FF_TARGET
#     FF_SOURCE FF_DROP FF_CORK FF_LABEL)
#   Idempotent — dobara chalao ta "already set ✓" (koi change nahi).
#
#   Uses the server's own db.js (like ff-packfix) — works with better-sqlite3 OR node:sqlite.
#   Factory VM (flavorflow.duckdns.org) te chalauna:
#     curl -s https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a0858b-flavorflow/tools/ff-soya220.sh | sudo bash
#   Override naal:
#     curl -s …/tools/ff-soya220.sh | sudo FF_SOURCE_ID=7 bash
set -u
echo "=== FF-SOYA220 $(date) ==="

# Server da apna db.js use karde haan (ohi jo ff-packfix / ff-lossfix ne kita) —
# eh better-sqlite3 hove ya node:sqlite, prepare/run/get/all/exec ikko jehe ne.
if [ -n "${FF_DIR:-}" ] && [ -f "$FF_DIR/db.js" ]; then DIR="$FF_DIR"
elif [ -f /opt/flavorflow/server/db.js ]; then DIR=/opt/flavorflow/server
else echo "FATAL: factory server (/opt/flavorflow/server/db.js) nahi labhya — eh script FACTORY VM (flavorflow.duckdns.org) te chalao"; exit 1
fi
cd "$DIR" || exit 1
BK="${FF_BACKUP_DIR:-/opt/flavorflow/backups}"
[ -n "${FF_DIR:-}" ] && BK="${FF_BACKUP_DIR:-$DIR/backups}"
mkdir -p "$BK" 2>/dev/null
echo "SERVER: $DIR"

export FF_BKDIR="$BK" FF_TS="$(date +%s)"
node - <<'JS'
const fs = require('fs');
let mod = require(process.cwd() + '/db');
let db = mod && typeof mod.prepare === 'function' ? mod : (mod && (mod.db || mod.default));
if (!db || typeof db.prepare !== 'function') {
  console.log('FATAL: db.js ne DB handle export nahi kita (keys: ' + Object.keys(mod || {}).join(', ') + ') — mainu eh line bhejo');
  process.exit(1);
}
const BK = process.env.FF_BKDIR + '/erp.db.bak-soya220-' + process.env.FF_TS;

const rx = (env, def) => new RegExp(process.env[env] || def, 'i');
const RX = {
  target: rx('FF_TARGET', 'soya.*220|220.*soya'),
  source: rx('FF_SOURCE', 'vinegar.*180|180.*vinegar'),
  drop:   rx('FF_DROP',   'label|sticker|plug'),
  cork:   rx('FF_CORK',   'crown|cork'),
  label:  rx('FF_LABEL',  '(label|sticker).*(soya|dark|220)|(soya|dark|220).*(label|sticker)'),
};
// drop test — TRAY items (tray, tray cap) are never dropped unless the regex itself says "tray"
const isDrop = (name) => RX.drop.test(name) && !(/tray/i.test(name) && !/tray/i.test(RX.drop.source));
const idEnv = (k) => { const v = parseInt(process.env[k] || '', 10); return Number.isFinite(v) && v > 0 ? v : 0; };
const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0);
const fmt = (v) => (Math.round(num(v) * 1000) / 1000).toString();
const stop = (msg) => { console.log('STOP: ' + msg); console.log('STOP: kuch nahi badleya — upar wale candidates dekh ke FF_*_ID de ke dobara chalao'); process.exit(2); };

const cols = (t) => db.prepare('PRAGMA table_info(' + t + ')').all();
const pcols = cols('products').map((c) => c.name);
const bcols = cols('packing_bom');
for (const need of ['product_id', 'material_id', 'qty_per_cb', 'qty_per_tray']) {
  if (!bcols.some((c) => c.name === need)) stop('packing_bom vich column "' + need + '" nahi — schema vakhra hai, mainu dasso');
}
const extraReq = bcols.filter((c) => !['product_id', 'material_id', 'qty_per_cb', 'qty_per_tray'].includes(c.name) && c.notnull && c.dflt_value == null && !c.pk);
if (extraReq.length) stop('packing_bom vich hor NOT NULL columns ne (' + extraReq.map((c) => c.name).join(', ') + ') — mainu dasso');

const products = db.prepare('SELECT * FROM products').all()
  .filter((p) => !pcols.includes('active') || p.active == null || Number(p.active) === 1);
const materials = db.prepare('SELECT * FROM packing_materials').all();
const bomOf = (pid) => db.prepare('SELECT b.material_id, b.qty_per_cb, b.qty_per_tray, m.name mname, m.unit, m.stock, m.category FROM packing_bom b JOIN packing_materials m ON m.id = b.material_id WHERE b.product_id = ? ORDER BY m.name').all(pid);
const show = (rows) => {
  if (!rows.length) { console.log('      (koi line nahi)'); return; }
  const w = Math.max(...rows.map((r) => r.mname.length), 8);
  console.log('      ' + 'MATERIAL'.padEnd(w) + '  PER CB   PER TRAY  UNIT   STOCK');
  for (const r of rows) console.log('      ' + r.mname.padEnd(w) + '  ' + fmt(r.qty_per_cb).padStart(6) + '   ' + fmt(r.qty_per_tray).padStart(8) + '  ' + String(r.unit || '').padEnd(5) + '  ' + fmt(r.stock));
};
const list = (arr, f) => arr.forEach((x) => console.log('      #' + x.id + '  ' + x.name + (f ? f(x) : '')));

// ---------- pick helper: id override → exact; else regex (+ preference) ----------
function pick(kind, arr, idKey, re, prefer) {
  const id = idEnv(idKey);
  if (id) { const x = arr.find((a) => a.id === id); if (!x) stop(idKey + '=' + id + ' nahi labhya'); return [x]; }
  let c = arr.filter((a) => re.test(String(a.name || '')));
  if (c.length > 1 && prefer) { const p = c.filter((a) => prefer.test(a.name)); if (p.length) c = p; }
  return c;
}

// ---------- 1) target product ----------
let tc = pick('target', products, 'FF_TARGET_ID', RX.target, /dark/i);
if (tc.length === 0) { console.log('TARGET: koi product "' + RX.target.source + '" naal match nahi — products:'); list(products); stop('target product nahi labhya (FF_TARGET_ID=<id> de ke chalao)'); }
if (tc.length > 1) { console.log('TARGET: ' + tc.length + ' products match:'); list(tc); stop('target ambiguous (FF_TARGET_ID=<id>)'); }
const target = tc[0];
console.log('TARGET: #' + target.id + ' ' + target.name + ' (' + fmt(target.bottles_per_cb) + '/CB' + (num(target.bottles_per_tray) > 0 ? ', ' + fmt(target.bottles_per_tray) + '/tray' : '') + ')');

// ---------- 2) source product ----------
let sc = pick('source', products, 'FF_SOURCE_ID', RX.source, null).filter((p) => p.id !== target.id);
if (sc.length === 0) { console.log('SOURCE: koi product "' + RX.source.source + '" naal match nahi — products:'); list(products); stop('source product nahi labhya (FF_SOURCE_ID=<id>)'); }
const keptKey = (pid) => bomOf(pid).filter((l) => !isDrop(l.mname)).map((l) => l.material_id + ':' + fmt(l.qty_per_cb) + ':' + fmt(l.qty_per_tray)).sort().join('|');
if (sc.length > 1) {
  const keys = new Set(sc.map((p) => keptKey(p.id)));
  if (keys.size === 1) {
    console.log('SOURCE: ' + sc.length + ' products match (' + sc.map((p) => p.name).join(' / ') + ') — labels/plugs chhad ke BOM ikko hai → pehla lai leya');
    sc = [sc[0]];
  } else {
    console.log('SOURCE: ' + sc.length + ' products match te ohna di BOM (labels/plugs ton bina) VAKHRI hai:');
    for (const p of sc) { console.log('   #' + p.id + ' ' + p.name); show(bomOf(p.id)); }
    stop('source ambiguous — dasso kehda: FF_SOURCE_ID=<id>');
  }
}
const source = sc[0];
const srcBom = bomOf(source.id);
console.log('SOURCE: #' + source.id + ' ' + source.name + ' (' + fmt(source.bottles_per_cb) + '/CB) — ' + srcBom.length + ' BOM lines');
if (!srcBom.length) stop('source di BOM khali hai — copy karan nu kuch nahi');
if (num(target.bottles_per_cb) > 0 && num(source.bottles_per_cb) > 0 && num(target.bottles_per_cb) !== num(source.bottles_per_cb)) {
  console.log('WARN: bottles/CB vakhre ne — target ' + fmt(target.bottles_per_cb) + ' vs source ' + fmt(source.bottles_per_cb) + '. Per-CB qty source wali copy ho rahi hai (check kar lena; Products vich target da bottles/CB theek karo je galat hai)');
}

// ---------- 3) crown cork + dark soya label materials ----------
let cc = pick('cork', materials, 'FF_CORK_ID', RX.cork, /220|soya|dark/i);
if (cc.length === 0) {
  console.log('CORK: koi material "' + RX.cork.source + '" naal match nahi. Milde-julde materials:');
  list(materials.filter((m) => /crown|cork|cap|closure/i.test(m.name)), (m) => '  [' + m.category + ']');
  stop('Crown Cork material nahi labhya — pehla Packing Material vich add karo, ya FF_CORK_ID=<id>');
}
if (cc.length > 1) { console.log('CORK: ' + cc.length + ' materials match:'); list(cc, (m) => '  [' + m.category + ']'); stop('crown cork ambiguous (FF_CORK_ID=<id>)'); }
const cork = cc[0];
let lc = pick('label', materials, 'FF_LABEL_ID', RX.label, /220/);
if (lc.length === 0) {
  console.log('LABEL: koi material "' + RX.label.source + '" naal match nahi. Label materials:');
  list(materials.filter((m) => /label|sticker/i.test(m.name)), (m) => '  [' + m.category + ']');
  stop('Dark Soya 220 label material nahi labhya — pehla Packing Material vich add karo, ya FF_LABEL_ID=<id>');
}
if (lc.length > 1) { console.log('LABEL: ' + lc.length + ' materials match:'); list(lc, (m) => '  [' + m.category + ']'); stop('label ambiguous (FF_LABEL_ID=<id>)'); }
const label = lc[0];
console.log('ADD: crown cork  = #' + cork.id + ' ' + cork.name + ' [' + cork.category + ']');
console.log('ADD: soya label  = #' + label.id + ' ' + label.name + ' [' + label.category + ']');

// ---------- 4) build the new BOM ----------
const keep = srcBom.filter((l) => !isDrop(l.mname));
const dropped = srcBom.filter((l) => isDrop(l.mname));
const maxQ = (rows) => rows.length ? { cb: Math.max(...rows.map((r) => num(r.qty_per_cb))), tray: Math.max(...rows.map((r) => num(r.qty_per_tray))) } : null;
const labelQ = maxQ(dropped.filter((l) => /label|sticker/i.test(l.mname)));
const plugQ = maxQ(dropped.filter((l) => /plug|cap|closure|lid|stopper/i.test(l.mname)));
const perBottle = { cb: num(target.bottles_per_cb) || num(source.bottles_per_cb), tray: num(target.bottles_per_tray) || 0 };
const corkQ = plugQ || perBottle;
const lblQ = labelQ || perBottle;
console.log('COPY: ' + keep.length + ' line(s) source ton: ' + keep.map((l) => l.mname).join(', '));
const susp = keep.filter((l) => /\b(cap|caps|closure|lid|stopper|ropp)\b/i.test(l.mname) && !/tray/i.test(l.mname) && l.material_id !== cork.id);
if (susp.length) console.log('WARN: eh line(s) vi copy ho rahiyan ne: ' + susp.map((l) => l.mname).join(', ') + ' — je eh 180 da plug/cap hai (crown cork di thaan) ta FF_DROP="label|sticker|plug|cap" naal dobara chalao');
console.log('DROP: ' + (dropped.length ? dropped.map((l) => l.mname).join(', ') : '(source vich koi label/plug line nahi si)'));
console.log('QTY : crown cork ' + fmt(corkQ.cb) + '/CB' + (corkQ.tray ? ' ' + fmt(corkQ.tray) + '/tray' : '') + (plugQ ? ' (180 de plug/cap wali line ton)' : ' (bottles/CB ton — source vich plug line nahi)')
  + ' · soya label ' + fmt(lblQ.cb) + '/CB' + (lblQ.tray ? ' ' + fmt(lblQ.tray) + '/tray' : '') + (labelQ ? ' (180 label wali line ton)' : ' (bottles/CB ton)'));

const desired = new Map();
for (const l of keep) desired.set(l.material_id, { cb: num(l.qty_per_cb), tray: num(l.qty_per_tray) });
desired.set(cork.id, { cb: corkQ.cb, tray: corkQ.tray });
desired.set(label.id, { cb: lblQ.cb, tray: lblQ.tray });
if (![...desired.values()].some((q) => q.cb > 0 || q.tray > 0)) stop('navi BOM di saari qty 0 hai — kuch galat hai');

const before = bomOf(target.id);
const same = before.length === desired.size && before.every((l) => { const d = desired.get(l.material_id); return d && fmt(d.cb) === fmt(l.qty_per_cb) && fmt(d.tray) === fmt(l.qty_per_tray); });
if (same) { console.log('BOM: ' + target.name + ' di BOM pehla hi eho hai — already set ✓ (koi change nahi)'); show(before); console.log('SOYA220 DONE ✓'); process.exit(0); }

console.log('BEFORE: ' + target.name + ' di purani BOM (' + before.length + ' lines):');
show(before);

// backup: consistent snapshot (VACUUM INTO), fallback = file copy of the live DB
let backed = false;
try { db.exec("VACUUM INTO '" + BK.replace(/'/g, "''") + "'"); backed = true; } catch (_) {}
if (!backed) {
  try {
    const row = db.prepare('PRAGMA database_list').all().find((r) => r.name === 'main');
    const src = row && row.file ? row.file : 'data/erp.db';
    try { db.exec('PRAGMA wal_checkpoint(TRUNCATE)'); } catch (_) {}
    fs.copyFileSync(src, BK); backed = true;
  } catch (e) { console.log('FATAL: backup fail (' + e.message + ') — kuch nahi badleya'); process.exit(1); }
}
console.log('DB BACKUP: ' + BK);

const del = db.prepare('DELETE FROM packing_bom WHERE product_id = ?');
const ins = db.prepare('INSERT INTO packing_bom (product_id, material_id, qty_per_cb, qty_per_tray) VALUES (?, ?, ?, ?)');
db.exec('BEGIN');
try {
  del.run(target.id);
  for (const [mid, q] of desired) ins.run(target.id, mid, q.cb, q.tray);
  db.exec('COMMIT');
} catch (e) {
  try { db.exec('ROLLBACK'); } catch (_) {}
  console.log('FATAL: write fail — rolled back (' + e.message + ')'); process.exit(1);
}
const after = bomOf(target.id);
console.log('AFTER: ' + target.name + ' di navi BOM (' + after.length + ' lines):');
show(after);
console.log('SOYA220 DONE ✓ — ' + target.name + ' da batch complete karan te (Deduct packing ticked) eho material stock vicho katega');
JS
RC=$?
echo ""
if [ $RC -eq 0 ]; then
  echo "NOTE: service restart di LOD NAHI — data change turant live hai."
  echo "App: Packing Material → 'Packing per Product (BOM)' tab → Dark Soya 220 di list check karo."
  echo "Pehla complete kite batches (khali BOM naal) kuch consume nahi kar sake — ohna layi Packing → Consume (manual) kar lena."
elif [ $RC -eq 2 ]; then
  echo "Kuch nahi badleya. Upar STOP wali line parho te ID de ke dobara chalao, jiven:"
  echo "  curl -s https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a0858b-flavorflow/tools/ff-soya220.sh | sudo FF_SOURCE_ID=7 bash"
fi
exit $RC
