import { NextRequest } from 'next/server';
import { handle, ok, fail, requireMobileUser, findDevice } from '../../_lib/mobileAuth';
import { registerPushToken, removePushToken } from '@/lib/fcm';

export const dynamic = 'force-dynamic';

// POST /api/v1/mobile/devices/push-token  (Bearer)  {token, platform?, deviceId?}
// Registers this phone's FCM token for the signed-in user (upsert; a rotated
// token replaces the previous one of the same device). → {ok:true}
export const POST = handle(async (req: NextRequest) => {
  const { user, tokenId } = await requireMobileUser(req);
  const body = (await req.json().catch(() => ({}))) as { token?: unknown; platform?: unknown; deviceId?: unknown };
  const token = typeof body.token === 'string' ? body.token.trim() : '';
  if (!token || token.length < 20 || token.length > 4096) return fail(400, 'VALIDATION', 'token is required.');
  const platform = typeof body.platform === 'string' && body.platform.trim() ? body.platform.trim().toLowerCase() : 'android';
  // device id: what the app sends, else the one recorded at login for this session
  let deviceId = typeof body.deviceId === 'string' ? body.deviceId.trim() : '';
  if (!deviceId) deviceId = (await findDevice(tokenId))?.deviceId || '';
  registerPushToken(user.id, token, platform, deviceId);
  return ok();
});

// DELETE /api/v1/mobile/devices/push-token?token=…  (Bearer)
// The app calls this right before sign-out. → {ok:true} (also when nothing matched)
export const DELETE = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const token = (req.nextUrl.searchParams.get('token') || '').trim();
  if (token) removePushToken(user.id, token);
  return ok();
});
