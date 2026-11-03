; Liya ERP kurulum dosyası (Inno Setup 6).
; Elle derlemek yerine kurulum_olustur.ps1'i çalıştırın: Release derler, sürümü
; CMakeLists.txt'den okur ve bu betiği derler. Çıktı: kurulum\cikti\

#ifndef UygulamaSurumu
  #define UygulamaSurumu "1.0"
#endif
; windeployqt'nin DLL/QML dosyalarını kopyaladığı Release klasörü.
#ifndef DerlemeKlasoru
  #define DerlemeKlasoru "..\build-msvc\Release"
#endif
; Hedef bilgisayarda yoksa kurulan Visual C++ çalışma zamanı.
#ifndef VCRedist
  #define VCRedist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Redist\MSVC\v143\vc_redist.x64.exe"
#endif

; Kısayol ve "Programlar ve Özellikler"de görünen ad.
#define UygulamaAdi "LİYA ERP"
; Kurulum klasörü: yolda Türkçe karakter olmasın (WebEngine vb. için güvenli).
#define KlasorAdi "Liya ERP"
#define ExeAdi "erp_programi.exe"

[Setup]
; AppId sabit kalmalı: yeni sürüm aynı kurulumun üzerine yazılır.
AppId={{5DF5CF29-E0EA-4223-BED7-D7ACC324FB83}
AppName={#UygulamaAdi}
AppVersion={#UygulamaSurumu}
AppVerName={#UygulamaAdi} {#UygulamaSurumu}
AppPublisher=Erkan Yurtoğlu
DefaultDirName={autopf}\{#KlasorAdi}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\assets\liya.ico
UninstallDisplayIcon={app}\{#ExeAdi}
UninstallDisplayName={#UygulamaAdi}
OutputDir=cikti
OutputBaseFilename=LiyaERP_Kurulum_{#UygulamaSurumu}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "masaustu"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#DerlemeKlasoru}\*"; DestDir: "{app}"; Excludes: "*.exp,*.lib,*.pdb,*.ilk,baglanti.ini"; Flags: ignoreversion recursesubdirs createallsubdirs
; Veritabanı bağlantısı: yalnızca ilk kurulumda konur; o bilgisayarda
; değiştirilmişse güncellemede ve kaldırmada dokunulmaz.
#if FileExists(AddBackslash(SourcePath) + "..\baglanti.ini")
Source: "..\baglanti.ini"; DestDir: "{app}"; Flags: onlyifdoesntexist uninsneveruninstall
#endif
Source: "{#VCRedist}"; DestDir: "{tmp}"; DestName: "vc_redist.x64.exe"; Flags: deleteafterinstall; Check: VCRedistGerekli

[Icons]
Name: "{autoprograms}\{#UygulamaAdi}"; Filename: "{app}\{#ExeAdi}"
Name: "{autodesktop}\{#UygulamaAdi}"; Filename: "{app}\{#ExeAdi}"; Tasks: masaustu

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Microsoft Visual C++ çalışma zamanı kuruluyor..."; Flags: waituntilterminated; Check: VCRedistGerekli
Filename: "{app}\{#ExeAdi}"; Description: "{cm:LaunchProgram,{#UygulamaAdi}}"; Flags: nowait postinstall skipifsilent

[Code]
// Program VS 2022 (14.44) araç takımıyla derleniyor; daha eski çalışma zamanı
// varsa ya da hiç yoksa vc_redist kurulur.
function RuntimeYeterli(Kok: Integer): Boolean;
var
  Kurulu, Minor: Cardinal;
begin
  Result := RegQueryDWordValue(Kok, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Kurulu)
    and (Kurulu = 1)
    and RegQueryDWordValue(Kok, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Minor', Minor)
    and (Minor >= 44);
end;

function VCRedistGerekli: Boolean;
begin
  Result := not (RuntimeYeterli(HKLM64) or RuntimeYeterli(HKLM32));
end;
