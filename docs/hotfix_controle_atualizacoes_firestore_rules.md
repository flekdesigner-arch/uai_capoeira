# Hotfix - Controle de Atualizacoes Firestore Rules

## Problema

No Windows Desktop, a tela Controle de Atualizacoes falhava no passo "Salvar rascunho" com:

```text
[cloud_firestore/permission-denied] Missing or insufficient permissions.
```

A falha acontecia antes do upload do APK, portanto nao era causada por Storage Rules. O rascunho e salvo em `versoes_app/{versionId}` pelo `AppUpdateAdminService`.

## Causa

As Firestore Rules usadas no fluxo de teste/deploy nao tinham regra explicita para `versoes_app`. Como o fallback final e fechado, o create/update do rascunho era negado mesmo para usuario admin do app.

## Alteracao

Foi criado o helper:

```js
canManageControleAtualizacoes()
```

Ele permite acesso administrativo quando:

- `isAdmin()` e verdadeiro; ou
- `usuarios/{uid}/permissoes_usuario/configuracoes.pode_controle_atualizacoes == true`.

O helper usa `exists(permissoesUsuarioDoc(request.auth.uid))`, entao ausencia do documento de permissoes resulta em `false` sem quebrar a avaliacao.

## Colecoes liberadas

### versoes_app

`versoes_app/{versionId}` agora permite:

- `read` para usuario autenticado;
- `create`, `update` e `delete` para `canManageControleAtualizacoes()`.

### configuracoes/app

`configuracoes/app` agora permite:

- `read` publico, preservando comportamento anterior de `configuracoes/{document}`;
- `create` e `update` para `canManageControleAtualizacoes()`;
- `delete` bloqueado no client.

Outros documentos em `configuracoes/{document}` continuam com o comportamento legado existente.

## Nao alterado

- Storage Rules nao foram alteradas.
- Functions nao foram alteradas.
- Codigo Flutter nao foi alterado.
- `pubspec.yaml` nao foi alterado.
- Nenhum deploy foi executado.

## Correcao P1 - permissoes_usuario

O review apontou que `canManageControleAtualizacoes()` confiava em `usuarios/{uid}/permissoes_usuario/configuracoes`, mas a subcolecao `permissoes_usuario` ainda podia ser escrita por qualquer usuario autenticado.

O match `usuarios/{userId}/permissoes_usuario/{document=**}` foi restringido para:

- leitura: admin ou o proprio usuario;
- create/update/delete: somente `isAdmin()`.

Com isso, um usuario comum nao consegue mais criar ou alterar `pode_controle_atualizacoes` para se autoelevar.

## Correcao blocker - usuarios/{userId}

O match `usuarios/{userId}` tambem permitia self-write amplo. Isso poderia deixar um usuario comum alterar campos usados por `isAdmin()`, como `tipo` e `peso_permissao`, e depois obter acesso ao Controle de Atualizacoes.

Foi adicionado self-update seguro: o proprio usuario pode atualizar apenas campos nao sensiveis. Campos administrativos e de identidade ficam bloqueados para self-update e so podem ser alterados por `isAdmin()`.

Campos bloqueados para self-update incluem `tipo`, `peso_permissao`, `role`, `papel`, `admin`, `administrador`, `isAdmin`, `permissoes`, `permissions`, `uid`, `email`, `criadoEm`, `criadoPor`, `nivel`, `nivel_acesso`, `accessLevel`, `status_conta`, `statusConta`, `ativo`, `super_admin` e `superadmin`.
