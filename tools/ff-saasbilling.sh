#!/usr/bin/env bash
# ff-saasbilling.sh — FlavorFlow SaaS SUBSCRIPTION billing (gateway patch).
#
#   Plans: Basic / Pro / Enterprise × monthly / yearly  (prices in plans.json — editable
#   from the owner console, no redeploy).  NO payment gateway: customers pay by CHEQUE /
#   NEFT, the owner marks the invoice PAID from the admin console (web-landing/admin.html)
#   or curl, and the tenant's paidUntil moves forward.  Proxy blocks (402) after
#   trial/paid period + grace days.  Demo tenants are never blocked.
#
#   Adds to gateway (/opt/flavorflow-saas/server/server.js), all before the /t/:code proxy:
#     GET  /api/saas/plans                          public: tiers, prices, payment instructions
#     GET  /api/saas/billing/status?code=X          tenant billing status (+ /t/X/api/saas/billing/status)
#     GET  /api/saas/admin/companies                owner (header x-admin-key)
#     GET  /api/saas/admin/plans  PUT (same)        edit prices / bank details / grace days
#     POST /api/saas/admin/set-plan                 {code, tier, cycle}              → plan + due invoice
#     POST /api/saas/admin/invoice                  {code, tier?, cycle?, amount?, periodFrom?}
#     POST /api/saas/admin/mark-paid                {code, invoiceNo, chequeNo, bank, paidOn, amount?}
#     POST /api/saas/admin/void                     {code, invoiceNo}
#     POST /api/saas/admin/extend                   {code, days | until, note}
#     POST /api/saas/admin/suspend                  {code, suspended: true|false, note}
#   Nightly (and at boot): renewal invoices auto-created 10 days before paidUntil → data/billing-due.json
#
#   Admin key: /opt/flavorflow-saas/admin.key (auto-created; printed below) or env FF_ADMIN_KEY.
#
# Run (VM):  curl -s https://raw.githubusercontent.com/manjotkhehra74-cloud/FlavorFlow/arena/01a0858b-flavorflow/tools/ff-saasbilling.sh | sudo bash
set -u
BASE="${FF_BASE:-/opt/flavorflow-saas}"
GW="$BASE/server/server.js"
TS=$(date +%s)
[ -f "$GW" ] || { echo "FATAL: gateway $GW nahi labhya (eh SaaS VM nahi?)"; exit 1; }
echo "=== FF-SAASBILLING $(date) ==="
mkdir -p "$BASE/data"

# ---------- 1) plans.json (defaults; owner edits via admin console) ----------
if [ ! -f "$BASE/plans.json" ]; then
cat > "$BASE/plans.json" <<'JSON'
{
  "currency": "INR",
  "trialDays": 30,
  "graceDays": 7,
  "renewalNoticeDays": 10,
  "trialTier": "pro",
  "tiers": {
    "basic": {
      "name": "Basic", "monthly": 999, "yearly": 9990, "users": 5,
      "tagline": "Small unit — stock, packing, dispatch & GST billing",
      "features": ["Up to 5 users", "Products, inventory & packing material", "Dispatch challans + PDF", "GST tax invoices & receivables", "Stock & sales reports", "WhatsApp support"],
      "blockedPaths": ["/api/production", "/api/audit"]
    },
    "pro": {
      "name": "Pro", "monthly": 1999, "yearly": 19990, "users": 15,
      "tagline": "Growing factory — production, recipes & controls",
      "features": ["Up to 15 users", "Everything in Basic", "Production batches, recipes / BOM", "Raw material & consumption tracking", "Approvals & full audit log", "Priority WhatsApp support"],
      "blockedPaths": []
    },
    "enterprise": {
      "name": "Enterprise", "monthly": 3999, "yearly": 39990, "users": 0,
      "tagline": "Multi-shift plant — unlimited users & onboarding",
      "features": ["Unlimited users", "Everything in Pro", "Custom roles & permissions", "On-site / video onboarding", "Data export & backup on request", "Phone support"],
      "blockedPaths": []
    }
  },
  "payment": {
    "payeeName": "FlavorFlow",
    "chequeInFavourOf": "FlavorFlow",
    "bankName": "",
    "accountNo": "",
    "ifsc": "",
    "upiId": "",
    "address": "",
    "whatsapp": "919501606877",
    "email": "",
    "note": "Cheque / NEFT only. WhatsApp a photo of the cheque or the NEFT UTR with your company code — activation within 1 working day of clearance."
  }
}
JSON
echo "PLANS: $BASE/plans.json created (Basic 999 / Pro 1999 / Enterprise 3999 per month; yearly = 10x)"
else echo "PLANS: plans.json already ✓ (kept)"; fi
# Retired feature wording (Packing Loss % sheet removed Sep 2026) — fix an existing plans.json in place.
node -e '
const fs=require("fs"),f=process.argv[1];try{const t=fs.readFileSync(f,"utf8");const n=t.split("Raw material & packing-loss tracking").join("Raw material & consumption tracking");if(n!==t){fs.writeFileSync(f,n);console.log("PLANS: feature text updated (packing-loss → consumption)");}}catch(e){}
' "$BASE/plans.json"

