// ff-timefix: Indian wall-clock timestamps (UTC+5:30), same ISO shape as before
/* ffDedup: notifyRoles off */ function notifyRoles() { /* superseded by broadcast/coverage */ }
/* ffDedup: disabled */ function ffBroadcast() { /* coverage handles notifications */ }
function istNow() { return new Date(Date.now() + 330 * 60 * 1000); }
/** helpers.js — shared utilities: dates, codes, weights, audit trail, notifications. */

const round2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;

/** SQLite-friendly UTC timestamp: 'YYYY-MM-DD HH:MM:SS' */
function nowIso() {
  return istNow().toISOString().replace('T', ' ').replace(/\..+$/, '');
}

function daysFromNowIso(days) {
  const d = new Date(Date.now() + days * 24 * 60 * 60 * 1000);
  return d.toISOString().replace('T', ' ').replace(/\..+$/, '');
}

function dateOnly(iso) {
  return (iso || '').slice(0, 10);
}

const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/** 'Monday' for a 'YYYY-MM-DD...' date string. */
function weekdayName(dateStr) {
  const d = String(dateStr || '').slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return '';
  return DAYS[new Date(`${d}T00:00:00Z`).getUTCDay()];
}

/**
 * Per-line dispatch weight maths — the single source of truth.
 * Units per line: cartons (CB) and trays (tray-enabled products only).
 */
function calcLine(product, cartons, trays) {
  const cb = Math.max(0, Math.floor(Number(cartons) || 0));
  const tr = Math.max(0, Math.floor(Number(trays) || 0));
  const cartonWeight = round2(cb * product.weight_per_cb);
  const trayWeight = round2(tr * (product.tray_weight || 0));
  const grossWeight = round2(cartonWeight + trayWeight);
  const totalBottles = cb * product.bottles_per_cb + tr * (product.bottles_per_tray || 0);
  return { cartons: cb, trays: tr, cartonWeight, trayWeight, grossWeight, totalBottles };
}

/** Audit trail row. Every mutating endpoint calls this. */
function _auditCore(db, user, action, entity, entityId, details) {
  db.prepare(
    `INSERT INTO audit_logs (user_id, user_name, role, action, entity, entity_id, details, created_at)
     VALUES (?,?,?,?,?,?,?,?)`
  ).run(user ? user.id : null, user ? user.name : 'system', user ? user.role : 'system', action, entity, String(entityId ?? ''), details || '', nowIso());
}

/** Create one notification row per active user belonging to the given roles. */
function notifyRoles_disabled_(db, roles, { type, title, body, route, refId }) {
  const users = db.prepare(`SELECT id FROM users WHERE active = 1 AND role IN (${roles.map(() => '?').join(',')})`).all(...roles);
  notifyUsers(db, users.map((u) => u.id), { type, title, body, route, refId });
}

/** Create one notification row per given user id. */
function notifyUsers(db, userIds, { type, title, body, route, refId }) {
  const stmt = db.prepare(
    `INSERT INTO notifications (user_id, type, title, body, route, ref_id, is_read, created_at)
     VALUES (?,?,?,?,?,?,0,?)`
  );
  for (const uid of userIds) {
    stmt.run(uid, type, title, body || '', route || '/notifications', refId != null ? String(refId) : null, nowIso());
  }
}

/**
 * Low-stock watchdog for finished goods — call after any inventory mutation.
 * Skips duplicates while an unread alert for the same product exists.
 */
function checkLowStock(db, productId) {
  const row = db.prepare(
    `SELECT p.id, p.name, p.min_stock_cb, i.qty_cb FROM products p
     JOIN inventory i ON i.product_id = p.id WHERE p.id = ?`
  ).get(productId);
  if (!row) return;
  if (row.qty_cb >= row.min_stock_cb) return;

  emitOncePerUser(db, 'low_stock', String(row.id),
    ['store_manager', 'store_keeper', 'admin', 'super_admin'],
    {
      title: `Low stock: ${row.name}`,
      body: `Only ${row.qty_cb} CB left (minimum ${row.min_stock_cb} CB). Tap to open Inventory.`,
      route: '/inventory?filter=low',
    });
}

