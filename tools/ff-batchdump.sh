#!/usr/bin/env bash
# FlavorFlow: dump routes/production.js + batches table schema + DB list to the
# web dir so the assistant can prepare the exact "same batch code on a new
# date" patch. Read-only — changes NOTHING.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
WB=$(find /opt/flavorflow /var/www /home /srv -maxdepth 6 -name main.dart.js -printf '%h\n' 2>/dev/null | head -1)
[ -z "${WB:-}" ] && { echo "FATAL: web build dir nahi mili"; exit 1; }
OUT="$WB/ff-batchdump.txt"
: > "$OUT"
echo "=== FF-BATCHDUMP $(date) ===" >> "$OUT"
echo "" >> "$OUT"
echo "########## DB FILES ##########" >> "$OUT"
find /opt/flavorflow -maxdepth 4 \( -name '*.db' -o -name '*.sqlite' \) -printf '%p %s bytes\n' 2>/dev/null >> "$OUT"
echo "" >> "$OUT"
echo "########## db.js (connection) ##########" >> "$OUT"
head -30 db.js >> "$OUT" 2>&1
echo "" >> "$OUT"
echo "########## FILE: routes/production.js ##########" >> "$OUT"
if [ -f routes/production.js ]; then cat -n routes/production.js >> "$OUT"; else ls -la routes >> "$OUT"; fi
echo "" >> "$OUT"
echo "########## BATCHES SCHEMA (live DB) ##########" >> "$OUT"
node -e "
const db = require('/opt/flavorflow/server/db');
try { console.log(db.prepare(\"SELECT sql FROM sqlite_master WHERE name='batches'\").get().sql); } catch(e) { console.log('ERR: '+e.message); }
try { for (const r of db.prepare(\"SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name='batches'\").all()) console.log('INDEX: '+(r.sql||'(auto)')); } catch(e) {}
" >> "$OUT" 2>&1
chmod 644 "$OUT"
echo "DUMP READY: https://flavorflow.duckdns.org/ff-batchdump.txt"
