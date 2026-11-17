; Установщик «Студии аватаров» для Windows (Inno Setup 6).
; Собирается в workflow build-avatar-studio.yml: ISCC /DAppVersion=... /DSourceDir=... windows\installer.iss
; Ставится для текущего пользователя (без прав администратора) в %LOCALAPPDATA%\Programs\Avatar Studio.
; Проекты лежат в «Документах», поэтому обновление и удаление программы их не трогают.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{6B0F3B52-7C1E-4E8A-9C55-5A1D2F0B7A11}
AppName=Avatar Studio
AppVersion={#AppVersion}
AppPublisher=GuYo
DefaultDirName={autopf}\Avatar Studio
DefaultGroupName=Avatar Studio
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer
OutputBaseFilename=Avatar-Studio-Setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\avatar_studio.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Avatar Studio"; Filename: "{app}\avatar_studio.exe"
Name: "{group}\{cm:UninstallProgram,Avatar Studio}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Avatar Studio"; Filename: "{app}\avatar_studio.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\avatar_studio.exe"; Description: "{cm:LaunchProgram,Avatar Studio}"; Flags: nowait postinstall skipifsilent
