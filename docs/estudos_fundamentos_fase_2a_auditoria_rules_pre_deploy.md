# Auditoria pre-deploy das Firestore Rules - Estudos/Fundamentos

Data: 2026-07-11
Fase: Fase 1 - Blindagem de seguranca das Firestore Rules para Estudos/Fundamentos

## Status geral

Status: APROVADO COM OBSERVACOES.

As rules candidatas de `firebase_rules_test/firestore.rules` e `firebase_rules_backup/firestore_mesclado_com_estudos_fundamentos.rules` foram comparadas, corrigidas pontualmente e validadas no emulador local. Elas removem o fallback global aberto da rule antiga e protegem os principais documentos sensiveis do modulo Estudos/Fundamentos.

Nenhum deploy foi feito. Producao nao foi alterada. APK nao foi gerado nesta fase.

## Arquivos analisados

- `firebase_rules_test/firestore.rules`
- `firebase_rules_backup/firestore_mesclado_com_estudos_fundamentos.rules`
- `firebase_rules_backup/firestore_producao_atual.rules`
- `firebase.json`
- `docs/`
- Uso de colecoes Firestore em `lib/` via `rg "collection\(|collectionGroup\(" lib`

## Comandos rodados

- `git status --short`
  - Resultado: existem alteracoes locais preexistentes fora desta fase, incluindo arquivos Flutter e `pubspec.yaml`. Nenhuma delas foi alterada nesta auditoria.
- `git log --oneline -5`
  - Resultado: ultimos commits incluem `37eb215 fix: corrigir overflow na lista de chamadas` e `9dc72af feat: implementar modulo estudos e fundamentos v1`.
- `Test-Path firestore.rules`
  - Resultado: `False`. Nao existe `firestore.rules` na raiz.
- `Select-String -Path firebase.json -Pattern '"firestore"|firestore.rules' -ErrorAction SilentlyContinue`
  - Resultado: sem ocorrencias. O `firebase.json` principal nao aponta para `firestore.rules`.
- `cmd /c fc firebase_rules_test\firestore.rules firebase_rules_backup\firestore_mesclado_com_estudos_fundamentos.rules`
  - Resultado: arquivos iguais apos a correcao.
- `powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1`
  - Resultado: todos os testes funcionais basicos e extras passaram.
- `rg "collection\(|collectionGroup\(" lib`
  - Resultado: usado para identificar colecoes antigas consumidas pelo app e possiveis riscos de quebra.

## Comparacao das rules

- Rule antiga de producao: `firebase_rules_backup/firestore_producao_atual.rules`.
  - Contem leitura global aberta: `match /{document=**} allow read: if true`.
  - Contem escrita global ampla para usuario autenticado: `match /{document=**} allow write: if request.auth != null`.
  - Esse comportamento e perigoso para gabaritos, resultados, tentativas e campos oficiais.

- Candidato seguro: `firebase_rules_test/firestore.rules` e `firebase_rules_backup/firestore_mesclado_com_estudos_fundamentos.rules`.
  - Os dois arquivos estao iguais.
  - O fallback final e fechado: `match /{document=**} { allow read, write: if false; }`.
  - Nao ha fallback global aberto no candidato.

## Correcao aplicada

Foi corrigida a funcao `perguntaPublicaSemGabarito(data)` nos dois arquivos candidatos para bloquear todos os campos proibidos listados para documento publico de pergunta:

- `alternativasCorretasIds`
- `nota`
- `aprovado`
- `certificado`
- `emblema`
- `badge`

Antes da correcao, o candidato ja bloqueava `respostaCorreta`, `alternativaCorretaId`, `correta`, `isCorrect`, `feedbackCorreto`, `justificativaCorreta` e `score`, mas nao cobria todos os nomes solicitados.

Arquivos alterados:

- `firebase_rules_test/firestore.rules`
- `firebase_rules_backup/firestore_mesclado_com_estudos_fundamentos.rules`
- `docs/estudos_fundamentos_fase_2a_auditoria_rules_pre_deploy.md`

## Resultado dos testes

Suite executada:

`powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1`

Resultado:

- Teste funcional basico: passou.
- Teste funcional extra: passou.
- Confirmado no log do script: nenhum deploy foi feito e producao nao foi alterada.
- Mensagens `PERMISSION_DENIED` no final do log correspondem aos testes negativos esperados.

## Seguranca do modulo Estudos/Fundamentos

Confirmado no candidato:

