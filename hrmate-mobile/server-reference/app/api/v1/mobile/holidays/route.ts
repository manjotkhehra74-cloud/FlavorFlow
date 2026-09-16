import { NextRequest } from 'next/server';
import { fail, handle, ok, requireMobileUser } from '../_lib/mobileAuth';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/holidays?year=YYYY  (Bearer; default = current year)
// → { ok:true, year:2026, items:[{ date:"YYYY-MM-DD", name, type:"public"|"restricted"|"optional"|null, optional:boolean }] }
// Same list the webapp's holiday calendar shows (the one attendance/today's `holiday` flag is computed from).
// Sorted by date. An empty list is fine — the app shows "No holidays published for 2026".
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const y = req.nextUrl.searchParams.get('year') || String(new Date().getFullYear());
  if (!/^\d{4}$/.test(y)) return fail(400, 'VALIDATION', 'year must be YYYY.');
  const items = await loadHolidays(user.id, Number(y)); // TODO wire: webapp holiday list (filter by the user's site/location if the webapp does)
  items.sort((a, b) => a.date.localeCompare(b.date));
  return ok({ year: Number(y), items });
});

type Holiday = { date: string; name: string; type: string | null; optional: boolean };

async function loadHolidays(userId: string, year: number): Promise<Holiday[]> {
  throw new Error('TODO: holidays ' + year + ' for ' + userId);
}
