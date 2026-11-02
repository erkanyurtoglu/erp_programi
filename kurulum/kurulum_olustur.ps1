# Liya ERP kurulum dosyasini (kurulum\cikti\LiyaERP_Kurulum_<surum>.exe) uretir:
#   1) pdf_sablonlari\assets\ikon.png'den assets\liya.ico'yu yeniler,
#   2) programi Release olarak derler (windeployqt Qt DLL'lerini exe yanina kopyalar),
#   3) erp_programi.iss'i Inno Setup ile derler.
# Surum CMakeLists.txt'deki "project(erp_programi VERSION x.y)" satirindan okunur.
# Calistirmak icin kurulum_olustur.bat'a cift tiklayin.

$ErrorActionPreference = 'Stop'
$kok = Split-Path -Parent $PSScriptRoot

$surum = (Select-String -Path "$kok\CMakeLists.txt" -Pattern 'project\(erp_programi VERSION ([0-9.]+)').Matches[0].Groups[1].Value
Write-Host "Surum: $surum"

# 1) Simge
if (Get-Command python -ErrorAction SilentlyContinue) {
    python "$PSScriptRoot\ikon_olustur.py"
    if ($LASTEXITCODE -ne 0) { throw "Simge uretilemedi." }
} else {
    Write-Warning "Python bulunamadi; mevcut assets\liya.ico kullaniliyor."
}

# 2) Release derleme
Push-Location $kok
try {
    if (-not (Test-Path "$kok\build-msvc\CMakeCache.txt")) {
        cmake --preset qt-msvc
        if ($LASTEXITCODE -ne 0) { throw "CMake yapilandirmasi basarisiz." }
    }
    cmake --build "$kok\build-msvc" --config Release
    if ($LASTEXITCODE -ne 0) { throw "Release derlemesi basarisiz." }
    # PDF "Farkli Kaydet" penceresi (PdfKayitYeriDialog.qml) bu modul olmadan acilmaz.
    if (-not (Test-Path "$kok\build-msvc\Release\qml\QtQuick\Dialogs\qtquickdialogsplugin.dll")) {
        throw "QtQuick.Dialogs modulu Release klasorunde yok (windeployqt calismamis olabilir)."
    }
} finally {
    Pop-Location
}

# 3) Inno Setup
$iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "Inno Setup 6 bulunamadi (https://jrsoftware.org/isdl.php)." }

$vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath
$redist = Get-ChildItem "$vs\VC\Redist\MSVC" -Recurse -Filter vc_redist.x64.exe | Select-Object -First 1
if (-not $redist) { throw "vc_redist.x64.exe bulunamadi ($vs\VC\Redist\MSVC)." }

& $iscc /Qp "/DUygulamaSurumu=$surum" "/DVCRedist=$($redist.FullName)" "$PSScriptRoot\erp_programi.iss"
if ($LASTEXITCODE -ne 0) { throw "Inno Setup derlemesi basarisiz." }

Write-Host ""
Write-Host "Kurulum dosyasi: $PSScriptRoot\cikti\LiyaERP_Kurulum_$surum.exe"