- `estudos_config/global`
  - Leitura apenas para usuario autenticado.
  - Escrita apenas para admin ou permissao granular `pode_gerenciar_estudos_fundamentos`.

- `estudos_ciclos`
  - Admin/permissao gerencia.
  - Aluno autenticado le apenas conteudo visivel, publicado ou `em_breve` quando `mostrarEmBreve == true`.
  - Rascunho/oculto/arquivado nao fica visivel se nao satisfizer status e `mostrarNaLinhaDoTempo`.

- `estudos`
  - Mesma politica de ciclos.
  - Testes confirmam leitura de publicado, bloqueio de rascunho e bloqueio de anonimo.

- `estudos_perguntas`
  - Admin/permissao le e gerencia.
  - Aluno nao le perguntas nesta fase, conforme teste atual.
  - Criacao/atualizacao por admin/permissao exige documento sem campos de gabarito/resultado proibidos.
  - Observacao: se a leitura de perguntas por aluno for aberta no futuro, sera necessario adicionar condicoes de visibilidade por `status`, `ativa/publicada`, `estudoId/cicloId` e manter a lista de campos proibidos.

- `estudos_gabaritos`
  - Aluno nao le.
  - Aluno nao escreve.
  - Apenas admin/permissao de estudos gerencia.

- `alunos_estudos_progresso`
  - Aluno acessa apenas progresso do proprio aluno vinculado via `areaAlunoGoogleUid`.
  - Admin/permissao acessa.
  - Escrita do aluno restringe chaves via `hasOnly(progressoCamposPermitidos())`.
  - Campos oficiais como `nota`, `aprovado`, `reprovado`, `certificado`, `certificadoUrl`, `emblema`, `badge`, `resultadoOficial`, `score` e `percentualAcertosOficial` nao sao aceitos por nao constarem na lista permitida.

- `avaliacoes_tentativas`
  - Leitura por admin/permissao ou pelo proprio aluno vinculado.
  - Criacao, atualizacao e exclusao bloqueadas para cliente.

- Fallback final
  - Fechado com `allow read, write: if false`.

## Riscos encontrados

### Risco principal: compatibilidade com modulos antigos

O candidato substitui o fallback global aberto por blocos explicitos. Isso melhora a seguranca, mas pode quebrar modulos antigos que dependiam do fallback antigo.

Blocos explicitamente contemplados no candidato:

- `usuarios`
- `usuarios/{uid}/permissoes_usuario`
- `alunos`
- `alunos/{alunoId}/contadores`
- `turmas`
- `turmas/{turmaId}/dashboard_cache`
- `turmas/{turmaId}/dashboard_cache_alunos`
- `turmas/{turmaId}/avaliacoes_alunos`
- `eventos`
- `eventos/{eventoId}/participantes_cache`
- `participacoes_eventos_em_andamento`
- `estatisticas`
- `estatisticas_acessos`
- `graduacoes`
- `inscricoes`
- `campeonato_inscricoes`
- `configuracoes`
- `config_graduacoes`

Risco de quebra identificado no app porque ha uso em `lib/` sem bloco explicito no candidato:

- `chamadas`: risco alto, usado por telas de chamadas.
- `log_presenca_alunos`: risco alto, usado por chamadas/frequencia.
- `locks_chamada`: risco alto, usado no fluxo de chamada.
- `contador_presencas_alunos`: risco medio/alto, usado em frequencia.
- `configuracoes_sistema`: risco alto, usado por tema, dashboard, chamadas e configuracoes administrativas.
- `academias`: risco medio, usado por cadastro/turmas.
- `participacoes_eventos`: risco medio, usado em certificados/eventos.
- `inscricoes_aprovadas`: risco medio, usado no fluxo de inscricoes.
- `site_conteudo`, `configuracoes_site`, `timeline_publicacoes`, `config_site_assistente`: risco medio para site/admin.
- `notificacoes`, `versoes_app`: risco medio para notificacoes/atualizacao.
- Colecoes de uniformes/financeiro (`uniformes_estoque`, `vendas_uniformes`, `pedidos_uniformes`, `remessas`, `fornecedores`, `pagamentos`, `movimentacoes_estoque`): risco medio/alto se esses modulos estiverem ativos.
- Colecoes novas/admin como `caca_bug_sessoes` e `area_aluno_*`: precisam teste manual se forem usadas em producao.

Conclusao de compatibilidade: precisa teste manual dos fluxos antigos antes de deploy real, especialmente chamadas/turmas/alunos/eventos/dashboard. O candidato preserva varias colecoes antigas, mas nao todas as colecoes usadas pelo app.

