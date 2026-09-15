import { NextRequest } from 'next/server';
import { handle, ok, requireMobileUser } from '../_lib/mobileAuth';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/announcements  (Bearer)
// → { ok:true, items:[{ id, title, body, at: ISO, pinned: boolean }] }  newest first, max 20,
//   only announcements visible to this user's department/role (same rule as the webapp).
// If the webapp has no announcements feature yet, return { ok:true, items: [] } — do NOT invent one.
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const items = await loadAnnouncements(user.id); // TODO wire (or return [])
  return ok({ items });
});

async function loadAnnouncements(userId: string): Promise<unknown[]> {
  throw new Error('TODO: webapp announcements for user ' + userId + ' (or return [] if the feature does not exist)');
}
