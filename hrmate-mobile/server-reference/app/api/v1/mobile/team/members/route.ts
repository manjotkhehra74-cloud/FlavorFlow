import { NextRequest } from 'next/server';
import { handle, ok, requireMobileUser } from '../../_lib/mobileAuth';
import { isoToday, memberDay, requireTeamAccess, teamMemberIds } from '../_shared';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/team/members?q=   (Bearer, managers)
// → { ok:true, items:[MemberRow…] }  — same rows as team/today (today's status included), filtered by
//   q against name / code / department (case-insensitive). The app filters locally too; this exists for big teams.
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  await requireTeamAccess(user.id);
  const q = (req.nextUrl.searchParams.get('q') || '').trim().toLowerCase();
  const ids = await teamMemberIds(user.id);
  const rows = await Promise.all(ids.map((id) => memberDay(id, isoToday())));
  const items = rows
    .map(({ punches: _p, shift: _s, ...m }) => m)
    .filter((m) => !q || [m.name, m.code, m.department].some((v) => (v || '').toLowerCase().includes(q)))
    .sort((a, b) => a.name.localeCompare(b.name));
  return ok({ items });
});
