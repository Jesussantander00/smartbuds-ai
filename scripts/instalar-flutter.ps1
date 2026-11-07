# SmartBuds AI - instala Flutter (si falta) y prepara el proyecto.
# Uso, desde la carpeta smartbuds-ai:
#   powershell -ExecutionPolicy Bypass -File .\scripts\instalar-flutter.ps1

$ErrorActionPreference = "Continue"  # git y flutter escriben progreso en stderr
$FlutterRoot = "C:\src\flutter"
$FlutterBin  = Join-Path $FlutterRoot "bin"
$Project     = Split-Path -Parent $PSScriptRoot

function Paso($texto) { Write-Host "`n==> $texto" -ForegroundColor Cyan }

# 1. Instalar Flutter si no existe
if (Test-Path (Join-Path $FlutterBin "flutter.bat")) {
    Paso "Flutter ya esta en $FlutterRoot"
} else {
    # Restos de un intento anterior incompleto
    if (Test-Path $FlutterRoot) {
        Paso "Borrando instalacion incompleta en $FlutterRoot"
        Remove-Item $FlutterRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force "C:\src" | Out-Null

    Paso "Buscando la version estable actual de Flutter"
    $rel  = Invoke-RestMethod -ErrorAction Stop "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json"
    $hash = $rel.current_release.stable
    $arch = ($rel.releases | Where-Object { $_.hash -eq $hash } | Select-Object -First 1).archive
    $url  = "$($rel.base_url)/$arch"
    $zip  = Join-Path $env:TEMP (Split-Path $arch -Leaf)
    Write-Host "    $url"

    # curl.exe reanuda (-C -) si la conexion se corta; se reintenta hasta 50 veces.
    Paso "Descargando Flutter (~1 GB). Si se corta, continua donde quedo."
    $ok = $false
    for ($i = 1; $i -le 50; $i++) {
        curl.exe -L --fail -C - --retry 5 --retry-delay 5 -o $zip $url
        if ($LASTEXITCODE -eq 0) { $ok = $true; break }
        Write-Host "    Conexion interrumpida (intento $i). Reanudando en 10 s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
    }
    if (-not $ok) { throw "No se pudo completar la descarga. Vuelve a ejecutar el script: retoma donde quedo." }

    Paso "Descomprimiendo en C:\src ... puede tardar varios minutos"
    tar.exe -xf $zip -C "C:\src"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    tar fallo; usando Expand-Archive (mas lento)" -ForegroundColor Yellow
        Expand-Archive $zip -DestinationPath "C:\src" -Force
    }
    if (-not (Test-Path (Join-Path $FlutterBin "flutter.bat"))) {
        throw "La descompresion no dejo flutter.bat en $FlutterBin"
    }
    Remove-Item $zip
}

# 2. PATH permanente (usuario) y en esta sesion
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not ($userPath -split ";" | Where-Object { $_ -eq $FlutterBin })) {
    Paso "Agregando $FlutterBin al PATH del usuario"
    [Environment]::SetEnvironmentVariable("Path", ($userPath.TrimEnd(";") + ";" + $FlutterBin), "User")
}
if (-not ($env:Path -split ";" | Where-Object { $_ -eq $FlutterBin })) {
    $env:Path += ";$FlutterBin"
}

# 3. Diagnostico
Paso "flutter --version"
flutter --version
Paso "flutter doctor"
flutter doctor

# 4. Preparar el proyecto
Set-Location $Project
Paso "flutter create (genera lo que falta de Android/iOS sin sobrescribir el codigo)"
flutter create --org com.smartbuds --project-name smartbuds_ai --platforms android,ios .
Paso "flutter pub get"
flutter pub get
Paso "flutter test"
flutter test

Write-Host "`nListo. Si flutter doctor pidio aceptar licencias, ejecuta:" -ForegroundColor Green
Write-Host "  flutter doctor --android-licenses" -ForegroundColor Green
Write-Host "Cierra y vuelve a abrir Android Studio para que reconozca el PATH nuevo." -ForegroundColor Green
