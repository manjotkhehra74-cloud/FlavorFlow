#!/usr/bin/env bash
# FlavorFlow ↔ HRMate — COMPANY-LEVEL attendance bridge (server side).
#   Admin app ch IK vaar HRMate address + API key save karda hai → company de
#   SAARE users nu dashboard / batch te hazri dikhdi hai. Key server te rehndi
#   hai (phone te kadi nahi jandi) — server hi HRMate nu call karda hai (proxy,
#   60 s cache, 7 s timeout). Bina is patch de app per-device mode ch chaldi hai.
#
#   core server.js (SaaS core + factory auto-detect), 404 catch-all ton PEHLA mount:
#     GET    /api/settings/hrmate        (login)  → {configured, base, wage, hasKey, updatedAt, updatedBy}
#     PUT    /api/settings/hrmate        (admin)  {base, key, wage, keepKey}
#     DELETE /api/settings/hrmate        (admin)
#     POST   /api/settings/hrmate/test   (admin)  {base?, key?, date?} → HRMate JSON | {ok:false, error}
#     GET    /api/hrmate/summary?date=   (login)  → HRMate JSON (200) | {ok:false, error} (502) | 404 not connected
#   Storage: app_settings key 'hrmate' (per-tenant erp.db). Block is versioned —
#   a newer block replaces the old one, an identical block is left alone.
#   Idempotent. Backup + node --check + auto-restore. FF_NO_RESTART=1 → no restart.
set -u
if [ -d /opt/flavorflow-saas/core ]; then DIR=/opt/flavorflow-saas/core; MODE=saas; SVC=flavorflow-saas;
elif [ -d /opt/flavorflow/server ]; then DIR=/opt/flavorflow/server; MODE=factory; SVC=flavorflow;
else echo "FATAL: koi server dir nahi labhi"; exit 1; fi
echo "=== FF-HRMATE ($MODE) $(date) ==="
TS=$(date +%s)
BLOCK=/tmp/ff-hrmate-block-$TS.js

