Write-Host "GERANDO APK MENOR + RENOMEANDO NO PADRAO UAI" -ForegroundColor Cyan
Write-Host "Projeto: UAI Capoeira" -ForegroundColor DarkCyan
Write-Host ""

$ProjectDir = "C:\Dev\projects\uai_capoeira"
Set-Location $ProjectDir

# =====================================================
# LE A VERSAO DO pubspec.yaml
# Exemplo:
# version: 2.0.62+1
# Nome final:
# uai_capoeira_2.0.62.apk
# =====================================================
$PubspecPath = Join-Path $ProjectDir "pubspec.yaml"

if (!(Test-Path $PubspecPath)) {
    Write-Host "ERRO: pubspec.yaml nao encontrado em: $PubspecPath" -ForegroundColor Red
    pause
    exit 1
}

$VersionLine = Get-Content $PubspecPath | Where-Object { $_ -match "^version:\s*" } | Select-Object -First 1

if (-not $VersionLine) {
    Write-Host "ERRO: Campo version nao encontrado no pubspec.yaml" -ForegroundColor Red
    pause
    exit 1
}

$FullVersion = ($VersionLine -replace "version:\s*", "").Trim()
$AppVersion = ($FullVersion -split "\+")[0].Trim()

if (-not $AppVersion) {
    Write-Host "ERRO: Nao foi possivel identificar a versao do app." -ForegroundColor Red
    pause
    exit 1
}

$FinalApkName = "uai_capoeira_$AppVersion.apk"

Write-Host "Versao detectada: $FullVersion" -ForegroundColor Yellow
Write-Host "Nome final do APK: $FinalApkName" -ForegroundColor Yellow
Write-Host ""

# =====================================================
# BUILD
# =====================================================
Write-Host "Limpando build antigo..." -ForegroundColor Yellow
flutter clean

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: falha no flutter clean" -ForegroundColor Red
    pause
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Baixando dependencias..." -ForegroundColor Yellow
flutter pub get

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: falha no flutter pub get" -ForegroundColor Red
    pause
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Gerando APK release somente ARM64..." -ForegroundColor Yellow
flutter build apk --release --target-platform android-arm64

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: falha ao gerar APK" -ForegroundColor Red
    pause
    exit $LASTEXITCODE
}

# =====================================================
# RENOMEIA / COPIA PARA PASTA FINAL
# =====================================================
$OriginalApk = Join-Path $ProjectDir "build\app\outputs\flutter-apk\app-release.apk"
$OutputDir = Join-Path $ProjectDir "build\app\outputs\uai-apks"
$FinalApk = Join-Path $OutputDir $FinalApkName

if (!(Test-Path $OriginalApk)) {
    Write-Host "ERRO: APK original nao encontrado em:" -ForegroundColor Red
    Write-Host $OriginalApk -ForegroundColor Red
    pause
    exit 1
}

if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

Copy-Item -Path $OriginalApk -Destination $FinalApk -Force

Write-Host ""
Write-Host "APK menor gerado e renomeado com sucesso!" -ForegroundColor Green
Write-Host ""
Write-Host "APK original:" -ForegroundColor Cyan
Write-Host $OriginalApk -ForegroundColor DarkYellow
Write-Host ""
Write-Host "APK pronto para subir no Laboratorio:" -ForegroundColor Cyan
Write-Host $FinalApk -ForegroundColor Yellow
Write-Host ""

# =====================================================
# MOSTRA TAMANHO DO APK FINAL
# =====================================================
$SizeBytes = (Get-Item $FinalApk).Length
$SizeMB = [math]::Round($SizeBytes / 1MB, 2)

Write-Host "Tamanho final: $SizeMB MB" -ForegroundColor Magenta
Write-Host ""
Write-Host "LEMBRETE:" -ForegroundColor Magenta
Write-Host "No Laboratorio de Atualizacoes, selecione este arquivo:" -ForegroundColor White
Write-Host $FinalApk -ForegroundColor Yellow
Write-Host ""

pause
