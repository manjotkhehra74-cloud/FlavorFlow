#!/usr/bin/env bash
# FlavorFlow notification coverage fix 3
# Captures every successful data-changing HTTP request at server level instead
# of relying on individual routes to remember audit(). Every active user is a
# target; role/permissions are deliberately NOT consulted.
# Excludes failed requests, LOGIN, Loss%, and notification read-state actions.
# Idempotent; file + DB backups; mock patch test; DB rollback probe;
# node --check; service/health verification; automatic restore on failure.
set -euo pipefail

ROOT="${FF_ROOT:-/opt/flavorflow/server}"
BACKUP_ROOT="${FF_BACKUP_ROOT:-/opt/flavorflow/backups}"
SERVICE="${FF_SERVICE:-flavorflow}"
SKIP_SERVICE="${FF_SKIP_SERVICE:-0}"

cd "$ROOT" || { echo "FATAL: $ROOT nahi mili"; exit 1; }
[ -f server.js ] || { echo "FATAL: server.js nahi mili"; exit 1; }
[ -f helpers.js ] || { echo "FATAL: helpers.js nahi mili"; exit 1; }
echo "=== FF-NOTIFYCOVERAGE3 $(date) ==="

TS=$(date +%s)
mkdir -p "$BACKUP_ROOT"
SERVER_BAK="$BACKUP_ROOT/server.js.bak-notifycoverage3-$TS"
HELPER_BAK="$BACKUP_ROOT/helpers.js.bak-notifycoverage3-$TS"
cp -a server.js "$SERVER_BAK"
cp -a helpers.js "$HELPER_BAK"
echo "BACKUP: server.js -> $SERVER_BAK"
echo "BACKUP: helpers.js -> $HELPER_BAK"

NOTIFY_EXISTED=0
NOTIFY_BAK=""
if [ -f notify_all.js ]; then
  NOTIFY_EXISTED=1
  NOTIFY_BAK="$BACKUP_ROOT/notify_all.js.bak-notifycoverage3-$TS"
  cp -a notify_all.js "$NOTIFY_BAK"
  echo "BACKUP: notify_all.js -> $NOTIFY_BAK"
fi

if [ -f data/erp.db ]; then
  DB_BAK="$BACKUP_ROOT/erp.db.bak-notifycoverage3-$TS"
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 data/erp.db ".backup '$DB_BAK'"
  else
    cp -a data/erp.db "$DB_BAK"
  fi
  echo "BACKUP: data/erp.db -> $DB_BAK"
fi

restore_files() {
  trap - ERR
  echo "AUTO-RESTORE: notification coverage patch rollback"
  cp -a "$SERVER_BAK" server.js
  cp -a "$HELPER_BAK" helpers.js
  if [ "$NOTIFY_EXISTED" = "1" ]; then
    cp -a "$NOTIFY_BAK" notify_all.js
  else
    rm -f notify_all.js
  fi
  if [ "$SKIP_SERVICE" != "1" ]; then systemctl restart "$SERVICE" || true; fi
}
trap 'rc=$?; restore_files; exit $rc' ERR

cat > notify_all.js <<'JS'
'use strict';
/* ff-notifycoverage3: permission-independent notification coverage. */
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
JS

node - <<'JS'
const fs = require('fs');
const serverFile = 'server.js';
const helperFile = 'helpers.js';

