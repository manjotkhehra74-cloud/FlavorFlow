import { NextRequest } from 'next/server';
import { handle, ok, requireMobileUser } from '../../_lib/mobileAuth';
import { assignCodes, matchLeaveType } from '../../_lib/leaveCodes';
import { listLeaveTypes } from '../../_lib/leaveTypes';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/leaves/balance  (Bearer)
// → { ok:true, available: number, pending: number,
//     balances:[{ type:"CL"|"SL"|"EL"|…, name, total, used, available }] }
// `available` = sum of all types (the Home tile shows it); Phase 3 uses `balances` per type.
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const balance = await loadLeaveBalance(user.id); // TODO wire
  // `type` MUST be the unique code from _lib/leaveCodes.ts ("EL") — the app sends it back on POST leaves.
  const types = assignCodes(await listLeaveTypes());
  const balances = (balance.balances as Array<Record<string, unknown>>).map((row) => {
    const t = matchLeaveType(String(row.key ?? row.type ?? ''), types);
    return { ...row, type: t ? t.code : String(row.type || '').toUpperCase(), name: t?.name ?? row.name };
  });
  return ok({ ...balance, balances });
});

async function loadLeaveBalance(userId: string): Promise<Record<string, unknown>> {
  throw new Error('TODO: webapp leave balance for user ' + userId + ' (same numbers the Leaves page shows)');
}
