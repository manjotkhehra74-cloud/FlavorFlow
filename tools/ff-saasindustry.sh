#!/usr/bin/env bash
# FlavorFlow INDUSTRY PACKS (server side) — har company nu USDI industry da
# data mile (app side: lib/core/industry_pack.dart):
#   1) gateway (SaaS): tenant spawn te COMPANY_NAME + COMPANY_INDUSTRY env
#      pass — registration form te chuni industry hun tenant tak pahunchdi hai
#   2) core server.js:
#        a) GET/PUT /api/settings/company ensure (ff-setfix wala hi block)
#        b) boot te app_settings 'company' row SEED: {name, industry-id,
#           unit labels} — website da free-text ("Rice / Flour / Feed Mill")
#           → preset id ('mill'); admin ne app ton badli hove ta override NAHI
#        c) POST/PUT /api/packing/materials te body.unit save (hook —
#           route andar kuch vi hove, unit column update ho janda)
#        d) ROUTE ORDER fix: settings route 404 catch-all ton PEHLA mount (nahi ta
#           har tenant te {"error":"Not found"} — app industry kade nahi vekhdi)
#   3) routes/dispatch.js: truck default 'NEEMRANA' hataya — destination
#      hun required (industry-wise defaults app bhejdi hai)
#   SaaS core te vi chaldi hai, factory server te vi (auto-detect).
# Idempotent. Backups + node --check + auto-restore.
set -u
if [ -d /opt/flavorflow-saas/core ]; then DIR=/opt/flavorflow-saas/core; MODE=saas;
elif [ -d /opt/flavorflow/server ]; then DIR=/opt/flavorflow/server; MODE=factory;
else echo "FATAL: koi server dir nahi labhi"; exit 1; fi
echo "=== FF-SAASINDUSTRY ($MODE) $(date) ==="
TS=$(date +%s)
export FF_DIR="$DIR" FF_MODE="$MODE" FF_TS="$TS"

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const DIR = process.env.FF_DIR, MODE = process.env.FF_MODE, TS = process.env.FF_TS;
let failed = false, changed = false;

function backup(f) { const b = f + '.bak-industry-' + TS; fs.copyFileSync(f, b); console.log('BACKUP: ' + b.split('/').pop()); return b; }
function check(f, b) {
  try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK: ' + f.split('/').pop()); return true; }
  catch (e) { fs.copyFileSync(b, f); console.log('SYNTAX FAIL — RESTORED ' + f.split('/').pop() + ': ' + String(e.stderr || e).slice(0, 300)); failed = true; return false; }
}

