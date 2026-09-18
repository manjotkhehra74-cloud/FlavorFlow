#!/usr/bin/env bash
# publish-apk.sh — put a TESTED native HRMate APK on https://hr.flavorflow.co.in/download
#
# Runs ON the VPS (hrmate-prod). No git, no image rebuild: the file is copied into the
# persistent data volume that /api/download/apk serves from.
#
#   sudo bash /opt/hrmate/scripts/publish-apk.sh ~/app-prod-release.apk 3.1.0 31
#   (or, without touching the checkout)
#   curl -fsSL <raw url of this file> | sudo bash -s -- ~/app-prod-release.apk 3.1.0 31
#
# v3 safety gates (added after the 3.0.0 bytes were published as "3.1.0" by mistake):
#   * the versionName INSIDE the APK must equal <version>  -> catches "uploaded the old file"
#   * if the named file is wrong/missing but another *.apk next to it has the right version
#     (browsers save re-downloads as "app-prod-release (1).apk"), that one is used and named
#   * the same bytes must not already be published (now or earlier: releases/history.log)
#   * reports whether Firebase Messaging + google-services config are inside the APK
#   * after publishing, the uploaded file and previously-published leftovers are removed from
#     the home directory so a stale copy can never be re-published (served copy = volume)
# Inspection runs with node INSIDE the container (always present) — no unzip/python needed.
set -euo pipefail
APK="${1:-}"; VER="${2:-}"; BUILD="${3:-}"
if [ -z "$APK" ] || [ -z "$VER" ] || [ -z "$BUILD" ]; then
  echo "usage: sudo bash $0 <app-prod-release.apk> <version e.g. 3.1.0> <build e.g. 31>"; exit 1
fi
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "STOP: version must look like 3.1.0"; exit 1; }
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "STOP: build must be a number"; exit 1; }
CONTAINER="${HRMATE_CONTAINER:-hrmate-hrmate-1}"
docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" || { echo "STOP: container $CONTAINER is not running"; exit 1; }
TMP=$(mktemp -d)
CTMP="/tmp/hrmate-publish-$$"
cleanup() { rm -rf "$TMP"; docker exec -u 0 "$CONTAINER" rm -rf "$CTMP" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# --- APK inspector (node, runs inside the container) ---------------------------------------
cat > "$TMP/inspect.js" <<'JS'
// Prints one line: status=<ok|nozip|nomanifest|badxml> versions=<x.y.z,...|?> push=<yes|lib-only|no|?>
//   versions : every dotted x.y.z string in the binary AndroidManifest.xml string pool
//              (android:versionName is always stored there)
//   push     : yes      = Firebase Messaging in the manifest AND google-services resources present
//              lib-only = the library is there but the APK was built WITHOUT google-services.json
'use strict';
const fs = require('fs'), zlib = require('zlib');
function out(status, versions, push) { console.log(`status=${status} versions=${versions} push=${push}`); process.exit(0); }
let buf;
try { buf = fs.readFileSync(process.argv[2]); } catch (e) { out('nozip', '?', '?'); }
// central directory
let eocd = -1;
for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 65557); i--) {
  if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
}
if (eocd < 0) out('nozip', '?', '?');
const count = buf.readUInt16LE(eocd + 10), cdOff = buf.readUInt32LE(eocd + 16);
const entries = new Map();
let p = cdOff;
try {
  for (let i = 0; i < count; i++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) break;
    const method = buf.readUInt16LE(p + 10), csize = buf.readUInt32LE(p + 20);
    const nlen = buf.readUInt16LE(p + 28), xlen = buf.readUInt16LE(p + 30), clen = buf.readUInt16LE(p + 32);
    const loff = buf.readUInt32LE(p + 42);
    entries.set(buf.toString('utf8', p + 46, p + 46 + nlen), { method, csize, loff });
    p += 46 + nlen + xlen + clen;
  }
} catch (e) { out('nozip', '?', '?'); }
function read(name) {
  const en = entries.get(name); if (!en) return null;
  try {
    if (buf.readUInt32LE(en.loff) !== 0x04034b50) return null;
    const nlen = buf.readUInt16LE(en.loff + 26), xlen = buf.readUInt16LE(en.loff + 28);
    const start = en.loff + 30 + nlen + xlen, raw = buf.subarray(start, start + en.csize);
    if (en.method === 0) return raw;
    if (en.method === 8) return zlib.inflateRawSync(raw);
  } catch (e) { /* fall through */ }
  return null;
}
const man = read('AndroidManifest.xml');
if (!man) out('nomanifest', '?', '?');
const strings = [];
try {
  if (man.readUInt16LE(0) !== 0x0003) out('badxml', '?', '?');
  let off = 8;
  while (off + 8 <= man.length) {
    const ctype = man.readUInt16LE(off), hsize = man.readUInt16LE(off + 2), csize = man.readUInt32LE(off + 4);
    if (ctype === 0x0001) { // ResStringPool
      const cnt = man.readUInt32LE(off + 8), flags = man.readUInt32LE(off + 16), sstart = man.readUInt32LE(off + 20);
      const utf8 = (flags & 0x100) !== 0, base = off + sstart;
      for (let i = 0; i < cnt; i++) {
        let q = base + man.readUInt32LE(off + hsize + 4 * i);
        if (utf8) {
          let n = man[q++]; if (n & 0x80) q++;
          let m = man[q++]; if (m & 0x80) m = ((m & 0x7f) << 8) | man[q++];
          strings.push(man.toString('utf8', q, q + m));
        } else {
          let n = man.readUInt16LE(q); q += 2;
          if (n & 0x8000) { n = ((n & 0x7fff) << 16) | man.readUInt16LE(q); q += 2; }
          strings.push(man.toString('utf16le', q, q + 2 * n));
        }
      }
      break;
    }
    if (csize === 0) break;
    off += csize;
  }
} catch (e) { out('badxml', '?', '?'); }
const versions = [...new Set(strings.filter(s => /^\d+\.\d+\.\d+$/.test(s)))].sort();
const lib = strings.some(s => s.includes('com.google.firebase.messaging'));
const arsc = read('resources.arsc') || Buffer.alloc(0);
const cfg = arsc.includes(Buffer.from('gcm_defaultSenderId', 'utf8')) || arsc.includes(Buffer.from('gcm_defaultSenderId', 'utf16le'));
out('ok', versions.length ? versions.join(',') : '?', lib ? (cfg ? 'yes' : 'lib-only') : 'no');
JS
docker exec -u 0 "$CONTAINER" mkdir -p "$CTMP"
docker cp "$TMP/inspect.js" "$CONTAINER:$CTMP/inspect.js"
inspect() {  # sets INFO_STATUS INFO_VERS INFO_PUSH for file $1 (never fails the script)
  INFO_STATUS="nozip"; INFO_VERS="?"; INFO_PUSH="?"
  local magic out
  magic=$(head -c 2 "$1" | od -An -c | tr -d ' ')
  [ "$magic" = "PK" ] || { INFO_STATUS="notzip:$magic"; return 0; }
  docker cp "$1" "$CONTAINER:$CTMP/apk" >/dev/null 2>&1 || return 0
  out=$(docker exec -u 0 "$CONTAINER" node "$CTMP/inspect.js" "$CTMP/apk" 2>/dev/null || true)
  docker exec -u 0 "$CONTAINER" rm -f "$CTMP/apk" >/dev/null 2>&1 || true
  case "$out" in
    status=*) INFO_STATUS=$(sed -n 's/^status=\([^ ]*\).*/\1/p' <<<"$out")
              INFO_VERS=$(sed -n 's/.* versions=\([^ ]*\).*/\1/p' <<<"$out")
              INFO_PUSH=$(sed -n 's/.* push=\([^ ]*\).*/\1/p' <<<"$out") ;;
  esac
  return 0
}
explain() {  # human text for a non-ok INFO_STATUS
  case "$1" in
    notzip:*) echo "not an APK (starts with '${1#notzip:}' — a saved web page, not the download)" ;;
    nozip) echo "damaged/incomplete upload (zip directory missing — upload again and wait for the progress bar)" ;;
    nomanifest) echo "no AndroidManifest.xml inside — not an Android APK" ;;
    *) echo "unreadable ($1)" ;;
  esac
}

