// Shared for the three team routes. Wire the TODOs to the webapp's EXISTING team/reporting-line logic.
//
// Team member shape (team/today.members[], team/members.items[], team/members/:id/day.member):
// { id, code, name, department, designation, avatarUrl,
//   status:"present"|"absent"|"leave"|"holiday"|"weekoff"|"half"|"notyet",
//   firstIn:ISO|null, lastOut:ISO|null, workedMinutes, late:boolean, leaveType:"EL"|null }
//
// STATUS RULE for a day with NO punch (same rule as the webapp dashboard):
//   leave → "leave"; holiday → "holiday"; weekly off → "weekoff";
//   date < today → "absent";
//   date == today → "absent" ONLY once the member's shift end (+ grace) has passed, else "notyet"
//   (at 01:00 nobody on the 07:00 day shift is "absent" yet — they are "notyet");
//   date > today → "notyet".
// SHIFT RULE: shift = the member's ASSIGNED shift (users.shift_id); if none, the webapp's default
// shift. Never pick a shift from the CURRENT clock time (pickShiftForNow(now)) — that labels every
// day-shift worker "Night Shift" when the manager looks at night. Only a real punch time may be
// used to auto-detect a shift, and only for that punched day.
import { MobileError } from '../_lib/mobileAuth';

export type MemberRow = {
  id: string; code: string; name: string; department: string; designation: string | null; avatarUrl: string | null;
  status: string; firstIn: string | null; lastOut: string | null; workedMinutes: number; late: boolean; leaveType: string | null;
};

// Who may see a team: the SAME rule the webapp uses for its Team / attendance dashboard
// (manager of a department / reporting line, HR, admin, super_admin). Everyone else → 403 FORBIDDEN.
export async function requireTeamAccess(userId: string): Promise<void> {
  const allowed = await canViewTeam(userId); // TODO wire
  if (!allowed) throw new MobileError(403, 'FORBIDDEN', 'You do not manage a team.');
}

// The people this user manages (webapp reporting line / department rule). For super_admin / HR
// this is everyone active. Never include the caller themself. Exclude system / service accounts
// (e.g. the seeded "Super Admin" login) and inactive / exited employees — only real staff who are
// expected to punch. `code` MUST be the employee code (e.g. WKH00418), never the internal user id.
export async function teamMemberIds(userId: string): Promise<string[]> { throw new Error('TODO: team of ' + userId); }
export async function canViewTeam(userId: string): Promise<boolean> { throw new Error('TODO: team visibility for ' + userId); }

// Attendance of one member for one day, using the same computation as attendance/today + history.
export async function memberDay(memberId: string, date: string): Promise<MemberRow & { punches: unknown[]; shift: { name: string; start: string; end: string } | null }> {
  throw new Error('TODO: day ' + date + ' for ' + memberId);
}

export function isoToday(): string {
  // Site-local date (Asia/Kolkata), not UTC — a punch at 01:00 IST belongs to that IST day.
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
}
