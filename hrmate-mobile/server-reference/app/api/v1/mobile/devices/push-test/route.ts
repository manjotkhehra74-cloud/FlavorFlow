import { NextRequest } from 'next/server';
import { handle, ok, requireMobileUser } from '../../_lib/mobileAuth';
import { countPushTokens, fcmStatus, sendFcmToUser } from '@/lib/fcm';

export const dynamic = 'force-dynamic';

const DELAY_S = 10;

// POST /api/v1/mobile/devices/push-test  (Bearer)
// Sends ONE real push to the caller's own registered phones after 10 s, so the
// acceptance check "notification arrives with the app closed" can be done from
// More → Notifications → "Send test notification" without touching attendance
// or leave data (nothing is written to the webapp's notifications inbox).
// → {ok:true, configured, project, tokens, inSeconds}
export const POST = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const st = fcmStatus();
  const tokens = countPushTokens(user.id);
  if (st.configured && tokens > 0) {
    const at = new Date(Date.now() + DELAY_S * 1000);
    const time = at.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Kolkata' });
    setTimeout(() => {
      sendFcmToUser(user.id, {
        title: 'HRMate test notification',
        body: `Push is working on this phone (${time}).`,
        link: '/settings',
      }).then((r) => console.log(`[fcm] test → ${user.code}: sent ${r.sent}, failed ${r.failed}, removed ${r.removed}`));
    }, DELAY_S * 1000);
  }
  return ok({ configured: st.configured, project: st.project, error: st.error, tokens, inSeconds: DELAY_S });
});