# ---------- 2) admin key (NEVER printed — boot-status.txt is public) ----------
#   Set your own: GCP console → VM → Edit → Custom metadata  ff-admin-key = <your secret>  → RESET
#   (ff-boot passes it as FF_ADMIN_KEY). Otherwise a random key is generated and kept in admin.key.
if [ -n "${FF_ADMIN_KEY:-}" ]; then printf '%s' "$FF_ADMIN_KEY" > "$BASE/admin.key"; chmod 600 "$BASE/admin.key"; echo "ADMIN KEY: set from metadata ff-admin-key ✓ (use it on https://flavorflow.co.in/admin.html)";
elif [ -f "$BASE/admin.key" ]; then echo "ADMIN KEY: existing admin.key kept ✓ (to change: GCP metadata ff-admin-key + RESET)";
else node -e 'process.stdout.write(require("crypto").randomBytes(24).toString("hex"))' > "$BASE/admin.key"; chmod 600 "$BASE/admin.key"; echo "ADMIN KEY: auto-generated → $BASE/admin.key (not shown). For the browser console set GCP metadata ff-admin-key = your own secret and RESET."; fi

# ---------- 3) gateway patch ----------
cp "$GW" "$GW.bak-saasbilling-$TS"
FF_GW="$GW" FF_TS="$TS" node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = process.env.FF_GW;
let src = fs.readFileSync(f, 'utf8');
if (src.includes('/* ffSaasBilling */')) { console.log('GATEWAY: saas billing already ✓'); process.exit(0); }
const anchor = "app.use('/t/:code'";
const i = src.indexOf(anchor);
if (i === -1) { console.log('GATEWAY: /t/:code proxy anchor nahi labhya'); process.exit(1); }

