Write-Host "Gerando build WINDOWS..." -ForegroundColor Cyan

$ErrorActionPreference = "Stop"

$Projeto = "C:\Dev\projects\uai_capoeira"
$NugetPath = "C:\Tools\NuGet\nuget.exe"

Set-Location $Projeto

Write-Host ""
Write-Host "Verificando NuGet..." -ForegroundColor Cyan

if (-not (Get-Command nuget -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path $NugetPath)) {
        Write-Host "NuGet não encontrado. Baixando manualmente..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Force "C:\Tools\NuGet" | Out-Null
        Invoke-WebRequest "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $NugetPath
    }

    $env:PATH = "$env:PATH;C:\Tools\NuGet"
}

Write-Host "NuGet OK." -ForegroundColor Green

Write-Host ""
Write-Host "Limpando build Windows antigo..." -ForegroundColor Cyan
if (Test-Path ".\build\windows") {
    Remove-Item ".\build\windows" -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Baixando dependências Flutter..." -ForegroundColor Cyan
flutter pub get

Write-Host ""
Write-Host "Gerando aplicação Windows release..." -ForegroundColor Cyan
flutter build windows --release

Write-Host ""
Write-Host "Aplicação Windows gerada com sucesso." -ForegroundColor Green
Write-Host "Pasta:"
Write-Host "$Projeto\build\windows\x64\runner\Release" -ForegroundColor Yellow

pause