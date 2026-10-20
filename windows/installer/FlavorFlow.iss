; Installable Windows desktop package for the existing Flutter Release folder.
; Build with ISCC /DAppVersion=1.2.4 windows\installer\FlavorFlow.iss.
#ifndef AppVersion
  #define AppVersion "1.2.4"
#endif

[Setup]
AppId={{D90AA01C-39A1-49E0-A220-6D261A589640}
AppName=FlavorFlow ERP
AppVersion={#AppVersion}
AppPublisher=FlavorFlow
DefaultDirName={localappdata}\Programs\FlavorFlow ERP
DefaultGroupName=FlavorFlow ERP
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\..\build\windows-installer
OutputBaseFilename=FlavorFlow-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\flavorflow_erp.exe
DisableProgramGroupPage=yes

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\FlavorFlow ERP"; Filename: "{app}\flavorflow_erp.exe"
Name: "{autodesktop}\FlavorFlow ERP"; Filename: "{app}\flavorflow_erp.exe"; Tasks: desktopicon

[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\flavorflow_erp.exe"; Description: "Launch FlavorFlow ERP"; Flags: nowait postinstall skipifsilent
