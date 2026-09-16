import { NextRequest } from 'next/server';
import { fail, handle, ok, requireMobileUser } from '../../../_lib/mobileAuth';
// response `leave.type` must be publicType(record.leaveTypeKey, assignCodes(await listLeaveTypes())).type — see _lib/leaveCodes.ts

export const dynamic = 'force-dynamic';

// POST /api/v1/mobile/leaves/:id/reject {reason}  (Bearer, manager/HR/admin)
// → 200 { ok:true, leave:{…status:"rejected", decisionNote} } via the SAME function the webapp's Reject button uses.
// → 400 VALIDATION (reason missing) · 403 FORBIDDEN · 409 CONFLICT (already decided)
export const POST = handle(async (req: NextRequest, ctx: { params: { id: string } }) => {
  const { user } = await requireMobileUser(req);
  const b = await req.json().catch(() => ({}));
  const reason = String(b.reason || '').trim();
  if (!reason) return fail(400, 'VALIDATION', 'Please give a reason for rejecting.');
  const r = await rejectLeave({ approverId: user.id, leaveId: ctx.params.id, reason }); // TODO wire
  if (!r.ok) return fail(r.status || 409, r.code || 'CONFLICT', r.error || 'Could not reject this leave.');
  return ok({ leave: r.leave });
});

async function rejectLeave(a: { approverId: string; leaveId: string; reason: string }): Promise<{ ok: boolean; status?: number; code?: string; error?: string; leave?: unknown }> {
  throw new Error('TODO: webapp reject for ' + a.leaveId + ' by ' + a.approverId);
}
