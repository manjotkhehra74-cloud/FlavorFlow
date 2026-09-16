import { NextRequest } from 'next/server';
import { handle, ok, requireMobileUser } from '../_lib/mobileAuth';

export const dynamic = 'force-dynamic';

// GET /api/v1/mobile/payslips  (Bearer) — the signed-in employee's OWN payslips, newest first.
// → { ok:true, items:[{ id, month:"YYYY-MM", label:"August 2026", netPay:number|null, currency:"INR",
//                        url:"https://hr.flavorflow.co.in/…" }] }
//
// `url` is what the app opens in the phone's browser / PDF viewer (nothing is rendered in the app).
// It MUST be reachable WITHOUT the webapp's login cookie: sign it (HMAC of id + expiry, e.g. 15 min)
// and let the webapp's existing payslip download handler accept that signature — or point it at a
// small `GET /api/v1/mobile/payslips/[id]/file?sig=…` that streams the same PDF.
//
// If the webapp has NO payroll/payslip module yet: do NOT create this file at all. The app probes
// `GET payslips`; a 404 hides the Payslips tile. (If the module exists but this user has none → { ok:true, items:[] }.)
export const GET = handle(async (req: NextRequest) => {
  const { user } = await requireMobileUser(req);
  const items = await loadPayslips(user.id); // TODO wire: webapp payroll store, only this user's slips
  items.sort((a, b) => b.month.localeCompare(a.month));
  return ok({ items });
});

type Payslip = { id: string; month: string; label: string; netPay: number | null; currency: string; url: string };

async function loadPayslips(userId: string): Promise<Payslip[]> {
  throw new Error('TODO: payslips for ' + userId);
}
