#!/usr/bin/env bash
# FlavorFlow ERP — SALES BILLING module (server side, every tenant + factory):
#   GST tax invoices, party (customer) master, receipts/outstanding, GST register.
#   1) routes/billing.js (new)  — /api/billing/* : settings, parties, products+rates,
#      invoices (create from dispatch or direct, cancel), payments, receivables,
#      summary, GSTR-1 style register (+CSV). Own tables, created at boot:
#      parties, invoices, invoice_items, invoice_payments, invoice_seq;
#      products += hsn_code / gst_rate / sale_rate / rate_per.
#   2) rbac.js — billing.view / billing.manage (mirrors dispatch perms) + NAV /billing
#   3) server.js — mount BEFORE the first /api mount (so the 404 catch-all never shadows it)
#   4) users with CUSTOM permission lists get billing.* backfilled from dispatch.*
#   SaaS core te vi (sab tenants), factory server te vi (auto-detect). Idempotent.
#   curl -s https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a0858b-flavorflow/tools/ff-billing.sh | sudo bash
set -u
if [ -d /opt/flavorflow-saas/core ]; then DIR=/opt/flavorflow-saas/core; MODE=saas; SVC=flavorflow-saas;
elif [ -d /opt/flavorflow/server ]; then DIR=/opt/flavorflow/server; MODE=factory; SVC=flavorflow;
else echo "FATAL: koi server dir nahi labhi"; exit 1; fi
echo "=== FF-BILLING ($MODE) $(date) ==="
TS=$(date +%s)
mkdir -p "$DIR/routes"
for F in "$DIR/server.js" "$DIR/rbac.js"; do [ -f "$F" ] && cp -a "$F" "$F.bak-billing-$TS"; done
echo "BACKUPS ✓ (suffix -billing-$TS)"

