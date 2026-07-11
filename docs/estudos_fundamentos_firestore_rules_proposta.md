# Estudos e Fundamentos - Proposta de Firestore Rules

Este arquivo e uma proposta versionavel de seguranca para o modulo Estudos e Fundamentos.
Ele nao esta conectado ao `firebase.json` e nao deve ser aplicado em producao sem revisao.

## Situacao atual do projeto

- `firebase.json` existe, mas configura apenas `functions` e `hosting`.
- `.firebaserc` aponta para o projeto `uai-capoeira-52753`.
- `firestore.rules` agora existe como proposta versionada inicial, mas NAO esta conectado ao `firebase.json`.
- Nao ha `storage.rules` versionado.
- Scripts atuais fazem deploy apenas de `functions` ou `hosting`.
- O deploy de rules precisa ser manual, revisado e mesclado com as rules atuais em producao antes de qualquer uso.


## Risco de sobrescrever rules de producao

Como as rules atuais de producao nao estavam versionadas no repositorio, um deploy direto de `firestore.rules` pode bloquear colecoes antigas do app.

Fluxo recomendado antes do primeiro deploy de rules:

1. Exportar/copiar as Firestore Rules atuais do Firebase Console.
2. Mesclar as regras existentes com a proposta do modulo Estudos e Fundamentos.
3. Definir helpers reais para `isAdmin()` e `alunoPertenceAoUsuario(alunoId)`.
4. Validar localmente/em emulador quando possivel.
5. Fazer revisao manual antes de qualquer `firebase deploy --only firestore:rules`.
6. So depois liberar criacao de `estudos_gabaritos`.

## Mapeamento real de permissoes e vinculo aluno-Google

### Admin e permissoes

Arquivos analisados:

- `lib/core/permissions/permissao_service.dart`
- `lib/core/permissions/permission_catalog.dart`
- `lib/modules/usuarios/services/user_service.dart`
- `lib/modules/usuarios/admin/usuario_permissoes_screen.dart`
- `lib/modules/sistema/admin/admin_screen.dart`

Modelo real encontrado:

- A colecao administrativa e `usuarios`.
- O documento do usuario usa o `uid` do Firebase Auth como docId: `usuarios/{uid}`.
- O documento principal guarda dados como `uid`, `email`, `status_conta`, `tipo` e `peso_permissao`.
- Um usuario e tratado como admin amplo quando `peso_permissao >= 90` ou `tipo` e `admin`/`administrador`.
- Contas bloqueadas, inativas ou rejeitadas nao devem gerenciar nada.
- Permissoes granulares ficam em `usuarios/{uid}/permissoes_usuario/configuracoes` como campos booleanos.
- A permissao deste modulo e `pode_gerenciar_estudos_fundamentos`.

Proposta de helper para rules:

```js
function isAdmin() {
  return isSignedIn()
    && usuarioContaLiberada(request.auth.uid)
    && (
      usuarioAdminAmplo(request.auth.uid)
      || usuarioTemPermissaoEstudos(request.auth.uid)
    );
}
```

Observacao: esta regra autoriza admin amplo e tambem usuarios com a permissao especifica do modulo. Antes de deploy, validar se ha valores legados adicionais de `tipo` ou `status_conta` em producao.

### Vinculo aluno-Google

Arquivos analisados:

- `lib/modules/area_aluno/services/area_aluno_session_service.dart`
- `lib/modules/area_aluno/services/area_aluno_google_service.dart`
- `lib/modules/area_aluno/screens/area_aluno_dashboard_screen.dart`
- `functions/index.js`
- `lib/modules/estudos_fundamentos/screens/estudos_home_screen.dart`
- `lib/modules/estudos_fundamentos/screens/ciclo_estudos_screen.dart`
- `lib/modules/estudos_fundamentos/repositories/progresso_estudos_repository.dart`

Modelo real encontrado:

- O vinculo Google fica no documento do aluno em `alunos/{alunoId}`.
- As Cloud Functions usam `db.collection('alunos').doc(alunoId)` para validar acesso.
- A busca de alunos vinculados usa `where('areaAlunoGoogleUid', '==', request.auth.uid)`.
- O vinculo so e considerado valido quando `areaAlunoGoogleVinculado === true`.
- O app permite um mesmo Google vinculado a varios alunos porque varios documentos `alunos/{alunoId}` podem apontar para o mesmo `areaAlunoGoogleUid`.
- Na sessao da Area do Aluno, o `alunoId` e derivado de `aluno_id`, `id` ou `docId`; no fluxo Google, o payload recebe `aluno_id_login`, `aluno_id` e `alunoSelecionadoId`.
- No progresso dos estudos, a chave principal e `alunos_estudos_progresso/{alunoId}/estudos/{estudoId}`. `googleUid` e apenas metadado.

