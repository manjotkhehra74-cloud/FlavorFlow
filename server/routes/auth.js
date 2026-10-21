/** routes/auth.js — sign in / session. */
const express = require('express');
const bcrypt = require('bcryptjs');
const db = require('../db');
const jwt = require('../jwt');
const { ROLES, NAV_ITEMS, permissionsForRole, navForRole } = require('../rbac');
const { audit } = require('../helpers');
const { authRequired } = require('../middleware');

const router = express.Router();

function sessionPayload(user) {
  return {
    user: {
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
      roleLabel: ROLES[user.role] ? ROLES[user.role].label : user.role,
      roleColor: ROLES[user.role] ? ROLES[user.role].color : '#334155',
    },
    permissions: (function(){try{var x=JSON.parse(user.permissions||'[]');return Array.isArray(x)&&x.length?x:permissionsForRole(user.role)}catch(e){return permissionsForRole(user.role)}})(),
    nav: (function(){var p=(function(){try{var x=JSON.parse(user.permissions||'[]');return Array.isArray(x)&&x.length?x:permissionsForRole(user.role)}catch(e){return permissionsForRole(user.role)}})();return NAV_ITEMS.filter(function(i){return p.includes('*')||p.includes(i.perm)})})(),
    currency: { code: 'INR', symbol: '₹', locale: 'en-IN', decimals: 2 },
  };
}

/* ---- login brute-force protection (safe on the public internet) ---- */
const WINDOW_MS = 10 * 60 * 1000;           // 10 minutes
const MAX_FAILS = Number(process.env.LOGIN_MAX_FAILS || 20);
const failures = new Map();                  // key: ip|email → { count, first }
function loginBlocked(key) {
  const f = failures.get(key);
  if (!f) return false;
  if (Date.now() - f.first > WINDOW_MS) { failures.delete(key); return false; }
  return f.count >= MAX_FAILS;
}
function loginFailed(key) {
  const f = failures.get(key);
  if (!f || Date.now() - f.first > WINDOW_MS) failures.set(key, { count: 1, first: Date.now() });
  else f.count += 1;
}
function loginSucceeded(key) { failures.delete(key); }

router.post('/login', (req, res) => {
  const { email, password } = req.body || {};
  if (!email || !password) return res.status(400).json({ error: 'Email and password are required.' });
  const key = `${req.ip}|${String(email).trim().toLowerCase()}`;
  if (loginBlocked(key)) {
    return res.status(429).json({ error: 'Too many wrong attempts. Please wait 10 minutes and try again.' });
  }

  const user = db.prepare('SELECT * FROM users WHERE lower(email) = lower(?)').get(String(email).trim());
  if (!user || !bcrypt.compareSync(String(password), user.password_hash)) {
    loginFailed(key);
    return res.status(401).json({ error: 'Invalid email or password.' });
  }
  if (!user.active) return res.status(403).json({ error: 'Your account has been deactivated. Contact the administrator.' });
  loginSucceeded(key);

  audit(db, user, 'LOGIN', 'user', user.id, `${user.name} signed in`);
  // ff-totploginfix6: always verify against the current DB secret.
  {
    const _totpUser = db.prepare('SELECT totp_secret, totp_enabled FROM users WHERE id = ?').get(user.id);
    if (_totpUser && Number(_totpUser.totp_enabled) === 1) {
      const _totpCode = String((req.body || {}).totpCode || '').replace(/\s+/g, '');
      if (!_totpCode) {
        res.status(401).json({ error: 'TOTP_REQUIRED' });
        return;
      }
      const { verify: _verifyLoginTotp } = require('../totp');
      if (!_verifyLoginTotp(_totpUser.totp_secret, _totpCode)) {
        res.status(401).json({ error: 'Wrong authenticator code — wait for a fresh code and try again.' });
        return;
      }
    }
  }

  res.json({ token: jwt.sign({ uid: user.id }), ...sessionPayload(user) });
});

router.get('/me', authRequired, (req, res) => res.json(sessionPayload(req.user)));

router.post('/logout', authRequired, (req, res) => {
  audit(db, req.user, 'LOGOUT', 'user', req.user.id, '');
  res.json({ ok: true });
});


// --- ff-totpfix: authenticator-app 2FA management (logged-in user) ---
const { newSecret: _totpNew, verify: _totpVerify } = require('../totp');
router.get('/totp/status', authRequired, (req, res) => {
  const u = db.prepare('SELECT totp_enabled FROM users WHERE id = ?').get(req.user.id);
  res.json({ enabled: !!(u && u.totp_enabled === 1) });
});
router.post('/totp/setup', authRequired, (req, res) => {
  const secret = _totpNew();
  db.prepare('UPDATE users SET totp_pending_secret = ? WHERE id = ?').run(secret, req.user.id); // ff-totpaccounts8
  const label = encodeURIComponent('FlavorFlow ERP:' + req.user.email);
  res.json({ secret, otpauth: 'otpauth://totp/' + label + '?secret=' + secret + '&issuer=' + encodeURIComponent('FlavorFlow ERP') + '&algorithm=SHA1&digits=6&period=30' /* ff-totpfix5-explicit-uri */ });
});
router.post('/totp/enable', authRequired, (req, res) => {
  const u = db.prepare('SELECT totp_secret, totp_pending_secret FROM users WHERE id = ?').get(req.user.id);
  const candidate = u && (u.totp_pending_secret || u.totp_secret);
  if (!candidate) { res.status(400).json({ error: 'Run setup first.' }); return; }
  if (!_totpVerify(candidate, (req.body || {}).code)) { res.status(400).json({ error: 'Wrong code — check the app and try again.' }); return; }
  db.prepare("UPDATE users SET totp_secret = ?, totp_pending_secret = '', totp_enabled = 1 WHERE id = ?").run(candidate, req.user.id);
  res.json({ ok: true });
});
router.post('/totp/disable', authRequired, (req, res) => {
  const u = db.prepare('SELECT totp_secret, totp_enabled FROM users WHERE id = ?').get(req.user.id);
  if (!u || u.totp_enabled !== 1) { res.json({ ok: true }); return; }
  if (!_totpVerify(u.totp_secret, (req.body || {}).code)) { res.status(400).json({ error: 'Wrong code — 2FA stays on.' }); return; }
  db.prepare("UPDATE users SET totp_enabled = 0, totp_secret = '', totp_pending_secret = '' WHERE id = ?").run(req.user.id);
  res.json({ ok: true });
});
// --- end ff-totpfix ---

module.exports = router;
