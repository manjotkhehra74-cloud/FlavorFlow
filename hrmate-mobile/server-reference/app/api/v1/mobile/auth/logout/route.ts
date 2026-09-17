import { NextRequest } from 'next/server';
import { handle, ok, requireMobileUser, revokeDevice, findDevice } from '../../_lib/mobileAuth';
import { removeDevicePushTokens } from '@/lib/fcm';

export const dynamic = 'force-dynamic';

// POST /api/v1/mobile/auth/logout  (Bearer) — revokes this device's token.
// Phase 6: also forgets the device's FCM tokens, so a signed-out phone stops
// receiving this user's notifications even if the app could not call
// DELETE devices/push-token first (offline, killed, …).
export const POST = handle(async (req: NextRequest) => {
  const { tokenId } = await requireMobileUser(req);
  const dev = await findDevice(tokenId);
  await revokeDevice(tokenId);
  if (dev?.deviceId) removeDevicePushTokens(dev.deviceId);
  return ok();
});
