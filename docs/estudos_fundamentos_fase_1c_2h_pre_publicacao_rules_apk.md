# Estudos e Fundamentos - Fase 1C-2H - Pre-publicacao rules e APK

Data: 2026-07-10

## Status atual

O modulo Estudos e Fundamentos v1 esta funcional em desenvolvimento e passou pelas validacoes locais feitas ate aqui.

- Admin de ciclos, estudos, perguntas e gabarito funcionando.
- Detalhe do estudo com perguntas funcionando.
- Nova pergunta neste estudo funcionando.
- Area do Aluno testada.
- Chrome testado.
- Emulador Android testado.
- Analyze passou.
- Testes locais das rules passaram.
- Plano de publicacao segura 1C-2G criado.
- Ainda nao houve deploy.
- Produção ainda nao teve Firestore Rules alteradas.

O usuario informou que apagou manualmente todos os gabaritos de teste das 4 perguntas.

## O que nao pode existir antes da publicacao

- Gabarito real ou teste salvo sem rules seguras publicadas.
- `firebase.json` alterado sem revisao.
- `firestore.rules` na raiz sem decisao explicita.
- APK publicado antes das rules.
- Deploy sem rollback pronto.

## Riscos

- Publicar rules sem confirmar backup do estado atual do Firebase Console.
- Liberar APK antes de consolidar a seguranca das rules.
- Confundir rules candidatas locais com regras de producao.
- Deixar dados de gabarito de teste ou lixo de validacao no ambiente de publicacao.
- Fazer publicacao sem validar o fluxo completo do app depois das rules.

## Acoes manuais obrigatorias

- Confirmar que `estudos_gabaritos` esta vazio antes de qualquer publicacao.
- Conferir se o `firebase.json` principal segue sem apontar para rules de producao.
- Conferir que nao existe `firestore.rules` na raiz do projeto.
- Separar backup das rules atuais do Firebase Console.
- Revisar o diff final das rules candidatas antes de publicar.
- Testar o app completo depois da publicacao das rules.
- Gerar APK somente depois de validar as rules publicadas.

## Checklist antes de deploy das rules

- Backup salvo das rules atuais do Firebase Console.
- `firebase.json` principal revisado e sem referencia indevida a rules.
- `firestore.rules` nao existe na raiz do repositorio.
- Rules candidatas continuam somente em:
  - `firebase_rules_backup/firestore_mesclado_com_estudos_fundamentos.rules`
  - `firebase_rules_test/firestore.rules`
- `estudos_gabaritos` vazio ou somente com dados aprovados para publicacao.
- `dart analyze lib/modules/estudos_fundamentos` executado com sucesso.
- `powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1` executado com sucesso.
- Revisao humana final concluida.

## Checklist depois de deploy das rules

- Validar login de admin e aluno.
- Validar Area do Aluno com acesso basico.
- Validar Area do Aluno com Google validado.
- Validar Admin > Estudos e Fundamentos.
- Validar detalhe do estudo e criacao de pergunta vinculada.
- Validar gabarito visivel somente no admin.
- Validar turmas, chamadas, dashboard, alunos e eventos.
- Confirmar que nenhum acesso indevido a `estudos_gabaritos` ocorreu.
- Confirmar que o comportamento publicado corresponde ao teste local.

## Checklist antes de gerar APK

- Rules publicadas e validadas.
- Login e fluxos principais validados no app.
- Admin e Area do Aluno checados novamente.
- Nenhum gabarito de teste remanescente.
- Nenhuma divergencia entre ambiente local e ambiente publicado.
- Revisao final aprovada.

## Checklist depois de instalar APK

- Abrir app em dispositivo alvo.
- Validar Area do Aluno.
- Validar acesso Google.
- Validar admin de Estudos e Fundamentos.
- Validar detalhe do estudo e perguntas vinculadas.
- Validar gabarito admin protegido.
- Validar turmas, chamadas, dashboard, alunos e eventos.

## Plano de rollback

- Restaurar as rules anteriores a partir do backup salvo do Firebase Console.
- Revalidar o comportamento com os mesmos testes do emulator.
- Suspender publicacao de APK se o rollback das rules indicar regressao.
- Repetir apenas com revisao humana e nova janela de publicacao.

## Ordem segura de publicacao

1. Fazer backup das rules atuais do Firebase Console.
2. Publicar as rules seguras revisadas.
3. Testar login, admin, Area do Aluno, turmas, chamadas, dashboard, alunos, eventos e Estudos.
4. Somente depois gerar APK/release.

## Confirmacoes

Nenhum deploy foi feito nesta fase.

Producao nao foi alterada.

Ainda nao e para publicar.

