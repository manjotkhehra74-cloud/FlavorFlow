#!/usr/bin/env bash
# Safely migrate FlavorFlow-issued login IDs from @flavorflow.in to
# @flavorflow.co.in in the existing factory DB and SaaS tenant DBs.
#
# Read-only preview (default):
#   sudo bash tools/ff-login-id-domain-migrate.sh --dry-run
# Apply only after reviewing the preview:
#   sudo bash tools/ff-login-id-domain-migrate.sh --apply
#
# Every affected database is backed up first. Any pre-existing target-ID
# collision aborts the run before any database is changed. Passwords, roles, numeric user
# IDs, permissions, tokens, and business records are not modified.
set -euo pipefail

MODE=dry-run
case "${1:-}" in
  ""|--dry-run) MODE=dry-run ;;
  --apply) MODE=apply ;;
  --help|-h)
    sed -n '2,13p' "$0"
    exit 0
    ;;
  *) echo "Usage: $0 [--dry-run|--apply]" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [--dry-run|--apply]" >&2
  exit 2
fi

DB_PATHS=()
if [[ -n "${FF_LOGIN_MIGRATION_DBS:-}" ]]; then
  IFS=':' read -r -a DB_PATHS <<< "$FF_LOGIN_MIGRATION_DBS"
else
  [[ -f /opt/flavorflow/server/data/erp.db ]] && DB_PATHS+=(/opt/flavorflow/server/data/erp.db)
  for db in /opt/flavorflow-saas/data/tenant-*/erp.db; do
    [[ -f "$db" ]] && DB_PATHS+=("$db")
  done
fi

BACKUP_ROOT="${FF_BACKUP_ROOT:-/opt/flavorflow/backups}"
python3 - "$MODE" "$BACKUP_ROOT" "${DB_PATHS[@]}" <<'PY'
import os
import re
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

mode, backup_root, *raw_paths = sys.argv[1:]
old_suffix = "@flavorflow.in"
new_suffix = "@flavorflow.co.in"

paths = []
for raw in raw_paths:
    path = os.path.realpath(raw)
    if path and path not in paths and os.path.isfile(path):
        paths.append(path)

if not paths:
    print("FATAL: no ERP databases found. Check the known paths or set FF_LOGIN_MIGRATION_DBS.", file=sys.stderr)
    sys.exit(2)

plans = []
conflicts = []
for path in paths:
    try:
        db = sqlite3.connect(path, timeout=30)
        db.row_factory = sqlite3.Row
        tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if "users" not in tables:
            print(f"SKIP: {path} (no users table)")
            db.close()
            continue
        columns = {r[1] for r in db.execute("PRAGMA table_info(users)")}
        if not {"id", "email"}.issubset(columns):
            print(f"FATAL: {path} has a users table without id/email columns.", file=sys.stderr)
            db.close()
            sys.exit(2)

        rows = db.execute("SELECT id, email FROM users WHERE email IS NOT NULL ORDER BY id").fetchall()
        emails = {}
        for row in rows:
            emails.setdefault(str(row["email"]).casefold(), []).append(row["id"])

        candidates = []
        planned_targets = {}
        for row in rows:
            old = str(row["email"])
            if not old.casefold().endswith(old_suffix):
                continue
            target = old[:-len(old_suffix)] + new_suffix
            target_key = target.casefold()
            existing_ids = [uid for uid in emails.get(target_key, []) if uid != row["id"]]
            if existing_ids:
                conflicts.append((path, row["id"], existing_ids[0]))
            if target_key in planned_targets:
                conflicts.append((path, row["id"], planned_targets[target_key]))
            else:
                planned_targets[target_key] = row["id"]
            candidates.append((row["id"], old, target))
        db.close()
        plans.append((path, candidates))
        print(f"PREFLIGHT: {path} — {len(candidates)} login ID(s) to rename")
    except sqlite3.Error as error:
        print(f"FATAL: cannot inspect {path}: {error}", file=sys.stderr)
        sys.exit(2)