function patchServer(source) {
  if (source.includes('ff-notifycoverage3-middleware')) return source;
  const routeMount = source.match(/app\.use\(\s*['"`]\/api(?:\/|['"`])/);
  if (!routeMount || routeMount.index == null) {
    throw new Error("server.js vich first app.use('/api...') mount nahi milya");
  }
  const code = "// ff-notifycoverage3-middleware: must be before API routes.\napp.use(require('./notify_all'));\n";
  return source.slice(0, routeMount.index) + code + source.slice(routeMount.index);
}

function patchHelpers(source) {
  if (source.includes('ff-notifycoverage3-audit-disabled')) return source;
  const call = /try\s*\{\s*ffBroadcast\(\.\.\.args\);\s*\}\s*catch\s*\(_\)\s*\{\s*\}/;
  if (!call.test(source)) {
    // No old audit broadcast means there is nothing to disable.
    return source;
  }
  return source.replace(call, '/* ff-notifycoverage3-audit-disabled: global middleware broadcasts once. */');
}

// Mandatory mock-file test before production files are written.
const mockServer = `const express = require('express');\nconst app = express();\napp.use(express.json());\napp.use('/api/products', require('./routes/products'));\napp.listen(4000);\n`;
const testedServer = patchServer(mockServer);
if (!testedServer.includes('ff-notifycoverage3-middleware') || testedServer.indexOf('notify_all') > testedServer.indexOf("app.use('/api/products'")) {
  throw new Error('MOCK SERVER PATCH TEST FAILED');
}
const mockHelper = `function audit(...args) { _auditCore(...args); try { ffBroadcast(...args); } catch (_) {} }`;
const testedHelper = patchHelpers(mockHelper);
if (!testedHelper.includes('ff-notifycoverage3-audit-disabled') || testedHelper.includes('ffBroadcast(...args)')) {
  throw new Error('MOCK HELPER PATCH TEST FAILED');
}
console.log('MOCK PATCH TESTS OK');

const serverOriginal = fs.readFileSync(serverFile, 'utf8');
const helperOriginal = fs.readFileSync(helperFile, 'utf8');
const serverUpdated = patchServer(serverOriginal);
const helperUpdated = patchHelpers(helperOriginal);
fs.writeFileSync(serverFile, serverUpdated);
fs.writeFileSync(helperFile, helperUpdated);
console.log(serverUpdated === serverOriginal ? 'SERVER: already patched' : 'SERVER: global middleware mounted before API routes');
console.log(helperUpdated === helperOriginal ? 'HELPERS: no old duplicate broadcast / already patched' : 'HELPERS: old audit broadcast disabled');
JS

node --check notify_all.js
node --check server.js
node --check helpers.js
echo "NODE SYNTAX OK: notify_all.js server.js helpers.js"

# Production-only integration probe. It sends a fake successful entry directly
# through the broadcaster inside a DB transaction and then intentionally rolls
# the transaction back, proving one insert per active user without leaving data.
if [ "$SKIP_SERVICE" != "1" ]; then
  node - <<'JS'
const db = require('./db');
const notify = require('./notify_all');
const actor = db.prepare('SELECT id, name, email FROM users WHERE active = 1 ORDER BY id LIMIT 1').get();
if (!actor) throw new Error('No active user found for notification probe');
const expected = Number(db.prepare('SELECT COUNT(*) n FROM users WHERE active = 1').get().n);
let verified = false;
try {
  db.transaction(() => {
    const inserted = notify._broadcast({
      method: 'POST', originalUrl: '/api/products/__ff_probe', user: actor,
      body: {name: '__FF_NOTIFY_PROBE__'}, params: {},
    });
    const rows = Number(db.prepare("SELECT COUNT(*) n FROM notifications WHERE body LIKE '%__FF_NOTIFY_PROBE__%'").get().n);
    if (inserted !== expected || rows !== expected) {
      throw new Error(`PROBE mismatch: active=${expected} inserted=${inserted} rows=${rows}`);
    }
    throw new Error('__FF_PROBE_ROLLBACK_OK__');
  })();
} catch (e) {
  if (e.message === '__FF_PROBE_ROLLBACK_OK__') verified = true;
  else throw e;
}
if (!verified) throw new Error('Notification rollback probe did not complete');
console.log(`DB ROLLBACK PROBE OK: ${expected}/${expected} active users targeted; 0 test rows retained`);
JS
fi

if [ "$SKIP_SERVICE" = "1" ]; then
  echo "SERVICE + DB PROBE SKIPPED (mock mode)"
else
  systemctl restart "$SERVICE"
  sleep 2
  systemctl is-active --quiet "$SERVICE"
  CODE=$(curl -sS -o /dev/null -w '%{http_code}' -m 8 http://127.0.0.1:4000/api/health || true)
  echo "health -> $CODE"
  [ "$CODE" = "200" ]
fi

trap - ERR
echo "NOTIFYCOVERAGE3 VERIFIED ✓ — har successful entry SARE active users nu, permission hove jaan na hove"
