#!/usr/bin/env bash
# FlavorFlow: dump the reports route (dispatch-register section) + dispatch
# routes to the web-served dir so the assistant can read them remotely and
# prepare an exact batch-code patch. Read-only — changes NOTHING.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
WB=$(find /opt/flavorflow /var/www /home /srv -maxdepth 6 -name main.dart.js -printf '%h\n' 2>/dev/null | head -1)
[ -z "${WB:-}" ] && { echo "FATAL: web build dir nahi mili"; exit 1; }
OUT="$WB/ff-repdump.txt"
: > "$OUT"
echo "=== FF-REPDUMP $(date) ===" >> "$OUT"
for f in routes/reports.js routes/dispatch.js; do
  echo "" >> "$OUT"
  echo "########## FILE: $f ##########" >> "$OUT"
  if [ -f "$f" ]; then
    cat -n "$f" >> "$OUT"
  else
    echo "(missing — actual routes files:)" >> "$OUT"
    ls -la routes >> "$OUT" 2>&1
  fi
done
echo "" >> "$OUT"
echo "########## SCHEMA ##########" >> "$OUT"
DB=$(find /opt/flavorflow -maxdepth 3 -name '*.db' -o -name '*.sqlite' 2>/dev/null | head -1)
echo "DB: ${DB:-not found}" >> "$OUT"
if [ -n "${DB:-}" ] && command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "$DB" ".schema dispatches" >> "$OUT" 2>&1
  sqlite3 "$DB" ".schema dispatch_items" >> "$OUT" 2>&1
else
  node -e "const db=require('better-sqlite3')(process.argv[1]);for(const t of ['dispatches','dispatch_items'])try{console.log(db.prepare('SELECT sql FROM sqlite_master WHERE name=?').get(t).sql)}catch(e){console.log(t+': '+e.message)}" "${DB:-}" >> "$OUT" 2>&1
fi
chmod 644 "$OUT"
echo "DUMP READY: https://flavorflow.duckdns.org/ff-repdump.txt"
echo "(kamm khatam hon te delete kar dena: sudo rm $OUT)"
