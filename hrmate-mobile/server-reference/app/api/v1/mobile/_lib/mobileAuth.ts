// Shared auth helper for /api/v1/mobile/* — the ONLY place that knows about
// the mobile JWT. Every mobile route calls requireMobileUser(req).
//
// Wire the two TODO functions to the webapp's EXISTING user model. Do not add
// a second user table and do not change how the webapp itself logs in.
import { NextRequest, NextResponse } from 'next/server';
import { createHmac, randomUUID, timingSafeEqual } from 'crypto';

export type MobileUser = {
  id: string;
  code: string;          // employee code, e.g. WKH00416
  name: string;
  email: string;
  role: string;          // employee | manager | hr | admin | superadmin
  department: string;
  avatarUrl: string | null;
  permissions: string[]; // reuse the webapp's permission strings
};

// ---- TODO 1: verify credentials with the webapp's existing logic ----------
// `login` is an employee code OR an email. Return the user or null.
export async function verifyCredentials(login: string, password: string): Promise<MobileUser | null> {
  throw new Error('TODO: call the webapp\'s existing credential check (same one the login page uses)');
}

// ---- TODO 2: load a user by id (for GET /me and token checks) -------------
export async function loadUser(id: string): Promise<MobileUser | null> {
  throw new Error('TODO: load the user from the webapp\'s existing store');
}

// ---- device / token registry (revocation) --------------------------------
// Minimal shape; back it with whatever the webapp already uses for persistence.
export type MobileDevice = { userId: string; deviceId: string; deviceName: string; tokenId: string; createdAt: string; revokedAt: string | null };
export async function saveDevice(d: MobileDevice): Promise<void> { throw new Error('TODO: persist device'); }
export async function findDevice(tokenId: string): Promise<MobileDevice | null> { throw new Error('TODO: find device by tokenId'); }
export async function revokeDevice(tokenId: string): Promise<void> { throw new Error('TODO: set revokedAt'); }

// ---- JWT (HS256, no external dependency) ----------------------------------
const SECRET = process.env.MOBILE_JWT_SECRET || process.env.AUTH_SECRET || process.env.NEXTAUTH_SECRET || '';
const TTL_SECONDS = 30 * 24 * 3600;
const b64u = (b: Buffer | string) => Buffer.from(b).toString('base64url');

export function signToken(userId: string): { token: string; tokenId: string; expiresAt: string } {
  if (!SECRET) throw new Error('MOBILE_JWT_SECRET is not set');
  const tokenId = randomUUID();
  const now = Math.floor(Date.now() / 1000);
  const header = b64u(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const payload = b64u(JSON.stringify({ sub: userId, jti: tokenId, iat: now, exp: now + TTL_SECONDS, aud: 'hrmate-mobile' }));
  const sig = createHmac('sha256', SECRET).update(`${header}.${payload}`).digest('base64url');
  return { token: `${header}.${payload}.${sig}`, tokenId, expiresAt: new Date((now + TTL_SECONDS) * 1000).toISOString() };
}

export function verifyToken(token: string): { sub: string; jti: string } | null {
  try {
    const [h, p, s] = token.split('.');
    if (!h || !p || !s) return null;
    const expected = createHmac('sha256', SECRET).update(`${h}.${p}`).digest('base64url');
    if (expected.length !== s.length || !timingSafeEqual(Buffer.from(expected), Buffer.from(s))) return null;
    const payload = JSON.parse(Buffer.from(p, 'base64url').toString('utf8'));
    if (payload.aud !== 'hrmate-mobile' || payload.exp < Math.floor(Date.now() / 1000)) return null;
    return { sub: String(payload.sub), jti: String(payload.jti) };
  } catch {
    return null;
  }
}

// ---- helpers used by every route -----------------------------------------
export class MobileError extends Error {
  constructor(public status: number, public code: string, message: string, public extra: Record<string, unknown> = {}) { super(message); }
}
export const fail = (status: number, code: string, error: string, extra: Record<string, unknown> = {}) =>
  NextResponse.json({ ok: false, error, code, ...extra }, { status });
export const ok = (data: Record<string, unknown> = {}) => NextResponse.json({ ok: true, ...data });

export function bearer(req: NextRequest): string | null {
  const h = req.headers.get('authorization') || '';
  return h.toLowerCase().startsWith('bearer ') ? h.slice(7).trim() : null;
}

/** Resolve the mobile user or throw a MobileError(401). Never touches cookies. */
export async function requireMobileUser(req: NextRequest): Promise<{ user: MobileUser; tokenId: string }> {
  const t = bearer(req);
  if (!t) throw new MobileError(401, 'UNAUTHENTICATED', 'Sign in required.');
  const v = verifyToken(t);
  if (!v) throw new MobileError(401, 'UNAUTHENTICATED', 'Session expired. Please sign in again.');
  const dev = await findDevice(v.jti);
  if (!dev || dev.revokedAt) throw new MobileError(401, 'UNAUTHENTICATED', 'This device was signed out.');
  const user = await loadUser(v.sub);
  if (!user) throw new MobileError(401, 'UNAUTHENTICATED', 'Account not found.');
  return { user, tokenId: v.jti };
}

/** Wrap a handler so MobileError → JSON error, anything else → 500 JSON.
 *  The second argument (route context with `params`, e.g. `[id]` routes) is passed through. */
export function handle<C = unknown>(fn: (req: NextRequest, ctx: C) => Promise<NextResponse>) {
  return async (req: NextRequest, ctx: C) => {
    try { return await fn(req, ctx); }
    catch (e: unknown) {
      if (e instanceof MobileError) return fail(e.status, e.code, e.message, e.extra);
      console.error('[mobile-api]', e);
      return fail(500, 'SERVER', 'Something went wrong on the server.');
    }
  };
}