Proposta de helper para rules:

```js
function alunoPertenceAoUsuario(alunoId) {
  return isSignedIn()
    && exists(/databases/$(database)/documents/alunos/$(alunoId))
    && get(/databases/$(database)/documents/alunos/$(alunoId)).data.areaAlunoGoogleVinculado == true
    && get(/databases/$(database)/documents/alunos/$(alunoId)).data.areaAlunoGoogleUid == request.auth.uid;
}
```

Conclusao: uma colecao auxiliar como `area_aluno_google_vinculos/{uid}/alunos/{alunoId}` nao e obrigatoria para a primeira versao das rules, porque o vinculo atual pode ser validado diretamente em `alunos/{alunoId}`. Ela pode ser considerada no futuro se as rules ficarem caras, se houver necessidade de auditoria dedicada, ou se o modelo de vinculo evoluir.

### Riscos restantes

- `firestore.rules` ainda nao esta mesclado com as rules atuais de producao.
- `firebase.json` ainda nao aponta para `firestore.rules`, por decisao de seguranca.
- As rules propostas precisam ser validadas contra dados reais de `status_conta`, `tipo`, `peso_permissao` e permissoes existentes.
- Antes de criar `estudos_gabaritos`, e obrigatorio proteger a colecao privada em rules implantadas e revisar com Firebase Console/emulador.
## Checklist antes de criar gabarito

- `firestore.rules` mesclado com as rules atuais de producao.
- `firebase.json` configurado para rules somente depois da decisao de deploy.
- `isAdmin()` validando admin amplo real do app.
- `podeGerenciarEstudosFundamentos()` validando admin amplo ou `pode_gerenciar_estudos_fundamentos`.
- `alunoPertenceAoUsuario(alunoId)` validando o aluno selecionado/vinculado ao Google.
- `estudos_gabaritos` bloqueado para qualquer leitura de aluno.
- `estudos_perguntas` impedindo campos como `respostaCorreta`, `alternativaCorretaId`, `correta`, `isCorrect`, `feedbackCorreto`, `justificativaCorreta` e `score`.
- Cloud Functions planejadas para correcao oficial futura.

## Objetivos de seguranca

- Aluno pode ler somente conteudo liberado.
- Aluno nao pode ler rascunhos, ocultos, arquivados ou gabaritos.
- Aluno pode gravar apenas progresso simples de leitura do proprio aluno selecionado.
- Admin pode gerenciar configuracao, ciclos, estudos, perguntas e gabaritos.
- Correcao oficial de avaliacao deve ficar em Cloud Functions, nao no Flutter.

## Helpers propostos apos mapeamento real

As funcoes abaixo refletem o modelo real encontrado no codigo, mas continuam sendo proposta. Antes de deploy, devem ser mescladas com as rules atuais de producao e validadas contra dados reais.

```js
function isSignedIn() {
  return request.auth != null;
}

function usuarioContaLiberada(uid) {
  return exists(/databases/$(database)/documents/usuarios/$(uid))
    && !("status_conta" in get(/databases/$(database)/documents/usuarios/$(uid)).data
      && get(/databases/$(database)/documents/usuarios/$(uid)).data.status_conta in [
        "bloqueada",
        "bloqueado",
        "inativa",
        "inativo",
        "rejeitada",
        "rejeitado"
      ]);
}

function usuarioAdminAmplo(uid) {
  return exists(/databases/$(database)/documents/usuarios/$(uid))
    && (
      (("peso_permissao" in get(/databases/$(database)/documents/usuarios/$(uid)).data)
        && get(/databases/$(database)/documents/usuarios/$(uid)).data.peso_permissao >= 90)
      || get(/databases/$(database)/documents/usuarios/$(uid)).data.tipo == "admin"
      || get(/databases/$(database)/documents/usuarios/$(uid)).data.tipo == "administrador"
    );
}

function usuarioTemPermissaoEstudos(uid) {
  return exists(/databases/$(database)/documents/usuarios/$(uid)/permissoes_usuario/configuracoes)
    && get(/databases/$(database)/documents/usuarios/$(uid)/permissoes_usuario/configuracoes).data.pode_gerenciar_estudos_fundamentos == true;
}

function isAdmin() {
  return isSignedIn()
    && usuarioContaLiberada(request.auth.uid)
    && (
      usuarioAdminAmplo(request.auth.uid)
      || usuarioTemPermissaoEstudos(request.auth.uid)
    );
}

function alunoPertenceAoUsuario(alunoId) {
  return isSignedIn()
    && exists(/databases/$(database)/documents/alunos/$(alunoId))
    && get(/databases/$(database)/documents/alunos/$(alunoId)).data.areaAlunoGoogleVinculado == true
    && get(/databases/$(database)/documents/alunos/$(alunoId)).data.areaAlunoGoogleUid == request.auth.uid;
}

function estudosConfig() {
  return get(/databases/$(database)/documents/estudos_config/global).data;
}

function statusPublicadoOuEmBrevePermitido(data) {
  return data.status == "publicado" ||
    (data.status == "em_breve" && estudosConfig().mostrarEmBreve == true);
}

function conteudoVisivelAluno(data) {
  return data.mostrarNaLinhaDoTempo == true && statusPublicadoOuEmBrevePermitido(data);
}
```
## Regras conceituais

