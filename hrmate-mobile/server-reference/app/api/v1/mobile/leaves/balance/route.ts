import { NextRequest } from 'next/server';
import { handle, ok, requireMobileUser } from '../../_lib/mobileAuth';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/leaves/balance  (Bearer)
// → { ok:true, available: number, pending: number,
//     balances:[{ type:"CL"|"SL"|"EL"|…, name, total, used, available }] }
// `available` = sum of all types (the Home tile shows it); Phase 3 uses `balances` per type.
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const balance = await loadLeaveBalance(user.id); // TODO wire
  return ok(balance);
});

async function loadLeaveBalance(userId: string): Promise<Record<string, unknown>> {
  throw new Error('TODO: webapp leave balance for user ' + userId + ' (same numbers the Leaves page shows)');
}
