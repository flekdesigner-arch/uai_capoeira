# Estudos e Fundamentos - Fase 2A - Planejamento de Avaliacoes

## Status atual

- Modulo Estudos e Fundamentos V1 implementado e commitado em `9dc72af feat: implementar modulo estudos e fundamentos v1`.
- Rules seguras de estudos ja aparecem nos commits recentes, com `af18ada chore: preparar rules seguras para estudos e compatibilidade legada` e `2e2a054 chore: ajustar rules pos-deploy para mensagens e cache`.
- Gabarito privado existe na colecao `estudos_gabaritos` e ja possui repository/admin Flutter para manutencao.
- Aluno ainda nao deve corrigir avaliacao no Flutter. A correcao oficial da Fase 2 deve ocorrer em Cloud Function com Admin SDK.
- Estado Git no inicio desta fase tinha alteracoes locais fora do escopo:
  - Modificados: `.flutter-plugins-dependencies`, `lib/app/home_page.dart`, telas de alunos/turmas, `pubspec.yaml`.
  - Nao rastreados: `lib/core/logo/`, cache/service de eventos, telas/widgets/admin de sistema.
- Nenhuma dessas alteracoes locais foi alterada por este planejamento.

## Estrutura encontrada

### Flutter - Estudos e Fundamentos

`lib/modules/estudos_fundamentos/models/`

- `estudos_config_model.dart`
- `estudo_ciclo_model.dart`
- `estudo_model.dart`
- `gabarito_estudo_model.dart`
- `pergunta_estudo_model.dart`
- `progresso_estudo_model.dart`

`lib/modules/estudos_fundamentos/repositories/`

- `estudos_ciclos_repository.dart`
- `estudos_repository.dart`
- `gabaritos_estudos_repository.dart`
- `perguntas_estudos_repository.dart`
- `progresso_estudos_repository.dart`

`lib/modules/estudos_fundamentos/screens/`

- `ciclo_estudos_screen.dart`
- `detalhe_estudo_screen.dart`
- `estudos_home_screen.dart`
- `meu_progresso_estudos_screen.dart`

`lib/modules/estudos_fundamentos/admin/`

- `detalhe_admin_estudo_screen.dart`
- `gerenciar_ciclos_estudos_screen.dart`
- `gerenciar_estudos_fundamentos_screen.dart`
- `gerenciar_estudos_screen.dart`
- `gerenciar_gabarito_pergunta_screen.dart`
- `gerenciar_perguntas_estudo_screen.dart`
- `preview_estudo_screen.dart`

### Colecoes ja usadas pelo modulo

- `estudos`
- `estudos_perguntas`
- `estudos_gabaritos`
- `alunos_estudos_progresso/{alunoId}/estudos/{estudoId}`

### Modelos e decisoes ja existentes

- `EstudoModel` possui `cicloId`, `status`, `mostrarNaLinhaDoTempo`, `mostrarComoEmBreve`, ordem e metadados.
- `EstudoCicloStatus` usa `rascunho`, `publicado`, `em_breve`, `oculto`, `arquivado`.
- `PerguntaEstudoModel` usa `tipo`, `alternativasPublicas`, `status`, `podeAparecerEmAvaliacao`, `peso`, `ordem`, `tags`.
- Tipos atuais de pergunta: `multipla_escolha` e `verdadeiro_falso`.
- `PerguntaEstudoStatus` usa `rascunho`, `ativa`, `inativa`, `arquivada`.
- `GabaritoEstudoModel` usa o documento com id da pergunta em `estudos_gabaritos/{perguntaId}`.
- Gabarito tem `alternativaCorretaId`, `alternativasCorretasIds`, `respostaEsperadaTexto`, `justificativaCorreta`, `peso`, `ativo`.
- `ProgressoEstudosRepository` ja adotou subcolecao por aluno: `alunos_estudos_progresso/{alunoId}/estudos/{estudoId}`.

### Cloud Functions

