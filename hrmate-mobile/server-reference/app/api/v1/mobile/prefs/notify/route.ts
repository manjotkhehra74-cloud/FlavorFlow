import { NextRequest } from 'next/server';
import { handle, ok, fail, requireMobileUser } from '../../_lib/mobileAuth';
import { getUserPrefs, setUserPrefs } from '@/lib/prefs';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/prefs/notify  (Bearer) → {ok:true, enabled}
// The SAME `user_prefs.notify_enabled` the webapp's Settings page uses: off means
// `sendPushToUser()` sends nothing (web push AND FCM) — no second preference store.
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  return ok({ enabled: getUserPrefs(user.id).notify_enabled !== 0 });
});

// PUT /api/v1/mobile/prefs/notify  (Bearer)  {enabled: boolean} → {ok:true, enabled}
export const PUT = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const body = (await req.json().catch(() => ({}))) as { enabled?: unknown };
  if (typeof body.enabled !== 'boolean') return fail(400, 'VALIDATION', 'enabled (true/false) is required.');
  const next = setUserPrefs(user.id, { notify_enabled: body.enabled ? 1 : 0 });
  return ok({ enabled: next.notify_enabled !== 0 });
});