# ---------- 1) rbac.js: permissions + nav ----------
export FF_DIR="$DIR"
PERM_MODE=$(node - <<'JS'
const fs = require('fs');
const f = process.env.FF_DIR + '/rbac.js';
if (!fs.existsSync(f)) { console.log('fallback'); process.exit(0); }
let src = fs.readFileSync(f, 'utf8');
let ok = true;
if (!src.includes("'billing.view'")) {
  const roleIdx = src.indexOf('const ROLE_PERMISSIONS');
  const navIdx = src.indexOf('const NAV_ITEMS');
  if (roleIdx === -1 || navIdx === -1 || navIdx < roleIdx) ok = false;
  else {
    let head = src.slice(0, roleIdx), mid = src.slice(roleIdx, navIdx); const tail = src.slice(navIdx);
    const h2 = head.replace(/'dispatch\.view',(\s*)'dispatch\.manage',/, "'dispatch.view',$1'dispatch.manage',$1'billing.view',$1'billing.manage',");
    if (h2 === head) ok = false; else head = h2;
    mid = mid.replace(/'dispatch\.view',(\s*'dispatch\.manage',)?/g, (m, mg) => mg ? "'dispatch.view', 'dispatch.manage', 'billing.view', 'billing.manage'," : "'dispatch.view', 'billing.view',");
    src = head + mid + tail;
  }
}
if (ok && !src.includes("path: '/billing'")) {
  const m = src.match(/[ \t]*\{ *path: *'\/dispatch'[^\n]*\n/);
  if (m) {
    const g = (m[0].match(/group:\s*'([^']+)'/) || [])[1] || 'Operations';
    src = src.replace(m[0], m[0] + "  { path: '/billing',     label: 'Billing',            icon: 'receipt_long',   perm: 'billing.view',        group: '" + g + "' },\n");
  }
}
if (ok) { fs.writeFileSync(f, src); try { require('child_process').execSync('node --check "' + f + '"'); console.log('billing'); } catch (e) { fs.copyFileSync(f + '.bak-billing-' + process.env.FF_TS, f); console.log('fallback'); } }
else console.log('fallback');
JS
)
export FF_TS="$TS"
if [ "$PERM_MODE" = "billing" ]; then echo "RBAC: billing.view/manage + NAV /billing ✓"; PV=billing.view; PM=billing.manage;
else echo "RBAC: pattern nahi labhya — routes dispatch.view/manage naal guard honge (menu app khud dikhaundi hai)"; PV=dispatch.view; PM=dispatch.manage; fi

# ---------- 2) routes/billing.js ----------
cat > "$DIR/routes/billing.js" <<'JSFILE'
/** FlavorFlow — Sales Billing: GST invoices, parties, receipts, GST register. (ff-billing) */
const express = require('express');
const router = express.Router();
const db = require('../db');
const MW = (() => { try { return require('../middleware'); } catch (_) { return {}; } })();
const H = (() => { try { return require('../helpers'); } catch (_) { return {}; } })();
const authRequired = typeof MW.authRequired === 'function' ? MW.authRequired : (req, res, next) => next();
const perm = (p) => (typeof MW.requirePerm === 'function' ? MW.requirePerm(p) : (req, res, next) => next());
const nowIso = typeof H.nowIso === 'function' ? H.nowIso : () => new Date().toISOString();
const audit = (...a) => { try { if (typeof H.audit === 'function') H.audit(...a); } catch (_) {} };
const PERM_VIEW = '__PV__', PERM_MANAGE = '__PM__';

// ---------- schema (per tenant, at boot) ----------
db.exec(`CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS parties (
  id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, gstin TEXT DEFAULT '', address TEXT DEFAULT '',
  state_code TEXT DEFAULT '', phone TEXT DEFAULT '', email TEXT DEFAULT '', credit_days INTEGER DEFAULT 0,
  active INTEGER DEFAULT 1, created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS invoice_seq (fy TEXT PRIMARY KEY, seq INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS invoices (
  id INTEGER PRIMARY KEY AUTOINCREMENT, number TEXT NOT NULL UNIQUE, fy TEXT NOT NULL, invoice_date TEXT NOT NULL,
  party_id INTEGER, party_name TEXT NOT NULL, party_gstin TEXT DEFAULT '', party_address TEXT DEFAULT '', party_state_code TEXT DEFAULT '',
  place_of_supply TEXT DEFAULT '', supply_type TEXT NOT NULL DEFAULT 'intra', dispatch_id INTEGER, dispatch_code TEXT DEFAULT '',
  subtotal REAL NOT NULL DEFAULT 0, discount REAL NOT NULL DEFAULT 0, taxable REAL NOT NULL DEFAULT 0,
  cgst REAL NOT NULL DEFAULT 0, sgst REAL NOT NULL DEFAULT 0, igst REAL NOT NULL DEFAULT 0, round_off REAL NOT NULL DEFAULT 0,
  total REAL NOT NULL DEFAULT 0, paid_amount REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'ISSUED',
  due_date TEXT DEFAULT '', remarks TEXT DEFAULT '', stock_deducted INTEGER DEFAULT 0,
  created_by INTEGER, created_by_name TEXT DEFAULT '', created_at TEXT NOT NULL, cancelled_at TEXT, cancel_reason TEXT DEFAULT '');
CREATE TABLE IF NOT EXISTS invoice_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_id INTEGER NOT NULL, product_id INTEGER, description TEXT NOT NULL,
  hsn_code TEXT DEFAULT '', qty REAL NOT NULL, unit TEXT DEFAULT '', pieces_per_pack REAL DEFAULT 1, rate_per TEXT DEFAULT 'pack',
  rate REAL NOT NULL, discount_pct REAL DEFAULT 0, gross REAL NOT NULL, discount_amt REAL DEFAULT 0, taxable REAL NOT NULL,
  gst_rate REAL DEFAULT 0, cgst REAL DEFAULT 0, sgst REAL DEFAULT 0, igst REAL DEFAULT 0, total REAL NOT NULL, batch_code TEXT DEFAULT '');
CREATE TABLE IF NOT EXISTS invoice_payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_id INTEGER NOT NULL, amount REAL NOT NULL, mode TEXT NOT NULL DEFAULT 'cash',
  ref_no TEXT DEFAULT '', bank TEXT DEFAULT '', paid_on TEXT NOT NULL, note TEXT DEFAULT '', created_by INTEGER, created_by_name TEXT DEFAULT '', created_at TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS idx_inv_date ON invoices(invoice_date);
CREATE INDEX IF NOT EXISTS idx_inv_party ON invoices(party_id);
CREATE INDEX IF NOT EXISTS idx_invitem_inv ON invoice_items(invoice_id);
CREATE INDEX IF NOT EXISTS idx_invpay_inv ON invoice_payments(invoice_id);`);
for (const [c, t] of [['hsn_code', 'TEXT'], ['gst_rate', 'REAL'], ['sale_rate', 'REAL'], ['rate_per', 'TEXT']]) {
  try { db.exec('ALTER TABLE products ADD COLUMN ' + c + ' ' + t); } catch (_) {}
}

// ---------- helpers ----------
const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const str = (v, max) => String(v == null ? '' : v).trim().slice(0, max || 200);
const bad = (res, msg, code) => res.status(code || 400).json({ error: msg });
const todayIst = () => new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10);
const isYmd = (s) => /^\d{4}-\d{2}-\d{2}$/.test(String(s || ''));
const fyOf = (ymd) => { const y = Number(ymd.slice(0, 4)), m = Number(ymd.slice(5, 7)); const a = m >= 4 ? y : y - 1; return String(a).slice(2) + '-' + String(a + 1).slice(2); };
const getSet = (k) => { try { return JSON.parse((db.prepare('SELECT value FROM app_settings WHERE key = ?').get(k) || {}).value || '{}'); } catch (_) { return {}; } };
const putSet = (k, v) => db.prepare('INSERT INTO app_settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value').run(k, JSON.stringify(v));
const runTx = (fn) => (typeof db.transaction === 'function' ? db.transaction(fn)() : fn());
const GSTIN_RE = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
// GST 2.0 (22 Sep 2025) slabs 0/5/18/40 — typical slab per industry of the company
// (packaged food, dairy, edible oil, bakery, water, soap, cosmetics(most), pharma, textile
// and footwear <= Rs 2,500 sit at 5%; paints, agro-chemicals, plastics, hardware at 18%).
const INDUSTRY_GST = { food: 5, dairy: 5, oil: 5, bakery: 5, water: 5, soap: 5, cosmetics: 5, pharma: 5, textile: 5, mill: 5, footwear: 5, paint: 18, agro: 18, plastic: 18, hardware: 18, general: 18 };
const industryGst = () => { const c = getSet('company'); const k = c && c.industry ? String(c.industry) : ''; return INDUSTRY_GST[k] == null ? 5 : INDUSTRY_GST[k]; };
const defaults = () => ({ prefix: 'INV', gstin: '', stateCode: '', legalName: '', address: '', phone: '', email: '',
  bankName: '', accountNo: '', ifsc: '', upiId: '', terms: 'Goods once sold will not be taken back. Interest @18% p.a. on overdue bills. Subject to local jurisdiction.',
  defaultGstRate: industryGst(), roundOff: true, creditDays: 0 });
const settings = () => Object.assign(defaults(), getSet('billing'));
const companyStateCode = (s) => (s.stateCode && /^\d{2}$/.test(s.stateCode)) ? s.stateCode : (GSTIN_RE.test(s.gstin || '') ? s.gstin.slice(0, 2) : '');
const userName = (req) => (req.user && (req.user.name || req.user.email)) || '';
const userId = (req) => (req.user && req.user.id) || null;

