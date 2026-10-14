# FlavorFlow ERP for Windows

FlavorFlow's existing Flutter client now has a native Windows x64 build path. It
uses the same login and HTTPS API as the mobile and web apps; it does not create
a Windows-specific company, database, or sample business dataset.

## Build artifact

The **FlavorFlow build** GitHub Actions workflow produces a portable ZIP named
`FlavorFlow-Windows-x64-portable`. It contains the complete Flutter release
folder. The workflow artifact is retained for 14 days; it is a build download,
not an installer or a published Windows Store release.

To run it:

1. Download and extract the entire ZIP to a folder on a Windows 10/11 x64 PC.
2. Keep all extracted files and folders together.
3. Run `flavorflow_erp.exe`.
4. Sign in with the company's existing FlavorFlow account. The `@flavorflow.co.in`
   suffix is an app login ID, not necessarily an email mailbox.

The first portable build is not code-signed, so Windows SmartScreen may show a
warning. The executable also requires the Microsoft Visual C++ 2015–2022 x64
runtime if it is not already installed on the PC.

## Build locally on Windows

From the repository root in PowerShell (with Flutter and Visual Studio's
**Desktop development with C++** workload installed):

```powershell
flutter config --enable-windows-desktop
.\tools\configure-windows.ps1
flutter pub get
dart run flutter_launcher_icons -f windows_launcher_icons.yaml
flutter build windows --release --dart-define=API_BASE=https://app.flavorflow.co.in/api
```

The helper creates the Windows runner if it is missing, sets the app title,
and adds a temporary MSVC compatibility define required by the current Windows
authentication and permission plugins on Visual Studio 18. The executable and
its runtime files are written to `build/windows/x64/runner/Release/`.

## Desktop behavior

- At desktop widths the app uses its existing sidebar layout. Login, RBAC,
  company switching, server settings, saved dispatch drafts, and the shared API
  are the same as in other app versions.
- Preferences and saved sessions live under the current Windows user profile.
  Windows device authentication/Windows Hello is offered only if the OS reports
  support; otherwise password login remains available. Signing out clears the
  session, but local preferences, drafts, and account-bound queued entries may
  remain, so use a separate Windows account on shared PCs.
- Product/material selectors keep a manual code-entry action. In dispatch, an
  available batch can be selected from the list or entered in the batch-code
  field. USB barcode scanners work when configured as keyboard devices.
- Camera scanning, adjustment photos, GPS stamps, phone notifications, and
  scheduled phone reminders are not offered on Windows. The in-app notification
  bell still reads alerts from the server.
- CSV/XLSX exports save in Downloads and open with the Windows default app. If
  no app association is available, the file remains in Downloads. PDF
  export/print actions use the platform printing flow and installed printer
  drivers.

The ZIP is portable; remove the extracted folder to remove the application
binaries. Deleting it does not erase Windows-profile data. Signing out removes
the saved session; biometric credentials can be cleared from Settings. Keep the
Windows account private because preferences, drafts, and queued entries can
remain in that profile.