const BLOCK = String.raw`/* ffSaasBilling */
const FF_PLANS = BASE + '/plans.json', FF_BILL = BASE + '/data/saas-billing.json', FF_DUE = BASE + '/data/billing-due.json';
const ffReadJson = (p, d) => { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (_) { return d; } };
const ffPlans = () => { const p = ffReadJson(FF_PLANS, {}); p.tiers = p.tiers || {}; p.payment = p.payment || {}; p.graceDays = Number(p.graceDays) || 0; p.renewalNoticeDays = Number(p.renewalNoticeDays) || 10; return p; };
const ffAdminKey = () => (process.env.FF_ADMIN_KEY || '').trim() || (fs.existsSync(BASE + '/admin.key') ? fs.readFileSync(BASE + '/admin.key', 'utf8').trim() : '');
const ffToday = () => new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10); // IST
const ffAddDays = (ymd, n) => { const d = new Date(ymd + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const ffAddCycle = (ymd, cycle) => { const d = new Date(ymd + 'T00:00:00Z'); if (cycle === 'yearly') d.setUTCFullYear(d.getUTCFullYear() + 1); else d.setUTCMonth(d.getUTCMonth() + 1); return ffAddDays(d.toISOString().slice(0, 10), -1); };
const ffDays = (a, b) => Math.round((new Date(b + 'T00:00:00Z') - new Date(a + 'T00:00:00Z')) / 864e5);
const ffFy = (ymd) => { const y = +ymd.slice(0, 4), m = +ymd.slice(5, 7); const a = m >= 4 ? y : y - 1; return String(a).slice(2) + '-' + String(a + 1).slice(2); };
function ffNextInvoiceNo() {
  const st = ffReadJson(FF_BILL, { seq: 0, fy: '' }); const fy = ffFy(ffToday());
  if (st.fy !== fy) { st.fy = fy; st.seq = 0; }
  st.seq += 1; fs.writeFileSync(FF_BILL, JSON.stringify(st, null, 2));
  return 'FF-INV-' + fy + '-' + String(st.seq).padStart(4, '0');
}
function ffAccess(c) {
  if (c.demo) return { ok: true, state: 'demo', until: '2099-12-31' };
  if (c.suspended) return { ok: false, state: 'suspended', until: c.paidUntil || c.trialEnds || '' };
  const today = ffToday(), paid = c.paidUntil || '', trial = c.trialEnds || '';
  const until = paid > trial ? paid : trial;
  if (until && today <= until) return { ok: true, state: paid && today <= paid ? 'active' : 'trial', until, daysLeft: ffDays(today, until) };
  const grace = until ? ffAddDays(until, ffPlans().graceDays) : '';
  if (grace && today <= grace) return { ok: true, state: 'grace', until, graceUntil: grace, daysLeft: ffDays(today, grace) };
  return { ok: false, state: 'expired', until };
}
function ffTierOf(c, a) { const p = ffPlans(); const t = (c.plan && c.plan.tier) || (a.state === 'trial' || a.state === 'grace' && !c.plan ? p.trialTier : '') || 'pro'; return p.tiers[t] ? t : 'pro'; }
function ffStatus(c, code) {
  const p = ffPlans(), a = ffAccess(c), tier = ffTierOf(c, a), t = p.tiers[tier] || {};
  const inv = (c.invoices || []).slice(-12).reverse();
  const due = (c.invoices || []).filter(x => x.status === 'due').slice(-1)[0] || null;
  return {
    company: c.name, code, industry: c.industry || '', state: a.state, ok: a.ok, until: a.until || '', graceUntil: a.graceUntil || '', daysLeft: a.daysLeft == null ? null : a.daysLeft,
    trialEnds: c.trialEnds || '', paidUntil: c.paidUntil || '', suspended: !!c.suspended, suspendNote: c.suspendNote || '',
    plan: { tier, name: t.name || tier, cycle: (c.plan && c.plan.cycle) || '', price: c.plan && c.plan.price != null ? c.plan.price : (t.monthly || 0), users: t.users == null ? 0 : t.users, features: t.features || [], chosen: !!c.plan, intent: c.planIntent || '' },
    dueInvoice: due, invoices: inv, payment: p.payment, currency: p.currency || 'INR', graceDays: p.graceDays,
    plans: Object.keys(p.tiers).map(k => ({ tier: k, name: p.tiers[k].name, monthly: p.tiers[k].monthly, yearly: p.tiers[k].yearly, users: p.tiers[k].users, features: p.tiers[k].features || [] })),
  };
}
function ffBlockMsg(c, a) {
  const w = (ffPlans().payment || {}).whatsapp || '';
  if (a.state === 'suspended') return 'Access to ' + c.name + ' is suspended' + (c.suspendNote ? ' (' + c.suspendNote + ')' : '') + '. Contact FlavorFlow' + (w ? ' on WhatsApp +' + w : '') + '.';
  return 'Subscription for ' + c.name + ' ended on ' + a.until + '. Pay by cheque / NEFT to continue' + (w ? ' — WhatsApp +' + w : '') + '.';
}
// per-tier gating on the proxied path: blocked feature paths + user limit (fail-open on any error)
function ffPlanBlock(req, res, c, a, code) {
  try {
    if (c.demo) return false;
    const p = ffPlans(), tier = ffTierOf(c, a), t = p.tiers[tier] || {};
    const path = req.originalUrl.replace('/t/' + code, '').split('?')[0];
    for (const b of (t.blockedPaths || [])) if (path === b || path.startsWith(b + '/') || path.startsWith(b + '?')) {
      res.status(402).json({ error: 'This feature is not in your ' + (t.name || tier) + ' plan — upgrade to Pro to use it.', code: 'PLAN_FEATURE', tier }); return true;
    }
    if (req.method === 'POST' && path === '/api/users' && t.users > 0) {
      let Database = null;
      try { Database = require(BASE + '/core/sqlite').DatabaseSync; } catch (_) { try { Database = require('node:sqlite').DatabaseSync; } catch (_) {} }
      if (Database) {
        const db = new Database(BASE + '/data/tenant-' + code + '/erp.db', { readOnly: true });
        let n = 0; try { n = db.prepare('SELECT COUNT(*) n FROM users WHERE COALESCE(active, 1) = 1').get().n; } catch (_) { n = db.prepare('SELECT COUNT(*) n FROM users').get().n; }
        try { db.close(); } catch (_) {}
        if (n >= t.users) { res.status(402).json({ error: 'Your ' + (t.name || tier) + ' plan allows ' + t.users + ' users (you have ' + n + '). Upgrade the plan to add more.', code: 'PLAN_USERS', tier }); return true; }
      }
    }
  } catch (e) { console.log('[billing] plan gate skipped: ' + e.message); }
  return false;
}
function ffCreateInvoice(code, c, o) {
  const p = ffPlans(); o = o || {};
  const tier = p.tiers[o.tier] ? o.tier : ((c.plan && c.plan.tier) || 'pro');
  const cycle = o.cycle === 'yearly' ? 'yearly' : (o.cycle === 'monthly' ? 'monthly' : ((c.plan && c.plan.cycle) || 'monthly'));
  const t = p.tiers[tier] || {};
  const amount = o.amount != null && !isNaN(Number(o.amount)) ? Number(o.amount) : Number(cycle === 'yearly' ? t.yearly : t.monthly) || 0;
  const today = ffToday();
  let from = o.periodFrom && /^\d{4}-\d{2}-\d{2}$/.test(o.periodFrom) ? o.periodFrom : today;
  if (!o.periodFrom) { if (c.paidUntil && c.paidUntil >= today) from = ffAddDays(c.paidUntil, 1); else if (!c.paidUntil && c.trialEnds && c.trialEnds >= today) from = ffAddDays(c.trialEnds, 1); }
  const inv = { no: ffNextInvoiceNo(), tier, cycle, amount, currency: p.currency || 'INR', periodFrom: from, periodTo: ffAddCycle(from, cycle), status: 'due', issuedAt: new Date().toISOString(), note: String(o.note || '').slice(0, 200) };
  c.invoices = c.invoices || []; c.invoices.push(inv);
  return inv;
}
function ffRenewalSweep() {
  try {
    const p = ffPlans(), today = ffToday(), due = [];
    let created = 0;
    for (const code of Object.keys(reg.companies)) {
      const c = reg.companies[code]; if (c.demo || !c.plan) continue;
      const open = (c.invoices || []).find(x => x.status === 'due');
      if (!open && c.paidUntil && ffDays(today, c.paidUntil) <= p.renewalNoticeDays) { ffCreateInvoice(code, c, {}); created++; }
      const a = ffAccess(c); const d = (c.invoices || []).find(x => x.status === 'due');
      if (d || !a.ok || a.state === 'grace') due.push({ code, company: c.name, state: a.state, until: a.until, invoice: d ? d.no : '', amount: d ? d.amount : 0, periodTo: d ? d.periodTo : '' });
    }
    if (created) save();
    const dueJson = JSON.stringify({ at: new Date().toISOString(), created, due }, null, 2);
    fs.writeFileSync(FF_DUE, dueJson);
    try { if (fs.existsSync(BASE + '/web/download')) fs.writeFileSync(BASE + '/web/download/billing-due.json', dueJson); } catch (_) {}
    if (created || due.length) console.log('[billing] sweep: ' + created + ' renewal invoice(s) created, ' + due.length + ' company(ies) due/expired');
  } catch (e) { console.log('[billing] sweep error: ' + e.message); }
}
setTimeout(ffRenewalSweep, 15000); setInterval(ffRenewalSweep, 6 * 3600e3);

const ffJson = express.json({ limit: '50kb' });
const ffAdmin = (req, res, next) => { const k = ffAdminKey(); if (!k || (req.headers['x-admin-key'] || '') !== k) return res.status(401).json({ error: 'Admin key required.' }); next(); };
const ffCo = (req, res) => { const code = String((req.body && req.body.code) || req.query.code || '').trim(); const c = reg.companies[code]; if (!c) { res.status(404).json({ error: 'Company not found: ' + code }); return null; } return { code, c }; };

app.get('/api/saas/plans', (req, res) => { const p = ffPlans(); res.json({ currency: p.currency || 'INR', trialDays: p.trialDays || 30, graceDays: p.graceDays, tiers: p.tiers, payment: p.payment }); });
const ffStatusRoute = (req, res) => { const code = String(req.params.code || req.query.code || '').trim(); const c = reg.companies[code]; if (!c) return res.status(404).json({ error: 'Company not found — check your company code.' }); res.json(ffStatus(c, code)); };
app.get('/api/saas/billing/status', ffStatusRoute);
app.get('/t/:code/api/saas/billing/status', ffStatusRoute);

app.get('/api/saas/admin/companies', ffAdmin, (req, res) => {
  res.json({ today: ffToday(), companies: Object.keys(reg.companies).map(code => { const c = reg.companies[code]; const s = ffStatus(c, code); return { code, name: c.name, industry: c.industry || '', created: c.created, adminEmail: c.adminEmail || '', adminName: c.adminName || '', port: c.port, demo: !!c.demo, state: s.state, until: s.until, daysLeft: s.daysLeft, trialEnds: s.trialEnds, paidUntil: s.paidUntil, plan: s.plan, dueInvoice: s.dueInvoice, invoices: c.invoices || [], suspended: !!c.suspended, planIntent: c.planIntent || '' }; }) });
});
app.get('/api/saas/admin/plans', ffAdmin, (req, res) => res.json(ffPlans()));
app.put('/api/saas/admin/plans', ffAdmin, ffJson, (req, res) => {
  const b = req.body || {}; if (!b.tiers || typeof b.tiers !== 'object') return res.status(400).json({ error: 'tiers missing' });
  fs.writeFileSync(FF_PLANS, JSON.stringify(b, null, 2)); res.json({ ok: true, plans: ffPlans() });
});
app.post('/api/saas/admin/set-plan', ffAdmin, ffJson, (req, res) => {
  const x = ffCo(req, res); if (!x) return; const p = ffPlans(); const b = req.body || {};
  if (!p.tiers[b.tier]) return res.status(400).json({ error: 'Unknown tier: ' + b.tier });
  const cycle = b.cycle === 'yearly' ? 'yearly' : 'monthly'; const t = p.tiers[b.tier];
  x.c.plan = { tier: b.tier, cycle, price: Number(cycle === 'yearly' ? t.yearly : t.monthly) || 0, setAt: new Date().toISOString() };
  let inv = null; if (b.invoice !== false && !(x.c.invoices || []).some(i => i.status === 'due')) inv = ffCreateInvoice(x.code, x.c, { tier: b.tier, cycle });
  save(); console.log('[billing] plan set: ' + x.code + ' → ' + b.tier + '/' + cycle + (inv ? ' invoice ' + inv.no : ''));
  res.json({ ok: true, plan: x.c.plan, invoice: inv, status: ffStatus(x.c, x.code) });
});
app.post('/api/saas/admin/invoice', ffAdmin, ffJson, (req, res) => {
  const x = ffCo(req, res); if (!x) return; const inv = ffCreateInvoice(x.code, x.c, req.body || {}); save();
  console.log('[billing] invoice ' + inv.no + ' for ' + x.code + ' ' + inv.amount); res.json({ ok: true, invoice: inv, status: ffStatus(x.c, x.code) });
});
app.post('/api/saas/admin/mark-paid', ffAdmin, ffJson, (req, res) => {
  const x = ffCo(req, res); if (!x) return; const b = req.body || {};
  const inv = (x.c.invoices || []).find(i => i.no === b.invoiceNo) || (x.c.invoices || []).filter(i => i.status === 'due').slice(-1)[0];
  if (!inv) return res.status(400).json({ error: 'No due invoice — create one first (set-plan / invoice).' });
  if (inv.status === 'paid') return res.status(400).json({ error: inv.no + ' is already paid.' });
  inv.status = 'paid'; inv.paidOn = /^\d{4}-\d{2}-\d{2}$/.test(b.paidOn || '') ? b.paidOn : ffToday();
  inv.mode = b.mode === 'neft' || b.mode === 'upi' || b.mode === 'cash' ? b.mode : 'cheque';
  inv.chequeNo = String(b.chequeNo || b.refNo || '').slice(0, 40); inv.bank = String(b.bank || '').slice(0, 80);
  if (b.amount != null && !isNaN(Number(b.amount))) inv.paidAmount = Number(b.amount);
  if (!x.c.paidUntil || inv.periodTo > x.c.paidUntil) x.c.paidUntil = inv.periodTo;
  if (!x.c.plan || x.c.plan.tier !== inv.tier || x.c.plan.cycle !== inv.cycle) x.c.plan = { tier: inv.tier, cycle: inv.cycle, price: inv.amount, setAt: new Date().toISOString() };
  x.c.suspended = false; save();
  console.log('[billing] PAID ' + inv.no + ' ' + x.code + ' → paidUntil ' + x.c.paidUntil);
  res.json({ ok: true, invoice: inv, paidUntil: x.c.paidUntil, status: ffStatus(x.c, x.code) });
});
app.post('/api/saas/admin/void', ffAdmin, ffJson, (req, res) => {
  const x = ffCo(req, res); if (!x) return; const inv = (x.c.invoices || []).find(i => i.no === (req.body || {}).invoiceNo);
  if (!inv) return res.status(404).json({ error: 'Invoice not found.' }); if (inv.status === 'paid') return res.status(400).json({ error: 'Paid invoice cannot be voided.' });
  inv.status = 'void'; save(); res.json({ ok: true, invoice: inv });
});
app.post('/api/saas/admin/extend', ffAdmin, ffJson, (req, res) => {
  const x = ffCo(req, res); if (!x) return; const b = req.body || {}; const today = ffToday();
  const base = [x.c.paidUntil || '', x.c.trialEnds || '', today].sort().pop();
  const until = /^\d{4}-\d{2}-\d{2}$/.test(b.until || '') ? b.until : ffAddDays(base, Math.max(1, Math.min(3660, Number(b.days) || 30)));
  if (x.c.paidUntil) x.c.paidUntil = until; else x.c.trialEnds = until;
  x.c.extensions = (x.c.extensions || []).concat([{ at: new Date().toISOString(), until, note: String(b.note || '').slice(0, 200) }]);
  save(); console.log('[billing] extend ' + x.code + ' → ' + until); res.json({ ok: true, until, status: ffStatus(x.c, x.code) });
});
app.post('/api/saas/admin/suspend', ffAdmin, ffJson, (req, res) => {
  const x = ffCo(req, res); if (!x) return; const b = req.body || {};
  x.c.suspended = b.suspended !== false; x.c.suspendNote = String(b.note || '').slice(0, 200); save();
  res.json({ ok: true, suspended: x.c.suspended, status: ffStatus(x.c, x.code) });
});

`;
src = src.slice(0, i) + BLOCK + src.slice(i);