function calc(lines, intra, roundOff) {
  let subtotal = 0, discount = 0, taxable = 0, cgst = 0, sgst = 0, igst = 0;
  const items = lines.map((l) => {
    const qty = num(l.qty), rate = num(l.rate), disc = Math.min(100, Math.max(0, num(l.discountPct))), g = Math.max(0, num(l.gstRate));
    const ppp = Math.max(1, num(l.piecesPerPack) || 1);
    const units = l.ratePer === 'piece' ? qty * ppp : qty;
    const gross = r2(units * rate);
    const dAmt = r2(gross * disc / 100);
    const tx = r2(gross - dAmt);
    const tax = r2(tx * g / 100);
    const c = intra ? r2(tax / 2) : 0, s = intra ? r2(tax - c) : 0, i = intra ? 0 : tax;
    subtotal += gross; discount += dAmt; taxable += tx; cgst += c; sgst += s; igst += i;
    return Object.assign({}, l, { qty, rate, discountPct: disc, gstRate: g, piecesPerPack: ppp, gross, discountAmt: dAmt, taxable: tx, cgst: c, sgst: s, igst: i, total: r2(tx + tax) });
  });
  const raw = r2(taxable + cgst + sgst + igst);
  const total = roundOff ? Math.round(raw) : raw;
  return { items, subtotal: r2(subtotal), discount: r2(discount), taxable: r2(taxable), cgst: r2(cgst), sgst: r2(sgst), igst: r2(igst), roundOff: r2(total - raw), total: r2(total) };
}
function nextNumber(dateYmd, prefix) {
  const fy = fyOf(dateYmd);
  const row = db.prepare('SELECT seq FROM invoice_seq WHERE fy = ?').get(fy);
  const seq = (row ? row.seq : 0) + 1;
  return { fy, seq, number: (prefix || 'INV') + '/' + fy + '/' + String(seq).padStart(4, '0') };
}
function productRows() {
  const sqlA = 'SELECT p.id, p.name, p.bottles_per_cb, p.weight_per_cb, p.hsn_code, p.gst_rate, p.sale_rate, p.rate_per, COALESCE(i.qty_cb, 0) qty_cb FROM products p LEFT JOIN inventory i ON i.product_id = p.id WHERE COALESCE(p.active, 1) = 1 ORDER BY p.name';
  const sqlB = 'SELECT p.id, p.name, p.bottles_per_cb, p.weight_per_cb, p.hsn_code, p.gst_rate, p.sale_rate, p.rate_per, COALESCE(i.qty_cb, 0) qty_cb FROM products p LEFT JOIN inventory i ON i.product_id = p.id ORDER BY p.name';
  try { return db.prepare(sqlA).all(); } catch (_) { return db.prepare(sqlB).all(); }
}
function invoiceStatus(inv) {
  if (inv.status === 'CANCELLED') return 'CANCELLED';
  if (inv.paid_amount >= inv.total - 0.005) return 'PAID';
  if (inv.paid_amount > 0) return 'PARTIAL';
  return 'ISSUED';
}
function adjustStock(items, sign) { // sign -1 = deduct, +1 = restore (packs)
  for (const it of items) {
    if (!it.product_id && !it.productId) continue;
    const pid = it.product_id || it.productId, q = num(it.qty) * sign;
    const inv = db.prepare('SELECT product_id FROM inventory WHERE product_id = ?').get(pid);
    if (inv) db.prepare('UPDATE inventory SET qty_cb = qty_cb + ? WHERE product_id = ?').run(q, pid);
    else { try { db.prepare('INSERT INTO inventory (product_id, qty_cb, qty_trays) VALUES (?,?,0)').run(pid, q); } catch (_) {} }
    const code = str(it.batch_code || it.batchCode, 40);
    if (code) {
      try {
        const b = db.prepare('SELECT id FROM batches WHERE code = ? AND product_id = ? ORDER BY id DESC LIMIT 1').get(code, pid);
        if (b) db.prepare('UPDATE batches SET used_cb = COALESCE(used_cb, 0) - ? WHERE id = ?').run(q, b.id);
      } catch (_) {}
    }
  }
}

router.use(express.json({ limit: '400kb' }));
router.use(authRequired);

// ---------- settings ----------
router.get('/settings', perm(PERM_VIEW), (req, res) => {
  const s = settings();
  res.json({ billing: s, company: getSet('company'), stateCode: companyStateCode(s) });
});
router.put('/settings', perm(PERM_MANAGE), (req, res) => {
  const b = req.body || {}, prev = settings();
  const gstin = str(b.gstin, 15).toUpperCase();
  if (gstin && !GSTIN_RE.test(gstin)) return bad(res, 'GSTIN format is invalid (15 characters, e.g. 03ABCDE1234F1Z5).');
  const v = {
    prefix: (str(b.prefix, 8).toUpperCase().replace(/[^A-Z0-9-]/g, '') || prev.prefix || 'INV'),
    gstin, stateCode: str(b.stateCode, 2) || (gstin ? gstin.slice(0, 2) : ''),
    legalName: str(b.legalName, 120), address: str(b.address, 300), phone: str(b.phone, 20), email: str(b.email, 80),
    bankName: str(b.bankName, 80), accountNo: str(b.accountNo, 30), ifsc: str(b.ifsc, 11).toUpperCase(), upiId: str(b.upiId, 60),
    terms: str(b.terms, 600), defaultGstRate: Math.max(0, num(b.defaultGstRate)), roundOff: b.roundOff !== false, creditDays: Math.max(0, Math.round(num(b.creditDays))),
  };
  putSet('billing', v);
  audit(db, req.user, 'UPDATE', 'billing', 0, 'Billing settings updated');
  res.json({ ok: true, billing: v });
});

