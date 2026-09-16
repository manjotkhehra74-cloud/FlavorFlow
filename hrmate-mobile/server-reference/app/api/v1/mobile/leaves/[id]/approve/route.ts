import { NextRequest } from 'next/server';
import { fail, handle, ok, requireMobileUser } from '../../../_lib/mobileAuth';

export const dynamic = 'force-dynamic';

// POST /api/v1/mobile/leaves/:id/approve  (Bearer, manager/HR/admin)
// → 200 { ok:true, leave:{…status:"approved"} } via the SAME function the webapp's Approve button uses
//   (balance deduction, attendance marking, notification to the employee).
// → 403 FORBIDDEN (not this caller's to approve) · 404 VALIDATION (unknown id) · 409 CONFLICT (already decided)
export const POST = handle(async (req: NextRequest, ctx: { params: { id: string } }) => {
  const { user } = await requireMobileUser(req);
  const id = ctx.params.id;
  const r = await approveLeave({ approverId: user.id, leaveId: id }); // TODO wire
  if (!r.ok) return fail(r.status || 409, r.code || 'CONFLICT', r.error || 'Could not approve this leave.');
  return ok({ leave: r.leave });
});

async function approveLeave(a: { approverId: string; leaveId: string }): Promise<{ ok: boolean; status?: number; code?: string; error?: string; leave?: unknown }> {
  throw new Error('TODO: webapp approve for ' + a.leaveId + ' by ' + a.approverId);
}
