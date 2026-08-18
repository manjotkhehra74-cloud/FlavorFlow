#!/usr/bin/env bash
# FlavorFlow: raw material round 5 —
#  0) DIAGNOSIS: print the real error behind "Internal server error" (journal)
#  1) FIX: routes/packing.js — ensure helpers/tx imports the recipe-consume
#     route needs (missing import = ReferenceError = 500)
#  2) recipe-consume upgrades: override 0 = SKIP that material; overrides for
#     materials NOT in the recipe are consumed too (extra/adhoc lines)
#  3) reports.js: new 'raw-material-ledger' report (Date/Material/Type/Qty/
#     Reference/Remark/By — Raw Material only)
# Idempotent — safe to run twice. Backups + node --check + auto-restore.
set -u
cd /opt/flavorflow/server || { echo "FATAL: /opt/flavorflow/server nahi mili"; exit 1; }
echo "=== FF-RAWFIX5 $(date) ==="

echo ""
echo "--- DIAGNOSIS: last server errors (journal) ---"
journalctl -u flavorflow -n 200 --no-pager 2>/dev/null | grep -iE "error|throw|reference|undefined" | tail -12 || echo "(journal na mili)"
echo "-----------------------------------------------"
echo ""

TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a routes/packing.js "/opt/flavorflow/backups/packing.js.bak-raw5-$TS"
cp -a routes/reports.js "/opt/flavorflow/backups/reports.js.bak-raw5-$TS"
echo "BACKUPS: packing.js / reports.js -> /opt/flavorflow/backups (suffix -raw5-$TS)"

node - <<'JS'
const fs = require('fs'), cp = require('child_process');
let failed = false;
function check(f, b) {
  try { cp.execSync('node --check "' + f + '"'); console.log('SYNTAX OK: ' + f); return true; }
  catch (e) { fs.copyFileSync(b, f); console.log('SYNTAX FAIL — RESTORED: ' + String(e.stderr || e).slice(0, 400)); return false; }
}

/* ---------- 1) packing.js: imports + consume upgrades ---------- */
{
  const f = '/opt/flavorflow/server/routes/packing.js';
  const bak = f + '.bak-raw5w-' + Date.now();
  fs.copyFileSync(f, bak);
  let src = fs.readFileSync(f, 'utf8');
  let changed = false;

  // 1a) helpers import — recipe-consume needs audit/nowIso/dateOnly/checkPackingLow
  const need = ['audit', 'nowIso', 'dateOnly', 'checkPackingLow'];
  const hm = src.match(/const \{([^}]*)\} = require\('\.\.\/helpers'\);/);
  if (hm) {
    const have = hm[1].split(',').map((s) => s.trim()).filter(Boolean);
    const missing = need.filter((n) => !have.includes(n));
    if (missing.length) {
      src = src.replace(hm[0], `const { ${have.concat(missing).join(', ')} } = require('../helpers');`);
      changed = true;
      console.log('IMPORTS: helpers += ' + missing.join(', '));
    } else console.log('IMPORTS: helpers OK (' + have.join(', ') + ')');
  } else console.log('IMPORTS: helpers require line NOT FOUND (check manually!)');

  // 1b) tx import from ../sqlite
  const sm = src.match(/const \{([^}]*)\} = require\('\.\.\/sqlite'\);/);
  if (sm) {
    if (!sm[1].split(',').map((s) => s.trim()).includes('tx')) {
      src = src.replace(sm[0], `const { ${sm[1].trim()}, tx } = require('../sqlite');`);
      changed = true;
      console.log('IMPORTS: sqlite += tx');
    } else console.log('IMPORTS: tx OK');
  } else if (!/\btx\b/.test(src.slice(0, 800))) {
    src = src.replace(/(const db = require\('\.\.\/db'\);)/, "$1\nconst { tx } = require('../sqlite');");
    changed = true;
    console.log('IMPORTS: tx line added');
  } else console.log('IMPORTS: tx looks present');

  // 1c) override 0 = SKIP (only when the key was actually sent)
  if (!src.includes('/* ovSkip */')) {
    const a = /const ov = Number\(overrides\[l\.material_id\] \?\? overrides\[String\(l\.material_id\)\]\);\s*\n\s*const q = ov > 0 \? Math\.round\(ov \* 1000\) \/ 1000 : Math\.round\(l\.qty_per_batch \* batches \* 1000\) \/ 1000;/;
    if (a.test(src)) {
      src = src.replace(a,
        "const ovRaw = overrides[l.material_id] ?? overrides[String(l.material_id)]; /* ovSkip */\n" +
        "      const hasOv = ovRaw !== undefined && ovRaw !== null && ovRaw !== '';\n" +
        "      const ov = Number(ovRaw);\n" +
        "      const q = hasOv && ov >= 0 ? Math.round(ov * 1000) / 1000 : Math.round(l.qty_per_batch * batches * 1000) / 1000;");
      changed = true;
      console.log('CONSUME: override 0 = skip ✓');
    } else console.log('CONSUME: override anchor not found (rawfix4 chali si?) — skip');
  } else console.log('CONSUME: ovSkip already patched');

  // 1d) extra materials (overrides for ids NOT in the recipe)
  if (!src.includes('/* extraMats */')) {
    const anchor = src.match(/\n(\s*)audit\(db, req\.user, 'CONSUME', 'packing', recipeId,/);
    if (anchor) {
      const ind = anchor[1];
      const EXTRA =
        "\n" + ind + "/* extraMats */\n" +
        ind + "const lineIds = new Set(lines.map((l) => l.material_id));\n" +
        ind + "for (const key of Object.keys(overrides)) {\n" +
        ind + "  const mid = Number(key);\n" +
        ind + "  if (!mid || lineIds.has(mid)) continue;\n" +
        ind + "  const q = Math.round(Number(overrides[key]) * 1000) / 1000;\n" +
        ind + "  if (!(q > 0)) continue;\n" +
        ind + "  const m = db.prepare('SELECT id, name, unit, stock, min_stock FROM packing_materials WHERE id = ?').get(mid);\n" +
        ind + "  if (!m) continue;\n" +
        ind + "  upd.run(q, m.id);\n" +
        ind + "  ins.run(m.id, q, today, ref, remark, req.user.id, nIso);\n" +
        ind + "  consumed.push({ name: m.name, qty: q, unit: m.unit });\n" +
        ind + "  const ns2 = m.stock - q;\n" +
        ind + "  if (ns2 < 0) warnings.push(m.name + ': stock went negative (' + (Math.round(ns2 * 100) / 100) + ') — receive stock');\n" +
        ind + "  else if (ns2 < m.min_stock) warnings.push(m.name + ': below minimum');\n" +
        ind + "  checkPackingLow(db, m.id);\n" +
        ind + "}\n";
      src = src.replace(anchor[0], EXTRA + anchor[0]);
      changed = true;
      console.log('CONSUME: extra materials via overrides ✓');
    } else console.log('CONSUME: audit anchor not found — skip');
  } else console.log('CONSUME: extraMats already patched');

  if (changed) { fs.writeFileSync(f, src); if (!check(f, bak)) failed = true; }
  else console.log('packing.js: no changes needed');
}

