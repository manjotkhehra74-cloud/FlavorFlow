/** server.js — FlavorFlow ERP API. Express + SQLite with strict per-endpoint RBAC. */
const path = require('path');
const fs = require('fs');
const express = require('express');
const cors = require('cors');

const { authRequired, errorHandler } = require('./middleware');
const db = require('./db'); // also migrates + seeds

const app = express();
if (process.env.TRUST_PROXY === '1') app.set('trust proxy', 1); // behind Caddy/nginx on the cloud
app.use(cors());
app.use(express.json({ limit: '1mb' }));


/* routes */
app.get('/api/health', (req, res) => res.json({ ok: true, service: 'flavorflow-erp', time: new Date().toISOString() }));
// ff-notifycoverage4-middleware: must be before API routes.
app.use(require('./notify_all'));
/* ffNavPerms */ try { app.use(require('./navperms').middleware); console.log('[ff-dispatchfix] menu-from-permissions mounted'); } catch (e) { console.log('[ff-dispatchfix] navperms mount error: ' + e.message); }
/* ffBilling */ try { app.use('/api/billing', require('./routes/billing')); console.log('[ff-billing] /api/billing mounted'); } catch (e) { console.log('[ff-billing] mount error: ' + e.message); }
app.use('/api/auth', require('./routes/auth'));
app.use('/api/dashboard', authRequired, require('./routes/dashboard'));
app.use('/api/products', authRequired, require('./routes/products'));
app.use('/api/inventory', authRequired, require('./routes/inventory'));
app.use('/api/drums', authRequired, require('./routes/drums'));
app.use('/api/packing', authRequired, require('./routes/packing'));
app.use('/api/adjustments', authRequired, require('./routes/adjustments'));
app.use('/api/production', authRequired, require('./routes/production'));
app.use('/api/dispatch', authRequired, require('./routes/dispatch'));
app.use('/api/notifications', authRequired, require('./routes/notifications'));
app.use('/api/users', authRequired, require('./routes/users'));
app.use('/api/reports', authRequired, require('./routes/reports'));
app.use('/api/audit', authRequired, require('./routes/audit'));

app.use('/api', (req, res) => res.status(404).json({ error: 'Not found' }));

/* Serve the web build when present (same-origin deployment).
   Supports the ready-to-run package layout (web/) and the Flutter dev layout (app/build/web). */
const webCandidates = [
  process.env.WEB_DIR,
  path.join(__dirname, '..', 'web'),
  path.join(__dirname, '..', 'app', 'build', 'web'),
].filter(Boolean);
const webBuild = webCandidates.find((p) => fs.existsSync(path.join(p, 'index.html')));
// Block the legacy request-body log path even if an old file remains on disk.
app.use('/ff-requests.txt', (_req, res) => res.sendStatus(404));
if (webBuild) {
  app.use(express.static(webBuild));
  app.get('*', (req, res) => res.sendFile(path.join(webBuild, 'index.html')));
  console.log(`[server] serving web app from ${webBuild}`);
}

app.use(errorHandler);

const PORT = Number(process.env.PORT || 4000);
const HOST = process.env.HOST || '0.0.0.0'; // cloud: 127.0.0.1 behind HTTPS proxy · LAN: 0.0.0.0

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

if (require.main === module) {
  app.listen(PORT, HOST, () => {
    console.log(`[server] FlavorFlow ERP API listening on http://${HOST}:${PORT}`);
    console.log('[server] currency: INR (₹) — Indian formatting on client');
  });
}

module.exports = { app, db };