- Linguagem: JavaScript, nao TypeScript.
- Arquivo principal: `functions/index.js`.
- `functions/package.json` define `"main": "index.js"`.
- Runtime declarado: Node `24`.
- Dependencias relevantes: `firebase-admin`, `firebase-functions`, `luxon`, `dotenv`, `axios`, `@google/generative-ai`.
- Admin SDK inicializado no topo com `admin.initializeApp()`.
- Firestore Admin SDK exposto como `const db = admin.firestore()`.
- Functions usam Firebase Functions v2:
  - `const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');`
  - `const { onSchedule } = require('firebase-functions/v2/scheduler');`
  - `const { onDocumentWritten } = require('firebase-functions/v2/firestore');`
- Padrao callable encontrado:
  - `exports.nomeDaFunction = onCall(async (request) => { ... })`
  - valida auth com `if (!request.auth)` ou `if (!request.auth?.uid)`.
  - erros oficiais com `throw new HttpsError('unauthenticated' | 'permission-denied' | 'invalid-argument' | 'not-found' | 'internal', 'mensagem')`.
- Padrao admin encontrado:
  - busca `usuarios/{uid}`;
  - valida `status`/`ativo`, `tipo`, `pesoPermissao`;
  - aceita perfis como `admin`, `administrador`, `super_admin`, `superadmin` conforme contexto.
- Functions existentes identificadas por export incluem, entre outras:
  - `testarNotificacaoAniversario`
  - `processarChamada`
  - `excluirChamada`
  - `registrarLocalizacaoAcesso`
  - `chatAssistente`
  - `validarAcessoAreaAluno`
  - `buscarAlunosVinculadosAoGoogle`
  - `resolverDestinoInicialUsuario`
  - `registrarEventoGoogleAreaAluno`
  - `vincularGoogleAreaAluno`
  - `validarAcessoGoogleAreaAluno`
  - `resetarVinculoGoogleAreaAluno`
  - `resetarVinculosGoogleAreaAlunoEmMassa`
  - `criarSolicitacaoAlteracaoAreaAluno`
  - `notifyNewAppVersion`
  - funcoes de saude Firebase
  - funcoes de cache de eventos/turmas

## Arquitetura proposta

### Cloud Function principal

Criar `finalizarTentativaEstudo` como callable v2 em `functions/index.js`, seguindo o estilo atual do arquivo:

```js
exports.finalizarTentativaEstudo = onCall(async (request) => {
  // validar auth
  // validar payload
  // validar vinculo aluno/google uid
  // buscar estudo/perguntas/gabaritos
  // corrigir no servidor
  // gravar tentativa oficial e resultado resumido em transacao/batch
  // retornar resumo seguro
});
```

### Entrada proposta

```json
{
  "alunoId": "alunoDocId",
  "estudoId": "estudoDocId",
  "respostas": [
    {
      "perguntaId": "perguntaDocId",
      "alternativaId": "a"
    }
  ],
  "startedAtClient": "opcional",
  "idempotencyKey": "opcional-recomendado"
}
```

Observacoes:

- `alunoId`, `estudoId` e `respostas` devem ser obrigatorios.
- `idempotencyKey` e recomendado para reduzir tentativas duplicadas por retry/replay.
- O Flutter pode enviar `startedAtClient` apenas como metadado informativo. Datas oficiais devem ser `serverTimestamp`.

### Validacoes obrigatorias

1. Exigir FirebaseAuth: `request.auth.uid`.
2. Validar payload e limites:
   - `alunoId` string nao vazia;
   - `estudoId` string nao vazia;
   - `respostas` array com tamanho razoavel;
   - cada resposta com `perguntaId` string nao vazia;
   - alternativa em campo esperado para tipos objetivos.
3. Validar que o aluno pertence ao Google uid autenticado:
   - buscar `alunos/{alunoId}`;
   - confirmar campo de vinculo Google usado pelo projeto, provavelmente `areaAlunoGoogleUid == request.auth.uid`;
   - se houver campos legados de vinculo, centralizar em helper pequeno e documentado.