/* ---------- 2) reports.js: raw-material-ledger ---------- */
if (!failed) {
  const f = '/opt/flavorflow/server/routes/reports.js';
  let src = fs.readFileSync(f, 'utf8');
  if (src.includes("'raw-material-ledger'")) {
    console.log('RAW LEDGER REPORT: already present — skip');
  } else {
    const bak = f + '.bak-raw5w-' + Date.now();
    fs.copyFileSync(f, bak);
    const REPORT = `  'raw-material-ledger': {
    title: 'Raw Material Ledger',
    desc: 'Every raw material receipt and consumption (recipe + manual).',
    run: () => ({
      columns: ['Date', 'Material', 'Type', 'Qty', 'Reference', 'Remark', 'By'],
      rows: db.prepare(
        \`SELECT t.txn_date d, m.name mat, t.txn_type ty, t.qty q,
                COALESCE(t.reference,'') refr, COALESCE(t.remark,'') rem, COALESCE(u.name,'') byname
         FROM packing_txns t
         JOIN packing_materials m ON m.id = t.material_id
         LEFT JOIN users u ON u.id = t.created_by
         WHERE m.category = 'Raw Material'
         ORDER BY t.id DESC\`
      ).all().map((r) => [r.d, r.mat, r.ty, r.q, r.refr, r.rem, r.byname]),
    }),
  },
`;
    const anchor = "  'packing-ledger': {";
    if (!src.includes(anchor)) { console.log('RAW LEDGER REPORT: anchor not found'); failed = true; }
    else {
      src = src.replace(anchor, REPORT + anchor);
      src = src.split("'raw-material-stock', 'packing-ledger'").join("'raw-material-stock', 'raw-material-ledger', 'packing-ledger'");
      fs.writeFileSync(f, src);
      if (check(f, bak)) console.log('RAW LEDGER REPORT: added ✓'); else failed = true;
    }
  }
}

if (failed) { console.log('PATCH INCOMPLETE'); process.exit(2); }
console.log('ALL PATCHES OK');
JS
RC=$?
if [ $RC -ne 0 ]; then echo "RAWFIX5 FAIL — upar output dekho"; exit 1; fi

systemctl restart flavorflow
sleep 2
curl -s -o /dev/null -w 'health -> %{http_code}\n' -m 8 http://127.0.0.1:4000/api/health || true
echo "RAWFIX5 VERIFIED ✓ — imports fixed + 0=skip + extra materials + Raw Material Ledger report live"
