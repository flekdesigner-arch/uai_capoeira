# Estudos e Fundamentos - Fase 2B - Cloud Function de Tentativa

## Funcao criada

Foi criada a callable Cloud Function `finalizarTentativaEstudo` em `functions/index.js`.

A funcao faz a correcao oficial no servidor usando Firebase Admin SDK, lendo gabaritos privados em `estudos_gabaritos/{perguntaId}` e gravando resultado oficial em colecoes protegidas.

Nao ha correcao no Flutter nesta fase.

## Entrada esperada

```json
{
  "alunoId": "string",
  "estudoId": "string",
  "clientAttemptId": "string-curta-segura",
  "respostas": [
    {
      "perguntaId": "string",
      "tipo": "string opcional",
      "alternativaSelecionadaId": "string opcional",
      "alternativasSelecionadasIds": ["string opcional"],
      "respostaTexto": "string opcional"
    }
  ]
}
```

`clientAttemptId` e obrigatorio no MVP. Ele precisa ser curto, sem barra e composto por letras, numeros, ponto, underscore ou hifen. O id da tentativa e deterministico:

```text
estudos_tentativas/{alunoId}_{estudoId}_{clientAttemptId}
```

## Validacoes implementadas

- Exige `request.auth.uid`.
- Exige `alunoId`, `estudoId`, `clientAttemptId` e `respostas` nao vazio.
- Busca `alunos/{alunoId}`.
- Valida `aluno.areaAlunoGoogleUid == request.auth.uid`.
- Valida `aluno.areaAlunoGoogleVinculado == true`.
- Somente depois de validar vinculo, estudo publicado, perguntas validas, pertencimento e formato das respostas do payload verifica tentativa idempotente existente.
- Em todos os retornos idempotentes, inclusive no caminho pos-transacao, confere se a tentativa salva tem `alunoId`, `estudoId` e `googleUid` iguais ao payload autenticado.
- Busca `estudos/{estudoId}`.
- Exige `estudo.status == "publicado"`.
- Busca perguntas em `estudos_perguntas` pelo `estudoId`.
- Considera avaliaveis perguntas com `podeAparecerEmAvaliacao != false` e status `publicado` ou `ativa`.
- Rejeita resposta para pergunta fora do estudo antes de qualquer retorno idempotente.
- Rejeita pergunta duplicada no payload antes de qualquer retorno idempotente.`n- Rejeita resposta malformada antes de qualquer retorno idempotente, mesmo em replay com `clientAttemptId` ja existente.
- Busca gabaritos em `estudos_gabaritos/{perguntaId}`.
- Para pergunta objetiva, exige gabarito ativo.
- Nunca retorna `alternativaCorretaId`, `alternativasCorretasIds`, `respostaEsperadaTexto` ou `justificativaCorreta`.

Observacao: o modelo Flutter atual usa `status == "ativa"` para perguntas. A funcao tambem aceita `publicado` para compatibilidade com a especificacao da Fase 2B.

## Tipos e formato das respostas

Tipos identificados no modelo atual `PerguntaEstudoTipo`:

- `multipla_escolha`
- `verdadeiro_falso`

A validacao basica de formato acontece depois de carregar as perguntas validas do estudo e antes de qualquer retorno idempotente:

- `multipla_escolha`: no MVP atual e alternativa unica. Exige exclusivamente `alternativaSelecionadaId` string nao vazia; rejeita `alternativasSelecionadasIds` se o campo estiver presente, mesmo vazio ou nulo.
- `verdadeiro_falso`: no MVP atual e alternativa unica. Exige exclusivamente `alternativaSelecionadaId` string nao vazia; rejeita `alternativasSelecionadasIds` se o campo estiver presente, mesmo vazio ou nulo.
- tipos futuros explicitamente multiplos (`multipla_selecao`, `multiplas_respostas`, `checkbox`, `multipla_escolha_multipla`): exigem `alternativasSelecionadasIds` array nao vazio de strings nao vazias, sem duplicadas, e nao aceitam `alternativaSelecionadaId`.
- tipos discursivos/texto futuros (`discursiva`, `texto`, `resposta_texto`, `dissertativa`, `aberta`): exigem `respostaTexto` string nao vazia e seguem como pendencia manual.
- tipos desconhecidos sao rejeitados com `invalid-argument` antes de qualquer caminho idempotente.

Assim, respostas duplicadas, pergunta fora do estudo e respostas malformadas sao rejeitadas mesmo quando `clientAttemptId` corresponde a uma tentativa ja existente.

## Correcao MVP

- `multipla_escolha` e `verdadeiro_falso`: compara `resposta.alternativaSelecionadaId` com a alternativa correta unica resolvida no servidor.
- Prioridade da alternativa correta unica: `gabarito.alternativaCorretaId` e a fonte principal. Se estiver vazio, `gabarito.alternativasCorretasIds` so e usado como fallback quando tiver exatamente 1 item.
- Multiplas alternativas: somente para tipo futuro explicitamente multiplo, compara o conjunto enviado em `resposta.alternativasSelecionadasIds` com `gabarito.alternativasCorretasIds`.
- Discursiva/texto: nao corrige automaticamente, marca `pendenteManual: true`, nao conta como acerto e muda status para `pendente_correcao`.

Tipos tratados como discursivos no MVP:

- `discursiva`
- `texto`
- `resposta_texto`
- `dissertativa`
- `aberta`

## Calculo MVP

- `totalQuestoes`: quantidade de perguntas avaliaveis.
- `totalObjetivas`: perguntas corrigidas automaticamente.
- `totalDiscursivas`: perguntas pendentes de correcao manual.
- `totalRespondidas`: respostas validas recebidas para perguntas do estudo.
- `acertos`: acertos objetivos.
- `percentual`: inteiro arredondado por `acertos / totalObjetivas * 100`, ou `0` se nao houver objetiva.
- `aprovado`: `percentual >= 70` e sem pendencia manual.
- `status`: `finalizada` sem pendencia manual, `pendente_correcao` com pendencia manual.

## Saida segura

```json
{
  "success": true,
  "tentativaId": "string",
  "estudoId": "string",
  "cicloId": "string",
  "totalQuestoes": 5,
  "totalObjetivas": 4,
  "totalDiscursivas": 1,
  "totalRespondidas": 5,
  "acertos": 3,
  "percentual": 75,
  "aprovado": false,
  "status": "pendente_correcao",
  "possuiPendenciaManual": true,
  "criterioAprovacaoPercentual": 70,
  "idempotente": false
}
```

Quando a mesma tentativa e reenviada com o mesmo `clientAttemptId`, a funcao retorna o resumo salvo com `idempotente: true` e nao incrementa `tentativasCount` novamente.

## Colecoes escritas

### `estudos_tentativas/{tentativaId}`

Campos gravados:

- `tentativaId`
- `alunoId`
- `googleUid`
- `estudoId`
- `cicloId`
- `clientAttemptId`
- `respostasResumoSeguro`
- `totalQuestoes`
- `totalObjetivas`
- `totalDiscursivas`
- `totalRespondidas`
- `acertos`
- `percentual`
- `aprovado`
- `status`
- `possuiPendenciaManual`
- `criterioAprovacaoPercentual: 70`
- `origem: "cloud_function"`
- `versaoAvaliacao: 1`
- `createdAt`
- `finalizedAt`

`respostasResumoSeguro` contem apenas:

- `perguntaId`
- `respondida`
- `correta`, apenas para objetiva
- `pendenteManual`
- `tipo`

Nao contem gabarito correto.

### `alunos_estudos_resultados/{alunoId}/estudos/{estudoId}`

Campos atualizados:

- `alunoId`
- `googleUid`
- `estudoId`
- `cicloId`
- `melhorPercentual`
- `ultimaTentativaId`
- `ultimoPercentual`
- `tentativasCount`
- `aprovado`
- `status`
- `concluidoEm`, quando aprovado e ainda inexistente
- `updatedAt`
- `origem: "cloud_function"`

## Transacao e idempotencia

A funcao valida primeiro `alunos/{alunoId}` e o vinculo com `request.auth.uid`. Em seguida valida `estudos/{estudoId}`, o status publicado, as perguntas validas do estudo e o payload de respostas. Respostas duplicadas, `perguntaId` fora do estudo e respostas malformadas por tipo de pergunta sao rejeitadas antes de qualquer retorno idempotente.

So depois dessas validacoes a funcao consulta `estudos_tentativas/{tentativaId}` para retorno idempotente. Todo retorno idempotente valida os campos salvos `alunoId`, `estudoId` e `googleUid` antes de devolver o resumo seguro. Essa protecao cobre o retorno idempotente inicial e tambem o caminho pos-transacao, evitando consulta de tentativa de outro aluno por um usuario autenticado que conheca ou adivinhe o `clientAttemptId`.

A gravacao oficial usa `db.runTransaction` e rele `estudos_tentativas/{tentativaId}` dentro da transacao antes de criar o documento e incrementar `tentativasCount`.

A transacao nao depende de variavel externa mutada pelo callback, porque callbacks de transacao Firestore podem ser reexecutados em conflito. Em vez disso, a transacao retorna explicitamente o estado final confiavel: `{ idempotente: true, tentativaData }` quando a tentativa ja existe ou `{ idempotente: false, tentativaData }` quando a tentativa foi realmente criada.

Se a tentativa ja existir dentro da transacao, a funcao valida novamente `alunoId`, `estudoId` e `googleUid`, retorna o resumo salvo e nao cria nova tentativa. `tentativasCount` so incrementa no ramo em que `transaction.create` e executado para uma tentativa nova.

## Regras de seguranca esperadas futuramente

Ainda nao foram alteradas nesta fase.

Recomendado para fase futura:

- Aluno pode ler somente tentativas/resultados vinculados ao proprio `request.auth.uid`.
- Aluno nao pode escrever tentativa, nota, acertos, percentual ou aprovado.
- Admin pode ler resultados e tentativas.
- Cloud Function/Admin SDK segue responsavel pela escrita oficial.
- `estudos_gabaritos` continua sem leitura para aluno.

## Como testar local/manualmente

Verificacao sintatica:

```bash
node --check functions/index.js
```

Teste manual recomendado via emulator/callable em fase seguinte:

1. Criar aluno com `areaAlunoGoogleUid` igual ao uid autenticado e `areaAlunoGoogleVinculado: true`.
2. Criar estudo publicado.
3. Criar perguntas avaliaveis em `estudos_perguntas`.
4. Criar gabaritos ativos em `estudos_gabaritos/{perguntaId}`.
5. Chamar `finalizarTentativaEstudo` com `clientAttemptId` unico.
6. Reenviar exatamente o mesmo payload e confirmar `idempotente: true` e contador sem incremento novo.
7. Validar que o retorno nao contem campos de gabarito.

## Limitacoes MVP

- Sem bloqueio por limite de tentativas.
- Sem correcao automatica de discursivas.
- Percentual e inteiro arredondado.
- Perguntas sem gabarito ativo ou sem alternativa correta resolvivel bloqueiam finalizacao se forem objetivas.
- Status de perguntas aceita `ativa` por compatibilidade com o modelo atual, alem de `publicado`.
- Nao houve deploy.
- Rules e Flutter ainda precisam de fases futuras.

## Confirmacao

- Nenhum firebase deploy foi executado.
- Producao nao foi alterada.
- Flutter nao foi alterado.
- Rules nao foram alteradas.
- APK nao foi gerado.
- `git add` nao foi executado.
- `git commit` nao foi executado.