### Observacao sobre futuras tentativas/resultados

Nao ha bloco explicito para `estudos_tentativas` ou `estudos_resultados` no candidato. Pelo fallback fechado, elas ficam bloqueadas para cliente por enquanto.

Recomendacao futura:

- `estudos_tentativas`: aluno pode criar tentativa propria apenas com campos nao oficiais e vinculacao validada; aluno nao pode alterar nota, aprovado, certificado, score oficial ou resultado oficial.
- `estudos_resultados`: leitura limitada ao proprio aluno/admin; escrita apenas backend/admin/permissao; Flutter nao deve escrever resultado oficial.
- Cloud Functions com Admin SDK podem gravar resultados oficiais ignorando rules, como esperado.

## Checklist para deploy manual futuro

Antes de publicar rules manualmente:

1. Exportar/copiar as rules atuais reais do Firebase Console no momento do deploy.
2. Comparar novamente com `firebase_rules_backup/firestore_producao_atual.rules`, pois este arquivo pode estar defasado em relacao ao Console.
3. Mesclar explicitamente regras das colecoes antigas ainda descobertas no app, principalmente `chamadas`, `log_presenca_alunos`, `locks_chamada` e `configuracoes_sistema`.
4. Rodar novamente `powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1`.
5. Fazer teste manual em ambiente controlado dos fluxos:
   - login/admin/permissoes
   - alunos
   - turmas/dashboard
   - chamadas/frequencia
   - eventos/participacoes
   - estudos/fundamentos admin e aluno
6. Publicar manualmente somente depois da validacao funcional.
7. Monitorar erros de permissao no app apos publicacao.

## Rollback sugerido

Se houver quebra apos deploy manual futuro:

1. Reverter no Firebase Console para a rule anterior salva/exportada imediatamente antes do deploy.
2. Validar login e fluxos criticos: chamadas, turmas, alunos, eventos e dashboard.
3. Reaplicar a versao segura somente apos incluir blocos explicitos para as colecoes que quebraram.

## Confirmacao final

Nenhum firebase deploy foi executado.

Producao nao foi alterada.

APK nao foi gerado nesta fase.
## Fase 1.1 - Cobertura complementar de colecoes antigas

Data: 2026-07-11

Objetivo: reduzir o risco de quebra dos modulos antigos apos fechamento do fallback global, adicionando blocos explicitos para colecoes usadas pelo app em `lib/`.

### Busca executada

Foram feitas buscas com `rg` em `lib/` para:

- `chamadas`
- `log_presenca_alunos`
- `locks_chamada`
- `configuracoes_sistema`
- `academias`
- `participacoes_eventos`
- `inscricoes_aprovadas`
- `uniformes`
- `site`
- `patrocinadores`
- `posts`
- `galeria`
- `banners`

Tambem foi feita busca especifica por `.collection(...)` para colecoes antigas e de modulos site/uniformes/eventos.

### Colecoes antigas encontradas e regra aplicada

Para preservar compatibilidade com a rule antiga, sem reabrir fallback global, as colecoes abaixo receberam bloco explicito com leitura publica e escrita apenas para usuario autenticado:

- `chamadas`: `allow read: if true; allow write: if isSignedIn();`
- `chamadas_turma`: `allow read: if true; allow write: if isSignedIn();`
- `log_presenca_alunos`: `allow read: if true; allow write: if isSignedIn();`
- `locks_chamada`: `allow read: if true; allow write: if isSignedIn();`
- `contador_presencas_alunos`: `allow read: if true; allow write: if isSignedIn();`
- `configuracoes_sistema`: `allow read: if true; allow write: if isSignedIn();`
- `academias`: `allow read: if true; allow write: if isSignedIn();`
- `participacoes_eventos`: `allow read: if true; allow write: if isSignedIn();`
- `inscricoes_aprovadas`: `allow read: if true; allow write: if isSignedIn();`
- `configuracoes_site`: `allow read: if true; allow write: if isSignedIn();`
- `site_conteudo`: `allow read: if true; allow write: if isSignedIn();`
- `timeline_publicacoes`: `allow read: if true; allow write: if isSignedIn();`
- `config_site_assistente`: `allow read: if true; allow write: if isSignedIn();`
- `patrocinadores_eventos`: `allow read: if true; allow write: if isSignedIn();`
- `patrocinadores_eventos/{patrocinadorId}/pagamentos`: `allow read: if true; allow write: if isSignedIn();`
- `posts`: `allow read: if true; allow write: if isSignedIn();`
- `galeria`: `allow read: if true; allow write: if isSignedIn();`
- `banners`: `allow read: if true; allow write: if isSignedIn();`
- `uniformes_estoque`: `allow read: if true; allow write: if isSignedIn();`
- `vendas_uniformes`: `allow read: if true; allow write: if isSignedIn();`
- `pedidos_uniformes`: `allow read: if true; allow write: if isSignedIn();`
- `remessas`: `allow read: if true; allow write: if isSignedIn();`
- `fornecedores`: `allow read: if true; allow write: if isSignedIn();`
- `pagamentos`: `allow read: if true; allow write: if isSignedIn();`
- `movimentacoes_estoque`: `allow read: if true; allow write: if isSignedIn();`