// ---------- parties (customers) ----------
router.get('/parties', perm(PERM_VIEW), (req, res) => {
  const q = '%' + str(req.query.q, 60).toLowerCase() + '%';
  const all = req.query.all === '1';
  const rows = db.prepare('SELECT p.*, (SELECT COALESCE(SUM(total - paid_amount), 0) FROM invoices i WHERE i.party_id = p.id AND i.status != \'CANCELLED\') outstanding, (SELECT COUNT(*) FROM invoices i WHERE i.party_id = p.id AND i.status != \'CANCELLED\') invoices FROM parties p WHERE (? OR p.active = 1) AND (LOWER(p.name) LIKE ? OR LOWER(p.gstin) LIKE ? OR p.phone LIKE ?) ORDER BY p.name').all(all ? 1 : 0, q, q, q);
  res.json({ parties: rows.map((r) => Object.assign(r, { outstanding: r2(r.outstanding) })) });
});
function partyBody(b) {
  const gstin = str(b.gstin, 15).toUpperCase();
  return { name: str(b.name, 120), gstin, address: str(b.address, 300), state_code: str(b.stateCode, 2) || (gstin ? gstin.slice(0, 2) : ''), phone: str(b.phone, 20), email: str(b.email, 80), credit_days: Math.max(0, Math.round(num(b.creditDays))) };
}
router.post('/parties', perm(PERM_MANAGE), (req, res) => {
  const p = partyBody(req.body || {});
  if (p.name.length < 2) return bad(res, 'Party name is required.');
  if (p.gstin && !GSTIN_RE.test(p.gstin)) return bad(res, 'GSTIN format is invalid.');
  const dup = db.prepare('SELECT id FROM parties WHERE LOWER(name) = LOWER(?) AND active = 1').get(p.name);
  if (dup) return bad(res, 'A party with this name already exists.');
  const r = db.prepare('INSERT INTO parties (name, gstin, address, state_code, phone, email, credit_days, active, created_at) VALUES (?,?,?,?,?,?,?,1,?)').run(p.name, p.gstin, p.address, p.state_code, p.phone, p.email, p.credit_days, nowIso());
  audit(db, req.user, 'CREATE', 'billing', Number(r.lastInsertRowid), 'Party "' + p.name + '" added');
  res.status(201).json({ ok: true, id: Number(r.lastInsertRowid) });
});
router.put('/parties/:id', perm(PERM_MANAGE), (req, res) => {
  const id = Number(req.params.id), p = partyBody(req.body || {});
  if (!db.prepare('SELECT id FROM parties WHERE id = ?').get(id)) return bad(res, 'Party not found.', 404);
  if (p.name.length < 2) return bad(res, 'Party name is required.');
  if (p.gstin && !GSTIN_RE.test(p.gstin)) return bad(res, 'GSTIN format is invalid.');
  db.prepare('UPDATE parties SET name = ?, gstin = ?, address = ?, state_code = ?, phone = ?, email = ?, credit_days = ?, active = 1 WHERE id = ?').run(p.name, p.gstin, p.address, p.state_code, p.phone, p.email, p.credit_days, id);
  audit(db, req.user, 'UPDATE', 'billing', id, 'Party "' + p.name + '" updated');
  res.json({ ok: true });
});
router.delete('/parties/:id', perm(PERM_MANAGE), (req, res) => {
  const id = Number(req.params.id);
  const p = db.prepare('SELECT * FROM parties WHERE id = ?').get(id);
  if (!p) return bad(res, 'Party not found.', 404);
  db.prepare('UPDATE parties SET active = 0 WHERE id = ?').run(id);
  audit(db, req.user, 'DELETE', 'billing', id, 'Party "' + p.name + '" removed');
  res.json({ ok: true });
});

// ---------- products: billing fields ----------
router.get('/products', perm(PERM_VIEW), (req, res) => { res.json({ products: productRows() }); });
router.put('/products/:id/rates', perm(PERM_MANAGE), (req, res) => {
  const id = Number(req.params.id), b = req.body || {};
  if (!db.prepare('SELECT id FROM products WHERE id = ?').get(id)) return bad(res, 'Product not found.', 404);
  const ratePer = b.ratePer === 'piece' ? 'piece' : 'pack';
  db.prepare('UPDATE products SET hsn_code = ?, gst_rate = ?, sale_rate = ?, rate_per = ? WHERE id = ?')
    .run(str(b.hsnCode, 8).replace(/[^0-9]/g, ''), Math.max(0, num(b.gstRate)), Math.max(0, num(b.saleRate)), ratePer, id);
  res.json({ ok: true });
});

// ---------- invoice helpers for the form ----------
router.get('/next-number', perm(PERM_VIEW), (req, res) => {
  const d = isYmd(req.query.date) ? String(req.query.date) : todayIst();
  res.json(nextNumber(d, settings().prefix));
});
router.get('/from-dispatch/:id', perm(PERM_VIEW), (req, res) => {
  const id = Number(req.params.id);
  const d = db.prepare('SELECT * FROM dispatches WHERE id = ?').get(id);
  if (!d) return bad(res, 'Dispatch not found.', 404);
  if (String(d.status || '').toUpperCase() === 'VOID') return bad(res, 'This dispatch is VOID — it cannot be invoiced.');
  const ex = db.prepare("SELECT id, number FROM invoices WHERE dispatch_id = ? AND status != 'CANCELLED'").get(id);
  const items = db.prepare('SELECT di.*, p.name product_name, p.bottles_per_cb, p.hsn_code, p.gst_rate, p.sale_rate, p.rate_per FROM dispatch_items di JOIN products p ON p.id = di.product_id WHERE di.dispatch_id = ?').all(id);
  const s = settings();
  res.json({
    dispatch: { id: d.id, code: d.code, date: d.dispatch_date, destination: d.destination, truck: d.truck_number },
    alreadyInvoiced: ex || null,
    lines: items.map((it) => ({
      productId: it.product_id, description: it.product_name, qty: num(it.cartons), batchCode: it.batch_code || '',
      piecesPerPack: num(it.bottles_per_cb) || 1, hsnCode: it.hsn_code || '', gstRate: it.gst_rate == null ? s.defaultGstRate : num(it.gst_rate),
      rate: num(it.sale_rate), ratePer: it.rate_per === 'piece' ? 'piece' : 'pack',
    })),
  });
});

