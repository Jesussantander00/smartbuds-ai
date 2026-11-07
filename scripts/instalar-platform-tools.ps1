# SmartBuds AI - instala Android SDK Platform-Tools (adb) en el SDK de Android Studio.
# Uso, desde la carpeta smartbuds-ai:
#   powershell -ExecutionPolicy Bypass -File .\scripts\instalar-platform-tools.ps1

$ErrorActionPreference = "Continue"
$Sdk = "C:\Users\USUARIO\Desktop\AndroidSDK"
$Url = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
$Zip = Join-Path $env:TEMP "platform-tools-latest-windows.zip"

function Paso($texto) { Write-Host "`n==> $texto" -ForegroundColor Cyan }

if (Test-Path (Join-Path $Sdk "platform-tools\adb.exe")) {
    Paso "adb ya esta instalado"
} else {
    Paso "Descargando Platform-Tools (~8 MB). Si se corta, continua donde quedo."
    $ok = $false
    for ($i = 1; $i -le 30; $i++) {
        curl.exe -L --fail -C - --retry 5 --retry-delay 3 -o $Zip $Url
        if ($LASTEXITCODE -eq 0) { $ok = $true; break }
        Write-Host "    Conexion interrumpida (intento $i). Reanudando en 5 s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
    if (-not $ok) { throw "No se pudo descargar. Vuelve a ejecutar el script." }

    Paso "Descomprimiendo en $Sdk"
    # El zip trae la carpeta platform-tools\ adentro.
    tar.exe -xf $Zip -C $Sdk
    if ($LASTEXITCODE -ne 0) { Expand-Archive $Zip -DestinationPath $Sdk -Force }
    Remove-Item $Zip -ErrorAction SilentlyContinue
}

Paso "Comprobando adb"
& (Join-Path $Sdk "platform-tools\adb.exe") version

Paso "flutter doctor"
flutter doctor

Paso "flutter devices"
flutter devices
