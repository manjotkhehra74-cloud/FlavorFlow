import { NextRequest } from 'next/server';
import { fail, handle, ok, saveDevice, signToken, verifyCredentials } from '../../_lib/mobileAuth';

export const dynamic = 'force-dynamic';

// POST /api/v1/mobile/auth/login {login, password, deviceId, deviceName}
export const POST = handle(async (req: NextRequest) => {
  const body = await req.json().catch(() => ({}));
  const login = String(body.login || '').trim();
  const password = String(body.password || '');
  const deviceId = String(body.deviceId || '').trim() || 'unknown';
  const deviceName = String(body.deviceName || 'Android').slice(0, 60);
  if (!login || !password) return fail(400, 'VALIDATION', 'Enter your employee code or email and password.');

  const user = await verifyCredentials(login, password);
  if (!user) return fail(401, 'UNAUTHENTICATED', 'Incorrect employee code / email or password.');

  const { token, tokenId, expiresAt } = signToken(user.id);
  await saveDevice({ userId: user.id, deviceId, deviceName, tokenId, createdAt: new Date().toISOString(), revokedAt: null });
  return ok({ token, expiresAt, user });
});
