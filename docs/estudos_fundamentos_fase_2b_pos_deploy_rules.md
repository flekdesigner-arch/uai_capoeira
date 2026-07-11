# Auditoria pos-deploy das Firestore Rules - Estudos/Fundamentos

Data: 2026-07-11

## Status

Status: APROVADO, MAS RECOMENDA NOVO DEPLOY DE RULES.

As regras publicadas em producao funcionaram nos fluxos principais testados manualmente, incluindo login gestao, alunos, dashboard turma, chamada/lock, Area do Aluno e Estudos sem gabarito exposto. A auditoria dos logs pos-deploy encontrou dois permission-denied legitimos causados por colecoes usadas pelo app antigo que ainda nao tinham bloco explicito no candidato: `mensagens_aniversario` e `cache_alunos`.

Nenhum firebase deploy foi executado nesta auditoria. Producao nao foi alterada nesta auditoria.

## Logs analisados

### 1. Mensagens de aniversario

Log observado:

`Erro em mensagens (nao critico): [cloud_firestore/permission-denied] Missing or insufficient permissions.`

Codigo analisado:

- `lib/main.dart`
- `lib/modules/alunos/services/mensagem_aniversario_service.dart`

Colecao identificada:

- `mensagens_aniversario`

Classificacao: PRECISA RULE.

Motivo: o app consulta mensagens ativas em `mensagens_aniversario`. A rule candidata nao tinha bloco explicito para essa colecao e o fallback final fechado bloqueava a leitura. Como e conteudo textual nao sensivel e usado pelo app, foi adicionada regra explicita.

Regra candidata aplicada:

- `allow read: if true;`
- `allow write: if isSignedIn();`

### 2. Cache Firestore / aluno detalhe

Logs observados:

- `Erro ao salvar cache no Firestore: [cloud_firestore/permission-denied] Missing or insufficient permissions.`
- `Erro ao ler cache do Firestore: [cloud_firestore/unavailable] Failed to get document from cache...`

Codigo analisado:

- `lib/modules/alunos/screens/aluno_detalhe_screen.dart`
- `lib/modules/turmas/services/dashboard_turma_cache_service.dart`
- `lib/modules/turmas/screens/dashboard_turmas_page.dart`

Colecao identificada para o erro literal:

- `cache_alunos`

Classificacao: PRECISA RULE para `cache_alunos`.

Motivo: `aluno_detalhe_screen.dart` salva, le e remove documentos em `cache_alunos`. A rule candidata nao cobria essa colecao. O erro de `unavailable` ao ler cache local e secundario, mas o permission-denied ao salvar indica falta real de rule.

Regra candidata aplicada:

- `allow read, write: if isSignedIn();`

Observacao: o Cache V2 do dashboard usa `turmas/{turmaId}/dashboard_cache` e `turmas/{turmaId}/dashboard_cache_alunos`, que ja estavam cobertos e funcionaram no teste manual.

### 3. Estudos config na Area do Aluno basica

Log observado:

`Erro ao carregar config de Estudos e Fundamentos: [cloud_firestore/permission-denied] Missing or insufficient permissions.`

Codigo analisado:

- `lib/modules/estudos_fundamentos/services/estudos_config_service.dart`
- `lib/modules/area_aluno/screens/area_aluno_dashboard_screen.dart`

Colecao/documento:

- `estudos_config/global`

Classificacao: ESPERADO E SEGURO.

Motivo: a rule de `estudos_config/global` permite leitura apenas para usuario autenticado. No fluxo basico da Area do Aluno sem Google/FirebaseAuth validado, o bloqueio e esperado. O app deve esconder o card de Estudos nesse estado. Nao foi alterada rule para tornar essa config publica, pois isso enfraqueceria a decisao de seguranca do modulo Estudos.

### 4. Cloud Function unauthenticated

Log observado:

`[firebase_functions/unauthenticated] Entre com uma conta Google para continuar.`

Codigo relacionado:

- `lib/modules/area_aluno/services/area_aluno_google_service.dart`
- `lib/modules/area_aluno/services/area_aluno_session_service.dart`
- `lib/modules/area_aluno/screens/area_aluno_dashboard_screen.dart`

Classificacao: ESPERADO E SEGURO.

Motivo: funcoes Google da Area do Aluno dependem de usuario autenticado. Em fluxo basico sem Google, a resposta unauthenticated e compatível com a protecao esperada. Nao requer ajuste de Firestore Rules.

