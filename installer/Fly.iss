#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "Fly"
#define AppPublisher "Fly"
#define AppExeName "fly.exe"

#ifndef PackageName
  #define PackageName "Fly-Setup-" + AppVersion
#endif

[Setup]
AppId={{F8A1A728-3E45-4D44-98B5-C7B9BC6F24D1}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\Fly
DefaultGroupName=Fly
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\dist
OutputBaseFilename={#PackageName}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=yes
UsePreviousAppDir=yes
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany={#AppPublisher}
VersionInfoDescription=Fly Windows Installer
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopShortcut}"; GroupDescription: "{cm:ShortcutGroup}"

[CustomMessages]
chinesesimp.DesktopShortcut=创建桌面快捷方式
english.DesktopShortcut=Create a desktop shortcut
chinesesimp.ShortcutGroup=快捷方式：
english.ShortcutGroup=Shortcuts:
chinesesimp.LaunchFly=启动 Fly
english.LaunchFly=Launch Fly
chinesesimp.MissingRuntime=未检测到 Microsoft Visual C++ 2015-2022 x64 运行库。Fly 可能无法启动。建议先从 Microsoft 官方安装运行库。是否仍继续安装？
english.MissingRuntime=Microsoft Visual C++ 2015-2022 x64 Runtime was not detected. Fly may not start. Install the runtime from Microsoft first. Continue anyway?

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Fly"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; AppUserModelID: "Fly.Desktop.Productivity.1"
Name: "{autodesktop}\Fly"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; AppUserModelID: "Fly.Desktop.Productivity.1"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchFly}"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
  if not FileExists(ExpandConstant('{sys}\VCRUNTIME140.dll')) then
  begin
    Result := MsgBox(
      ExpandConstant('{cm:MissingRuntime}'),
      mbConfirmation, MB_YESNO) = IDYES;
  end;
end;
