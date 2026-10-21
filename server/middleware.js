/** middleware.js — JWT authentication + per-endpoint permission enforcement. */
const jwt = require('./jwt');
const db = require('./db');
const { hasPermission } = require('./rbac');

/** Attaches req.user (fresh from DB — role changes & deactivation apply instantly). */
function authRequired(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  const payload = token && jwt.verify(token);
  if (!payload) return res.status(401).json({ error: 'Unauthenticated. Please sign in.' });

  const user = db.prepare('SELECT id, name, email, role, active, permissions FROM users WHERE id = ?').get(payload.uid);
  if(user){try{user.permissions=JSON.parse(user.permissions||'[]');if(!Array.isArray(user.permissions))user.permissions=[]}catch(e){user.permissions=[]}}
  if (!user || !user.active) return res.status(401).json({ error: 'Account inactive or removed.' });

  req.user = user;
  next();
}

/** Hard authorization gate used on EVERY protected route. */
function requirePerm(perm) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'Unauthenticated. Please sign in.' });
    var _c=req.user&&req.user.permissions;var _h=Array.isArray(_c)&&(_c.includes('*')||_c.includes(perm));if(!_h&&!hasPermission(req.user.role,perm)){
      return res.status(403).json({
        error: 'Forbidden',
        message: `Your role does not have permission "${perm}".`,
        required: perm,
        role: req.user.role,
      });
    }
    next();
  };
}

const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/** Standard JSON error handler. */
function errorHandler(err, req, res, _next) {
  console.error('[api]', err.message);
  if (err && err.status) return res.status(err.status).json({ error: err.message });
  return res.status(500).json({ error: 'Internal server error', detail: err.message });
}

const bad = (msg, status = 400) => Object.assign(new Error(msg), { status });

module.exports = { authRequired, requirePerm, wrap, errorHandler, bad };