Justificativa: a rule antiga tinha leitura global publica e escrita global para autenticado. Estes blocos tornam esse comportamento explicito apenas nas colecoes conhecidas, mantendo o fallback final fechado para colecoes nao mapeadas e mantendo a protecao de Estudos/Fundamentos.

### Testes rodados na Fase 1.1

- `cmd /c fc firebase_rules_test\firestore.rules firebase_rules_backup\firestore_mesclado_com_estudos_fundamentos.rules`
  - Resultado: arquivos iguais.
- `powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1`
  - Resultado: todos os testes funcionais basicos e extras passaram.
  - As mensagens `PERMISSION_DENIED` no log sao dos cenarios negativos esperados.

### Seguranca de Estudos preservada

A Fase 1.1 nao alterou os blocos de Estudos/Fundamentos. Permanece confirmado:

- `estudos_gabaritos` sem acesso para aluno.
- `estudos_perguntas` exige documento publico sem campos de gabarito/resultado proibidos.
- `alunos_estudos_progresso` permite escrita do aluno apenas em campos de progresso permitidos.
- Campos oficiais como `nota`, `aprovado`, `certificado`, `score` e similares continuam bloqueados no progresso do aluno.
- Rascunhos/ocultos/arquivados continuam fora da leitura de aluno quando nao satisfazem as condicoes de visibilidade.
- Fallback final continua fechado: `allow read, write: if false`.

### Risco restante

Ainda precisa teste manual antes de qualquer deploy real, porque os blocos complementares preservam compatibilidade ampla, mas nao validam fluxo de negocio tela a tela. Testar manualmente:

- chamadas/frequencia
- turmas/dashboard
- alunos
- eventos/participacoes/patrocinadores
- site publico e admin de site
- uniformes/estoque/vendas/pedidos/remessas

Nao foi feito Firebase deploy. Producao nao foi alterada. APK nao foi gerado nesta fase.

## Correcoes pos-review

Data: 2026-07-11

Foram corrigidos somente os achados do review nas Firestore Rules candidatas.

### P1 - Caca Bug coberto

Uso confirmado em `lib/core/caca_bug/caca_bug_service.dart`:

- `caca_bug_sessoes/{sessaoId}`
- `caca_bug_sessoes/{sessaoId}/eventos/{eventoId}`

Regra aplicada:

- `read`: apenas `isAdmin()`.
- `create, update`: usuario autenticado, porque o proprio app cliente registra sessao, finaliza sessoes antigas e grava eventos em lote.
- `delete`: apenas `isAdmin()`.

Decisao: a escrita autenticada preserva a compatibilidade necessaria para usuarios monitorados pelo Caca Bug. A leitura foi mantida mais restrita que a rule antiga, usando o helper `isAdmin()` ja existente.

### P2 - Logo dinamica coberta

Uso confirmado em `lib/core/logo/uai_logo_service.dart`:

- `configuracoes_sistema/logo_dinamica/temas/{themeId}`

Regra aplicada:

- `read`: publico, alinhado ao uso visual do app e a leitura ja publica de `configuracoes_sistema/{document}`.
- `write`: usuario autenticado, mantendo compatibilidade com a regra candidata ja existente para `configuracoes_sistema/{document}`.

A subcolecao passou a ter bloco explicito, sem depender de fallback global.

### Validacao pos-review

Comandos rodados:

- `cmd /c fc firebase_rules_test\firestore.rules firebase_rules_backup\firestore_mesclado_com_estudos_fundamentos.rules`
  - Resultado: arquivos iguais.
- `powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1`
  - Resultado: todos os testes funcionais basicos e extras passaram.

### Confirmacao pos-review

Nenhum firebase deploy foi executado.

Producao nao foi alterada.

Flutter nao foi alterado.
