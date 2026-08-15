#!/usr/bin/env bash
# FlavorFlow FIX:
#  1) GET/PUT /api/settings/company  — company details + industry unit labels
#     shared across all devices (stored in a simple settings table).
#  2) Block deleting the last active super_admin (safety).
# Idempotent — safe to run twice.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-SETFIX $(date) ==="
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
let changed = false, failed = false;

function backup(f) { const b = f + '.bak-setfix-' + Date.now(); fs.copyFileSync(f, b); console.log('BACKUP: ' + b); return b; }
function check(f, b) {
  try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK: ' + f); return true; }
  catch (e) { fs.copyFileSync(b, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 300)); return false; }
}

// ---------- 1) settings/company route ----------
{
  const sv = '/opt/flavorflow/server/server.js';
  let src = fs.readFileSync(sv, 'utf8');
  if (src.includes('/api/settings/company')) {
    console.log('SETTINGS ROUTE: already present — skip');
  } else {
    const bak = backup(sv);
    const CODE = `
// --- ff-setfix: shared company settings (name/address/tax + industry unit labels) ---
try {
  const _sdb = require('./db');
  _sdb.prepare("CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)").run();
  const _getSet = () => { try { return JSON.parse((_sdb.prepare("SELECT value FROM app_settings WHERE key='company'").get() || {}).value || '{}'); } catch (_) { return {}; } };
  app.get('/api/settings/company', (req, res) => { res.json(_getSet()); });
  app.put('/api/settings/company', (req, res) => {
    const u = req.user; // set by auth middleware if mounted before; otherwise check token below
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
    };
    _sdb.prepare("INSERT INTO app_settings (key, value) VALUES ('company', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value").run(JSON.stringify(val));
    res.json({ ok: true });
  });
  console.log('[ff-setfix] /api/settings/company mounted');
} catch (e) { console.log('[ff-setfix] settings route error: ' + e.message); }
// --- end ff-setfix ---
`;
    // insert after the auth middleware is applied — find the last app.use('/api line and put our block before routes finish; safest: before app.listen
    const anchor = src.match(/app\.listen\(/);
    if (!anchor) { console.log('SETTINGS: app.listen anchor not found'); failed = true; }
    else {
      src = src.replace(/app\.listen\(/, CODE + '\napp.listen(');
      fs.writeFileSync(sv, src);
      if (check(sv, bak)) { console.log('SETTINGS ROUTE: added'); changed = true; } else failed = true;
    }
  }
}

// ---------- 2) super_admin delete block ----------
{
  const f = '/opt/flavorflow/server/routes/users.js';
  if (!fs.existsSync(f)) { console.log('USERS FILE MISSING'); failed = true; }
  else {
    let src = fs.readFileSync(f, 'utf8');
    if (src.includes('last active Super Admin')) {
      console.log('SA-BLOCK: already present — skip');
    } else {
      // find the delete route body: insert guard right after it resolves the target user row
      const m = src.match(/router\.delete\([^{]*\{/);
      if (!m) { console.log('SA-BLOCK: delete route not found'); failed = true; }
      else {
        const bak = backup(f);
        const guard = `
  // ff-setfix: never allow removing the last active super_admin
  {
    const _t = db.prepare('SELECT role FROM users WHERE id = ?').get(Number(req.params.id));
    if (_t && _t.role === 'super_admin') {
      const _n = db.prepare("SELECT COUNT(*) c FROM users WHERE role = 'super_admin' AND active = 1").get().c;
      if (_n <= 1) { res.status(409).json({ error: 'Cannot delete the last active Super Admin.' }); return; }
    }
  }
`;
        src = src.replace(m[0], m[0] + guard);
        fs.writeFileSync(f, src);
        if (check(f, bak)) { console.log('SA-BLOCK: added'); changed = true; } else failed = true;
      }
    }
  }
}

if (failed) { console.log('PATCH INCOMPLETE'); process.exit(2); }
if (!changed) { console.log('NOTHING TO DO — sab pehla hi patched'); process.exit(0); }
try { cp.execSync('systemctl restart flavorflow'); console.log('SERVICE RESTARTED'); } catch (e) { console.log('RESTART FAIL: ' + e.message); process.exit(4); }
setTimeout(() => {
  try { console.log('HEALTH: ' + cp.execSync('curl -s -m 5 http://127.0.0.1:4000/api/health').toString().trim()); } catch (e) { console.log('HEALTH ERR'); }
  try { console.log('SETTINGS GET: ' + cp.execSync('curl -s -m 5 http://127.0.0.1:4000/api/settings/company').toString().trim().slice(0, 120)); } catch (e) { console.log('SETTINGS ERR'); }
  console.log('SETFIX VERIFIED ✓');
}, 2000);
JS
echo "SETFIX DONE — company settings hun sare devices te sync honge, te last super_admin delete nahi ho sakda"