/** Low-stock watchdog for packing materials. */
function checkPackingLow(db, materialId) {
  const m = db.prepare('SELECT id, name, stock, min_stock FROM packing_materials WHERE id = ?').get(materialId);
  if (!m) return;
  if (m.stock >= m.min_stock) return;

  emitOncePerUser(db, 'packing_low', String(m.id),
    ['store_manager', 'store_keeper', 'admin', 'super_admin'],
    {
      title: `Low packing stock: ${m.name}`,
      body: `Only ${m.stock} pcs left (minimum ${m.min_stock}). Tap to open Packing Material.`,
      route: '/packing?filter=low',
    });
}

function emitOncePerUser(db, type, refId, roles, { title, body, route }) {
  const targets = db.prepare(
    `SELECT id FROM users WHERE active = 1 AND role IN (${roles.map(() => '?').join(',')})`
  ).all(...roles);
  const existsStmt = db.prepare(
    `SELECT COUNT(*) c FROM notifications WHERE user_id = ? AND type = ? AND ref_id = ? AND is_read = 0`
  );
  const insertStmt = db.prepare(
    `INSERT INTO notifications (user_id, type, title, body, route, ref_id, is_read, created_at)
     VALUES (?,?,?,?,?,?,0,?)`
  );
  for (const u of targets) {
    if (existsStmt.get(u.id, type, refId).c > 0) continue;
    insertStmt.run(u.id, type, title, body, route, refId, nowIso());
  }
}


/* ff-notifyfix: every audited action notifies every active user (except the
   actor). Logins and Packing Loss % sheet edits are excluded. */
let _ffNotifCols = null;
function ffBroadcast_disabled_(db, user, action, entity, refId, detail) {
  if (!user || !user.id) return;
  if (String(action).toUpperCase() === 'LOGIN') return;
  const d = String(detail || '');
  if (/^Loss (sheet|month)/i.test(d)) return; // Packing Loss % excluded
  if (!_ffNotifCols) {
    try { _ffNotifCols = db.prepare('PRAGMA table_info(notifications)').all().map((c) => c.name); }
    catch (_) { _ffNotifCols = []; }
  }
  if (!_ffNotifCols.includes('user_id')) return;
  const routes = {
    adjustment: '/adjustments', dispatch: '/dispatch', batch: '/production',
    user: '/users', product: '/products', inventory: '/inventory',
    packing: '/packing', report: '/reports', system: '/settings',
  };
  const title = (user.name || 'Someone') + ' · ' + String(action).toLowerCase() + ' ' + String(entity || '');
  const body = d.length > 220 ? d.slice(0, 217) + '...' : d;
  const nowFn = (typeof istNow === 'function') ? istNow : (typeof nowIso === 'function') ? nowIso : () => new Date().toISOString();
  const now = nowFn();
  const vals = {
    user_id: 0, type: 'activity', title, body,
    route: routes[String(entity)] || '/notifications',
    entity: String(entity || ''), ref_id: Number(refId) || 0,
    is_read: 0, created_at: now,
  };
  const names = Object.keys(vals).filter((k) => _ffNotifCols.includes(k));
  if (!names.includes('user_id') || !names.includes('title')) return;
  const ins = db.prepare('INSERT INTO notifications (' + names.join(',') + ') VALUES (' + names.map(() => '?').join(',') + ')');
  const targets = db.prepare('SELECT id FROM users WHERE active = 1 AND id <> ?').all(user.id);
  for (const t of targets) {
    vals.user_id = t.id;
    try { ins.run(...names.map((k) => vals[k])); } catch (_) {}
  }
}
function audit(...args) {
  _auditCore(...args);
  /* ff-notifycoverage4-audit-disabled: global middleware broadcasts once. */
}

module.exports = {
  round2, nowIso, daysFromNowIso, dateOnly, weekdayName,
  calcLine, audit, notifyRoles, notifyUsers, checkLowStock, checkPackingLow,
};