// ---------- invoices ----------
router.get('/invoices', perm(PERM_VIEW), (req, res) => {
  const w = ["1=1"], a = [];
  if (isYmd(req.query.from)) { w.push('invoice_date >= ?'); a.push(String(req.query.from)); }
  if (isYmd(req.query.to)) { w.push('invoice_date <= ?'); a.push(String(req.query.to)); }
  if (req.query.partyId) { w.push('party_id = ?'); a.push(Number(req.query.partyId)); }
  if (req.query.status) { w.push('status = ?'); a.push(str(req.query.status, 12).toUpperCase()); }
  if (req.query.q) { const q = '%' + str(req.query.q, 60).toLowerCase() + '%'; w.push('(LOWER(number) LIKE ? OR LOWER(party_name) LIKE ? OR LOWER(dispatch_code) LIKE ?)'); a.push(q, q, q); }
  const rows = db.prepare('SELECT id, number, invoice_date, party_id, party_name, party_gstin, dispatch_id, dispatch_code, supply_type, taxable, cgst, sgst, igst, total, paid_amount, status, due_date, created_by_name, created_at FROM invoices WHERE ' + w.join(' AND ') + ' ORDER BY invoice_date DESC, id DESC LIMIT 500').all(...a);
  res.json({ invoices: rows.map((r) => Object.assign(r, { balance: r2(r.total - r.paid_amount) })) });
});
router.get('/invoices/:id', perm(PERM_VIEW), (req, res) => {
  const inv = db.prepare('SELECT * FROM invoices WHERE id = ?').get(Number(req.params.id));
  if (!inv) return bad(res, 'Invoice not found.', 404);
  const items = db.prepare('SELECT * FROM invoice_items WHERE invoice_id = ? ORDER BY id').all(inv.id);
  const payments = db.prepare('SELECT * FROM invoice_payments WHERE invoice_id = ? ORDER BY paid_on, id').all(inv.id);
  res.json({ invoice: Object.assign(inv, { balance: r2(inv.total - inv.paid_amount) }), items, payments, settings: settings(), company: getSet('company') });
});
router.post('/invoices', perm(PERM_MANAGE), (req, res) => {
  const b = req.body || {}, s = settings();
  const date = isYmd(b.invoiceDate) ? String(b.invoiceDate) : todayIst();
  const partyId = Number(b.partyId) || 0;
  const party = partyId ? db.prepare('SELECT * FROM parties WHERE id = ?').get(partyId) : null;
  const pName = party ? party.name : str(b.partyName, 120);
  if (!pName) return bad(res, 'Select a party (customer) or type a name.');
  const pGstin = party ? party.gstin : str(b.partyGstin, 15).toUpperCase();
  const pAddr = party ? party.address : str(b.partyAddress, 300);
  const myState = companyStateCode(s);
  const pos = str(b.placeOfSupply, 2) || (party ? party.state_code : '') || (pGstin ? pGstin.slice(0, 2) : '') || myState;
  const intra = !myState || !pos || myState === pos;
  const rawLines = Array.isArray(b.items) ? b.items : [];
  if (!rawLines.length) return bad(res, 'Add at least one item.');
  const prods = {}; for (const p of productRows()) prods[p.id] = p;
  const lines = [];
  for (const l of rawLines) {
    const pid = Number(l.productId) || 0, p = prods[pid];
    const qty = num(l.qty);
    if (qty <= 0) continue;
    const rate = num(l.rate);
    if (rate < 0) return bad(res, 'Rate cannot be negative.');
    lines.push({
      productId: p ? p.id : null, description: str(l.description, 160) || (p ? p.name : ''), hsnCode: str(l.hsnCode, 8) || (p ? (p.hsn_code || '') : ''),
      qty, unit: str(l.unit, 12), piecesPerPack: num(l.piecesPerPack) || (p ? num(p.bottles_per_cb) : 1) || 1, ratePer: l.ratePer === 'piece' ? 'piece' : 'pack',
      rate, discountPct: num(l.discountPct), gstRate: l.gstRate == null || l.gstRate === '' ? (p && p.gst_rate != null ? num(p.gst_rate) : s.defaultGstRate) : num(l.gstRate),
      batchCode: str(l.batchCode, 40).toUpperCase(),
    });
    if (!lines[lines.length - 1].description) return bad(res, 'Item description is required.');
  }
  if (!lines.length) return bad(res, 'Every item needs a quantity above zero.');
  const dispatchId = Number(b.dispatchId) || 0;
  let dispatchCode = '';
  if (dispatchId) {
    const d = db.prepare('SELECT id, code, status FROM dispatches WHERE id = ?').get(dispatchId);
    if (!d) return bad(res, 'Dispatch not found.', 404);
    const ex = db.prepare("SELECT number FROM invoices WHERE dispatch_id = ? AND status != 'CANCELLED'").get(dispatchId);
    if (ex) return bad(res, 'Dispatch ' + d.code + ' is already invoiced (' + ex.number + '). Cancel that invoice first.');
    dispatchCode = d.code || '';
  }
  const deductStock = !dispatchId && b.deductStock === true;
  if (deductStock) {
    for (const l of lines) {
      if (!l.productId) continue;
      const inv = db.prepare('SELECT COALESCE(qty_cb, 0) qty_cb FROM inventory WHERE product_id = ?').get(l.productId);
      if (!inv || inv.qty_cb < l.qty) return bad(res, 'Not enough stock for ' + l.description + ' (in stock: ' + (inv ? inv.qty_cb : 0) + ').');
    }
  }
  const c = calc(lines, intra, s.roundOff !== false);
  const creditDays = party && party.credit_days ? party.credit_days : (s.creditDays || 0);
  const due = creditDays ? new Date(new Date(date + 'T00:00:00Z').getTime() + creditDays * 864e5).toISOString().slice(0, 10) : date;
  const out = runTx(() => {
    const n = nextNumber(date, s.prefix);
    db.prepare('INSERT INTO invoice_seq (fy, seq) VALUES (?, ?) ON CONFLICT(fy) DO UPDATE SET seq = excluded.seq').run(n.fy, n.seq);
    const r = db.prepare(`INSERT INTO invoices (number, fy, invoice_date, party_id, party_name, party_gstin, party_address, party_state_code, place_of_supply, supply_type,
      dispatch_id, dispatch_code, subtotal, discount, taxable, cgst, sgst, igst, round_off, total, paid_amount, status, due_date, remarks, stock_deducted, created_by, created_by_name, created_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,'ISSUED',?,?,?,?,?,?)`)
      .run(n.number, n.fy, date, party ? party.id : null, pName, pGstin, pAddr, party ? party.state_code : (pGstin ? pGstin.slice(0, 2) : ''), pos, intra ? 'intra' : 'inter',
        dispatchId || null, dispatchCode, c.subtotal, c.discount, c.taxable, c.cgst, c.sgst, c.igst, c.roundOff, c.total, due, str(b.remarks, 300), deductStock ? 1 : 0, userId(req), userName(req), nowIso());
    const id = Number(r.lastInsertRowid);
    const ins = db.prepare(`INSERT INTO invoice_items (invoice_id, product_id, description, hsn_code, qty, unit, pieces_per_pack, rate_per, rate, discount_pct, gross, discount_amt, taxable, gst_rate, cgst, sgst, igst, total, batch_code)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`);
    for (const it of c.items) ins.run(id, it.productId, it.description, it.hsnCode, it.qty, it.unit, it.piecesPerPack, it.ratePer, it.rate, it.discountPct, it.gross, it.discountAmt, it.taxable, it.gstRate, it.cgst, it.sgst, it.igst, it.total, it.batchCode);
    if (deductStock) adjustStock(c.items, -1);
    audit(db, req.user, 'CREATE', 'billing', id, 'Invoice ' + n.number + ' → ' + pName + ' ₹' + c.total + (dispatchCode ? ' (dispatch ' + dispatchCode + ')' : ''));
    return { id, number: n.number };
  });
  res.status(201).json({ ok: true, id: out.id, number: out.number, total: c.total, supplyType: intra ? 'intra' : 'inter' });
});
router.post('/invoices/:id/cancel', perm(PERM_MANAGE), (req, res) => {
  const inv = db.prepare('SELECT * FROM invoices WHERE id = ?').get(Number(req.params.id));
  if (!inv) return bad(res, 'Invoice not found.', 404);
  if (inv.status === 'CANCELLED') return bad(res, 'Already cancelled.');
  if (inv.paid_amount > 0) return bad(res, 'Receipts are recorded against this invoice — delete them first.');
  const items = db.prepare('SELECT * FROM invoice_items WHERE invoice_id = ?').all(inv.id);
  runTx(() => {
    db.prepare("UPDATE invoices SET status = 'CANCELLED', cancelled_at = ?, cancel_reason = ? WHERE id = ?").run(nowIso(), str((req.body || {}).reason, 200), inv.id);
    if (inv.stock_deducted) adjustStock(items, +1);
  });
  audit(db, req.user, 'CANCEL', 'billing', inv.id, 'Invoice ' + inv.number + ' cancelled' + (inv.stock_deducted ? ' (stock restored)' : ''));
  res.json({ ok: true });
});

