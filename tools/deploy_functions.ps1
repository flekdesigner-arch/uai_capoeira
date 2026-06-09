Write-Host "🚀 Iniciando deploy das Cloud Functions..." -ForegroundColor Cyan

Set-Location "C:\Dev\projects\uai_capoeira"

firebase deploy --only functions

Write-Host ""
Write-Host "✅ Processo finalizado." -ForegroundColor Green
pause