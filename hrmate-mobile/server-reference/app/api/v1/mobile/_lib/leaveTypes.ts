// WIRING ONLY — the single function that reads the webapp's leave types. All code logic lives in
// leaveCodes.ts (assignCodes / matchLeaveType / publicType); routes call `assignCodes(await listLeaveTypes())`.
import type { LeaveType } from './leaveCodes';

// TODO wire: return the webapp's leave types (the same list its leave settings / apply form use):
//   [{ key: "lt_earned", name: "Earned Leave", code: "EL" }, { key: "lt_casual", name: "Casual Leave" }, …]
// `key`  = the id the webapp stores on leave records and policies (e.g. "lt_earned")
// `name` = the display name
// `code` = the webapp's own short code/abbreviation field IF it has one (the eligibility message says
//          "Earned Leave (EL)", so it probably does) — otherwise leave it undefined and assignCodes derives it.
export async function listLeaveTypes(): Promise<LeaveType[]> {
  throw new Error('TODO: webapp leave types');
}