```js
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    match /estudos_config/global {
      allow read: if isSignedIn();
      allow write: if isAdmin();
    }

    match /estudos_ciclos/{cicloId} {
      allow read: if isSignedIn() && conteudoVisivelAluno(resource.data);
      allow create, update, delete: if isAdmin();
    }

    match /estudos/{estudoId} {
      allow read: if isSignedIn() && conteudoVisivelAluno(resource.data);
      allow create, update, delete: if isAdmin();
    }

    match /alunos_estudos_progresso/{alunoId}/estudos/{estudoId} {
      allow read: if isAdmin() || alunoPertenceAoUsuario(alunoId);

      allow create, update: if alunoPertenceAoUsuario(alunoId)
        && request.resource.data.alunoId == alunoId
        && request.resource.data.estudoId == estudoId
        && request.resource.data.status in ["iniciado", "concluido"]
        && request.resource.data.percentualLeitura is int
        && request.resource.data.percentualLeitura >= 0
        && request.resource.data.percentualLeitura <= 100
        && request.resource.data.keys().hasOnly([
          "alunoId",
          "googleUid",
          "estudoId",
          "cicloId",
          "status",
          "iniciadoEm",
          "concluidoEm",
          "atualizadoEm",
          "ultimaVisualizacaoEm",
          "percentualLeitura",
          "origem"
        ]);

      allow delete: if false;
    }

    match /estudos_perguntas/{perguntaId} {
      allow read: if signedIn()
        && resource.data.status == "ativa"
        && resource.data.podeAparecerEmAvaliacao == true
        && !("correta" in resource.data)
        && !("isCorrect" in resource.data)
        && !("respostaCorreta" in resource.data)
        && !("alternativaCorretaId" in resource.data)
        && !("justificativaCorreta" in resource.data)
        && !("feedbackCorreto" in resource.data)
        && !("score" in resource.data);

      allow create, update, delete: if isAdmin()
        && !("correta" in request.resource.data)
        && !("isCorrect" in request.resource.data)
        && !("respostaCorreta" in request.resource.data)
        && !("alternativaCorretaId" in request.resource.data)
        && !("justificativaCorreta" in request.resource.data)
        && !("feedbackCorreto" in request.resource.data)
        && !("score" in request.resource.data);
    }

    match /estudos_gabaritos/{perguntaId} {
      allow read, write: if isAdmin();
      // Alunos nunca leem gabaritos. Cloud Functions usa Admin SDK e ignora rules.
    }

    match /avaliacoes_tentativas/{tentativaId} {
      allow read: if isAdmin()
        || (isSignedIn() && resource.data.alunoId is string && alunoPertenceAoUsuario(resource.data.alunoId));

      // Criacao/correcao oficial deve ser feita por Cloud Functions.
      allow create, update, delete: if false;
    }
  }
}
```

## Observacoes importantes

- Firestore Rules nao conseguem proteger dados sensiveis se eles forem gravados no mesmo documento publico.
- Por isso, `estudos_perguntas` nunca deve conter resposta correta.
- `estudos_gabaritos` deve ser privado para admin/backend.
- Cloud Functions com Admin SDK nao depende das rules para ler gabaritos e corrigir tentativas.
- Antes de producao, e necessario definir a funcao real `alunoPertenceAoUsuario(alunoId)`.
- As queries do app devem continuar filtrando `status` e `mostrarNaLinhaDoTempo` para ficarem compatÃ­veis com rules restritivas.




