import { NextRequest } from 'next/server';
import { fail, handle, ok, requireMobileUser } from '../../_lib/mobileAuth';

export const dynamic = 'force-dynamic';

// POST /api/v1/mobile/attendance/punch  (Bearer)
// body: { type:"in"|"out", lat, lng, accuracyM, mocked, method:"biometric"|"password", deviceId, clientTime }
// 200 → { ok:true, punch:{ id, type, at: ISO, method, distanceM, insideGeofence }, message? }
// 409 GEOFENCE → { ok:false, code:"GEOFENCE", error:"…", distanceM, radiusM }
// 409 CONFLICT → already punched in / not punched in / duplicate within 60 s
// 400 VALIDATION → bad body / mocked location rejected
//
// The SERVER is the authority: recompute the distance with the site geofence the webapp already
// stores (do not trust the client's inside flag), apply the SAME rules the web punch uses
// (shift window, duplicate guard, mock-GPS policy), and record the punch through the SAME
// function the webapp's punch button uses — so reports, payroll and the dashboard see it.
export const POST = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const b = await req.json().catch(() => ({}));
  const type = b.type === 'in' || b.type === 'out' ? b.type : null;
  const lat = Number(b.lat), lng = Number(b.lng);
  if (!type || !Number.isFinite(lat) || !Number.isFinite(lng)) return fail(400, 'VALIDATION', 'Punch type and location are required.');
  if (b.mocked === true) return fail(400, 'VALIDATION', 'Mock location detected. Turn off fake-GPS apps and try again.');

  const fence = await loadGeofence(user.id);                    // TODO wire: same geofence as attendance/today
  const distanceM = haversineM(lat, lng, fence.lat, fence.lng);
  const allowance = Math.min(Number(b.accuracyM) || 0, 30);     // small GPS-accuracy allowance
  if (distanceM > fence.radiusM + allowance) {
    return fail(409, 'GEOFENCE', `You are ${Math.round(distanceM)} m from the site.`, { distanceM: Math.round(distanceM), radiusM: fence.radiusM });
  }

  const result = await recordPunch({                            // TODO wire: the webapp's existing punch function
    userId: user.id, type, at: new Date(), lat, lng, accuracyM: Number(b.accuracyM) || null,
    method: String(b.method || 'biometric'), deviceId: String(b.deviceId || ''), distanceM, insideGeofence: true,
  });
  if (!result.ok) return fail(409, 'CONFLICT', result.error || 'Punch not allowed right now.');
  return ok({ punch: result.punch, message: result.message });
});

function haversineM(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000, r = (d: number) => (d * Math.PI) / 180;
  const dLat = r(lat2 - lat1), dLng = r(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function loadGeofence(userId: string): Promise<{ lat: number; lng: number; radiusM: number }> {
  throw new Error('TODO: site geofence for user ' + userId + ' (same values attendance/today returns)');
}
type PunchInput = { userId: string; type: 'in' | 'out'; at: Date; lat: number; lng: number; accuracyM: number | null; method: string; deviceId: string; distanceM: number; insideGeofence: boolean };
async function recordPunch(p: PunchInput): Promise<{ ok: boolean; error?: string; message?: string; punch?: unknown }> {
  throw new Error('TODO: call the webapp\'s punch service for ' + p.userId + ' (same duplicate/shift rules as the web punch)');
}
