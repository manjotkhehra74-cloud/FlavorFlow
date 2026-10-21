/**
 * jwt.js — Minimal dependency-free HS256 JSON Web Token sign/verify.
 */
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

function loadSecret() {
  const envSecret = String(process.env.JWT_SECRET || '').trim();
  if (envSecret.length >= 32) return envSecret;

  const secretPath = process.env.JWT_SECRET_FILE || path.join(__dirname, '.jwt-secret');
  try {
    const fileSecret = fs.readFileSync(secretPath, 'utf8').trim();
    if (fileSecret.length >= 32) return fileSecret;
  } catch (_) {
    // The deployment can provide a protected secret file or set JWT_SECRET.
  }
  throw new Error('Configure JWT_SECRET (at least 32 characters) or provide a secure JWT secret file.');
}

const SECRET = loadSecret();
const TTL_SECONDS = Number(process.env.JWT_TTL_SECONDS || 60 * 60 * 12); // 12 h

function b64url(buf) {
  return Buffer.from(buf).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function b64urlJson(obj) {
  return b64url(JSON.stringify(obj));
}

function sign(payload, ttlSeconds = TTL_SECONDS) {
  const header = b64urlJson({ alg: 'HS256', typ: 'JWT' });
  const now = Math.floor(Date.now() / 1000);
  const body = b64urlJson({ ...payload, iat: now, exp: now + ttlSeconds });
  const data = `${header}.${body}`;
  const sig = crypto.createHmac('sha256', SECRET).update(data).digest();
  return `${data}.${b64url(sig)}`;
}

function verify(token) {
  if (typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [header, body, sig] = parts;
  const expected = crypto.createHmac('sha256', SECRET).update(`${header}.${body}`).digest();
  let given;
  try {
    given = Buffer.from(sig.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  } catch {
    return null;
  }
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return null;
  try {
    const payload = JSON.parse(Buffer.from(body.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8'));
    if (!payload.exp || payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

module.exports = { sign, verify };
