# Fase 2G-B - Storage Rules para Estudos/Fundamentos

## Objetivo

Foi criado um `storage.rules` versionado para substituir a dependencia de regras mantidas apenas no Firebase Console e proteger os uploads do modulo Estudos/Fundamentos.

O `firebase.json` agora referencia:

```json
"storage": {
  "rules": "storage.rules"
}
```

Nenhum deploy foi executado nesta fase.

## Risco do fallback antigo

A regra antiga de producao tinha leitura publica global e, no fim, um fallback de escrita para qualquer usuario autenticado:

```js
match /{allPaths=**} {
  allow write: if request.auth != null;
}
```

Esse fallback permitia que qualquer conta logada escrevesse em qualquer pasta sem regra especifica. Na pratica, isso deixava `estudos_fundamentos/...` aberto para upload, update e delete por alunos autenticados.

## Regras para estudos_fundamentos

Foram adicionados matches especificos para os paths usados pelo app:

```text
estudos_fundamentos/ciclos/{cicloId}/capa/{fileName}
estudos_fundamentos/ciclos/{cicloId}/estudos/{estudoId}/capa/{fileName}
estudos_fundamentos/ciclos/{cicloId}/estudos/{estudoId}/imagens/{fileName}
```

As regras permitem `create` e `update` somente quando:

- o usuario esta autenticado;
- o usuario e admin amplo por `usuarios/{uid}.peso_permissao >= 90` ou `tipo in ['admin', 'administrador']`; ou
- o usuario tem `usuarios/{uid}/permissoes_usuario/configuracoes.pode_gerenciar_estudos_fundamentos == true`;
- o arquivo enviado tem `contentType` de imagem;
- o tamanho e de ate 15 MB.

A leitura foi mantida publica (`allow read: if true`) por compatibilidade com o comportamento atual de imagens por URL/download URL no app. Isso deve ser revisado em uma fase futura se o Storage passar a conter dados sensiveis.

## Delete bloqueado no client

Nos paths de `estudos_fundamentos`, `allow delete: if false`.

A limpeza real dos arquivos continua responsabilidade da Cloud Function com Admin SDK ao apagar estudo ou ciclo. O Admin SDK ignora Storage Rules, entao essa regra bloqueia apenas clientes Flutter/Web autenticados.

## Compatibilidade com pastas antigas

As pastas antigas informadas foram preservadas com comportamento equivalente ao atual:

- `assinaturas`
- `assinaturas_inscricoes`
- `assinaturas_campeonato`
- `fotos_competidores`
- `fotos_inscricoes`
- `comprovantes_pagamento`
- `foto_alunos`
- `apks`

Tambem foram pesquisados usos de `FirebaseStorage` no app antes de fechar o fallback. Para reduzir risco de quebra, foram adicionadas regras temporarias de compatibilidade para paths encontrados que dependiam do fallback autenticado:

- `eventos/{allPaths=**}`
- `patrocinadores/{allPaths=**}`
- `profile_pictures/{allPaths=**}`
- `turmas_logos/{allPaths=**}`
- `uniformes/{allPaths=**}`
- `fotos_perfil_alunos/{allPaths=**}`
- `logos_dinamicas/{allPaths=**}`
- `timeline/{allPaths=**}`

Essas regras ainda sao amplas e devem ser endurecidas em fases futuras por modulo, mas evitam que o fechamento do fallback quebre fluxos conhecidos.

## Fallback final

O fallback perigoso de escrita autenticada foi removido. O novo fallback final e fechado:

```js
match /{allPaths=**} {
  allow write: if false;
}
```

A leitura publica global foi mantida por enquanto:

```js
match /{allPaths=**} {
  allow read: if true;
}
```

## Validacao

A sintaxe deve ser validada com Firebase CLI antes de deploy. Nesta fase, o deploy nao foi executado.

Comando recomendado:

```powershell
firebase deploy --only storage --config firebase.json --dry-run
```

Se a CLI local nao suportar `--dry-run`, usar emulador ou validar no fluxo de deploy controlado sem aplicar alteracoes em producao.