// ---------- receipts ----------
router.post('/invoices/:id/payments', perm(PERM_MANAGE), (req, res) => {
  const inv = db.prepare('SELECT * FROM invoices WHERE id = ?').get(Number(req.params.id));
  if (!inv) return bad(res, 'Invoice not found.', 404);
  if (inv.status === 'CANCELLED') return bad(res, 'Invoice is cancelled.');
  const b = req.body || {}, amount = r2(num(b.amount));
  if (amount <= 0) return bad(res, 'Amount must be above zero.');
  const balance = r2(inv.total - inv.paid_amount);
  if (amount > balance + 0.5) return bad(res, 'Amount exceeds the balance (₹' + balance + ').');
  const mode = ['cash', 'cheque', 'neft', 'rtgs', 'upi', 'card', 'other'].includes(String(b.mode || '').toLowerCase()) ? String(b.mode).toLowerCase() : 'cash';
  const paidOn = isYmd(b.paidOn) ? String(b.paidOn) : todayIst();
  const out = runTx(() => {
    const r = db.prepare('INSERT INTO invoice_payments (invoice_id, amount, mode, ref_no, bank, paid_on, note, created_by, created_by_name, created_at) VALUES (?,?,?,?,?,?,?,?,?,?)')
      .run(inv.id, amount, mode, str(b.refNo, 40), str(b.bank, 60), paidOn, str(b.note, 200), userId(req), userName(req), nowIso());
    const paid = r2(inv.paid_amount + amount);
    const st = invoiceStatus(Object.assign({}, inv, { paid_amount: paid }));
    db.prepare('UPDATE invoices SET paid_amount = ?, status = ? WHERE id = ?').run(paid, st, inv.id);
    return { id: Number(r.lastInsertRowid), paid, status: st };
  });
  audit(db, req.user, 'RECEIPT', 'billing', inv.id, 'Receipt ₹' + amount + ' (' + mode + ') against ' + inv.number);
  res.status(201).json(Object.assign({ ok: true }, out));
});
router.delete('/invoices/:id/payments/:pid', perm(PERM_MANAGE), (req, res) => {
  const inv = db.prepare('SELECT * FROM invoices WHERE id = ?').get(Number(req.params.id));
  const p = inv && db.prepare('SELECT * FROM invoice_payments WHERE id = ? AND invoice_id = ?').get(Number(req.params.pid), inv.id);
  if (!inv || !p) return bad(res, 'Receipt not found.', 404);
  runTx(() => {
    db.prepare('DELETE FROM invoice_payments WHERE id = ?').run(p.id);
    const paid = r2(Math.max(0, inv.paid_amount - p.amount));
    db.prepare('UPDATE invoices SET paid_amount = ?, status = ? WHERE id = ?').run(paid, invoiceStatus(Object.assign({}, inv, { paid_amount: paid })), inv.id);
  });
  audit(db, req.user, 'DELETE', 'billing', inv.id, 'Receipt ₹' + p.amount + ' removed from ' + inv.number);
  res.json({ ok: true });
});
router.get('/receivables', perm(PERM_VIEW), (req, res) => {
  const today = todayIst();
  const rows = db.prepare("SELECT id, number, invoice_date, due_date, party_id, party_name, total, paid_amount, status FROM invoices WHERE status IN ('ISSUED','PARTIAL') ORDER BY invoice_date").all();
  const out = rows.map((r) => {
    const days = Math.floor((new Date(today + 'T00:00:00Z') - new Date(r.invoice_date + 'T00:00:00Z')) / 864e5);
    const overdue = r.due_date && r.due_date < today;
    return Object.assign(r, { balance: r2(r.total - r.paid_amount), days, overdue, bucket: days <= 30 ? '0-30' : days <= 60 ? '31-60' : days <= 90 ? '61-90' : '90+' });
  });
  const byParty = {};
  for (const r of out) { const k = r.party_name; byParty[k] = byParty[k] || { party: k, partyId: r.party_id, balance: 0, invoices: 0, oldest: r.invoice_date }; byParty[k].balance = r2(byParty[k].balance + r.balance); byParty[k].invoices++; }
  const buckets = { '0-30': 0, '31-60': 0, '61-90': 0, '90+': 0 };
  for (const r of out) buckets[r.bucket] = r2(buckets[r.bucket] + r.balance);
  res.json({ receivables: out, total: r2(out.reduce((s, r) => s + r.balance, 0)), byParty: Object.values(byParty).sort((a, b) => b.balance - a.balance), buckets });
});

