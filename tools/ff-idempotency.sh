#!/usr/bin/env bash
# FlavorFlow — Idempotency-Key replay on the server (MAN-13, offline entries).
#
#   The phone keeps an entry it could not send and re-sends it with an
#   `Idempotency-Key` header. Without this patch a re-send after a lost reply
#   would save the entry twice. With it, a repeated key returns the FIRST saved
#   reply and writes nothing new.
#     - only 2xx replies are stored (rejected requests can be fixed and retried)
#     - keys are kept 30 days in table idempotency_keys (erp.db)
#     - a key that is still being processed answers 409 (the phone retries later)
#   Idempotent · backup first · node --check + auto-restore · restarts the service.
set -u
if [ -d /opt/flavorflow-saas/core ]; then DIR=/opt/flavorflow-saas/core; SVC=flavorflow-saas; MODE=saas
elif [ -d /opt/flavorflow/server ]; then DIR=/opt/flavorflow/server; SVC=flavorflow; MODE=factory
else echo "FATAL: server folder nahi labhi"; exit 1; fi
echo "=== FF-IDEMPOTENCY ($MODE) $(date) ==="
cd "$DIR" || exit 1
TS=$(date +%s)
mkdir -p /opt/flavorflow/backups
cp -a server.js "/opt/flavorflow/backups/server.js.bak-idem-$TS" || { echo "FATAL: backup nahi bana"; exit 1; }
echo "BACKUP -> /opt/flavorflow/backups/server.js.bak-idem-$TS"

BLOCK=/tmp/ff-idem-block-$TS.js
cat > "$BLOCK" <<'EOF'
// --- ff-idempotency v1: replay the saved reply for a repeated Idempotency-Key ---
/* ffIdempotency */
try {
  const _idDb = require('./db');
  const _idCrypto = require('crypto');
  _idDb.prepare("CREATE TABLE IF NOT EXISTS idempotency_keys (scope TEXT NOT NULL, k TEXT NOT NULL, status INTEGER NOT NULL, body TEXT, created_at TEXT NOT NULL, PRIMARY KEY (scope, k))").run();
  _idDb.prepare("DELETE FROM idempotency_keys WHERE created_at < datetime('now', '-30 days')").run();
  const _idBusy = new Set();
  app.use((req, res, next) => {
    const key = req.get('Idempotency-Key');
    if (!key || !req.get('authorization') || !['POST', 'PUT', 'DELETE'].includes(req.method)) return next();
    if (!/^[A-Za-z0-9._:-]{8,80}$/.test(key)) return res.status(400).json({ ok: false, error: 'Idempotency-Key format galat hai' });
    const scope = _idCrypto.createHash('sha256').update(req.method + ' ' + req.originalUrl).digest('hex');
    const saved = _idDb.prepare('SELECT status, body FROM idempotency_keys WHERE scope = ? AND k = ?').get(scope, key);
    if (saved) return res.status(saved.status).type('application/json').send(saved.body || '{}');
    const lock = scope + ':' + key;
    if (_idBusy.has(lock)) return res.status(409).json({ ok: false, error: 'Yeh entry abhi save ho rahi hai — thodi der baad dobara try karo', code: 'IDEMPOTENT_BUSY' });
    _idBusy.add(lock);
    const _sendOriginal = res.send.bind(res);
    res.send = function (payload) {
      try {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          const text = typeof payload === 'string' ? payload : (Buffer.isBuffer(payload) ? payload.toString('utf8') : JSON.stringify(payload));
          _idDb.prepare("INSERT OR IGNORE INTO idempotency_keys (scope, k, status, body, created_at) VALUES (?, ?, ?, ?, datetime('now'))").run(scope, key, res.statusCode, text);
        }
      } catch (_) { /* saving the replay is best-effort */ }
      _idBusy.delete(lock);
      return _sendOriginal(payload);
    };
    res.on('close', () => _idBusy.delete(lock));
    next();
  });
} catch (e) { console.error('ffIdempotency mount failed: ' + e.message); }
// --- end ff-idempotency v1 ---
EOF

FF_BLOCK="$BLOCK" node <<'JS'
const fs = require('fs'), cp = require('child_process');
const f = process.cwd() + '/server.js';
let src = fs.readFileSync(f, 'utf8');
const block = fs.readFileSync(process.env.FF_BLOCK, 'utf8');
const START = '// --- ff-idempotency v';
const END_RE = /\/\/ --- end ff-idempotency v[0-9]+ ---[ \t]*\n?/;
const bak = f + '.bak-idem-' + Date.now();
fs.copyFileSync(f, bak);
const si = src.indexOf(START);
if (si >= 0) {
  const em = END_RE.exec(src.slice(si));
  if (em) {
    const ls = src.lastIndexOf('\n', si) + 1;
    src = src.slice(0, ls) + src.slice(si + em.index + em[0].length);
    console.log('old ff-idempotency block removed (upgrade)');
  }
}
const firstApi = src.match(/^[ \t]*app\.use\(\s*['"]\/api(?:\/|['"])/m);
if (firstApi) {
  src = src.slice(0, firstApi.index) + block + '\n' + src.slice(firstApi.index);
  console.log('ff-idempotency mounted before the first /api route');
} else if (/app\.listen\(/.test(src)) {
  src = src.replace(/app\.listen\(/, block + '\napp.listen(');
  console.log('ff-idempotency mounted before app.listen');
} else {
  console.log('FATAL: koi anchor nahi labhya (app.use /api ya app.listen)');
  process.exit(1);
}
fs.writeFileSync(f, src);
try { cp.execSync('node --check "' + f + '"'); console.log('SERVER: syntax OK'); }
catch (e) { fs.copyFileSync(bak, f); console.log('SERVER: SYNTAX FAIL — restored'); process.exit(1); }
process.exit(3); // 3 = changed
JS
RC=$?
rm -f "$BLOCK"
if [ $RC -eq 1 ]; then echo "IDEMPOTENCY FAILED (upar dekho, server purane version te hai)"; exit 1; fi
if [ $RC -eq 3 ] && [ -z "${FF_NO_RESTART:-}" ]; then
  systemctl restart "$SVC" && echo "SERVER: $SVC restarted"
  sleep 4
fi
ST=$(curl -s -o /dev/null -w '%{http_code}' -m 6 http://127.0.0.1:4000/api/health 2>/dev/null)
echo "HEALTH /api/health -> $ST $( [ "$ST" = "200" ] && echo '✓' || echo '✗ (journalctl -u '"$SVC"' -n 40 dekho)')"
echo "IDEMPOTENCY DONE ✓ — hun offline entries duplicate nahi banange"