4. Buscar `estudos/{estudoId}`:
   - deve existir;
   - `status == publicado`;
   - `mostrarNaLinhaDoTempo == true`;
   - nao aceitar `rascunho`, `em_breve`, `oculto` ou `arquivado`.
5. Buscar perguntas publicas em `estudos_perguntas`:
   - `estudoId == estudoId`;
   - `status == ativa`;
   - `podeAparecerEmAvaliacao == true`.
6. Validar respostas contra perguntas oficiais:
   - ignorar ou rejeitar `perguntaId` que nao pertence ao estudo; recomendacao: rejeitar com `invalid-argument`.
   - rejeitar pergunta duplicada no payload.
   - calcular `totalRespondidas` apenas para perguntas oficiais.
7. Buscar gabaritos privados em `estudos_gabaritos/{perguntaId}`:
   - todos os itens avaliaveis devem ter gabarito ativo;
   - se faltar gabarito ativo, retornar erro controlado e nao salvar nota oficial.
8. Corrigir no servidor:
   - `multipla_escolha`: comparar alternativa enviada com `alternativaCorretaId` ou conjunto em `alternativasCorretasIds`.
   - `verdadeiro_falso`: tratar como alternativa objetiva se as alternativas publicas seguirem ids fixos.
   - para multiplas corretas, comparar conjuntos normalizados quando o payload passar array.
9. Calcular:
   - `totalQuestoes`;
   - `totalRespondidas`;
   - `acertos`;
   - `pesoTotal`;
   - `pesoObtido`;
   - `percentual`;
   - `aprovado`, se houver criterio definido.
10. Persistir tentativa oficial.
11. Atualizar resultado resumido do aluno/estudo.
12. Retornar apenas resumo seguro, sem gabarito completo e sem justificativas corretas.

### Saida segura proposta

```json
{
  "success": true,
  "tentativaId": "id",
  "alunoId": "alunoDocId",
  "estudoId": "estudoDocId",
  "cicloId": "cicloDocId",
  "totalQuestoes": 5,
  "totalRespondidas": 5,
  "acertos": 4,
  "percentual": 80,
  "aprovado": true,
  "status": "finalizada"
}
```

Nao retornar:

- `alternativaCorretaId`;
- `alternativasCorretasIds`;
- `respostaEsperadaTexto`;
- `justificativaCorreta`;
- lista completa de correcao por pergunta, salvo decisao futura de devolver apenas `correta: true/false` sem revelar qual seria a correta.

## Colecoes e schemas propostos

### Tentativas oficiais

Recomendacao: colecao raiz `estudos_tentativas/{tentativaId}`.

Motivo:

- facilita auditoria/admin cross-aluno;
- facilita query por `alunoId`, `estudoId`, `cicloId`, `finalizedAt`;
- evita duplicar subcolecoes profundas para telas administrativas;
- fica protegida por rules, com escrita apenas via Admin SDK.

Documento:

```json
{
  "alunoId": "alunoDocId",
  "googleUid": "firebaseAuthUid",
  "estudoId": "estudoDocId",
  "cicloId": "cicloDocId",
  "respostas": [
    {
      "perguntaId": "perguntaDocId",
      "tipo": "multipla_escolha",
      "alternativaId": "a",
      "alternativasIds": [],
      "respondida": true,
      "correta": true,
      "peso": 1,
      "pontosObtidos": 1
    }
  ],
  "totalQuestoes": 5,
  "totalRespondidas": 5,
  "acertos": 4,
  "pesoTotal": 5,
  "pesoObtido": 4,
  "percentual": 80,
  "aprovado": true,
  "status": "finalizada",
  "startedAt": "serverTimestamp ou timestamp aprovado",
  "finalizedAt": "serverTimestamp",
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp",
  "origem": "area_aluno",
  "versaoAvaliacao": 1,
  "idempotencyKey": "opcional",
  "functionVersion": "fase_2b_v1"
}
```