# --- candidates: the named file first, then every other *.apk next to it (newest first) -----
DIR=$(dirname "$APK")
[ -f "$APK" ] && APK=$(readlink -f "$APK")
declare -a CANDS=()
[ -f "$APK" ] && CANDS+=("$APK")
while IFS= read -r f; do
  [ -n "$f" ] || continue
  f=$(readlink -f "$f"); [ "$f" = "$APK" ] || CANDS+=("$f")
done < <(ls -1t "$DIR"/*.apk 2>/dev/null || true)
if [ "${#CANDS[@]}" -eq 0 ]; then
  echo "STOP: file not found: $APK (no *.apk in $DIR). Upload the APK first (SSH -> UPLOAD FILE), then run again."; exit 1
fi

CHOSEN=""; CHOSEN_PUSH="?"; FALLBACK=""; FALLBACK_PUSH="?"; LISTING=""
for f in "${CANDS[@]}"; do
  inspect "$f"
  if [ "$INFO_STATUS" != "ok" ] && [ "$INFO_STATUS" != "badxml" ]; then
    LISTING+="  $f -> $(explain "$INFO_STATUS")"$'\n'; continue
  fi
  LISTING+="  $f -> version ${INFO_VERS}, push ${INFO_PUSH}, $(stat -c %s "$f") bytes, uploaded $(date -r "$f" '+%d-%m-%Y %H:%M')"$'\n'
  case ",$INFO_VERS," in
    *",$VER,"*) [ -n "$CHOSEN" ] || { CHOSEN="$f"; CHOSEN_PUSH="$INFO_PUSH"; } ;;
    ",?,")      [ -n "$FALLBACK" ] || { FALLBACK="$f"; FALLBACK_PUSH="$INFO_PUSH"; } ;;
  esac
done
if [ -z "$CHOSEN" ] && [ -n "$FALLBACK" ]; then
  echo "warn: could not read the version inside $FALLBACK — trusting you that it is $VER"
  CHOSEN="$FALLBACK"; CHOSEN_PUSH="$FALLBACK_PUSH"
fi
if [ -z "$CHOSEN" ]; then
  echo "STOP: no APK here is version $VER. Files found:"
  printf '%s' "$LISTING"
  echo "  -> WRONG FILE (an older download). On your PC: Codemagic -> latest build -> download"
  echo "     app-prod-release.apk again, upload that new file with SSH -> UPLOAD FILE, run again."
  exit 1
fi
[ "$CHOSEN" = "$APK" ] || echo "note: using $CHOSEN (it is version $VER; $APK is not)"
echo "file: $CHOSEN ($(stat -c %s "$CHOSEN") bytes, uploaded $(date -r "$CHOSEN" '+%d-%m-%Y %H:%M'))"
echo "version inside APK: $VER ✓"
case "$CHOSEN_PUSH" in
  yes)      echo "push notifications inside APK: yes ✓" ;;
  lib-only) echo "WARNING: this APK was built WITHOUT google-services.json — push notifications will NOT work."
            echo "         (Codemagic must build a commit that contains mobile/android/app/google-services.json)" ;;
  no)       echo "note: this APK has no Firebase Messaging (pre-3.1.0 code)" ;;
  *)        echo "push notifications inside APK: unknown (could not inspect)" ;;
esac

# --- same bytes already published? ------------------------------------------------------------
SHA=$(sha256sum "$CHOSEN" | cut -d' ' -f1)
CUR=$(docker exec "$CONTAINER" cat /app/data/releases/apk-info.json 2>/dev/null || true)
CUR_SHA=$(printf '%s' "$CUR" | grep -o '"sha256":"[0-9a-f]*"' | cut -d'"' -f4 || true)
CUR_VER=$(printf '%s' "$CUR" | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || true)
CUR_BUILD=$(printf '%s' "$CUR" | grep -o '"build":[0-9]*' | cut -d: -f2 || true)
HIST=$(docker exec "$CONTAINER" cat /app/data/releases/history.log 2>/dev/null || true)
if [ -z "$HIST" ] && [ -n "$CUR_SHA" ]; then   # first run of v3: remember what is live now
  HIST="seed $CUR_VER $CUR_BUILD $CUR_SHA"
  docker exec -u 0 "$CONTAINER" sh -c "echo '$HIST' >> /app/data/releases/history.log"
fi
if [ -n "$CUR_SHA" ] && [ "$SHA" = "$CUR_SHA" ] && [ "$VER" = "$CUR_VER" ] && [ "$BUILD" = "$CUR_BUILD" ]; then
  echo "already published: $VER ($BUILD) with these exact bytes — nothing to do"; exit 0
fi
if printf '%s\n' "$HIST" | grep -q " $SHA\$"; then
  echo "STOP: these exact bytes were already published earlier ($(printf '%s\n' "$HIST" | grep " $SHA\$" | head -1 | cut -d' ' -f1-3)) — this is an OLD file."
  echo "  -> download the APK from the latest Codemagic build, upload it, run again."; exit 1
fi

# --- publish ----------------------------------------------------------------------------------
NAME="HRMate-${VER}.apk"
SIZE=$(stat -c %s "$CHOSEN")
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"version":"%s","build":%s,"file":"%s","sizeBytes":%s,"sha256":"%s","publishedAt":"%s"}\n' \
  "$VER" "$BUILD" "$NAME" "$SIZE" "$SHA" "$NOW" > "$TMP/apk-info.json"
docker exec -u 0 "$CONTAINER" mkdir -p /app/data/releases
docker cp "$CHOSEN" "$CONTAINER:/app/data/releases/$NAME"
docker cp "$TMP/apk-info.json" "$CONTAINER:/app/data/releases/apk-info.json"
docker exec -u 0 "$CONTAINER" sh -c "echo '$NOW $VER $BUILD $SHA' >> /app/data/releases/history.log"
docker exec -u 0 "$CONTAINER" chmod -R a+rX /app/data/releases
echo "PUBLISHED $NAME  ($SIZE bytes, sha256 $SHA)"

# --- tidy the home directory: the published file + anything published before ------------------
rm -f "$CHOSEN" && echo "removed $CHOSEN (the served copy is inside the container)"
for f in "${CANDS[@]}"; do
  [ -f "$f" ] || continue
  s=$(sha256sum "$f" | cut -d' ' -f1)
  if printf '%s\n' "$HIST" | grep -q " $s\$"; then rm -f "$f" && echo "removed old $f (was published earlier)"; fi
done
echo "--- verify"
curl -s https://hr.flavorflow.co.in/api/download/apk-info; echo
curl -s -o /dev/null -w 'download: HTTP %{http_code}, %{size_download} bytes\n' https://hr.flavorflow.co.in/api/download/apk
