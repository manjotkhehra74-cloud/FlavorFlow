import { NextRequest } from 'next/server';
import { handle, ok, requireMobileUser, revokeDevice } from '../../_lib/mobileAuth';

export const dynamic = 'force-dynamic';

// POST /api/v1/mobile/auth/logout  (Bearer) — revokes this device's token
export const POST = handle(async (req: NextRequest) => {
  const { tokenId } = await requireMobileUser(req);
  await revokeDevice(tokenId);
  return ok();
});
