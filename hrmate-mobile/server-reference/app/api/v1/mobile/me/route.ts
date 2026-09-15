import { NextRequest } from 'next/server';
import { handle, ok, requireMobileUser } from '../_lib/mobileAuth';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/me  (Bearer) — the template every later route copies
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  return ok({ user });
});
