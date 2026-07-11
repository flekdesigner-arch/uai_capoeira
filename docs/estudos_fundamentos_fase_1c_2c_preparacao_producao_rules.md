# Estudos e Fundamentos - Fase 1C-2C - Preparacao segura para producao das Firestore Rules

Data: 2026-07-10

## Objetivo

Auditoria de preparacao para futura publicacao das Firestore Rules do modulo Estudos e Fundamentos, sem deploy e sem alteracao funcional no app.

## Status das fases concluidas

- Fase 1C: perguntas publicas do modulo Estudos e Fundamentos criadas sem gabarito no documento publico.
- Fase 1C-2A: proposta segura de Firestore Rules mantida em artefatos locais de backup/teste.
- Fase 1C-2B: gabarito administrativo protegido criado, usando `estudos_gabaritos/{perguntaId}`.
- Fase 1C-2B: botao `Gabarito` integrado apenas na tela admin de perguntas.
- Fase 1C-2B: ativar, desativar, switch de ativo e exclusao do gabarito passam por confirmacao.
- Fase 1C-2B: resposta correta nao e salva em `estudos_perguntas`.

## Auditoria tecnica

### firebase.json principal

O `firebase.json` principal foi inspecionado e continua sem bloco `firestore`.

Nao foi identificado diff em `firebase.json` durante esta auditoria.

### Artefatos locais de rules

As rules candidatas e arquivos de teste permanecem em artefatos locais:

- `firebase_rules_backup/firestore_mesclado_com_estudos_fundamentos.rules`
- `firebase_rules_backup/firestore_producao_atual.rules`
- `firebase_rules_test/firestore.rules`
- `firebase_rules_test/firebase.json`
- `firebase_rules_test/run_estudos_rules_tests.ps1`
- `firebase_rules_test/functional_tests/estudos_rules_test.js`
- `firebase_rules_test/functional_tests/estudos_rules_extra_test.js`

Esses arquivos sao usados para validacao local no Firestore Emulator. Nao houve conexao desses arquivos ao `firebase.json` principal.

### Uso de gabarito no app

A busca por `estudos_gabaritos`, `GabaritosEstudosRepository` e `GerenciarGabaritoPerguntaScreen` indicou uso no fluxo administrativo do modulo Estudos e Fundamentos:

- `lib/modules/estudos_fundamentos/repositories/gabaritos_estudos_repository.dart`
- `lib/modules/estudos_fundamentos/admin/gerenciar_gabarito_pergunta_screen.dart`
- `lib/modules/estudos_fundamentos/admin/gerenciar_perguntas_estudo_screen.dart`

Nao foi encontrado uso de `estudos_gabaritos` na Area do Aluno durante a auditoria.

### Perguntas publicas

A busca por campos de resposta correta no modulo indicou que os campos sensiveis (`alternativaCorretaId`, `alternativasCorretasIds`, `respostaEsperadaTexto`, `justificativaCorreta`) estao no modelo/tela/repositorio de gabarito protegido.

Nao foi identificado campo de resposta correta sendo salvo no modelo publico `PerguntaEstudoModel` ou no repositorio publico `PerguntasEstudosRepository`.

## Validacao local

Comando executado:

```powershell
dart analyze lib/modules/estudos_fundamentos
```

Resultado:

```text
Analyzing estudos_fundamentos...
No issues found!
```

Comando executado:

```powershell
powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1
```

Resultado:

```text
TODOS OS TESTES DAS RULES PASSARAM
Nenhum deploy foi feito.
Producao nao foi alterada.
```

Os logs `PERMISSION_DENIED` no final do script fazem parte dos cenarios negativos testados pelas rules locais.

## Riscos de publicar rules sem teste manual

