// PURE helpers (copy verbatim, nothing to wire here). Give every webapp leave type a UNIQUE short
// code and resolve incoming values back to the webapp type. Used by leaves/balance, leaves (GET/POST),
// leaves/[id]/approve, leaves/[id]/reject — the mobile app shows `code` and sends it back unchanged.
//
//   { key:"lt_earned",   name:"Earned Leave" }            → EL
//   { key:"lt_casual",   name:"Casual Leave" }            → CL
//   { key:"lt_sick",     name:"Sick Leave" }              → SL
//   { key:"lt_short",    name:"Short Leave" }             → SHL   (SL already taken → 2 letters + initials)
//   { key:"lt_comp",     name:"Compensatory Off" }        → CO
//   { key:"x", name:"Earned Leave (EL)" } / { code:"EL" } → EL    (explicit code or "(XX)" in the name wins)

export type LeaveType = { key: string; name: string; code?: string | null };
export type CodedLeaveType = LeaveType & { code: string };

const stripPrefix = (key: string) => (key || '').replace(/^lt[_-]/i, '');

function candidates(t: LeaveType): string[] {
  const out: string[] = [];
  if (t.code && t.code.trim()) out.push(t.code.trim().toUpperCase());
  const paren = /\(([A-Za-z]{1,4})\)/.exec(t.name || '');
  if (paren) out.push(paren[1].toUpperCase());
  const words = (t.name || '').replace(/\(.*?\)/g, ' ').replace(/[^A-Za-z ]/g, ' ').split(/\s+/).filter(Boolean);
  if (words.length >= 2) {
    out.push(words.map((w) => w[0]).join('').toUpperCase().slice(0, 4));                      // Earned Leave → EL
    out.push((words[0].slice(0, 2) + words.slice(1).map((w) => w[0]).join('')).toUpperCase()); // Short Leave → SHL
  } else if (words.length === 1) {
    out.push(words[0].slice(0, 2).toUpperCase());
  }
  const k = stripPrefix(t.key).toUpperCase();
  if (k) out.push(k);                                                                            // EARNED
  return out.length ? out : ['?'];
}

/** Assign a unique code to every type (order-stable, deterministic). ALWAYS go through this. */
export function assignCodes(types: LeaveType[]): CodedLeaveType[] {
  const taken = new Set<string>();
  return types.map((t) => {
    const c = candidates(t);
    let code = c.find((x) => !taken.has(x));
    if (!code) { let i = 2; while (taken.has(`${c[0]}${i}`)) i++; code = `${c[0]}${i}`; }
    taken.add(code);
    return { ...t, code };
  });
}

/** "EL" | "lt_earned" | "earned" | "Earned Leave" → the type (case-insensitive), else null. */
export function matchLeaveType(input: string, types: CodedLeaveType[]): CodedLeaveType | null {
  const q = (input || '').trim().toLowerCase();
  if (!q) return null;
  return (
    types.find((t) => t.code.toLowerCase() === q) ||
    types.find((t) => (t.key || '').toLowerCase() === q) ||
    types.find((t) => stripPrefix(t.key).toLowerCase() === q) ||
    types.find((t) => (t.name || '').toLowerCase() === q) ||
    types.find((t) => (t.name || '').replace(/\s*\(.*?\)\s*/g, '').toLowerCase() === q) ||
    null
  );
}

/** For responses: { type:"EL", typeName:"Earned Leave" } from whatever the webapp stores on the record. */
export function publicType(stored: string, types: CodedLeaveType[]): { type: string; typeName: string } {
  const t = matchLeaveType(stored, types);
  return t ? { type: t.code, typeName: t.name } : { type: (stored || '').toUpperCase(), typeName: stored || '' };
}