Observacao de seguranca:

- Mesmo em tentativa segura, evitar armazenar resposta correta textual ou alternativa correta. Guardar `correta`, `peso` e `pontosObtidos` e suficiente para historico.

### Resultado resumido

Recomendacao: `alunos_estudos_resultados/{alunoId}/estudos/{estudoId}`.

Motivo:

- segue o padrao ja existente de progresso: `alunos_estudos_progresso/{alunoId}/estudos/{estudoId}`;
- simplifica leitura do proprio aluno;
- facilita rules por `{alunoId}`;
- mantem um documento pequeno e direto para a tela de resultado/progresso.

Documento:

```json
{
  "alunoId": "alunoDocId",
  "googleUid": "firebaseAuthUid",
  "estudoId": "estudoDocId",
  "cicloId": "cicloDocId",
  "melhorPercentual": 80,
  "ultimoPercentual": 80,
  "ultimaTentativaId": "tentativaDocId",
  "tentativasCount": 2,
  "aprovado": true,
  "concluidoEm": "serverTimestamp quando aprovado/concluido",
  "primeiraTentativaEm": "serverTimestamp",
  "ultimaTentativaEm": "serverTimestamp",
  "updatedAt": "serverTimestamp",
  "origem": "area_aluno",
  "versaoAvaliacao": 1
}
```

### Alternativa considerada

`alunos_estudos_resultados/{alunoId}_{estudoId}` em colecao raiz tambem funcionaria, mas perde a simetria com progresso e deixa rules de leitura por aluno menos naturais. Para admin, a colecao raiz de tentativas ja cobre auditoria ampla; resultados podem ganhar collection group query em `estudos` se necessario.

## Regras futuras necessarias

Nao alterar rules nesta fase. Para a fase futura, o desenho recomendado e:

- `estudos_tentativas/{tentativaId}`:
  - aluno autenticado pode ler somente se `resource.data.googleUid == request.auth.uid` e/ou se `resource.data.alunoId` estiver vinculado ao uid autenticado;
  - aluno nao pode criar, atualizar ou apagar;
  - admin pode ler tudo;
  - escrita oficial feita apenas por Cloud Function/Admin SDK, que bypassa Firestore Rules.
- `alunos_estudos_resultados/{alunoId}/estudos/{estudoId}`:
  - aluno autenticado pode ler apenas o proprio resultado;
  - aluno nao pode escrever `acertos`, `percentual`, `aprovado`, `melhorPercentual`, `tentativasCount` ou `ultimaTentativaId`;
  - admin pode ler tudo;
  - escrita oficial feita apenas por Cloud Function/Admin SDK.
- Manter `estudos_gabaritos` sem leitura para aluno.
- Se houver necessidade de listar resultados por admin via collection group, incluir regra especifica para administradores.

## Riscos e decisoes

- Tentativas duplicadas:
  - usar `idempotencyKey` opcional na Fase 2B;
  - criar indice logico por `googleUid + alunoId + estudoId + idempotencyKey`;
  - se nao houver key, aceitar nova tentativa conforme politica.
- Replay/reenvio:
  - limitar payload;
  - registrar `createdAt/finalizedAt`;
  - considerar janela minima entre tentativas ou limite por estudo.
- Aluno enviar resposta de pergunta que nao pertence ao estudo:
  - rejeitar com `invalid-argument`; nao corrigir parcialmente.
- Pergunta duplicada no payload:
  - rejeitar com `invalid-argument`.
- Pergunta sem gabarito ativo:
  - bloquear finalizacao com erro controlado;
  - registrar log server-side para admin corrigir cadastro.
- Estudo em `rascunho`, `em_breve`, `oculto` ou `arquivado`:
  - nao permitir finalizacao.
- Limite de tentativas:
  - decisao pendente. Schema suporta `tentativasCount`; falta regra de negocio.