// ---------- summary + GST register ----------
function range(req) {
  const to = isYmd(req.query.to) ? String(req.query.to) : todayIst();
  const from = isYmd(req.query.from) ? String(req.query.from) : (to.slice(0, 8) + '01');
  return { from, to };
}
router.get('/summary', perm(PERM_VIEW), (req, res) => {
  const { from, to } = range(req);
  const t = db.prepare("SELECT COUNT(*) n, COALESCE(SUM(taxable),0) taxable, COALESCE(SUM(cgst+sgst+igst),0) tax, COALESCE(SUM(total),0) total, COALESCE(SUM(paid_amount),0) paid FROM invoices WHERE status != 'CANCELLED' AND invoice_date BETWEEN ? AND ?").get(from, to);
  const byParty = db.prepare("SELECT party_name party, COUNT(*) invoices, COALESCE(SUM(total),0) total, COALESCE(SUM(total - paid_amount),0) balance FROM invoices WHERE status != 'CANCELLED' AND invoice_date BETWEEN ? AND ? GROUP BY party_name ORDER BY total DESC LIMIT 15").all(from, to);
  const byProduct = db.prepare("SELECT ii.description product, SUM(ii.qty) qty, COALESCE(SUM(ii.taxable),0) taxable FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id WHERE i.status != 'CANCELLED' AND i.invoice_date BETWEEN ? AND ? GROUP BY ii.description ORDER BY taxable DESC LIMIT 15").all(from, to);
  const byMonth = db.prepare("SELECT substr(invoice_date,1,7) month, COUNT(*) invoices, COALESCE(SUM(taxable),0) taxable, COALESCE(SUM(cgst+sgst+igst),0) tax, COALESCE(SUM(total),0) total FROM invoices WHERE status != 'CANCELLED' AND invoice_date >= date(?, '-11 months') AND invoice_date <= ? GROUP BY month ORDER BY month").all(to, to);
  const rec = db.prepare("SELECT COALESCE(SUM(total - paid_amount),0) v FROM invoices WHERE status IN ('ISSUED','PARTIAL')").get();
  res.json({ from, to, invoices: t.n, taxable: r2(t.taxable), tax: r2(t.tax), total: r2(t.total), received: r2(t.paid), outstanding: r2(rec.v), byParty, byProduct, byMonth });
});
function registerRows(from, to) {
  return db.prepare(`SELECT i.number, i.invoice_date, i.party_name, i.party_gstin, i.place_of_supply, i.supply_type, i.status, i.total invoice_total,
      ii.hsn_code, ii.gst_rate, SUM(ii.taxable) taxable, SUM(ii.cgst) cgst, SUM(ii.sgst) sgst, SUM(ii.igst) igst, SUM(ii.qty) qty
    FROM invoices i JOIN invoice_items ii ON ii.invoice_id = i.id
    WHERE i.invoice_date BETWEEN ? AND ?
    GROUP BY i.id, ii.hsn_code, ii.gst_rate ORDER BY i.invoice_date, i.id, ii.gst_rate`).all(from, to)
    .map((r) => Object.assign(r, { taxable: r2(r.taxable), cgst: r2(r.cgst), sgst: r2(r.sgst), igst: r2(r.igst), kind: r.party_gstin ? 'B2B' : 'B2C' }));
}
router.get('/register', perm(PERM_VIEW), (req, res) => {
  const { from, to } = range(req);
  const rows = registerRows(from, to);
  const live = rows.filter((r) => r.status !== 'CANCELLED');
  const byRate = {};
  for (const r of live) { const k = String(r.gst_rate); byRate[k] = byRate[k] || { rate: r.gst_rate, taxable: 0, cgst: 0, sgst: 0, igst: 0 }; byRate[k].taxable = r2(byRate[k].taxable + r.taxable); byRate[k].cgst = r2(byRate[k].cgst + r.cgst); byRate[k].sgst = r2(byRate[k].sgst + r.sgst); byRate[k].igst = r2(byRate[k].igst + r.igst); }
  res.json({ from, to, rows, byRate: Object.values(byRate).sort((a, b) => a.rate - b.rate),
    totals: { taxable: r2(live.reduce((s, r) => s + r.taxable, 0)), cgst: r2(live.reduce((s, r) => s + r.cgst, 0)), sgst: r2(live.reduce((s, r) => s + r.sgst, 0)), igst: r2(live.reduce((s, r) => s + r.igst, 0)) } });
});
router.get('/register.csv', perm(PERM_VIEW), (req, res) => {
  const { from, to } = range(req);
  const esc = (v) => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"';
  const head = ['Invoice No', 'Date', 'Party', 'GSTIN', 'Type', 'Place of Supply', 'Supply', 'HSN', 'Qty', 'GST %', 'Taxable', 'CGST', 'SGST', 'IGST', 'Invoice Total', 'Status'];
  const lines = [head.join(',')];
  for (const r of registerRows(from, to)) lines.push([r.number, r.invoice_date, r.party_name, r.party_gstin, r.kind, r.place_of_supply, r.supply_type, r.hsn_code, r.qty, r.gst_rate, r.taxable, r.cgst, r.sgst, r.igst, r.invoice_total, r.status].map(esc).join(','));
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', 'attachment; filename="gst-register-' + from + '-to-' + to + '.csv"');
  res.send('\ufeff' + lines.join('\r\n'));
});

