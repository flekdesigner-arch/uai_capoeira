Write-Host "🌐 Gerando build WINDOWS..." -ForegroundColor Cyan

Set-Location "C:\Dev\projects\uai_capoeira"

flutter pub get

Write-Host "🚀 GERANDO APLICAÇÃO WINDOWS..." -ForegroundColor Cyan

flutter build windows --release

Write-Host ""
Write-Host "✅ APLICAÇÃO GERADA com sucesso." -ForegroundColor Green
pause