import { NextRequest } from 'next/server';
import { handle, ok, requireMobileUser } from '../../_lib/mobileAuth';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/attendance/today  (Bearer)
// Response contract (ARCHITECTURE.md §5) — the app renders exactly this:
// {
//   ok: true,
//   status: "in" | "out" | "none",      // in = punched in, not yet out · out = day complete · none = no punch yet
//   firstIn: ISO string | null,
//   lastOut: ISO string | null,
//   workedMinutes: number,              // completed minutes today (live if still "in")
//   shift: { name, start: "09:00", end: "18:00" } | null,   ← the user's ASSIGNED shift (or the webapp default); never pickShiftForNow(now) — a day-shift user must not see "Night Shift" at 01:00
//   onLeave: boolean, holiday: boolean, holidayName: string | null,
//   geofence: { lat, lng, radiusM }      // site geofence the punch screen (Phase 2) will check against
// }
// TODO: replace the body with the webapp's EXISTING attendance/shift/leave/holiday lookups for `user.id`
// for today's date in Asia/Kolkata. No new tables, no duplicated rules.
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const today = await loadTodayAttendance(user.id); // TODO wire
  return ok(today);
});

async function loadTodayAttendance(userId: string): Promise<Record<string, unknown>> {
  throw new Error('TODO: use the webapp\'s attendance service (same data the dashboard "Today" card shows) for user ' + userId);
}
