import { NextRequest } from 'next/server';
import { fail, handle, ok, requireMobileUser } from '../../_lib/mobileAuth';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/attendance/history?from=YYYY-MM-DD&to=YYYY-MM-DD  (Bearer, max 62 days)
// → { ok:true, days:[{ date:"YYYY-MM-DD", status:"present"|"absent"|"leave"|"holiday"|"weekoff"|"half",
//                      firstIn, lastOut, workedMinutes,
//                      punches:[{ id, type:"in"|"out", at: ISO, method, distanceM, insideGeofence }] }] }
// Phase 2 calls it with from=to=today (today's punch list); Phase 5 uses it for the calendar.
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const from = req.nextUrl.searchParams.get('from') || '';
  const to = req.nextUrl.searchParams.get('to') || from;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)) return fail(400, 'VALIDATION', 'from/to must be YYYY-MM-DD.');
  const days = await loadHistory(user.id, from, to); // TODO wire: same data as the webapp attendance calendar
  return ok({ days });
});

async function loadHistory(userId: string, from: string, to: string): Promise<unknown[]> {
  throw new Error('TODO: attendance days for ' + userId + ' ' + from + '..' + to);
}
