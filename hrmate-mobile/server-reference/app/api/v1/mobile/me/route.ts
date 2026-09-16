import { NextRequest } from 'next/server';
import { handle, ok, requireMobileUser } from '../_lib/mobileAuth';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/me  (Bearer) — the template every later route copies.
// Phase 5 adds the read-only `profile` block shown on the app's Profile page.
// → { ok:true, user:{ id, code, name, email, role, department, avatarUrl, permissions },
//     profile:{ designation, joinedOn:"YYYY-MM-DD"|null, phone, manager:{ id, name }|null,
//               shift:{ name, start:"HH:mm", end:"HH:mm" }|null, site } }
// Every profile field is optional — send null when the webapp has no value. The app hides null rows.
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const profile = await loadProfile(user.id); // TODO wire: the webapp's employee master (same record the HR "Employee" page shows)
  return ok({ user, profile });
});

type Profile = {
  designation: string | null;
  joinedOn: string | null;                       // date of joining, YYYY-MM-DD
  phone: string | null;
  manager: { id: string; name: string } | null;  // reporting manager
  shift: { name: string; start: string; end: string } | null; // the employee's ASSIGNED shift (users.shift_id) — null when none is assigned; do NOT fall back to the time-of-day / first shift like attendance/today does (a profile must not change between morning and night)
  site: string | null;                           // work location / unit name
};

async function loadProfile(userId: string): Promise<Profile> {
  throw new Error('TODO: employee master for ' + userId);
}