// ---------- 1) gateway: pass company name + industry to tenant process ----------
if (MODE === 'saas') {
  const g = '/opt/flavorflow-saas/server/server.js';
  if (!fs.existsSync(g)) { console.log('GATEWAY: server.js missing — skip'); }
  else {
    let src = fs.readFileSync(g, 'utf8');
    if (src.includes('/* ffIndustry */')) console.log('GATEWAY: already ✓');
    else {
      const anchor = src.match(/\n(\s*)const p = spawn\('node'/);
      if (!anchor) { console.log('GATEWAY: spawn anchor nahi labhya'); failed = true; }
      else {
        const bak = backup(g);
        const ind = anchor[1];
        src = src.replace(anchor[0],
          '\n' + ind + "/* ffIndustry */ env.COMPANY_NAME = c.name || ''; env.COMPANY_INDUSTRY = c.industry || '';" + anchor[0]);
        fs.writeFileSync(g, src);
        if (check(g, bak)) { console.log('GATEWAY: industry env ✓'); changed = true; }
      }
    }
  }
}

// ---------- 2) core server.js ----------
{
  const sv = DIR + '/server.js';
  let src = fs.readFileSync(sv, 'utf8');
  const bak = backup(sv);
  let touched = false;

  // 2a) settings route (same shape as ff-setfix) — only if absent
  if (!src.includes('/api/settings/company')) {
    const CODE = `
// --- ff-setfix: shared company settings (name/address/tax + industry unit labels) ---
try {
  const _sdb = require('./db');
  _sdb.prepare("CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)").run();
  const _getSet = () => { try { return JSON.parse((_sdb.prepare("SELECT value FROM app_settings WHERE key='company'").get() || {}).value || '{}'); } catch (_) { return {}; } };
  app.get('/api/settings/company', (req, res) => { res.json(_getSet()); });
  app.put('/api/settings/company', (req, res) => {
    const u = req.user;
    if (!u || (u.role !== 'super_admin' && u.role !== 'admin')) { res.status(403).json({ error: 'Only Admin/Super Admin can change company settings.' }); return; }
    const b = req.body || {};
    const val = {
      name: String(b.name || '').slice(0, 120),
      address: String(b.address || '').slice(0, 200),
      taxLine: String(b.taxLine || '').slice(0, 200),
      industry: String(b.industry || 'food').slice(0, 40),
      cartonLabel: String(b.cartonLabel || 'Cartons').slice(0, 30),
      cartonShort: String(b.cartonShort || 'CB').slice(0, 12),
      trayLabel: String(b.trayLabel || 'Trays').slice(0, 30),
      pieceLabel: String(b.pieceLabel || 'Bottles').slice(0, 30),
      industryConfirmed: true,
    };
    _sdb.prepare("INSERT INTO app_settings (key, value) VALUES ('company', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value").run(JSON.stringify(val));
    res.json({ ok: true });
  });
  console.log('[ff-setfix] /api/settings/company mounted');
} catch (e) { console.log('[ff-setfix] settings route error: ' + e.message); }
// --- end ff-setfix ---
`;
    if (!/app\.listen\(/.test(src)) { console.log('CORE: app.listen anchor nahi labhya'); failed = true; }
    else { src = src.replace(/app\.listen\(/, CODE + '\napp.listen('); touched = true; console.log('CORE: settings route added'); }
  } else {
    console.log('CORE: settings route present ✓');
    // admin's explicit PUT marks the industry as confirmed (boot seed then never overrides)
    if (!src.includes('industryConfirmed')) {
      const m = src.match(/pieceLabel: String\(b\.pieceLabel \|\| 'Bottles'\)\.slice\(0, 30\),/);
      if (m) { src = src.replace(m[0], m[0] + '\n      industryConfirmed: true,'); touched = true; console.log('CORE: PUT marks industryConfirmed ✓'); }
      else console.log('CORE: PUT shape different — industryConfirmed flag skipped (seed still safe: only fills empty/unknown)');
    }
  }

  // 2b) boot seed from env (SaaS) + normalise free-text industry → preset id
  //     v3: researched secondary units (Crates / Dozens / Packs / Inner Boxes) + legacy
  //     tray-name migration. An older seed block (no 'v3' marker) is cut out and
  //     re-inserted so live servers pick up new presets / industries too.
  const SEED_END = "} catch (e) { console.log('[ff-industry] seed error: ' + e.message); }";
  if (src.includes('/* ffIndustrySeed */') && !src.includes('/* ffIndustrySeed v3 */')) {
    const a = src.indexOf('/* ffIndustrySeed */');
    const e = src.indexOf(SEED_END, a);
    if (e > a) {
      const ls = src.lastIndexOf('\n', a) + 1;
      const le = src.indexOf('\n', e); const cutEnd = le < 0 ? src.length : le + 1;
      src = src.slice(0, ls) + src.slice(cutEnd);
      touched = true;
      console.log('CORE: old industry boot-seed removed (pre-v3) — re-inserting');
    } else console.log('CORE: old boot-seed end marker nahi labhya — block left as is');
  }
  if (!src.includes('/* ffIndustrySeed */')) {
    const SEED = `
/* ffIndustrySeed */ /* ffIndustrySeed v3 */
try {
  const _idb = require('./db');
  _idb.prepare("CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)").run();
  const PRESETS = {
    food: ['Cartons', 'CB', 'Trays', 'Bottles'], dairy: ['Crates', 'Crate', 'Trays', 'Packets'], oil: ['Cartons', 'CB', 'Trays', 'Tins'],
    bakery: ['Cartons', 'CB', 'Trays', 'Packets'], water: ['Cases', 'Case', 'Crates', 'Bottles'], soap: ['Cartons', 'CB', 'Trays', 'Bars'],
    cosmetics: ['Cartons', 'CB', 'Trays', 'Units'], paint: ['Cartons', 'CB', 'Trays', 'Tins'], agro: ['Cartons', 'CB', 'Trays', 'Bottles'],
    pharma: ['Boxes', 'Box', 'Strips', 'Units'], textile: ['Bales', 'Bale', 'Dozens', 'Pieces'], mill: ['Bags', 'Bag', 'Stacks', 'KG'],
    footwear: ['Cartons', 'CB', 'Dozens', 'Pairs'], plastic: ['Cartons', 'CB', 'Packs', 'Pieces'], hardware: ['Cartons', 'CB', 'Inner Boxes', 'Pieces'],
    general: ['Cartons', 'CB', 'Trays', 'Pieces'],
  };
  const KEYS = {
    mill: ['rice', 'flour', 'atta', 'feed', 'mill', 'grain', 'dal', 'pulse', 'sheller', 'chakki'],
    dairy: ['dairy', 'milk', 'ghee', 'paneer', 'curd', 'butter', 'cheese', 'ice cream'],
    oil: ['oil', 'mustard', 'refinery', 'kachi ghani', 'vanaspati'],
    bakery: ['bakery', 'biscuit', 'snack', 'namkeen', 'confection', 'chips', 'bread', 'cookie', 'sweet'],
    water: ['water', 'beverage', 'juice', 'soda', 'drink', 'cold drink'],
    soap: ['soap', 'detergent', 'washing', 'cleaner', 'phenyl'],
    cosmetics: ['cosmetic', 'personal care', 'shampoo', 'cream', 'hair', 'herbal care'],
    paint: ['paint', 'lubricant', 'grease', 'varnish', 'coating', 'thinner'],
    agro: ['agro', 'fertilizer', 'pesticide', 'seed', 'crop', 'insecticide', 'bio'],
    pharma: ['pharma', 'ayurved', 'medicine', 'tablet', 'syrup', 'capsule', 'drug', 'nutra'],
    textile: ['textile', 'hosiery', 'garment', 'yarn', 'fabric', 'knit', 'cloth', 'shawl', 'apparel'],
    footwear: ['footwear', 'shoe', 'chappal', 'slipper', 'sandal', 'boot'],
    plastic: ['plastic', 'packaging', 'polymer', 'pouch', 'film', 'mould', 'pvc', 'pipe'],
    hardware: ['utensil', 'hardware', 'steel', 'fastener', 'tool', 'bolt', 'cycle', 'auto part', 'machine', 'forging', 'casting', 'metal'],
    food: ['food', 'sauce', 'ketchup', 'pickle', 'spice', 'masala', 'condiment', 'jam', 'vinegar', 'noodle', 'tea', 'coffee', 'flavour', 'flavor', 'honey', 'papad'],
  };
  const LABELS = {
    'food & beverage': 'food', 'dairy': 'dairy', 'edible oil': 'oil', 'bakery & snacks': 'bakery', 'beverages / water': 'water',
    'soap & detergent': 'soap', 'cosmetics & personal care': 'cosmetics', 'paint & lubricants': 'paint', 'agro-chemicals & fertilizer': 'agro',
    'pharma / ayurvedic': 'pharma', 'textile / hosiery': 'textile', 'rice / flour / feed mill': 'mill', 'footwear': 'footwear',
    'plastic & packaging': 'plastic', 'utensils & hardware': 'hardware', 'general manufacturing': 'general',
  };
  const industryId = (raw) => {
    const v = String(raw || '').trim().toLowerCase().replace(/[ ]+/g, ' ');
    if (!v) return '';
    if (PRESETS[v]) return v;
    if (LABELS[v]) return LABELS[v];
    for (const id of Object.keys(KEYS)) for (const k of KEYS[id]) if (v.includes(k)) return id;
    return 'general';
  };
  const row = (() => { try { return JSON.parse((_idb.prepare("SELECT value FROM app_settings WHERE key='company'").get() || {}).value || '{}'); } catch (_) { return {}; } })();
  const envId = industryId(process.env.COMPANY_INDUSTRY);
  const curId = industryId(row.industry);
  let next = null;
  if (envId && (!row.industry || !PRESETS[String(row.industry)] || (curId !== envId && !row.industryConfirmed))) {
    next = { ...row, name: row.name || process.env.COMPANY_NAME || '', industry: envId };
  } else if (row.industry && !PRESETS[String(row.industry)]) {
    next = { ...row, industry: curId || 'general' };
  }
  /* ffTrayFix: secondary-unit names the OLD presets seeded (beverage "Shells", hosiery "Rolls",
     footwear "Racks", plastic / hardware "Trays") were never typed by an admin — move them to the
     researched trade unit (Crates / Dozens / Packs / Inner Boxes). Admin-typed names stay. */
  const LEGACY_TRAY = { water: ['Shells'], textile: ['Rolls'], footwear: ['Racks'], plastic: ['Trays'], hardware: ['Trays'] };
  const cur = next || row;
  if (!next && PRESETS[String(cur.industry)] && (LEGACY_TRAY[cur.industry] || []).includes(String(cur.trayLabel || ''))) {
    next = { ...row, trayLabel: PRESETS[cur.industry][2] };
    console.log('[ff-industry] tray unit ' + cur.trayLabel + ' -> ' + next.trayLabel + ' (' + cur.industry + ')');
  }
  if (next) {
    const u = PRESETS[next.industry] || PRESETS.general;
    next.cartonLabel = u[0]; next.cartonShort = u[1]; next.trayLabel = u[2]; next.pieceLabel = u[3];
    next.address = next.address || ''; next.taxLine = next.taxLine || '';
    _idb.prepare("INSERT INTO app_settings (key, value) VALUES ('company', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value").run(JSON.stringify(next));
    console.log('[ff-industry] company industry set: ' + next.industry + ' (' + (next.name || '-') + ')');
  }
} catch (e) { console.log('[ff-industry] seed error: ' + e.message); }
`;
    if (!/app\.listen\(/.test(src)) { console.log('CORE: app.listen anchor nahi labhya (seed)'); failed = true; }
    else { src = src.replace(/app\.listen\(/, SEED + '\napp.listen('); touched = true; console.log('CORE: industry boot-seed added'); }
  } else console.log('CORE: industry boot-seed present ✓');

  // 2d) ROUTE ORDER — ff-setfix block was inserted right before app.listen(; if the
  //     server's 404 catch-all (res.status(404)…'Not found') sits above it, Express never
  //     reaches GET/PUT /api/settings/company → app gets {"error":"Not found"} and silently
  //     falls back to phone-local settings (industry never arrives from the server).
  //     Fix: drop the old block, re-insert a v2 block BEFORE the first /api mount
  //     (own express.json() + authRequired, so position no longer matters).
  {
    const START = '// --- ff-setfix: shared company settings';
    const END = '// --- end ff-setfix ---';
    const V2 = '// --- ff-setfix v2 (early mount): shared company settings ---';
    const firstApi = src.match(/^[ \t]*app\.use\(\s*['"]\/api(?:\/|['"])/m);
    const has404 = /404/.test(src);
    if (src.includes(V2)) console.log('CORE: settings route early-mounted ✓');
    else if (!firstApi) console.log('CORE: koi app.use(\'/api/…\') mount nahi labhya — route order unchanged (agar 404 aave ta server.js bhejo)');
    else {
      const si = src.indexOf(START), ei = src.indexOf(END);
      if (si >= 0 && ei > si) {
        // cut old block (whole lines)
        const ls = src.lastIndexOf('\n', si) + 1;
        const le = src.indexOf('\n', ei); const cutEnd = le < 0 ? src.length : le + 1;
        src = src.slice(0, ls) + src.slice(cutEnd);
        console.log('CORE: old settings block removed (was ' + (has404 ? 'below the 404 handler' : 'late') + ')');
      }
      const ROUTE = `
${V2}
try {
  const _sdb = require('./db');
  _sdb.prepare("CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)").run();
  const _getSet = () => { try { return JSON.parse((_sdb.prepare("SELECT value FROM app_settings WHERE key='company'").get() || {}).value || '{}'); } catch (_) { return {}; } };
  const _mw = (() => { try { return require('./middleware'); } catch (_) { return {}; } })();
  const _auth = typeof _mw.authRequired === 'function' ? _mw.authRequired : ((req, res, next) => next());
  app.get('/api/settings/company', (req, res) => { res.json(_getSet()); });
  app.put('/api/settings/company', require('express').json({ limit: '50kb' }), _auth, (req, res) => {
    const u = req.user;
    if (!u || (u.role !== 'super_admin' && u.role !== 'admin')) { res.status(403).json({ error: 'Only Admin/Super Admin can change company settings.' }); return; }
    const b = req.body || {};
    const prev = _getSet();
    const val = {
      name: String(b.name || prev.name || '').slice(0, 120),
      address: String(b.address || '').slice(0, 200),
      taxLine: String(b.taxLine || '').slice(0, 200),
      industry: String(b.industry || prev.industry || 'general').slice(0, 40),
      cartonLabel: String(b.cartonLabel || 'Cartons').slice(0, 30),
      cartonShort: String(b.cartonShort || 'CB').slice(0, 12),
      trayLabel: String(b.trayLabel || 'Trays').slice(0, 30),
      pieceLabel: String(b.pieceLabel || 'Bottles').slice(0, 30),
      industryConfirmed: true,
    };
    _sdb.prepare("INSERT INTO app_settings (key, value) VALUES ('company', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value").run(JSON.stringify(val));
    res.json({ ok: true });
  });
  console.log('[ff-setfix] /api/settings/company mounted (early)');
} catch (e) { console.log('[ff-setfix] settings route error: ' + e.message); }
// --- end ff-setfix v2 ---
`;
      const m2 = src.match(/^[ \t]*app\.use\(\s*['"]\/api(?:\/|['"])/m);   // re-match after the cut
      src = src.slice(0, m2.index) + ROUTE + '\n' + src.slice(m2.index);
      touched = true;
      console.log('CORE: settings route re-mounted BEFORE first /api mount ✓ (404 shadow fixed)');
    }
  }

  // 2c) materials unit hook — saves body.unit on POST/PUT /api/packing/materials
  if (!src.includes('/* ffMaterialUnit */')) {
    const HOOK = `
/* ffMaterialUnit */
app.use('/api/packing/materials', (req, res, next) => {
  try {
    if ((req.method === 'POST' || req.method === 'PUT') && req.body && typeof req.body.unit === 'string' && req.body.unit.trim()) {
      const unit = req.body.unit.trim().slice(0, 12);
      const name = String(req.body.name || '').trim();
      const id = req.method === 'PUT' ? Number((req.path || '').split('/').filter(Boolean)[0]) : 0;
      res.on('finish', () => {
        if (res.statusCode >= 300) return;
        try {
          const _udb = require('./db');
          if (id) _udb.prepare('UPDATE packing_materials SET unit = ? WHERE id = ?').run(unit, id);
          else if (name) {
            const r = _udb.prepare('SELECT id FROM packing_materials WHERE name = ? ORDER BY id DESC LIMIT 1').get(name);
            if (r) _udb.prepare('UPDATE packing_materials SET unit = ? WHERE id = ?').run(unit, r.id);
          }
        } catch (e) { console.log('[ff-industry] unit save: ' + e.message); }
      });
    }
  } catch (_) {}
  next();
});
`;
    let m = src.match(/\n(\s*)app\.use\(['"]\/api\/packing['"]/);
    if (!m) m = src.match(/\n(\s*)app\.use\(['"]\/api\//);
    if (!m) console.log('CORE: koi app.use(/api/...) anchor nahi — unit hook skipped (app fallback: unit default rahega)');
    else { src = src.replace(m[0], '\n' + HOOK + m[0]); touched = true; console.log('CORE: materials unit hook added'); }
  } else console.log('CORE: materials unit hook present ✓');

  if (touched) { fs.writeFileSync(sv, src); if (check(sv, bak)) changed = true; }
  else { try { fs.unlinkSync(bak); } catch (_) {} }
}

// ---------- 3) dispatch.js: no hard-coded NEEMRANA default ----------
{
  const f = DIR + '/routes/dispatch.js';
  if (!fs.existsSync(f)) console.log('DISPATCH: routes/dispatch.js missing — skip');
  else {
    let src = fs.readFileSync(f, 'utf8');
    if (!src.includes("'NEEMRANA'")) console.log('DISPATCH: no NEEMRANA default ✓');
    else {
      const bak = backup(f);
      src = src.replace(/String\(b\.destination \|\| 'NEEMRANA'\)/g, "String(b.destination || '')");
      src = src.replace(/if \(!number\) throw bad\('Truck number is required\.'\);/,
        "if (!number) throw bad('Truck number is required.');\n  if (!destination) throw bad('Destination is required.');");
      src = src.replace(/'NEEMRANA'/g, "''");
      fs.writeFileSync(f, src);
      if (check(f, bak)) { console.log('DISPATCH: NEEMRANA default removed ✓'); changed = true; }
    }
  }
}

if (failed) { console.log('PATCH INCOMPLETE — kuch step fail (upar dekho); jo pass hoye oh lag gaye'); process.exit(2); }
if (!changed) { console.log('NOTHING TO DO — sab pehla hi patched'); process.exit(0); }
process.exit(0);
JS
RC=$?
[ $RC -eq 2 ] && echo "SAASINDUSTRY: partial — fer vi restart karke check karde haan"

if [ "$MODE" = "saas" ]; then systemctl restart flavorflow-saas; else systemctl restart flavorflow; fi
sleep 5
if [ "$MODE" = "saas" ]; then
  curl -s -m 8 http://127.0.0.1:4100/api/saas/health && echo ""
  node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const reg = JSON.parse(fs.readFileSync('/opt/flavorflow-saas/data/registry.json', 'utf8'));
for (const [code, c] of Object.entries(reg.companies || {})) {
  let out = '';
  try { out = cp.execSync('curl -s -m 6 http://127.0.0.1:' + c.port + '/api/settings/company').toString().trim().slice(0, 160); } catch (e) { out = 'ERR'; }
  console.log('TENANT ' + code + ' [' + (c.industry || '-') + '] -> ' + out);
}
JS
else
  curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health
  curl -s -m 6 http://127.0.0.1:4000/api/settings/company | head -c 200; echo ""
fi
echo "SAASINDUSTRY DONE ✓ — har tenant di /api/settings/company hun industry id deve (app ohde hisaab naal units/categories/destinations dikhaugi)"
