import { NextRequest } from 'next/server';
import { fail, handle, ok, requireMobileUser } from '../../../../_lib/mobileAuth';
import { isoToday, memberDay, requireTeamAccess, teamMemberIds } from '../../../_shared';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/team/members/:id/day?date=YYYY-MM-DD   (Bearer, managers; member must be in the caller's team)
// → { ok:true, member:MemberRow, shift:{name,start,end}|null,
//     day:{ date, status, firstIn, lastOut, workedMinutes, punches:[{id,type,at,method,distanceM,insideGeofence}] } }
//   `day` has exactly the attendance/history day shape so the app reuses its parser.
export const GET = handle(async (req: NextRequest, ctx: { params: { id: string } }) => {
  const { user } = await requireMobileUser(req);
  await requireTeamAccess(user.id);
  const date = req.nextUrl.searchParams.get('date') || isoToday();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return fail(400, 'VALIDATION', 'date must be YYYY-MM-DD.');
  const ids = await teamMemberIds(user.id);
  if (!ids.includes(ctx.params.id)) return fail(403, 'FORBIDDEN', 'This employee is not in your team.');
  const { punches, shift, ...member } = await memberDay(ctx.params.id, date);
  return ok({
    member,
    shift,
    day: { date, status: member.status, firstIn: member.firstIn, lastOut: member.lastOut, workedMinutes: member.workedMinutes, punches },
  });
});