// proxy: replace the trial-only 402 with the subscription state check (+ plan gating)
const re = /if \(new Date\(c\.trialEnds \+ 'T23:59:59'\) < new Date\(\)\)\s*\n?\s*return res\.status\(402\)\.json\(\{[^\n]*\n/;
const REPL = "  { const ffA = ffAccess(c); if (!ffA.ok) return res.status(402).json({ error: ffBlockMsg(c, ffA), code: 'SUBSCRIPTION_' + ffA.state.toUpperCase(), billing: ffStatus(c, req.params.code) }); if (ffPlanBlock(req, res, c, ffA, req.params.code)) return; }\n";
if (re.test(src)) src = src.replace(re, REPL);
else {
  const j = src.indexOf("if (!c) return res.status(404)", i);
  const nl = src.indexOf('\n', j);
  if (j === -1) { console.log('GATEWAY: proxy 404 line nahi labhi — 402 check add nahi hoya'); process.exit(1); }
  src = src.slice(0, nl + 1) + REPL + src.slice(nl + 1);
  console.log('GATEWAY: trial check pattern different — subscription check inserted after 404 line');
}
// register: remember the plan the customer picked on the website (owner sees it in the console)
src = src.replace("reg.companies[code] = { name, industry, port, created: new Date().toISOString(), trialEnds, adminName, adminEmail, adminPassword };",
  "reg.companies[code] = { name, industry, port, created: new Date().toISOString(), trialEnds, adminName, adminEmail, adminPassword, planIntent: String(b.plan || '').slice(0, 30), phone: String(b.phone || '').slice(0, 20) };");
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('GATEWAY: saas billing routes + subscription gate ✓'); }
catch (e) { fs.copyFileSync(f + '.bak-saasbilling-' + process.env.FF_TS, f); console.log('GATEWAY SYNTAX FAIL — RESTORED'); process.exit(1); }
JS
[ $? -ne 0 ] && { echo "SAASBILLING FAIL (gateway)"; exit 1; }

# ---------- 4) restart + verify ----------
if [ -z "${FF_NO_RESTART:-}" ]; then
  systemctl restart flavorflow-saas
  sleep 4
  echo "HEALTH: $(curl -s -m 8 http://127.0.0.1:4100/api/saas/health | head -c 120)"
  echo "PLANS: $(curl -s -m 8 http://127.0.0.1:4100/api/saas/plans | head -c 160)…"
  CODE=$(node -e 'try{const r=require(process.env.B+"/data/registry.json");const k=Object.keys(r.companies||{}).find(k=>!r.companies[k].demo)||Object.keys(r.companies||{})[0];console.log(k||"")}catch(e){console.log("")}' B="$BASE")
  [ -n "$CODE" ] && echo "STATUS[$CODE]: $(curl -s -m 8 "http://127.0.0.1:4100/api/saas/billing/status?code=$CODE" | head -c 220)…"
  echo "ADMIN: companies (no key) -> $(curl -s -m 8 -o /dev/null -w '%{http_code}' http://127.0.0.1:4100/api/saas/admin/companies)  (401 = guard OK)"
fi
echo "SAASBILLING DONE ✓ — owner console: https://flavorflow.co.in/admin.html (unlock with the admin key)"
