# Fase 2C1 - Cloud Function buscarPerguntasEstudo

## Objetivo

Implementar a callable `buscarPerguntasEstudo` para entregar ao Flutter somente perguntas publicas e sanitizadas de um estudo publicado. O aluno nao le `estudos_perguntas` diretamente pelo Firestore; a funcao valida o vinculo `alunoId` + `request.auth.uid` no servidor e monta um DTO seguro por whitelist.

## Entrada esperada

```json
{
  "alunoId": "string",
  "estudoId": "string"
}
```

## Validacoes

- Exige `request.auth.uid`.
- Exige `alunoId` e `estudoId` como strings nao vazias.
- Busca `alunos/{alunoId}` e retorna `not-found` se nao existir.
- Confirma `areaAlunoGoogleUid == request.auth.uid` e `areaAlunoGoogleVinculado == true`.
- Busca `estudos/{estudoId}` e retorna `not-found` se nao existir.
- Exige `status == "publicado"` no estudo.
- Busca `estudos_perguntas` por `estudoId`.
- Considera apenas perguntas com `status == "publicado"` ou `status == "ativa"`.
- Ignora perguntas com `podeAparecerEmAvaliacao == false`.
- Ordena por `ordem` e usa `perguntaId` como fallback estavel.

Quando o estudo publicado nao tiver perguntas validas para avaliacao, a funcao retorna sucesso com lista vazia. A tela Flutter deve tratar esse estado como ausencia de perguntas disponiveis, sem considerar erro de seguranca.

## Retorno seguro

```json
{
  "success": true,
  "alunoId": "string",
  "estudoId": "string",
  "cicloId": "string",
  "totalPerguntas": 0,
  "perguntas": [
    {
      "perguntaId": "string",
      "estudoId": "string",
      "cicloId": "string",
      "enunciado": "string",
      "tipo": "multipla_escolha",
      "alternativasPublicas": [
        {
          "id": "a",
          "texto": "Alternativa",
          "ordem": 1
        }
      ],
      "dificuldade": "facil",
      "peso": 1,
      "ordem": 1,
      "tags": []
    }
  ]
}
```

Os tipos atuais esperados pelo Flutter e pela `finalizarTentativaEstudo` sao:

- `multipla_escolha`
- `verdadeiro_falso`

Para esses tipos, a tela futura deve enviar `perguntaId` e `alternativaSelecionadaId` para `finalizarTentativaEstudo`.

## Sanitizacao

A funcao nao copia o documento bruto de `estudos_perguntas`. Ela monta uma DTO por whitelist.

Campos permitidos na pergunta:

- `perguntaId`
- `estudoId`
- `cicloId`
- `enunciado`
- `tipo`
- `alternativasPublicas`
- `dificuldade`
- `peso`
- `ordem`
- `tags`
- `obrigatoria`, se existir
- `podeAparecerEmAvaliacao`, se existir

Campos permitidos em `alternativasPublicas`:

- `id`
- `texto`
- `label`
- `letra`
- `ordem`
- `valor`

Campos sensiveis nunca retornados, nem na raiz nem dentro de alternativas ou objetos aninhados:

- `respostaCorreta`
- `alternativaCorretaId`
- `alternativasCorretasIds`
- `correta`
- `isCorrect`
- `feedbackCorreto`
- `justificativaCorreta`
- `respostaEsperadaTexto`
- `nota`
- `aprovado`
- `certificado`
- `emblema`
- `badge`
- `score`
- `gabarito`
- `answer`
- `correctAnswer`
- `correct`
- `solution`

A funcao tambem nao le `estudos_gabaritos`.

## Por que nao usar leitura direta em estudos_perguntas

A Fase 2C0 decidiu nao liberar `estudos_perguntas` diretamente para aluno via Firestore Rules. O motivo e que regras de leitura direta precisam avaliar vinculo do aluno e sanitizar dados em documentos que podem ter campos sensiveis, inclusive gabarito embutido em alternativas. Como o Admin SDK ignora Rules, a sanitizacao precisa ser explicita na Cloud Function antes de retornar dados ao cliente.

## Como o Flutter devera usar

1. O aluno autenticado chama `buscarPerguntasEstudo` com `alunoId` e `estudoId`.
2. A tela renderiza somente os campos retornados no DTO seguro.
3. Ao finalizar, a tela chama `finalizarTentativaEstudo` enviando `alunoId`, `estudoId`, `clientAttemptId` e respostas.
4. O Flutter nunca calcula nota nem acessa gabarito.

## Limitacoes MVP

- Nao ha paginacao; a funcao retorna todas as perguntas validas do estudo.
- Lista vazia e retornada como sucesso quando nao ha perguntas validas.
- A sanitizacao usa whitelist fixa; novos campos publicos futuros precisam ser adicionados conscientemente.
- A funcao nao valida limite de tentativas; isso permanece na `finalizarTentativaEstudo`/fase futura.

## Confirmacao

Nenhum firebase deploy foi executado.
Producao nao foi alterada.
Flutter nao foi alterado.
Rules nao foram alteradas.