## Alteracoes feitas nas rules candidatas

Arquivos alterados:

- `firebase_rules_test/firestore.rules`
- `firebase_rules_backup/firestore_mesclado_com_estudos_fundamentos.rules`

Blocos adicionados:

```rules
match /mensagens_aniversario/{document} {
  allow read: if true;
  allow write: if isSignedIn();
}

match /cache_alunos/{document} {
  allow read, write: if isSignedIn();
}
```

## Seguranca de Estudos preservada

Confirmado:

- `estudos_gabaritos` continua protegido contra aluno.
- `estudos_perguntas` continua bloqueando campos sensiveis de gabarito/resultado.
- `alunos_estudos_progresso` continua bloqueando `nota`, `aprovado`, `certificado`, `score` e campos oficiais equivalentes.
- Rascunho/oculto/arquivado continua fora da leitura do aluno.
- Fallback final continua fechado: `allow read, write: if false`.

## Testes rodados

- `cmd /c fc firebase_rules_test\firestore.rules firebase_rules_backup\firestore_mesclado_com_estudos_fundamentos.rules`
  - Resultado: arquivos iguais.
- `powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1`
  - Resultado: todos os testes funcionais basicos e extras passaram.
  - Os `PERMISSION_DENIED` no log do emulador sao os cenarios negativos esperados dos testes.

## Recomendacao

Recomenda novo deploy manual de Firestore Rules contendo apenas estes ajustes candidatos, apos revisar o diff e manter fora do pacote quaisquer alteracoes Flutter/Dart paralelas.

Apos esse deploy manual futuro, retestar:

- carregamento de mensagens de aniversario;
- leitura/escrita/remocao de cache em `cache_alunos` no detalhe do aluno;
- Estudos na Area do Aluno basica sem Google, que deve continuar escondido/bloqueado;
- Estudos na Area do Aluno com Google validado.

## Confirmacao

Nenhum firebase deploy foi executado.

Producao nao foi alterada nesta auditoria.
## Correcao do review P1 - cache_alunos

Data: 2026-07-11

O review apontou que `cache_alunos` estava amplo demais com `allow read, write: if isSignedIn();`.

### Uso inspecionado

Arquivo analisado:

- `lib/modules/alunos/screens/aluno_detalhe_screen.dart`

Uso encontrado:

- `saveToCache(key, data)` grava em `cache_alunos/{key}` com campos `dados`, `timestamp` e `valido_ate`.
- `loadFromCache(key)` le `cache_alunos/{key}`.
- `invalidateCache(key)` apaga `cache_alunos/{key}`.
- As chaves nao sao sempre o alunoId puro. Foram encontrados formatos como `aluno_$alunoId`, `permissoes_$userId`, `isAdmin_$userId`, `frequencia_${alunoId}_...`, `eventos_$alunoId` e `svg_$graduacaoId`.
- O documento nao tem um campo top-level `alunoId` confiavel; os dados ficam encapsulados em `dados` e variam por tipo de cache.

### Decisao de seguranca

Como nao ha docId igual ao alunoId nem campo top-level confiavel para validar vinculo com `alunoPertenceAoUsuario(alunoId)`, foi aplicada a opcao segura: restringir `cache_alunos` somente a admin.

Regra atualizada nas candidatas:

```rules
match /cache_alunos/{document} {
  allow read, create, update, delete: if isAdmin();
}
```

Isso remove o acesso global para qualquer usuario autenticado e evita leitura/adulteracao de cache de outros alunos.

### Risco restante

Precisa teste manual no detalhe do aluno apos futuro deploy das rules, especialmente com usuario professor/gestor que nao seja admin. O impacto esperado, se houver bloqueio, deve ser limitado a persistencia do cache Firestore; a tela ainda pode buscar dados diretamente das colecoes principais conforme suas permissoes. Se for necessario liberar cache para gestores nao-admin no futuro, o app deve gravar um campo top-level confiavel (`alunoId`, `ownerUid` ou escopo equivalente) ou separar caches por subcolecao/usuario para permitir regra segura.

### Validacao

- `cmd /c fc firebase_rules_test\firestore.rules firebase_rules_backup\firestore_mesclado_com_estudos_fundamentos.rules`: arquivos iguais.
- `powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1`: todos os testes funcionais basicos e extras passaram.

Nenhum firebase deploy foi executado.

Producao nao foi alterada.

Flutter nao foi alterado.
