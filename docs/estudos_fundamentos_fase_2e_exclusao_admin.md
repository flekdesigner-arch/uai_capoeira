# Fase 2E - Exclusao administrativa de Estudos/Fundamentos

## Objetivo

Adicionar exclusao administrativa controlada para conteudo de Estudos/Fundamentos, usando Cloud Function com Admin SDK para evitar cascata pesada no Flutter e reduzir risco de exclusao parcial.

## Function criada

`excluirConteudoEstudosFundamentos`

Entrada:

```json
{
  "tipo": "pergunta | estudo | ciclo",
  "id": "documentId",
  "confirmar": true
}
```

A Function exige usuario autenticado e valida administrador ativo em `usuarios/{uid}` com `peso_permissao >= 90` ou tipo `admin/administrador/super_admin/superadmin`.

## O que cada exclusao apaga

### Pergunta

- `estudos_perguntas/{perguntaId}`
- `estudos_gabaritos/{perguntaId}`

Tentativas historicas nao sao apagadas ao apagar somente uma pergunta, porque elas guardam resumo de uma tentativa ja finalizada.

### Estudo

- `estudos/{estudoId}`
- perguntas em `estudos_perguntas` com `estudoId == estudoId`
- gabaritos em `estudos_gabaritos/{perguntaId}` das perguntas apagadas
- tentativas em `estudos_tentativas` com `estudoId == estudoId`
- resultados em `alunos_estudos_resultados/{alunoId}/estudos/{estudoId}` quando `data.estudoId == estudoId` ou quando o proprio document ID e `estudoId`
- progresso em `alunos_estudos_progresso/{alunoId}/estudos/{estudoId}` quando `data.estudoId == estudoId` ou quando o proprio document ID e `estudoId`

### Ciclo

- `estudos_ciclos/{cicloId}`
- todos os estudos com `cicloId == cicloId`
- perguntas e gabaritos desses estudos
- perguntas orfas com `cicloId == cicloId` cujo `estudoId` nao pertence aos estudos apagados
- tentativas/resultados/progresso dos estudos apagados

## Admin Flutter

Foram adicionadas acoes perigosas com confirmacao forte digitando `APAGAR`:

- apagar pergunta no detalhe do estudo e na lista geral de perguntas;
- apagar estudo no detalhe do estudo;
- apagar ciclo na lista de ciclos.

Durante a exclusao, a tela usa o estado `_salvando` para bloquear novas acoes. Ao finalizar, mostra o resumo retornado pela Function.

## Riscos e cuidados

- A exclusao e irreversivel.
- A limpeza de resultados/progresso usa `collectionGroup('estudos')` e apaga somente documentos cujo path pertence ao prefixo esperado e cujo `data.estudoId` bate com o estudo excluido.
- Se documentos antigos de progresso/resultado nao tiverem `estudoId`, eles podem nao ser apagados automaticamente.
- A Function nao apaga tentativas ao excluir somente uma pergunta.

## Como testar com conteudo de teste

1. Criar ciclo, estudo, pergunta e gabarito de teste.
2. Responder a atividade com aluno de teste para gerar tentativa/resultado/progresso.
3. No admin, apagar uma pergunta e conferir que pergunta/gabarito somem.
4. Criar novamente dados de teste e apagar o estudo, conferindo perguntas, gabaritos, tentativas, resultado e progresso.
5. Criar novo ciclo de teste com estudo/pergunta e apagar o ciclo.
6. Conferir o resumo exibido na tela e o Firestore.

## Confirmacao

Nenhum deploy foi executado.
Nenhum APK foi gerado.
Rules nao foram alteradas.
pubspec.yaml nao foi alterado.
