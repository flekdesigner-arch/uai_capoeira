# Estudos e Fundamentos - Fase 2C0 - Rules para resultados e rota de perguntas

## Decisao de rota

A leitura direta de `estudos_perguntas` pelo aluno NAO sera liberada nesta fase.

Motivos:

- exigir apenas usuario autenticado nao garante vinculo com um `alunoId` especifico;
- documentos de pergunta podem carregar gabarito embutido em `alternativasPublicas`, como `correta` ou `isCorrect`, e Rules nao conseguem sanitizar campos aninhados antes de retornar o documento;
- a tela de respostas deve receber perguntas por uma Cloud Function futura, por exemplo `buscarPerguntasEstudo` ou `listarPerguntasEstudo`, validando `alunoId + request.auth.uid` e retornando somente dados sanitizados.

## Rules mantidas/alteradas

Arquivos mantidos em paralelo e identicos:

- `firebase_rules_test/firestore.rules`
- `firebase_rules_backup/firestore_mesclado_com_estudos_fundamentos.rules`

### `estudos_perguntas/{perguntaId}`

- Admin/gestor autorizado pode ler e gerenciar.
- Aluno/client comum nao le diretamente.
- A futura tela do aluno deve usar Cloud Function sanitizada.

### `estudos_gabaritos/{perguntaId}`

- Continua privado para aluno.
- Admin/gestor autorizado pode acessar.

### `alunos_estudos_resultados/{alunoId}/estudos/{estudoId}`

- Aluno Google vinculado ao `alunoId` pode ler o proprio resultado resumido.
- Outro aluno nao pode ler.
- Admin/gestor autorizado pode ler.
- Client nao pode criar, atualizar nem deletar resultado oficial.
- Escrita oficial continua via Cloud Function/Admin SDK, bypassando Rules.

### `estudos_tentativas/{tentativaId}`

- Admin/gestor autorizado pode ler.
- Aluno nao le historico completo de tentativas nesta fase.
- Client nao pode escrever tentativa.
- Escrita oficial continua via Cloud Function/Admin SDK.

## Testes atualizados

`firebase_rules_test/functional_tests/estudos_rules_test.js` cobre:

- aluno nao consegue `getDoc` em `estudos_perguntas`;
- aluno nao consegue listar `estudos_perguntas` por query, mesmo com `estudoId` e `status`;
- aluno nao consegue listar `estudos_perguntas` sem filtro de `status`;
- admin consegue ler `estudos_perguntas`;
- aluno nao consegue ler `estudos_gabaritos`;
- aluno consegue ler proprio resultado resumido;
- outro aluno nao consegue ler resultado alheio;
- aluno nao consegue escrever resultado oficial;
- admin consegue ler `estudos_tentativas`;
- aluno nao consegue ler `estudos_tentativas`;
- aluno nao consegue escrever `estudos_tentativas`.

## Proxima fase recomendada

Implementar Cloud Function `buscarPerguntasEstudo` ou `listarPerguntasEstudo` para:

- exigir FirebaseAuth;
- receber `alunoId` e `estudoId`;
- validar vinculo `alunos/{alunoId}.areaAlunoGoogleUid == request.auth.uid`;
- validar estudo publicado;
- buscar perguntas ativas/publicadas no Admin SDK;
- remover qualquer campo sensivel no topo e dentro de `alternativasPublicas`;
- retornar somente payload seguro para a tela de resposta.

## Validacoes locais

```powershell
powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1
cmd /c fc firebase_rules_test\firestore.rules firebase_rules_backup\firestore_mesclado_com_estudos_fundamentos.rules
```

## Confirmacoes

- Nenhum deploy foi executado.
- Producao nao foi alterada.
- Flutter/Dart nao foi alterado por esta fase.
- `functions/index.js` nao foi alterado por esta fase.
- `firebase.json` principal nao foi alterado.
- `firestore.rules` na raiz nao foi criado.