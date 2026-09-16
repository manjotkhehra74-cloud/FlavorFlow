// ONE place that maps the webapp's internal leave-type keys (e.g. "EARNED") to the short codes the
// mobile app shows and sends (e.g. "EL"). Used by leaves/balance, leaves (GET/POST), approve, reject.
// Rule: every mobile payload exposes `type` = shortCode(t) and `typeName` = t.name; every incoming
// `type` is resolved with matchLeaveType() BEFORE calling any webapp function. No webapp rule changes.

export type LeaveType = { key: string; name: string; code?: string | null };

// TODO wire: return the webapp's leave types (the same list its leave settings / apply form use),
// e.g. [{ key: "EARNED", name: "Earned Leave (EL)", code: "EL" }, { key: "CASUAL", name: "Casual Leave (CL)" }]
export async function listLeaveTypes(): Promise<LeaveType[]> {
  throw new Error('TODO: webapp leave types');
}

/** "EL" for {key:"EARNED", name:"Earned Leave (EL)"} — explicit code, else "(XX)" from the name, else key. */
export function shortCode(t: LeaveType): string {
  if (t.code && t.code.trim()) return t.code.trim().toUpperCase();
  const m = /\(([A-Za-z]{1,4})\)/.exec(t.name || '');
  if (m) return m[1].toUpperCase();
  return (t.key || '').toUpperCase();
}

/** Case-insensitive match on short code, internal key or full name: "EL" | "earned" | "Earned Leave (EL)" → the type. */
export function matchLeaveType(input: string, types: LeaveType[]): LeaveType | null {
  const q = (input || '').trim().toLowerCase();
  if (!q) return null;
  return (
    types.find((t) => shortCode(t).toLowerCase() === q) ||
    types.find((t) => (t.key || '').toLowerCase() === q) ||
    types.find((t) => (t.name || '').toLowerCase() === q) ||
    null
  );
}

/** Convenience for responses: { type:"EL", typeName:"Earned Leave (EL)" } from an internal key. */
export function publicType(key: string, types: LeaveType[]): { type: string; typeName: string } {
  const t = matchLeaveType(key, types);
  return t ? { type: shortCode(t), typeName: t.name } : { type: (key || '').toUpperCase(), typeName: key || '' };
}
