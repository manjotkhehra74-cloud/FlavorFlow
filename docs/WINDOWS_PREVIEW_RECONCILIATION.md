# Windows preview-to-running-app reconciliation

The Flutter executable is built from `lib/`, **not** from `Windows App/`. The latter is a handoff mirror. A Windows-specific branch or a copied page is not proof of visual parity with an approved preview. The October 18 installed-app screenshot showed the then-current dashboard code (flat KPI strips, Workspace Snapshot, Quick Actions), not an installer packaging error. The dashboard was subsequently changed in source, but only a newly installed build will contain it. The Windows footer now displays the build commit prefix to distinguish builds without guessing from a screenshot.

## Recoverable preview inventory

These are the actual image assets present in this repository on this branch. Their illustrative content (sample companies, example records, dates, mock server state) must **not** become defaults or backend data. They are reference images, not runnable screens. A comparison requires a screenshot of the running route/state at the same window size; a successful compile is insufficient.

| Reference image (`preview/`) | Runtime area to compare | Status |
| --- | --- | --- |
| `windows-2fa-setup-concept.png` | Settings, 2FA dialog | Visual parity not verified |
| `windows-adjustment-form-revised-concept.png` | Stock Adjustments, new request | Visual parity not verified; material API not deployed |
| `windows-approval-history-concept.png` | Approvals, history | Visual parity not verified |
| `windows-approvals-register-concept.png` | Approvals, pending | **Rejected early concept; do not implement as approval** |
| `windows-audit-trail-concept.png` | Audit Log | Filterable live register and full-row selection to inspector; visual parity not verified |
| `windows-daily-labour-concept.png` | Productivity & Labour, labour | Visual parity not verified |
| `windows-daily-labour-entry-concept.png` | Productivity & Labour, entry | Visual parity not verified |
| `windows-edit-user-concept.png` | User Management, edit user | Visual parity not verified |
| `windows-labour-analysis-concept.png` | Productivity & Labour, analysis | Visual parity not verified |
| `windows-language-picker-concept.png` | Language selector | Visual parity not verified |
| `windows-notifications-register-concept.png` | Notifications | Visual parity not verified |
| `windows-offline-entries-concept.png` | Sync / offline entries | Visual parity not verified |
| `windows-productivity-concept.png` | Productivity & Labour, overview | Visual parity not verified |
| `windows-reports-library-concept.png` | Reports | Desktop metric strip/list implemented in `lib/features/reports/reports_page.dart`; **visual parity not verified** |
| `windows-user-form-concept.png` | User Management, add user | Full-width account editor and role-based permissions coded; visual parity not verified |
| `windows-users-roles-concept.png` | User Management, roles | Searchable full-width live account register and read-only role matrix coded; visual parity not verified |

`preview/windows_ui_preview.html` is an earlier interactive concept containing **illustrative fake data**. It is not a production UI specification and its sample values must not be used in Flutter. The selected previews mentioned during later design discussions (Products, Inventory, Production, Packing, Billing, etc.) are **not in this repository** in an identifiable complete approved-image set; the historical selections alone do not make any checked-in image approved. Do not silently mark them implemented or reuse rejected candidates. Find the approved assets and compare each dialog and state against a running Windows build before declaring full completion.

## Release gate

1. For every approved reference: confirm the image is present and approved, map it to the live route/dialog, compare actual Windows capture against the reference, and record differences.
2. Implement the differences in `lib/`, keep mobile behavior unchanged, then sync handoff page copies under `Windows App/`.
3. Verify Flutter analyze/tests, build the installer, install on a Windows PC and capture actual UI; verify server-dependent flows separately. CI silent install/uninstall alone is **not** visual validation.
4. Read the build prefix at the bottom of the Windows window and compare it to the installer run's commit. Installing an earlier artifact or launching a separate portable copy will show an earlier prefix (or no prefix).

**Current state:** full preview reconciliation is not complete. Do not call the Windows redesign released or visually verified.