# ---------------------------------------------------------------------------
# The block that goes into core server.js (plain file → no template-literal
# escaping games; keep it free of backslashes anyway).
# ---------------------------------------------------------------------------
cat > "$BLOCK" <<'EOF'
// --- ff-hrmate v1: company-level HRMate attendance bridge (settings + read-only proxy) ---
/* ffHrMate */
try {
  const _hdb = require('./db');
  _hdb.prepare("CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)").run();
  const _hmw = (() => { try { return require('./middleware'); } catch (_) { return {}; } })();
  const _hauth = typeof _hmw.authRequired === 'function' ? _hmw.authRequired : ((req, res, next) => next());
  const _hjson = require('express').json({ limit: '20kb' });
  const _hget = () => { try { return JSON.parse((_hdb.prepare("SELECT value FROM app_settings WHERE key='hrmate'").get() || {}).value || '{}'); } catch (_) { return {}; } };
  const _hput = (v) => _hdb.prepare("INSERT INTO app_settings (key, value) VALUES ('hrmate', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value").run(JSON.stringify(v));
  const _hbase = (raw) => {
    let s = String(raw || '').trim();
    if (!s) return '';
    if (s.indexOf('://') < 0) s = 'https://' + s;
    while (s.endsWith('/')) s = s.slice(0, -1);
    for (const suf of ['/api/v1/attendance/summary', '/api/v1', '/api']) { if (s.endsWith(suf)) s = s.slice(0, -suf.length); }
    while (s.endsWith('/')) s = s.slice(0, -1);
    try { const u = new URL(s); if (!u.hostname || (u.protocol !== 'https:' && u.protocol !== 'http:')) return ''; return s.slice(0, 200); } catch (_) { return ''; }
  };
  const _hisAdmin = (u) => !!u && (u.role === 'super_admin' || u.role === 'admin');
  const _hcache = new Map(); // date -> { at, ok, body }
  const _hdate = (q) => {
    const d = String(q || '').trim();
    if (/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(d)) return d;
    return new Date(Date.now() + 330 * 60000).toISOString().slice(0, 10); // IST today
  };
  const _hfetch = (base, key, date, cb) => {
    let u;
    try { u = new URL(base + '/api/v1/attendance/summary'); } catch (_) { cb({ status: 0, error: 'bad address' }); return; }
    u.searchParams.set('date', date);
    if (key) u.searchParams.set('api_key', key);
    const headers = { accept: 'application/json', 'user-agent': 'FlavorFlow-ERP hrmate-bridge' };
    if (key) { headers.authorization = 'Bearer ' + key; headers['x-api-key'] = key; }
    let done = false;
    const finish = (r) => { if (!done) { done = true; cb(r); } };
    let req;
    try {
      req = (u.protocol === 'http:' ? require('http') : require('https')).get(u, { headers, timeout: 7000 }, (res) => {
        let body = '';
        res.setEncoding('utf8');
        res.on('data', (c) => { if (body.length < 300000) body += c; });
        res.on('end', () => { let j = null; try { j = JSON.parse(body); } catch (_) {} finish({ status: res.statusCode, json: j }); });
        res.on('error', (e) => finish({ status: 0, error: e.message }));
      });
    } catch (e) { finish({ status: 0, error: e.message }); return; }
    req.on('timeout', () => { req.destroy(new Error('timeout 7s')); });
    req.on('error', (e) => finish({ status: 0, error: e.message }));
  };
  const _hresult = (r) => {
    if (r.status === 200 && r.json && r.json.ok !== false) return { ok: true, json: r.json };
    if (r.json && r.json.ok === false) return { ok: false, error: String(r.json.error || r.json.message || 'HRMate refused the request'), status: r.status };
    if (r.status === 401 || r.status === 403) return { ok: false, error: 'HRMate rejected the API key', status: r.status };
    if (r.status === 404) return { ok: false, error: 'HRMate summary API not found — update HRMate', status: 404 };
    if (r.status && r.status >= 400) return { ok: false, error: 'HRMate answered HTTP ' + r.status, status: r.status };
    if (r.status === 200) return { ok: false, error: 'Unexpected reply from HRMate (not JSON)', status: 200 };
    return { ok: false, error: 'Could not reach HRMate' + (r.error ? ' (' + r.error + ')' : ''), status: 0 };
  };
  const _hview = (c) => ({ configured: !!c.base, base: c.base || '', wage: Number(c.wage) || 0, hasKey: !!c.key, updatedAt: c.updatedAt || null, updatedBy: c.updatedBy || null });

  app.get('/api/settings/hrmate', _hauth, (req, res) => { res.json(_hview(_hget())); });
  app.put('/api/settings/hrmate', _hjson, _hauth, (req, res) => {
    if (!_hisAdmin(req.user)) { res.status(403).json({ error: 'Only Admin/Super Admin can connect HRMate for the company.' }); return; }
    const b = req.body || {};
    const prev = _hget();
    const base = _hbase(b.base);
    if (!base) { res.status(400).json({ error: 'HRMate address missing' }); return; }
    const key = (typeof b.key === 'string' && b.key.trim()) ? b.key.trim().slice(0, 200) : (b.keepKey ? (prev.key || '') : '');
    const wage = Math.max(0, Math.min(100000, Number(b.wage) || 0));
    const who = req.user ? (req.user.name || req.user.email || null) : null;
    _hput({ base, key, wage, updatedAt: new Date().toISOString(), updatedBy: who });
    _hcache.clear();
    res.json(Object.assign({ ok: true }, _hview(_hget())));
  });
  app.delete('/api/settings/hrmate', _hauth, (req, res) => {
    if (!_hisAdmin(req.user)) { res.status(403).json({ error: 'Only Admin/Super Admin can disconnect HRMate.' }); return; }
    _hput({});
    _hcache.clear();
    res.json({ ok: true, configured: false });
  });
  app.post('/api/settings/hrmate/test', _hjson, _hauth, (req, res) => {
    if (!_hisAdmin(req.user)) { res.status(403).json({ error: 'Only Admin/Super Admin can test HRMate.' }); return; }
    const b = req.body || {};
    const prev = _hget();
    const base = _hbase(b.base || prev.base);
    if (!base) { res.json({ ok: false, error: 'HRMate address missing' }); return; }
    const key = (typeof b.key === 'string' && b.key.trim()) ? b.key.trim() : (prev.key || '');
    _hfetch(base, key, _hdate(b.date), (r) => { const out = _hresult(r); res.json(out.ok ? out.json : out); });
  });
  app.get('/api/hrmate/summary', _hauth, (req, res) => {
    const c = _hget();
    if (!c.base) { res.status(404).json({ ok: false, error: 'HRMate not connected' }); return; }
    const date = _hdate(req.query && req.query.date);
    const hit = _hcache.get(date);
    if (hit && Date.now() - hit.at < (hit.ok ? 60000 : 20000)) { res.status(hit.ok ? 200 : 502).json(hit.body); return; }
    _hfetch(c.base, c.key || '', date, (r) => {
      const out = _hresult(r);
      const body = out.ok ? out.json : out;
      _hcache.set(date, { at: Date.now(), ok: out.ok, body });
      if (_hcache.size > 400) _hcache.delete(_hcache.keys().next().value);
      res.status(out.ok ? 200 : 502).json(body);
    });
  });
  console.log('[ff-hrmate] /api/settings/hrmate + /api/hrmate/summary mounted');
} catch (e) { console.log('[ff-hrmate] mount error: ' + e.message); }
// --- end ff-hrmate v1 ---
EOF

