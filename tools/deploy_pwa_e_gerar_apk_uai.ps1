param(
  [switch]$Auto,
  [string]$Version = "",
  [int]$Build = 0,
  [switch]$SkipPwa,
  [switch]$SkipAndroid,
  [switch]$SkipWindows,
  [switch]$SkipPrepare
)
$ProjectDir = "C:\Dev\projects\uai_capoeira"
if ([string]::IsNullOrWhiteSpace($Version) -or $Build -le 0) {
  $pubspecPath = Join-Path $ProjectDir "pubspec.yaml"
  if (!(Test-Path $pubspecPath)) { throw "pubspec.yaml nao encontrado: $pubspecPath" }

  # Le como UTF-8 via .NET, sem jamais regravar o arquivo nesta etapa.
  $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
  try {
    $text = $utf8.GetString([System.IO.File]::ReadAllBytes($pubspecPath))
  } catch {
    throw "pubspec.yaml nao esta em UTF-8 valido. Corrija o encoding antes de publicar."
  }

  $match = [regex]::Match($text, '(?m)^version:\s*([^+\r\n]+)\+(\d+)\s*$')
  if (!$match.Success) { throw "Campo version invalido no pubspec.yaml. Esperado: version: X.Y.Z+BUILD" }

  if ([string]::IsNullOrWhiteSpace($Version)) { $Version = $match.Groups[1].Value.Trim() }
  if ($Build -le 0) { $Build = [int]$match.Groups[2].Value }
}
$releaseArgs = @{ Version = $Version; Build = $Build; ProjectDir = $ProjectDir }
if ($SkipPwa) { $releaseArgs["SkipPwa"] = $true }
if ($SkipAndroid) { $releaseArgs["SkipAndroid"] = $true }
if ($SkipWindows) { $releaseArgs["SkipWindows"] = $true }
if ($SkipPrepare) { $releaseArgs["SkipPrepare"] = $true }
& (Join-Path $ProjectDir "tools\release\release_uai.ps1") @releaseArgs
exit $LASTEXITCODE
