/** routes/users.js — user administration (Super Admin / Admin). */
const express = require('express');
const bcrypt = require('bcryptjs');
const db = require('../db');
const { tx } = require('../sqlite');
const { requirePerm, bad } = require('../middleware');
const { ROLES, permissionsForRole } = require('../rbac');
const { audit, nowIso } = require('../helpers');

const router = express.Router();

/** Admin may not touch super_admin accounts. */
function guardTarget(req, target) {
  if (target.role === 'super_admin' && req.user.role !== 'super_admin') {
    throw bad('Only the Super Admin can modify Super Admin accounts.', 403);
  }
}

router.get('/', requirePerm('users.view'), (req, res) => {
  const rows = db.prepare(
    `SELECT id, name, email, role, active, permissions, created_at FROM users WHERE active = 1  ORDER BY id`
  ).all().map(r=>{try{r.permissions=JSON.parse(r.permissions||'[]');if(!Array.isArray(r.permissions))r.permissions=[]}catch(e){r.permissions=[]}return r});
  res.json({
    users: rows,
    roles: Object.entries(ROLES).map(([id, r]) => ({ id, label: r.label, color: r.color, permissions: permissionsForRole(id) })),
  });
});

router.post('/', requirePerm('users.manage'), (req, res) => {
  const b = req.body || {};
  const name = String(b.name || '').trim();
  const email = String(b.email || '').trim().toLowerCase();
  const role = String(b.role || '');
  const password = String(b.password || '');
  if (!name) throw bad('Name is required.');
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw bad('A valid email is required.');
  if (!ROLES[role]) throw bad('Invalid role.');
  if (role === 'super_admin' && req.user.role !== 'super_admin') throw bad('Only the Super Admin can create Super Admin accounts.', 403);
  if (password.length < 6) throw bad('Password must be at least 6 characters.');
  if (db.prepare('SELECT id FROM users WHERE active = 1 AND lower(email) = ?').get(email)) throw bad('Email already registered.', 409);

  const info = db.prepare(
    `INSERT INTO users (name, email, password_hash, role, active, permissions, created_at) VALUES (?,?,?,?,?,?,?)`
  ).run(name, email, bcrypt.hashSync(password, 10), role, 1, JSON.stringify(Array.isArray(b.permissions)?b.permissions:[]), nowIso());
  audit(db, req.user, 'CREATE', 'user', info.lastInsertRowid, `Created user ${name} <${email}> with role ${role}`);
  res.status(201).json({ id: info.lastInsertRowid });
});

router.put('/:id', requirePerm('users.manage'), (req, res) => {
  const id = Number(req.params.id);
  const target = db.prepare('SELECT * FROM users WHERE active = 1 AND id = ?').get(id);
  if (!target) throw bad('User not found.', 404);
  guardTarget(req, target);

  const b = req.body || {};
  const name = String(b.name ?? target.name).trim();
  const role = String(b.role ?? target.role);
  const active = b.active == null ? target.active : (b.active ? 1 : 0);

  if (!ROLES[role]) throw bad('Invalid role.');
  if (role === 'super_admin' && req.user.role !== 'super_admin' && target.role !== 'super_admin') {
    throw bad('Only the Super Admin can grant the Super Admin role.', 403);
  }
  if (id === req.user.id && !active) throw bad('You cannot deactivate your own account.');
  if (target.role === 'super_admin' && (!active || role !== 'super_admin')) {
    const others = db.prepare(`SELECT COUNT(*) c FROM users WHERE active = 1 AND role='super_admin' AND id != ?`).get(id).c;
    if (others === 0) throw bad('At least one active Super Admin must remain.', 409);
  }

  db.prepare('UPDATE users SET name=?, role=?, active=?, permissions=? WHERE id=?').run(name, role, active, JSON.stringify(Array.isArray(b.permissions)?b.permissions:[]), id);
  if (b.password) {
    if (String(b.password).length < 6) throw bad('Password must be at least 6 characters.');
    db.prepare('UPDATE users SET password_hash=? WHERE id=?').run(bcrypt.hashSync(String(b.password), 10), id);
  }
  audit(db, req.user, 'UPDATE', 'user', id, `Updated user ${name}: role=${role}, active=${active}${b.password ? ', password reset' : ''}`);
  res.json({ ok: true });

});





// DELETE user (soft-delete)
router.delete('/:id', requirePerm('users.manage'), (req, res) => {
  // ff-setfix: never allow removing the last active super_admin
  {
    const _t = db.prepare('SELECT role FROM users WHERE id = ?').get(Number(req.params.id));
    if (_t && _t.role === 'super_admin') {
      const _n = db.prepare("SELECT COUNT(*) c FROM users WHERE role = 'super_admin' AND active = 1").get().c;
      if (_n <= 1) { res.status(409).json({ error: 'Cannot delete the last active Super Admin.' }); return; }
    }
  }

  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) return res.status(400).json({error: 'Invalid user id.'});
  const me = db.prepare('SELECT id, role FROM users WHERE active = 1 AND id = ?').get(id);
  if (!me) return res.status(404).json({error: 'User not found.'});
  if (me.id === req.user.id) return res.status(400).json({error: 'You cannot delete your own account.'});
  if (me.role === 'super_admin') return res.status(400).json({error: 'Super admin cannot be deleted.'});
  const result = tx(db, () => {
    db.prepare("UPDATE users SET active = 0, name = '[deleted] ' || name, email = 'del_' || id || '@deleted.local', password_hash = '' WHERE id = ?").run(id);
    audit(db, req.user, 'USER_DELETE', 'users', id, 'Deleted user #' + id);
    return { ok: true };
  });
  return res.json(result);
});

module.exports = router;
