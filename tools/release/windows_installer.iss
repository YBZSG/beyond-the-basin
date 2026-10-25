#ifndef Payload
  #error Supply /DPayload=<staged runtime folder>
#endif
#ifndef ReleaseOutput
  #error Supply /DReleaseOutput=<output folder>
#endif
[Setup]
AppId=PoolCore.Windows
AppName=PoolCore
AppVersion=0.6.13
AppPublisher=YBZSG
AppPublisherURL=https://github.com/YBZSG/beyond-the-basin
AppSupportURL=https://github.com/YBZSG/beyond-the-basin/issues
AppUpdatesURL=https://github.com/YBZSG/beyond-the-basin/releases
DefaultDirName={localappdata}\Programs\PoolCore
DefaultGroupName=PoolCore
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#ReleaseOutput}
OutputBaseFilename=PoolCore-PC-0.6.13-Setup
Compression=lzma2/normal
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\PoolCore.exe
CloseApplications=no
RestartApplications=no
SetupLogging=yes
InfoBeforeFile={#Payload}\INSTALL.txt
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked
[Files]
Source: "{#Payload}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\PoolCore"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Start-PoolCore-Scene.ps1"" -World campaign -NR keep"; WorkingDir: "{app}"; IconFilename: "{app}\PoolCore.exe"
Name: "{group}\PoolCore - Reference Wing"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Start-PoolCore-Scene.ps1"" -World reference -NR keep"; WorkingDir: "{app}"; IconFilename: "{app}\PoolCore.exe"
Name: "{group}\Uninstall PoolCore"; Filename: "{uninstallexe}"
Name: "{autodesktop}\PoolCore"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Start-PoolCore-Scene.ps1"" -World campaign -NR keep"; WorkingDir: "{app}"; IconFilename: "{app}\PoolCore.exe"; Tasks: desktopicon
; No profile or user-data files are installed or deleted by this installer.
