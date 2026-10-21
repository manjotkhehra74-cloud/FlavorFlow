'use strict';
/* ff-notifycoverage4: permission-independent notification coverage. */
const db = require('./db');
let columns;

function nowIso() {
  try {
    const h = require('./helpers');
    if (typeof h.istNow === 'function') return h.istNow();
    if (typeof h.nowIso === 'function') return h.nowIso();
  } catch (_) {}
  return new Date().toISOString();
}

function cleanPath(req) {
  return String(req.originalUrl || req.url || '').split('?')[0];
}

function sectionFor(path) {
  if (/\/packing\/(recipes?|recipe-consume)/i.test(path) || /^\/api\/raw(?:\/|$)/i.test(path)) {
    return {label: 'Raw Material', entity: 'packing', route: '/raw'};
  }
  const first = path.replace(/^\/api\//, '').split('/')[0].toLowerCase();
  const map = {
    products: ['Product Master', 'product', '/products'],
    inventory: ['Inventory', 'inventory', '/inventory'],
    drums: ['Drum Stock', 'inventory', '/drums'],
    packing: ['Packing Material', 'packing', '/packing'],
    production: ['Production', 'batch', '/production'],
    dispatch: ['Dispatch', 'dispatch', '/dispatch'],
    adjustments: ['Stock Adjustments', 'adjustment', '/adjustments'],
    approvals: ['Approvals', 'adjustment', '/approvals'],
    users: ['User Management', 'user', '/users'],
    reports: ['Reports', 'report', '/reports'],
    settings: ['Settings', 'system', '/settings'],
    auth: ['Security Settings', 'system', '/settings'],
  };
  const row = map[first] || ['ERP', first || 'system', '/notifications'];
  return {label: row[0], entity: row[1], route: row[2]};
}

function actionFor(method, path) {
  if (/approve/i.test(path)) return 'APPROVE';
  if (/reject/i.test(path)) return 'REJECT';
  if (/dispatch/i.test(path) && /complete|confirm|send/i.test(path)) return 'DISPATCH';
  if (/complete|close/i.test(path)) return 'COMPLETE';
  if (/start/i.test(path)) return 'START';
  if (/receive|receipt/i.test(path)) return 'RECEIVE';
  if (/consume/i.test(path)) return 'CONSUME';
  if (method === 'DELETE') return 'DELETE';
  if (method === 'PUT' || method === 'PATCH') return 'UPDATE';
  return 'CREATE';
}

function shouldSkip(req) {
  const method = String(req.method || '').toUpperCase();
  if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(method)) return true;
  const path = cleanPath(req);
  if (/\/api\/auth\/login(?:\/|$)/i.test(path)) return true; // explicit LOGIN exclusion
  if (/\/loss(?:\/|$)/i.test(path)) return true; // explicit Loss% exclusion
  if (/\/api\/notifications(?:\/|$)/i.test(path)) return true; // read/unread controls are not entries
  return false;
}

function usefulReference(body) {
  if (!body || typeof body !== 'object') return '';
  const safeKeys = ['name', 'code', 'batch_code', 'batchCode', 'number', 'reference', 'destination', 'status', 'date', 'txn_date'];
  for (const key of safeKeys) {
    const value = body[key];
    if (typeof value === 'string' && value.trim()) return value.trim().slice(0, 100);
    if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  }
  return '';
}

function broadcast(req) {
  if (shouldSkip(req)) return 0;
  const user = req.user;
  if (!user || !user.id) return 0;

  if (!columns) columns = db.prepare('PRAGMA table_info(notifications)').all().map((c) => c.name);
  if (!columns.includes('user_id') || !columns.includes('title')) {
    throw new Error('notifications table must contain user_id and title');
  }

  const path = cleanPath(req);
  const method = String(req.method || '').toUpperCase();
  const section = sectionFor(path);
  const action = actionFor(method, path);
  const ref = usefulReference(req.body);
  const actor = String(user.name || user.email || 'User');
  const title = `${actor} · ${action.toLowerCase()} ${section.label}`;
  const body = ref ? `${section.label}: ${ref}` : `${section.label} entry saved successfully.`;
  const id = Number((req.params || {}).id) || 0;
  const created = nowIso();
  const values = {
    user_id: 0,
    type: 'activity',
    title,
    body,
    message: body,
    route: section.route,
    entity: section.entity,
    ref_id: id,
    is_read: 0,
    read: 0,
    created_at: created,
  };
  const names = Object.keys(values).filter((name) => columns.includes(name));
  const insert = db.prepare(`INSERT INTO notifications (${names.join(',')}) VALUES (${names.map(() => '?').join(',')})`);

  // Intentionally no role/permission join or filter: every active user means
  // every active user, even when they cannot open the related section.
  const targets = db.prepare('SELECT id FROM users WHERE active = 1 ORDER BY id').all();
  let inserted = 0;
  const errors = [];
  for (const target of targets) {
    values.user_id = target.id;
    try {
      insert.run(...names.map((name) => values[name]));
      inserted++;
    } catch (e) {
      errors.push(`user ${target.id}: ${e.message}`);
    }
  }
  if (errors.length) throw new Error(`notification inserts failed (${errors.join('; ')})`);
  return inserted;
}

function middleware(req, res, next) {
  if (!shouldSkip(req)) {
    res.once('finish', () => {
      if (res.statusCode >= 200 && res.statusCode < 400) {
        try {
          const count = broadcast(req);
          if (count) console.log(`[notify-all] ${req.method} ${cleanPath(req)} -> ${count} users`);
        } catch (e) {
          console.error(`[notify-all] FAILED ${req.method} ${cleanPath(req)}: ${e.message}`);
        }
      }
    });
  }
  next();
}

middleware._broadcast = broadcast;
middleware._shouldSkip = shouldSkip;
module.exports = middleware;
