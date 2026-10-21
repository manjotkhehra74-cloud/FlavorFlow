/** FlavorFlow — menu follows the user's EFFECTIVE permissions (ff-dispatchfix).
 *  The core builds the menu with rbac.navForRole(role) — role defaults only — while the API checks each
 *  user's own permission list (Users → Edit → permission chips). A user given dispatch.view could open
 *  Dispatch but never saw it in the menu. This middleware rewrites `nav` in the /api/auth/login and
 *  /api/auth/me responses from the `permissions` array the same response carries: rbac NAV_ITEMS order,
 *  Dashboard always, super_admin = everything, entries added by other patches kept when their permission
 *  is granted. Pure functions (navFor / rewrite) are unit-tested by ff-dispatchfix before install.
 */
'use strict';
const ALWAYS = new Set(['dashboard.view']);
const RE = /^\/api\/auth\/(login|me)\/?$/;
function items() { try { const r = require('./rbac'); return Array.isArray(r.NAV_ITEMS) ? r.NAV_ITEMS : []; } catch (_) { return []; } }
function navFor(navItems, permissions, serverNav) {
  const perms = new Set((Array.isArray(permissions) ? permissions : []).map(String));
  const all = perms.has('*');
  const ok = (perm) => !perm || all || ALWAYS.has(perm) || perms.has(perm);
  const out = [], seen = new Set();
  for (const it of navItems || []) if (it && it.path && !seen.has(it.path) && ok(it.perm)) { out.push(it); seen.add(it.path); }
  for (const it of serverNav || []) if (it && it.path && !seen.has(it.path) && ok(it.perm)) { out.push(it); seen.add(it.path); }
  return out;
}
function rewrite(body) {
  if (!body || typeof body !== 'object' || !Array.isArray(body.nav)) return body;
  const role = body.user && body.user.role;
  const perms = role === 'super_admin' ? ['*'] : body.permissions;
  if (!Array.isArray(perms)) return body;
  body.nav = navFor(items(), perms, body.nav);
  return body;
}
function middleware(req, res, next) {
  let hit = false;
  try { hit = RE.test(String(req.originalUrl || req.url || '').split('?')[0]); } catch (_) {}
  if (hit && res && typeof res.json === 'function') {
    const oj = res.json;
    res.json = function (...args) {
      try { rewrite(args[0]); } catch (_) {}
      return oj.apply(this, args);
    };
  }
  next();
}
module.exports = { navFor, rewrite, middleware, items };
