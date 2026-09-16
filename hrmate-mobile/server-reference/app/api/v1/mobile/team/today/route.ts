import { NextRequest } from 'next/server';
import { handle, ok, requireMobileUser } from '../../_lib/mobileAuth';
import { isoToday, memberDay, requireTeamAccess, teamMemberIds } from '../_shared';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/team/today?date=YYYY-MM-DD   (Bearer, managers — 403 otherwise; date defaults to today IST)
// → { ok:true, date, counts:{ total, present, absent, onLeave, late }, members:[MemberRow…] }
//   present = punched in today (still in OR already out, incl. half day); absent = working day, no punch, no leave;
//   onLeave = approved leave covers the date; late = first punch after shift start + grace (the webapp's rule).
//   Sort: present (in) → present (out) → absent → leave → off, then by name.
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  await requireTeamAccess(user.id);
  const date = req.nextUrl.searchParams.get('date') || isoToday();
  const ids = await teamMemberIds(user.id);
  const rows = await Promise.all(ids.map((id) => memberDay(id, date)));
  const members = rows.map(({ punches: _p, shift: _s, ...m }) => m);
  const counts = {
    total: members.length,
    present: members.filter((m) => ['present', 'half'].includes(m.status)).length,
    absent: members.filter((m) => m.status === 'absent').length,
    onLeave: members.filter((m) => m.status === 'leave').length,
    late: members.filter((m) => m.late).length,
  };
  const rank = (m: { status: string; lastOut: string | null }) =>
    m.status === 'present' && !m.lastOut ? 0 : m.status === 'present' || m.status === 'half' ? 1 : m.status === 'absent' ? 2 : m.status === 'leave' ? 3 : 4;
  members.sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name));
  return ok({ date, counts, members });
});
