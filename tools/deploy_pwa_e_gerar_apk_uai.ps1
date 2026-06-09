param(
    [switch]$Auto
)

Write-Host "PUBLICAR PWA + GERAR APK UAI MENOR" -ForegroundColor Cyan
Write-Host "Projeto: UAI Capoeira" -ForegroundColor DarkCyan
Write-Host ""

$ProjectDir = "C:\Dev\projects\uai_capoeira"
Set-Location $ProjectDir

# =====================================================
# LE A VERSAO DO pubspec.yaml
# Exemplo:
# version: 2.0.64+1
# Nome final:
# uai_capoeira_2.0.64.apk
# =====================================================
$PubspecPath = Join-Path $ProjectDir "pubspec.yaml"

if (!(Test-Path $PubspecPath)) {
    Write-Host "ERRO: pubspec.yaml nao encontrado em: $PubspecPath" -ForegroundColor Red
    exit 1
}

$VersionLine = Get-Content $PubspecPath | Where-Object { $_ -match "^version:\s*" } | Select-Object -First 1

if (-not $VersionLine) {
    Write-Host "ERRO: Campo version nao encontrado no pubspec.yaml" -ForegroundColor Red
    exit 1
}

$FullVersion = ($VersionLine -replace "version:\s*", "").Trim()
$AppVersion = ($FullVersion -split "\+")[0].Trim()

if (-not $AppVersion) {
    Write-Host "ERRO: Nao foi possivel identificar a versao do app." -ForegroundColor Red
    exit 1
}

$FinalApkName = "uai_capoeira_$AppVersion.apk"

Write-Host "Versao detectada: $FullVersion" -ForegroundColor Yellow
Write-Host "Nome final do APK: $FinalApkName" -ForegroundColor Yellow
Write-Host ""

# =====================================================
# CONFIRMACAO
# =====================================================
Write-Host "Este script vai executar:" -ForegroundColor Cyan
Write-Host "1. flutter clean" -ForegroundColor White
Write-Host "2. flutter pub get" -ForegroundColor White
Write-Host "3. flutter build web --release" -ForegroundColor White
Write-Host "4. firebase deploy --only hosting" -ForegroundColor White
Write-Host "5. flutter build apk --release --target-platform android-arm64" -ForegroundColor White
Write-Host "6. copiar e renomear APK para build\app\outputs\uai-apks\$FinalApkName" -ForegroundColor White
Write-Host ""

if (-not $Auto) {
    $Confirm = Read-Host "Deseja continuar? Digite S para sim"

    if ($Confirm.ToUpper() -ne "S") {
        Write-Host "Operacao cancelada pelo usuario." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "Modo automatico ativo: confirmacao manual ignorada." -ForegroundColor Green
}

# =====================================================
# CLEAN + PUB GET
# =====================================================
Write-Host ""
Write-Host "Limpando build antigo..." -ForegroundColor Yellow
flutter clean

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: falha no flutter clean" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Baixando dependencias..." -ForegroundColor Yellow
flutter pub get

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: falha no flutter pub get" -ForegroundColor Red
    exit $LASTEXITCODE
}

# =====================================================
# BUILD WEB + DEPLOY PWA
# =====================================================
Write-Host ""
Write-Host "Gerando build web release do PWA..." -ForegroundColor Yellow
flutter build web --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: falha no flutter build web" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Publicando PWA no Firebase Hosting..." -ForegroundColor Yellow
firebase deploy --only hosting

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: falha no firebase deploy --only hosting" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "PWA publicado com sucesso!" -ForegroundColor Green

# =====================================================
# BUILD APK MENOR ARM64
# =====================================================
Write-Host ""
Write-Host "Gerando APK release somente ARM64..." -ForegroundColor Yellow
flutter build apk --release --target-platform android-arm64

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: falha ao gerar APK" -ForegroundColor Red
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
    exit 1
}

if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

Copy-Item -Path $OriginalApk -Destination $FinalApk -Force

# =====================================================
# RESULTADO FINAL
# =====================================================
$SizeBytes = (Get-Item $FinalApk).Length
$SizeMB = [math]::Round($SizeBytes / 1MB, 2)

Write-Host ""
Write-Host "PROCESSO FINALIZADO COM SUCESSO!" -ForegroundColor Green
Write-Host ""
Write-Host "PWA:" -ForegroundColor Cyan
Write-Host "Publicado no Firebase Hosting." -ForegroundColor Green
Write-Host ""
Write-Host "APK original:" -ForegroundColor Cyan
Write-Host $OriginalApk -ForegroundColor DarkYellow
Write-Host ""
Write-Host "APK pronto para subir no Laboratorio:" -ForegroundColor Cyan
Write-Host $FinalApk -ForegroundColor Yellow
Write-Host ""
Write-Host "Tamanho final: $SizeMB MB" -ForegroundColor Magenta
Write-Host ""
Write-Host "LEMBRETE:" -ForegroundColor Magenta
Write-Host "No Laboratorio de Atualizacoes, selecione este arquivo:" -ForegroundColor White
Write-Host $FinalApk -ForegroundColor Yellow
Write-Host ""

exit 0
