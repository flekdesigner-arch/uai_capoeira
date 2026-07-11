# Testes locais das Firestore Rules - Estudos e Fundamentos
# NÃO faz deploy.
# NÃO altera produção.
# NÃO altera firebase.json principal.
# Apenas roda os testes locais no Firestore Emulator.

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================"
Write-Host " Testes locais das Rules - Estudos"
Write-Host "============================================"
Write-Host ""

$projectRoot = Resolve-Path "$PSScriptRoot\.."
Set-Location $projectRoot

Write-Host "Projeto: $projectRoot"
Write-Host ""

$jdk21 = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory |
  Where-Object { $_.Name -like "jdk-21*" } |
  Select-Object -First 1 -ExpandProperty FullName

if (-not $jdk21) {
  throw "JDK 21 nao encontrado em C:\Program Files\Eclipse Adoptium"
}

$env:JAVA_HOME = $jdk21
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

Write-Host "Java em uso:"
java -version
Write-Host ""

Write-Host "Verificando arquivos..."
if (!(Test-Path "firebase_rules_test\firebase.json")) {
  throw "Arquivo firebase_rules_test\firebase.json nao encontrado."
}

if (!(Test-Path "firebase_rules_test\firestore.rules")) {
  throw "Arquivo firebase_rules_test\firestore.rules nao encontrado."
}

if (!(Test-Path "firebase_rules_test\functional_tests\estudos_rules_test.js")) {
  throw "Arquivo estudos_rules_test.js nao encontrado."
}

if (!(Test-Path "firebase_rules_test\functional_tests\estudos_rules_extra_test.js")) {
  throw "Arquivo estudos_rules_extra_test.js nao encontrado."
}

Write-Host "Arquivos OK."
Write-Host ""

Write-Host "Rodando teste funcional basico..."
firebase emulators:exec --project demo-uai-capoeira-rules --only firestore --config firebase_rules_test/firebase.json "node firebase_rules_test/functional_tests/estudos_rules_test.js"

Write-Host ""
Write-Host "Rodando teste funcional extra..."
firebase emulators:exec --project demo-uai-capoeira-rules --only firestore --config firebase_rules_test/firebase.json "node firebase_rules_test/functional_tests/estudos_rules_extra_test.js"

Write-Host ""
Write-Host "============================================"
Write-Host " TODOS OS TESTES DAS RULES PASSARAM"
Write-Host " Nenhum deploy foi feito."
Write-Host " Producao nao foi alterada."
Write-Host "============================================"
Write-Host ""