if conflicts:
    print("\nABORTED: login-ID collisions found; no database was changed.", file=sys.stderr)
    for path, old_id, conflicting_id in conflicts:
        print(f"  {path}: user row {old_id} conflicts with existing row {conflicting_id}", file=sys.stderr)
    print("Resolve these accounts before running --apply.", file=sys.stderr)
    sys.exit(3)

changed = sum(len(candidates) for _, candidates in plans)
if changed == 0:
    print("No @flavorflow.in login IDs found. Nothing to change.")
    sys.exit(0)

print(f"\nMODE: {mode.upper()} — {changed} login ID(s) across {len(plans)} database(s).")
print("Only the exact @flavorflow.in suffix is changed; other IDs are left untouched.")
if mode == "dry-run":
    print("No changes made. Review the counts, then run again with --apply.")
    sys.exit(0)

stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
try:
    os.makedirs(backup_root, mode=0o700, exist_ok=True)
    backups = {}
    for path, candidates in plans:
        if not candidates:
            continue
        parent = Path(path).parent.name
        label = "factory" if path.endswith("/flavorflow/server/data/erp.db") else re.sub(r"[^A-Za-z0-9_.-]", "_", parent)
        backup = os.path.join(backup_root, f"{label}-erp.db.bak-login-id-domain-{stamp}")
        fd = os.open(backup, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600)
        os.close(fd)
        source = sqlite3.connect(path, timeout=30)
        target = sqlite3.connect(backup)
        try:
            source.backup(target)
            check = target.execute("PRAGMA quick_check").fetchone()[0]
            if check != "ok":
                raise RuntimeError(f"backup integrity check failed for {path}: {check}")
        finally:
            target.close()
            source.close()
        os.chmod(backup, 0o600)
        backups[path] = backup
        print(f"BACKUP: {path} -> {backup}")
except Exception as error:
    print(f"FATAL: backup failed; no user IDs were changed: {error}", file=sys.stderr)
    sys.exit(4)

applied = []
try:
    for path, candidates in plans:
        if not candidates:
            continue
        db = sqlite3.connect(path, timeout=30)
        try:
            db.execute("BEGIN IMMEDIATE")
            for user_id, old, target in candidates:
                current = db.execute("SELECT email FROM users WHERE id = ?", (user_id,)).fetchone()
                if current is None or current[0] != old:
                    raise RuntimeError(f"user row {user_id} changed after preflight in {path}; transaction rolled back")
                collision = db.execute(
                    "SELECT id FROM users WHERE lower(email) = lower(?) AND id <> ? LIMIT 1",
                    (target, user_id),
                ).fetchone()
                if collision is not None:
                    raise RuntimeError(f"target-ID collision appeared in {path}; transaction rolled back")
                result = db.execute("UPDATE users SET email = ? WHERE id = ? AND email = ?", (target, user_id, old))
                if result.rowcount != 1:
                    raise RuntimeError(f"could not update user row {user_id} in {path}; transaction rolled back")
            check = db.execute("PRAGMA quick_check").fetchone()[0]
            if check != "ok":
                raise RuntimeError(f"database integrity check failed for {path}: {check}")
            db.commit()
            applied.append(path)
            print(f"APPLIED: {len(candidates)} login ID(s) in {path}")
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()
except Exception as error:
    print(f"FATAL: migration stopped: {error}", file=sys.stderr)
    if applied:
        print("Earlier database(s) in this run were changed. Backups are available:", file=sys.stderr)
        for path in applied:
            print(f"  {path} -> {backups[path]}", file=sys.stderr)
    sys.exit(5)

print(f"\nSUCCESS: migrated {changed} login ID(s). Existing numeric user IDs, passwords, roles, permissions, tokens, and business records were preserved.")
print("Users should sign in with the new @flavorflow.co.in ID. Phones with a saved old biometric ID may need one manual sign-in to refresh it.")
PY