module.exports = router;
JSFILE
sed -i "s/__PV__/$PV/; s/__PM__/$PM/" "$DIR/routes/billing.js"
node --check "$DIR/routes/billing.js" || { echo "ROUTE SYNTAX FAIL"; exit 1; }
echo "ROUTES: routes/billing.js ✓ (guards: $PV / $PM)"

# ---------- 3) server.js: early mount ----------
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = process.env.FF_DIR + '/server.js';
let src = fs.readFileSync(f, 'utf8');
if (src.includes('/* ffBilling */')) { console.log('SERVER: billing already mounted ✓'); process.exit(0); }
const m = src.match(/^[ \t]*app\.use\(\s*['"]\/api(?:\/|['"])/m);
const LINE = "/* ffBilling */ try { app.use('/api/billing', require('./routes/billing')); console.log('[ff-billing] /api/billing mounted'); } catch (e) { console.log('[ff-billing] mount error: ' + e.message); }\n";
if (m) src = src.slice(0, m.index) + LINE + src.slice(m.index);
else { const l = src.indexOf('app.listen('); if (l === -1) { console.log('SERVER: koi anchor nahi'); process.exit(1); } src = src.slice(0, l) + LINE + src.slice(l); }
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SERVER: /api/billing mounted early ✓'); }
catch (e) { fs.copyFileSync(f + '.bak-billing-' + process.env.FF_TS, f); console.log('SERVER SYNTAX FAIL — RESTORED'); process.exit(1); }
JS
[ $? -ne 0 ] && { echo "BILLING FAIL (server.js)"; exit 1; }

# ---------- 4) custom-permission users: backfill billing.* from dispatch.* ----------
if [ "$PERM_MODE" = "billing" ]; then
node - <<'JS'
const path = require('path'), fs = require('fs');
const DIR = process.env.FF_DIR;
const dbs = [];
if (DIR.includes('flavorflow-saas')) { const root = '/opt/flavorflow-saas/data'; for (const d of fs.readdirSync(root)) if (d.startsWith('tenant-') && fs.existsSync(path.join(root, d, 'erp.db'))) dbs.push(path.join(root, d, 'erp.db')); }
else dbs.push(DIR + '/data/erp.db');
let Database = null;
try { Database = require(DIR + '/sqlite').DatabaseSync; } catch (_) { try { Database = require('node:sqlite').DatabaseSync; } catch (_) {} }
if (!Database) { console.log('BACKFILL: sqlite wrapper nahi — skip (custom-perm users nu admin ton billing perm deni pau)'); process.exit(0); }
let total = 0;
for (const f of dbs) {
  try {
    const db = new Database(f);
    const rows = db.prepare("SELECT id, name, permissions FROM users WHERE permissions IS NOT NULL AND permissions != '' AND permissions != '[]'").all();
    for (const u of rows) {
      let p; try { p = JSON.parse(u.permissions); } catch (_) { continue; }
      if (!Array.isArray(p) || !p.length) continue;
      const n = p.length;
      if (p.includes('dispatch.view') && !p.includes('billing.view')) p.push('billing.view');
      if (p.includes('dispatch.manage') && !p.includes('billing.manage')) p.push('billing.manage');
      if (p.length !== n) { db.prepare('UPDATE users SET permissions = ? WHERE id = ?').run(JSON.stringify(p.sort()), u.id); total++; }
    }
    db.close();
  } catch (e) { console.log('BACKFILL ' + f + ': ' + e.message); }
}
console.log('BACKFILL: ' + total + ' custom-permission user(s) got billing perms (' + dbs.length + ' DB)');
JS
fi

systemctl restart "$SVC"
sleep 6
if [ "$MODE" = "saas" ]; then
  P=$(node -e 'try{const r=require("/opt/flavorflow-saas/data/registry.json");const c=Object.values(r.companies||{})[0];console.log(c?c.port:"")}catch(e){console.log("")}')
  [ -n "$P" ] && curl -s -m 8 -o /dev/null -w "TENANT :$P /api/billing/settings (no token) -> %{http_code}  (401 = route live, auth guard OK)\n" "http://127.0.0.1:$P/api/billing/settings"
else
  curl -s -m 8 -o /dev/null -w "FACTORY /api/billing/settings (no token) -> %{http_code}  (401 = route live)\n" http://127.0.0.1:4000/api/billing/settings
fi
echo "BILLING DONE ✓ — app: Billing section (invoices, parties, receipts, GST register); Products: HSN / GST % / sale rate"
