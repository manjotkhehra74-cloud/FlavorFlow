#!/usr/bin/env bash
# FlavorFlow: product SEQUENCE fix (saari app vich ikko tarteeb) —
#   User di mangi tarteeb:
#     1) Glass bottle   (250gm / 180ml)
#     2) HDPE bottle    (610ml / 740gm)
#     3) 1.0 / 1.3      (1 Ltr / 1.3kg)
#     4) 4.0 / 4.7      (4 Ltr / 4.7kg)
#   Kiven:
#     - products table vich sort_order column (idempotent)
#     - name-pattern naal groups: 10/20/30/40 (group andar name A-Z)
#     - SAARIYAN server files vich 'ORDER BY name' / 'ORDER BY p.name'
#       (products wale queries) → 'ORDER BY sort_order, name'
#   /products endpoint hi app de saare dropdowns/lists nu data dinda hai,
#   so client apne aap sahi tarteeb vich dikhauga (Loss% sections vi).
# Idempotent. Backups + node --check + auto-restore.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-SEQFIX $(date) ==="

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a data/erp.db "/opt/flavorflow/backups/erp.db.bak-seq-$TS" 2>/dev/null
for F in server.js helpers.js routes/*.js; do [ -f "$F" ] && cp -a "$F" "/opt/flavorflow/backups/$(basename $F).bak-seq-$TS"; done
echo "BACKUPS -> /opt/flavorflow/backups (suffix -seq-$TS)"

echo ""
echo "--- STEP 1: sort_order column + values ---"
node - <<'JS'
const db = require('/opt/flavorflow/server/db');
try {
  const cols = db.prepare('PRAGMA table_info(products)').all().map(c => c.name);
  if (!cols.includes('sort_order')) {
    db.prepare('ALTER TABLE products ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 999').run();
    console.log('sort_order column: ADDED');
  } else console.log('sort_order column: already there');
  // groups: 10 glass (250gm/180ml) · 20 HDPE (610ml/740gm) · 30 1L/1.3kg · 40 4L/4.7kg
  db.prepare(`UPDATE products SET sort_order = CASE
      WHEN name LIKE '%250%' OR name LIKE '%180%' THEN 10
      WHEN name LIKE '%610%' OR name LIKE '%740%' THEN 20
      WHEN name LIKE '%1.3%' OR name LIKE '%1 Ltr%' OR name LIKE '%1Ltr%' OR name LIKE '%1 ltr%' THEN 30
      WHEN name LIKE '%4.7%' OR name LIKE '%4 Ltr%' OR name LIKE '%4Ltr%' OR name LIKE '%4 ltr%' THEN 40
      ELSE 999 END`).run();
  const rows = db.prepare('SELECT sort_order, name FROM products ORDER BY sort_order, name').all();
  for (const r of rows) console.log('  ' + String(r.sort_order).padStart(3) + '  ' + r.name);
  const missed = rows.filter(r => r.sort_order === 999);
  if (missed.length) console.log('NOTE: ' + missed.length + ' product(s) kise group vich nahi aaye (999 = sab ton thalle) — dass dena, pattern jod devange');
} catch (e) { console.log('DB error:', e.message); process.exit(2); }
JS
[ $? -ne 0 ] && { echo "SEQFIX DB FAIL"; exit 1; }

echo ""
echo "--- STEP 2: ORDER BY patches (products queries) ---"
node - <<'JS'
const fs = require('fs'), cp = require('child_process');
const glob = ['server.js', 'helpers.js'].concat(fs.readdirSync('/opt/flavorflow/server/routes').map(x => 'routes/' + x).filter(x => x.endsWith('.js')));
function fix(sql) {
  let out = sql;
  out = out.replace(/ORDER BY\s+p\.name\b/gi, 'ORDER BY p.sort_order, p.name');
  out = out.replace(/ORDER BY\s+name\b/gi, 'ORDER BY sort_order, name');
  return out;
}
for (const rel of glob) {
  const f = '/opt/flavorflow/server/' + rel;
  if (!fs.existsSync(f)) continue;
  let src = fs.readFileSync(f, 'utf8');
  if (src.includes('sort_order, name') && !/FROM\s+products[^;]{0,200}ORDER BY\s+(p\.)?name\b/i.test(src)) { console.log(rel + ': already patched'); continue; }
  const bak = f + '.bak-seqw-' + Date.now();
  fs.copyFileSync(f, bak);
  let n = 0;
  // single/double quoted strings
  src = src.replace(/(['"])((?:(?!\1)[^\n])*)\1/g, (m, q, sql) => {
    if (!/FROM\s+products|JOIN\s+products/i.test(sql)) return m;
    const out = fix(sql); if (out !== sql) { n++; return q + out + q; } return m;
  });
  // backtick strings (multiline)
  src = src.replace(/`([^`]*)`/g, (m, sql) => {
    if (!/FROM\s+products|JOIN\s+products/i.test(sql)) return m;
    const out = fix(sql); if (out !== sql) { n++; return '`' + out + '`'; } return m;
  });
  if (n) {
    fs.writeFileSync(f, src);
    try { cp.execSync('node --check "' + f + '"'); console.log(rel + ': ' + n + ' query patched — SYNTAX OK'); }
    catch (e) { fs.copyFileSync(bak, f); console.log(rel + ': SYNTAX FAIL — RESTORED'); process.exit(3); }
  } else console.log(rel + ': no products ORDER BY to patch');
}
JS
[ $? -ne 0 ] && { echo "SEQFIX PATCH FAIL — restored"; exit 1; }

systemctl restart flavorflow
sleep 2
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
echo "SEQFIX VERIFIED ✓ — tarteeb hun har jagah: Glass (250/180) → HDPE (610/740) → 1L/1.3 → 4L/4.7"