- Bloquear leitura de estudos publicados para alunos autenticados por diferenca entre dados reais e fixtures do emulator.
- Bloquear progresso de leitura se documentos reais tiverem campos extras nao cobertos nos testes locais.
- Liberar leitura indevida por permissao administrativa granular mal configurada em usuarios reais.
- Quebrar telas admin se alguma colecao real tiver formato antigo ou campos ausentes.
- Interromper fluxos legados fora do modulo Estudos e Fundamentos caso a mesclagem final das rules altere comportamento existente.
- Publicar rules sem plano de rollback claro pode aumentar tempo de indisponibilidade para alunos/admins.

## Checklist antes de deploy

- Confirmar novamente que `firebase.json` principal ainda nao aponta para rules candidatas sem decisao explicita.
- Comparar rules candidatas com rules de producao atual e revisar somente as diferencas esperadas.
- Rodar `dart analyze lib/modules/estudos_fundamentos`.
- Rodar `powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1`.
- Fazer teste manual completo em ambiente seguro/staging, se disponivel.
- Validar usuario admin completo, usuario com permissao granular, aluno autenticado e anonimo.
- Validar documentos reais ou copia sanitizada de dados reais para estudos, perguntas, gabaritos e progresso.
- Garantir que nenhum campo de resposta correta exista em `estudos_perguntas`.
- Garantir que alunos nao consigam ler `estudos_gabaritos`.
- Definir responsavel, janela de publicacao e plano de rollback.

## Checklist depois de deploy futuro

- Validar login de aluno e leitura de estudos publicados.
- Validar que aluno nao le `estudos_gabaritos`.
- Validar progresso de leitura do proprio aluno.
- Validar que aluno nao escreve progresso de outro usuario.
- Validar admin lendo e editando config/ciclos/estudos/perguntas/gabaritos.
- Validar usuario sem permissao admin negado nas colecoes administrativas.
- Validar que anonimo nao acessa config/gabaritos e nao le conteudo restrito.
- Monitorar erros de permissao no app e no console Firebase.
- Confirmar que nenhuma Cloud Function foi necessaria para esta fase.

## Fluxos manuais que precisam ser testados

### Area do Aluno

- Aluno autenticado abre Area do Aluno.
- Aluno visualiza lista inicial de estudos publicados.
- Aluno abre estudo publicado.
- Aluno registra progresso de leitura proprio.
- Aluno nao ve gabarito, resposta correta, justificativa ou alternativa correta.
- Aluno nao acessa estudo rascunho/inativo quando nao permitido.
- Usuario anonimo nao acessa conteudo restrito.

### Admin Estudos e Fundamentos

- Admin abre configuracao global do modulo.
- Admin cria/edita ciclo.
- Admin cria/edita estudo/artigo.
- Admin usa preview/editor.
- Admin cria/edita pergunta publica sem resposta correta.
- Admin duplica pergunta e confirma que gabarito nao e copiado automaticamente.
- Admin abre tela de gabarito pelo botao `Gabarito`.
- Admin cria, edita, ativa, desativa e exclui gabarito protegido.
- Admin confirma que ativar/desativar, switch e exclusao pedem confirmacao.

### Permissoes

- Usuario admin completo consegue ler/escrever colecoes administrativas esperadas.
- Usuario com permissao granular consegue executar apenas acoes permitidas.
- Aluno nao consegue ler `estudos_gabaritos`.
- Aluno nao consegue escrever `estudos_gabaritos`.
- Aluno nao consegue gravar campos proibidos no progresso.
- Usuario nao consegue acessar progresso de outro usuario.

## Findings

### Alto

Nenhum finding Alto identificado nesta auditoria.

### Medio

Nenhum finding Medio identificado nesta auditoria.

### Baixo

Nenhum finding Baixo identificado nesta auditoria.

## Recomendacao final

Ainda nao publicar as rules em producao ate concluir teste manual completo dos fluxos listados acima, preferencialmente com dados reais sanitizados ou ambiente de staging.

## Confirmacoes

Nenhum deploy foi feito.

Producao nao foi alterada.

Nao houve alteracao no `firebase.json` principal.

Nao houve alteracao em rules de producao.

Nao foram criadas Cloud Functions.