/** routes/audit.js — read-only audit trail. */
const express = require('express');
const db = require('../db');
const { requirePerm } = require('../middleware');

const router = express.Router();

router.get('/', requirePerm('audit.view'), (req, res) => {
  const entity = String(req.query.entity || '').trim();
  const limit = Math.min(500, Math.max(1, Number(req.query.limit) || 200));
  const rows = entity
    ? db.prepare(`SELECT * FROM audit_logs WHERE entity = ? ORDER BY id DESC LIMIT ?`).all(entity, limit)
    : db.prepare(`SELECT * FROM audit_logs ORDER BY id DESC LIMIT ?`).all(limit);
  res.json({ logs: rows });
});

module.exports = router;
