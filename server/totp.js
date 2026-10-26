'use strict';
/** ff-totpfix5 — RFC 6238 TOTP, SHA1, 6 digits, 30-second period. */
const crypto = require('crypto');
const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function b32encode(buf) {
  let bits = 0, value = 0, out = '';
  for (const byte of buf) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += B32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
    value = bits ? value & ((1 << bits) - 1) : 0;
  }
  if (bits) out += B32[(value << (5 - bits)) & 31];
  return out;
}

function b32decode(input) {
  const text = String(input || '').toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = 0, value = 0;
  const out = [];
  for (const ch of text) {
    value = (value << 5) | B32.indexOf(ch);
    bits += 5;
    while (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
    value = bits ? value & ((1 << bits) - 1) : 0;
  }
  return Buffer.from(out);
}

function newSecret() {
  return b32encode(crypto.randomBytes(20));
}

function codeAt(secret, epochSeconds = Math.floor(Date.now() / 1000), digits = 6) {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(Number(epochSeconds) / 30)));
  const digest = crypto.createHmac('sha1', b32decode(secret)).update(counter).digest();
  const offset = digest[digest.length - 1] & 15;
  const binary = digest.readUInt32BE(offset) & 0x7fffffff;
  return String(binary % (10 ** digits)).padStart(digits, '0');
}

function verify(secret, suppliedCode) {
  const code = String(suppliedCode || '').replace(/\s+/g, '');
  if (!secret || !/^\d{6}$/.test(code)) return false;
  const now = Math.floor(Date.now() / 1000);
  // Current step plus two either side = safe ±60-second device drift.
  for (let step = -2; step <= 2; step++) {
    const expected = codeAt(secret, now + step * 30);
    if (crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(code))) return true;
  }
  return false;
}

module.exports = {newSecret, codeAt, verify};