export FF_DIR="$DIR" FF_MODE="$MODE" FF_TS="$TS" FF_BLOCK="$BLOCK"
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const DIR = process.env.FF_DIR, TS = process.env.FF_TS;
const f = DIR + '/server.js';
if (!fs.existsSync(f)) { console.log('FATAL: ' + f + ' nahi'); process.exit(1); }
let src = fs.readFileSync(f, 'utf8');
const block = fs.readFileSync(process.env.FF_BLOCK, 'utf8').replace(/\s+$/, '') + '\n';
const START = '// --- ff-hrmate v';
const END_RE = /\/\/ --- end ff-hrmate v[0-9]+ ---[ \t]*\n?/;

// 1) identical block already there → nothing to do
if (src.includes(block)) { console.log('CORE: ff-hrmate block present ✓ (identical)'); process.exit(0); }

const bak = f + '.bak-hrmate-' + TS;
fs.copyFileSync(f, bak);
console.log('BACKUP: ' + bak.split('/').pop());

// 2) older/different block → cut it (whole lines)
const si = src.indexOf(START);
if (si >= 0) {
  const em = END_RE.exec(src.slice(si));
  if (em) {
    const ls = src.lastIndexOf('\n', si) + 1;
    const cutEnd = si + em.index + em[0].length;
    src = src.slice(0, ls) + src.slice(cutEnd);
    console.log('CORE: old ff-hrmate block removed (upgrading)');
  }
}

// 3) insert BEFORE the first /api mount (so the core's 404 catch-all never shadows it)
const firstApi = src.match(/^[ \t]*app\.use\(\s*['"]\/api(?:\/|['"])/m);
if (firstApi) {
  src = src.slice(0, firstApi.index) + block + '\n' + src.slice(firstApi.index);
  console.log('CORE: ff-hrmate block mounted BEFORE first /api mount ✓');
} else if (/app\.listen\(/.test(src)) {
  src = src.replace(/app\.listen\(/, block + '\napp.listen(');
  console.log('CORE: koi app.use(\'/api…\') nahi labhya — block app.listen ton pehlan paya (404 order check karo)');
} else { console.log('FATAL: koi anchor nahi (app.use /api ya app.listen)'); process.exit(1); }

fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SERVER: syntax OK ✓'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SERVER: SYNTAX FAIL — restored: ' + String(e.stderr || e).slice(0, 300)); process.exit(1); }
process.exit(3); // 3 = changed
JS
RC=$?
rm -f "$BLOCK"
if [ $RC -eq 1 ]; then echo "HRMATE FAILED (upar dekho)"; exit 1; fi

if [ $RC -eq 3 ] && [ -z "${FF_NO_RESTART:-}" ]; then
  systemctl restart "$SVC" && echo "SERVER: $SVC restarted"
  sleep 6
fi

# ---- verify: route mounted ⇢ 401 (login required), NOT 404 ----
if [ "$MODE" = "saas" ]; then
  node - <<'JS'
const fs = require('fs'), cp = require('child_process');
let reg = {}; try { reg = JSON.parse(fs.readFileSync('/opt/flavorflow-saas/data/registry.json', 'utf8')); } catch (_) {}
let ok = 0, bad = 0, n = 0;
for (const [code, c] of Object.entries(reg.companies || {})) {
  if (!c.port) continue; n++;
  let st = '000';
  try { st = cp.execSync('curl -s -o /dev/null -w "%{http_code}" -m 6 http://127.0.0.1:' + c.port + '/api/settings/hrmate').toString().trim(); } catch (_) {}
  if (st === '401' || st === '200') { ok++; if (ok <= 3) console.log('TENANT ' + code + ' -> ' + st + ' ✓'); }
  else { bad++; console.log('TENANT ' + code + ' -> ' + st + ' ✗'); }
}
console.log('HRMATE tenants: ' + ok + '/' + n + ' route live' + (bad ? ' (' + bad + ' abhi boot ho rahe / fail — 20 s baad dubara check)' : ''));
JS
else
  ST=$(curl -s -o /dev/null -w '%{http_code}' -m 6 http://127.0.0.1:4000/api/settings/hrmate 2>/dev/null)
  echo "FACTORY /api/settings/hrmate -> $ST $( [ "$ST" = 401 ] || [ "$ST" = 200 ] && echo '✓' || echo '✗')"
fi
echo "HRMATE DONE ✓ — app: Settings → HRMATE → Connect (Whole company) — key server te rehndi hai, saare users nu hazri dikhdi hai"
