# SmartBuds AI - descarga los modelos de voz de Vosk y los deja en
# android/app/src/main/assets para empaquetarlos en la app:
#   - model-es  : reconocimiento de voz en espanol (~40 MB)
#   - model-spk : modelo de hablante para "Solo mi voz" (~13 MB)
# Uso, desde la carpeta smartbuds-ai:
#   powershell -ExecutionPolicy Bypass -File .\scripts\descargar-modelo-voz.ps1

$ErrorActionPreference = "Continue"
$Project = Split-Path -Parent $PSScriptRoot
$Assets  = Join-Path $Project "android\app\src\main\assets"

function Paso($texto) { Write-Host "`n==> $texto" -ForegroundColor Cyan }

function Get-VoskModel($Name, $Target, $CheckFile) {
    $Dest = Join-Path $Assets $Target
    if (Test-Path (Join-Path $Dest $CheckFile)) {
        Paso "$Target ya esta descargado"
        return
    }
    $Url = "https://alphacephei.com/vosk/models/$Name.zip"
    $Zip = Join-Path $env:TEMP "$Name.zip"
    $Tmp = Join-Path $env:TEMP "$Name-extract"

    Paso "Descargando $Name. Si se corta, continua donde quedo."
    $ok = $false
    for ($i = 1; $i -le 30; $i++) {
        curl.exe -L --fail -C - --retry 5 --retry-delay 3 -o $Zip $Url
        if ($LASTEXITCODE -eq 0) { $ok = $true; break }
        Write-Host "    Conexion interrumpida (intento $i). Reanudando en 5 s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
    if (-not $ok) { throw "No se pudo descargar $Name. Vuelve a ejecutar el script." }

    Paso "Descomprimiendo $Name"
    if (Test-Path $Tmp) { Remove-Item $Tmp -Recurse -Force }
    New-Item -ItemType Directory -Force $Tmp | Out-Null
    tar.exe -xf $Zip -C $Tmp
    if ($LASTEXITCODE -ne 0) { Expand-Archive $Zip -DestinationPath $Tmp -Force }

    $Inner = Join-Path $Tmp $Name
    if (-not (Test-Path $Inner)) { $Inner = $Tmp }
    New-Item -ItemType Directory -Force $Assets | Out-Null
    if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
    Move-Item $Inner $Dest

    Remove-Item $Zip -ErrorAction SilentlyContinue
    Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
    Paso "Listo: $Dest"
}

Get-VoskModel "vosk-model-small-es-0.42" "model-es" "am"
Get-VoskModel "vosk-model-spk-0.4" "model-spk" "mfcc.conf"

Write-Host "`nModelos listos. Reinstala la app para incluirlos." -ForegroundColor Green