- Versao do gabarito:
  - `versaoAvaliacao` deve iniciar em `1`;
  - ideal futuro: salvar `gabaritoAtualizadoEmSnapshot` ou `avaliacaoVersion` por estudo/pergunta.
- Perguntas discursivas:
  - modelo tem `respostaEsperadaTexto`, mas tipos publicos atuais nao incluem discursiva;
  - Fase 2B deve rejeitar tipo nao objetivo ou marcar como nao suportado.
- Multipla escolha com mais de uma correta:
  - modelo suporta `alternativasCorretasIds`;
  - payload deve suportar `alternativasIds`;
  - comparacao deve ser por conjunto normalizado.
- Privacidade do gabarito:
  - tentativa pode armazenar `correta: true/false`, mas nao deve armazenar resposta correta.
- Consistencia:
  - gravar tentativa e resultado em batch ou transaction;
  - se resultado precisar comparar `melhorPercentual`, usar transaction.
- Criterio de aprovacao:
  - pendente. Recomendacao inicial: parametro configuravel por estudo/config, fallback 70%.

## Plano de implementacao

### Fase 2B - Cloud Function base

- Adicionar `finalizarTentativaEstudo` em `functions/index.js`.
- Criar helpers locais pequenos para:
  - auth obrigatoria;
  - normalizacao de strings/arrays;
  - validacao de vinculo aluno/Google uid;
  - correcao objetiva.
- Ler `alunos`, `estudos`, `estudos_perguntas`, `estudos_gabaritos`.
- Corrigir no servidor.
- Persistir `estudos_tentativas`.
- Persistir `alunos_estudos_resultados/{alunoId}/estudos/{estudoId}`.
- Retornar resumo seguro.
- Nao fazer deploy nesta fase sem autorizacao explicita posterior.

### Fase 2C - Flutter aluno responder

- Criar tela/fluxo de avaliacao do estudo.
- Buscar apenas perguntas publicas ativas.
- Enviar respostas para callable `finalizarTentativaEstudo`.
- Nao implementar correcao local.
- Tratar erros de cadastro/gabarito indisponivel com mensagem segura.

### Fase 2D - Resultado do aluno

- Ler `alunos_estudos_resultados/{alunoId}/estudos/{estudoId}`.
- Exibir resumo: percentual, acertos, total, aprovado, tentativas.
- Opcional: listar tentativas do proprio aluno sem gabarito.

### Fase 2E - Admin resultados

- Tela admin para consultar tentativas/resultados por aluno, estudo e ciclo.
- Indicadores agregados por estudo.
- Filtros por aprovado, percentual, periodo e aluno.
- Sem expor gabarito alem do que ja existe nas telas admin de gabarito.

### Fase 2F - Polish/testes

- Testes unitarios de helpers de correcao em Functions, se o projeto aceitar suite local.
- Casos manuais/emulador:
  - auth ausente;
  - aluno nao vinculado;
  - estudo rascunho;
  - pergunta sem gabarito;
  - resposta duplicada;
  - multipla correta;
  - tentativa repetida.
- Revisar indices Firestore necessarios.
- Revisar rules futuras.

## Comandos seguros executados

- `git status --short`
- `git log --oneline -8`
- leitura de diretorios em `lib/modules/estudos_fundamentos/*`
- leitura de `functions/package.json`
- leitura/inspecao de trechos e padroes em `functions/index.js`
- leitura de modelos/repositories de estudos

## Comandos recomendados para fase futura

O `functions/package.json` nao declara `lint` nem `test`. Scripts disponiveis:

- `npm run serve`
- `npm run shell`
- `npm run start`
- `npm run logs`

Para Fase 2B, recomendacao minima antes de deploy futuro:

- `node --check functions/index.js`
- emulador/callable local via `npm run serve`, se o ambiente permitir.

## Confirmacoes desta fase

- Nenhum deploy foi executado.
- Producao nao foi alterada.
- Flutter nao foi alterado.
- Rules nao foram alteradas.
- APK nao foi gerado.
- `git add` nao foi executado.
- `git commit` nao foi executado.
