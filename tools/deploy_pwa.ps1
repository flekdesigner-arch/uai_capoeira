Write-Host "🌐 Gerando build web do PWA..." -ForegroundColor Cyan

Set-Location "C:\Dev\projects\uai_capoeira"

flutter build web --release

Write-Host "🚀 Fazendo deploy do Hosting..." -ForegroundColor Cyan

firebase deploy --only hosting

Write-Host ""
Write-Host "✅ PWA publicado com sucesso." -ForegroundColor Green
pause