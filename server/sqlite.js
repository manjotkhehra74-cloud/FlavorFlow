/**
 * sqlite.js — database driver with ZERO native/compiled dependencies.
 *
 * Primary: Node.js built-in SQLite (`node:sqlite`, available in Node 24 LTS
 * — and 22.5+/23.4+ experimentally). No prebuilds, no node-gyp, works
 * identically on Windows, macOS and Linux.
 *
 * Optional fallback: `better-sqlite3` if a project explicitly installs it.
 */
let driver = 'node:sqlite';
let DatabaseSync = null;

try {
  ({ DatabaseSync } = require('node:sqlite'));
} catch {
  try {
    DatabaseSync = require('better-sqlite3');
    driver = 'better-sqlite3';
  } catch {
    throw new Error(
      'No SQLite driver available. FlavorFlow ERP needs Node.js 24 (LTS) or newer — ' +
      'download it from https://nodejs.org'
    );
  }
}

/** BEGIN IMMEDIATE / COMMIT / ROLLBACK wrapper (built-in driver has no helper). */
function tx(db, fn) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const out = fn();
    db.exec('COMMIT');
    return out;
  } catch (err) {
    try { db.exec('ROLLBACK'); } catch { /* already rolled back */ }
    throw err;
  }
}

function pragma(db, statement) {
  db.exec(`PRAGMA ${statement}`);
}

module.exports = { DatabaseSync, driver, tx, pragma };
