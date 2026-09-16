import { NextRequest } from 'next/server';
import { handle, ok, requireMobileUser } from '../../_lib/mobileAuth';
import { listLeaveTypes, shortCode } from '../../_lib/leaveTypes';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/leaves/balance  (Bearer)
// → { ok:true, available: number, pending: number,
//     balances:[{ type:"CL"|"SL"|"EL"|…, name, total, used, available }] }
// `available` = sum of all types (the Home tile shows it); Phase 3 uses `balances` per type.
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const balance = await loadLeaveBalance(user.id); // TODO wire
  // `type` MUST be shortCode(t) from _lib/leaveTypes.ts (same value the app sends back on POST leaves).
  const types = await listLeaveTypes();
  const balances = (balance.balances as Array<Record<string, unknown>>).map((row) => {
    const t = types.find((x) => x.key === row.key || x.key === row.type || shortCode(x) === row.type);
    return { ...row, type: t ? shortCode(t) : String(row.type || '').toUpperCase(), name: t?.name ?? row.name };
  });
  return ok({ ...balance, balances });
});

async function loadLeaveBalance(userId: string): Promise<Record<string, unknown>> {
  throw new Error('TODO: webapp leave balance for user ' + userId + ' (same numbers the Leaves page shows)');
}
