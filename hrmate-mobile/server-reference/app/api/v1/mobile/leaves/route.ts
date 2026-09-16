import { NextRequest } from 'next/server';
import { fail, handle, ok, requireMobileUser } from '../_lib/mobileAuth';
import { assignCodes, matchLeaveType } from '../_lib/leaveCodes';
import { listLeaveTypes } from '../_lib/leaveTypes';

export const dynamic = 'force-dynamic';

// LEAVE TYPE CODES: `type` in every payload (balance, list, create, approve, reject) is the SAME short
// code that leaves/balance returns (e.g. "EL"), plus `typeName` ("Earned Leave (EL)"). The webapp's
// internal key differs (e.g. "lt_earned") — _lib/leaveCodes.ts owns the mapping: assignCodes() gives every
// type a unique code, matchLeaveType() resolves incoming values, publicType() formats responses.
// GET items must use publicType(record.leaveTypeKey, types) → {type:"EL", typeName:"Earned Leave"}.
//
// Shared leave shape (list, create, approve, reject all return it):
// { id, type:"EL", typeName:"Earned Leave (EL)", from:"YYYY-MM-DD", to:"YYYY-MM-DD", days:1.5, halfDay:false,
//   reason, status:"pending"|"approved"|"rejected"|"cancelled", appliedAt:ISO, decidedAt:ISO|null,
//   decidedBy:{id,name}|null, decisionNote:string|null, employee:{id,code,name} }

// GET /api/v1/mobile/leaves?status=&scope=  (Bearer)
//   scope omitted/"mine" → the caller's own requests (newest first, last 12 months is enough)
//   scope="team"         → requests the caller is allowed to approve (manager/HR/admin — reuse the
//                          webapp's approval visibility rule); FORBIDDEN 403 for everyone else
//   status=pending|approved|rejected (optional filter)
// → { ok:true, items:[…] }
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const scope = req.nextUrl.searchParams.get('scope') || 'mine';
  const status = req.nextUrl.searchParams.get('status') || undefined;
  if (scope === 'team') {
    if (!(await canApproveLeaves(user.id))) return fail(403, 'FORBIDDEN', 'You cannot approve leaves.');
    return ok({ items: await listTeamLeaves(user.id, status) });
  }
  return ok({ items: await listMyLeaves(user.id, status) });
});

// POST /api/v1/mobile/leaves {type, from, to, halfDay, reason}  (Bearer)
// → 200 { ok:true, leave:{…} } — created through the SAME function the webapp's apply form uses
//   (balance check, overlap check, holidays/week-offs, notifications to the approver).
// → 400 VALIDATION (missing fields / bad dates / insufficient balance — message is shown verbatim)
// → 409 CONFLICT   (overlaps an existing request)
export const POST = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const b = await req.json().catch(() => ({}));
  const type = String(b.type || '').trim();
  const from = String(b.from || ''), to = String(b.to || from);
  const reason = String(b.reason || '').trim();
  const halfDay = b.halfDay === true;
  const day = /^\d{4}-\d{2}-\d{2}$/;
  if (!type || !day.test(from) || !day.test(to)) return fail(400, 'VALIDATION', 'Leave type and dates are required.');
  if (to < from) return fail(400, 'VALIDATION', 'End date is before start date.');
  if (halfDay && from !== to) return fail(400, 'VALIDATION', 'Half day is only for a single day.');
  if (!reason) return fail(400, 'VALIDATION', 'Please enter a reason.');
  const types = assignCodes(await listLeaveTypes());
  const lt = matchLeaveType(type, types); // "EL" | "lt_earned" | "Earned Leave" → the webapp type
  if (!lt) return fail(400, 'VALIDATION', `Unknown leave type "${type}". Known: ${types.map((t) => t.code).join(', ')}`);
  const r = await createLeave({ userId: user.id, type: lt.key, from, to, halfDay, reason }); // TODO wire (internal key!)
  if (!r.ok) return fail(r.status || 400, r.code || 'VALIDATION', r.error || 'Leave request was not accepted.');
  return ok({ leave: r.leave });
});

// ---- TODO wire to the webapp's existing leave module (no duplicated rules) ----
async function canApproveLeaves(userId: string): Promise<boolean> { throw new Error('TODO: approval permission for ' + userId); }
async function listMyLeaves(userId: string, status?: string): Promise<unknown[]> { throw new Error('TODO: leaves of ' + userId + ' ' + (status || '')); }
async function listTeamLeaves(approverId: string, status?: string): Promise<unknown[]> { throw new Error('TODO: leaves awaiting ' + approverId + ' ' + (status || '')); }
type NewLeave = { userId: string; type: string; from: string; to: string; halfDay: boolean; reason: string };
async function createLeave(l: NewLeave): Promise<{ ok: boolean; status?: number; code?: string; error?: string; leave?: unknown }> {
  throw new Error('TODO: create via the webapp\'s apply function for ' + l.userId);
}
