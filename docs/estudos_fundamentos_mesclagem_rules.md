# Mesclagem segura de Firestore Rules - Estudos e Fundamentos

Este documento prepara a mesclagem das Firestore Rules reais de produção com a proposta versionada do módulo Estudos e Fundamentos.

ATENÇÃO: não fazer deploy direto de `firestore.rules`. As rules atuais de produção não estavam versionadas neste repositório e podiam conter permissões essenciais de outras coleções do app.

---

## Situação atual

- `firebase.json` configura `functions` e `hosting`, mas não configura `firestore.rules`.
- `.firebaserc` aponta para o projeto `uai-capoeira-52753`.
- A Firebase CLI está instalada no ambiente.
- Não foi encontrado script de deploy ou exportação de Firestore Rules.
- `functions/package.json` contém scripts para emulador/functions/logs, não para rules.
- Foi criado um backup fiel das rules atuais em `firebase_rules_backup/firestore_producao_atual.rules`.
- Foi criado um arquivo mesclado seguro/proposto em `firebase_rules_backup/firestore_mesclado_com_estudos_fundamentos.rules` com fallback final fechado.
- O inventário de coleções detectadas ficou em `docs/firestore_colecoes_inventario.md`.

Conclusão: nesta fase, não houve alteração em produção. O arquivo mesclado é apenas candidato/proposta segura.

---

## Análise das rules atuais de produção

As rules descritas anteriormente eram permissivas em dois pontos globais:

```js
match /{document=**} {
  allow read: if true;
}

match /{document=**} {
  allow write: if request.auth != null;
}
```

Isso significa:

- qualquer documento podia ser lido publicamente;
- qualquer usuário autenticado podia escrever em qualquer documento que não estivesse mais restrito por um match anterior mais específico;
- as permissões do Firestore são acumulativas, então um `allow read: if true` em nível global torna insegura qualquer coleção futura com dados sensíveis;
- por isso `estudos_gabaritos` não pode existir em um ambiente com fallback global aberto;
- também não faz sentido manter a regra global de escrita no arquivo seguro final, porque ela exporia futuras coleções administrativas e de correção.

Conclusão prática:

- o arquivo seguro precisa fechar o fallback final;
- cada coleção antiga precisa ser reintroduzida explicitamente no merge;
- o bloco de Estudos e Fundamentos precisa ficar restrito por coleção;
- antes do primeiro deploy, é obrigatório testar no emulador ou em ambiente de homologação.

---

## Coleções legadas explicitadas para remover fallback global

As coleções abaixo foram explicitadas no arquivo mesclado seguro para substituir o fallback global aberto:

- `estatisticas/graduacoes`
- `estatisticas/visitas`
- `estatisticas/{document}`
- `estatisticas_acessos/{document}`
- `graduacoes/{document}`
- `alunos/{document}`
- `usuarios/{userId}`
- `usuarios/{userId}/permissoes_usuario/{document=**}`
- `alunos/{alunoId}/contadores/{document=**}`
- `campeonato_inscricoes/{document}`
- `inscricoes/{document}`
- `configuracoes/{document}`
- `config_graduacoes/{document}`
- `participacoes_eventos_em_andamento/{document}`
- `eventos/{document}`
- `eventos/{eventoId}/participantes_cache/{document}`
- `turmas/{document}`
- `turmas/{turmaId}/dashboard_cache/{document}`
- `turmas/{turmaId}/dashboard_cache_alunos/{document}`
- `turmas/{turmaId}/avaliacoes_alunos/{document}`

Esses blocos preservam o comportamento antigo conhecido, principalmente leitura pública e escrita autenticada onde o legado funcionava assim. A segurança continua fraca para algumas coleções antigas, mas agora o risco está explicitado por coleção e não mais escondido em fallback global.

---

## Por que não fazer deploy direto

O arquivo `firestore_mesclado_com_estudos_fundamentos.rules` é uma proposta segura para validação.

Se ele for conectado ao `firebase.json` principal e implantado sem testar todos os fluxos, o deploy pode substituir regras existentes e quebrar áreas antigas do app, como alunos, chamadas, eventos, usuários, área do aluno, dashboard e administração.

---

## Como obter as rules atuais no Firebase Console

1. Abrir o Firebase Console do projeto `uai-capoeira-52753`.
2. Ir em Firestore Database.
3. Abrir a aba Rules.
4. Copiar todo o conteúdo atual das rules.
5. Salvar localmente como referência, por exemplo:
   `firebase_rules_backup/firestore_producao_atual.rules`.
6. Nunca substituir esse backup pela proposta sem revisar.

---

## Como comparar e mesclar

1. Comparar o backup de produção com o arquivo candidato.
2. Preservar todos os helpers e matches existentes de produção.
3. Adicionar os helpers do módulo Estudos e Fundamentos, adaptando nomes se já existirem helpers equivalentes.
4. Inserir os matches do módulo dentro de:

```js
service cloud.firestore {
  match /databases/{database}/documents {
    // regras aqui
  }
}
```

5. Evitar catch-all aberto.
6. Validar no emulador ou no Rules Playground com usuários reais de teste.
7. Só depois configurar `firebase.json` para apontar para o arquivo final de rules.
8. Só depois executar deploy controlado de rules.

---

## Helpers necessários

Os helpers abaixo representam o modelo real encontrado no app.

```js
function isSignedIn() {
  return request.auth != null;
}

function usuarioDoc(uid) {
  return /databases/$(database)/documents/usuarios/$(uid);
}

function permissoesUsuarioDoc(uid) {
  return /databases/$(database)/documents/usuarios/$(uid)/permissoes_usuario/configuracoes;
}

function alunoDoc(alunoId) {
  return /databases/$(database)/documents/alunos/$(alunoId);
}

function usuarioContaLiberada(uid) {
  return exists(usuarioDoc(uid))
    && !(
      ("status_conta" in get(usuarioDoc(uid)).data)
      && get(usuarioDoc(uid)).data.status_conta in [
        "bloqueada",
        "bloqueado",
        "inativa",
        "inativo",
        "rejeitada",
        "rejeitado"
      ]
    );
}

function isAdmin() {
  return isSignedIn()
    && usuarioContaLiberada(request.auth.uid)
    && exists(usuarioDoc(request.auth.uid))
    && (
      (("peso_permissao" in get(usuarioDoc(request.auth.uid)).data)
        && get(usuarioDoc(request.auth.uid)).data.peso_permissao >= 90)
      || get(usuarioDoc(request.auth.uid)).data.tipo == "admin"
      || get(usuarioDoc(request.auth.uid)).data.tipo == "administrador"
    );
}

function podeGerenciarEstudosFundamentos() {
  return isAdmin()
    || (
      isSignedIn()
      && usuarioContaLiberada(request.auth.uid)
      && exists(permissoesUsuarioDoc(request.auth.uid))
      && get(permissoesUsuarioDoc(request.auth.uid)).data.pode_gerenciar_estudos_fundamentos == true
    );
}

function alunoPertenceAoUsuario(alunoId) {
  return isSignedIn()
    && exists(alunoDoc(alunoId))
    && get(alunoDoc(alunoId)).data.areaAlunoGoogleVinculado == true
    && get(alunoDoc(alunoId)).data.areaAlunoGoogleUid == request.auth.uid;
}
```

---

## Bloco de rules do módulo Estudos e Fundamentos

Este bloco deve ser mesclado dentro do match principal de documentos. Ajustar nomes de helpers se a rule de produção já tiver equivalentes.

```js
function estudosConfig() {
  return get(/databases/$(database)/documents/estudos_config/global).data;
}

function statusPublicadoOuEmBrevePermitido(data) {
  return data.status == "publicado"
    || (data.status == "em_breve" && estudosConfig().mostrarEmBreve == true);
}

function conteudoVisivelParaAluno(data) {
  return data.mostrarNaLinhaDoTempo == true
    && statusPublicadoOuEmBrevePermitido(data);
}

function progressoCamposPermitidos() {
  return [
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
  ];
}

function perguntaPublicaSemGabarito(data) {
  return !("respostaCorreta" in data)
    && !("alternativaCorretaId" in data)
    && !("correta" in data)
    && !("isCorrect" in data)
    && !("feedbackCorreto" in data)
    && !("justificativaCorreta" in data)
    && !("score" in data);
}

match /estudos_config/global {
  allow read: if isSignedIn();
  allow create, update, delete: if podeGerenciarEstudosFundamentos();
}

match /estudos_ciclos/{cicloId} {
  allow read: if podeGerenciarEstudosFundamentos()
    || (isSignedIn() && conteudoVisivelParaAluno(resource.data));
  allow create, update, delete: if podeGerenciarEstudosFundamentos();
}

match /estudos/{estudoId} {
  allow read: if podeGerenciarEstudosFundamentos()
    || (isSignedIn() && conteudoVisivelParaAluno(resource.data));
  allow create, update, delete: if podeGerenciarEstudosFundamentos();
}

match /estudos_perguntas/{perguntaId} {
  allow read: if podeGerenciarEstudosFundamentos();
  allow create, update: if podeGerenciarEstudosFundamentos()
    && perguntaPublicaSemGabarito(request.resource.data);
  allow delete: if podeGerenciarEstudosFundamentos();
}

match /alunos_estudos_progresso/{alunoId}/estudos/{estudoId} {
  allow read: if podeGerenciarEstudosFundamentos() || alunoPertenceAoUsuario(alunoId);
  allow create, update: if alunoPertenceAoUsuario(alunoId)
    && request.resource.data.alunoId == alunoId
    && request.resource.data.googleUid == request.auth.uid
    && request.resource.data.estudoId == estudoId
    && request.resource.data.status in ["iniciado", "concluido"]
    && request.resource.data.percentualLeitura is int
    && request.resource.data.percentualLeitura >= 0
    && request.resource.data.percentualLeitura <= 100
    && request.resource.data.keys().hasOnly(progressoCamposPermitidos());
  allow delete: if false;
}

match /estudos_gabaritos/{perguntaId} {
  allow read, create, update, delete: if podeGerenciarEstudosFundamentos();
}

match /avaliacoes_tentativas/{tentativaId} {
  allow read: if podeGerenciarEstudosFundamentos()
    || (
      isSignedIn()
      && resource.data.alunoId is string
      && alunoPertenceAoUsuario(resource.data.alunoId)
    );
  allow create, update, delete: if false;
}

match /{document=**} {
  allow read, write: if false;
}
```

---

## Compatibilidade das queries atuais

- Ciclos do aluno usam filtros por `status` e `mostrarNaLinhaDoTempo` em `estudos_ciclos`.
- Estudos do aluno usam filtros por `cicloId`, `status` e `mostrarNaLinhaDoTempo` em `estudos`.
- Rascunhos, ocultos e arquivados são filtrados no código e também seriam bloqueados pelas rules propostas.
- Progresso grava somente campos de leitura simples: `alunoId`, `googleUid`, `estudoId`, `cicloId`, `status`, datas, `percentualLeitura` e `origem`.
- Perguntas ainda são somente administrativas; aluno não lê `estudos_perguntas` nesta fase.

Possível ponto de atenção: queries com `whereIn` e múltiplos filtros podem exigir índices do Firestore, mas isso é separado da segurança das rules.

---

## Checklist antes do primeiro deploy de rules

- Copiar as rules atuais de produção do Firebase Console.
- Salvar backup local fora do arquivo candidato.
- Mesclar manualmente as rules antigas com o bloco de Estudos e Fundamentos.
- Revisar helpers duplicados ou conflitantes.
- Validar `isAdmin()` com um admin amplo e um usuário sem acesso.
- Validar `podeGerenciarEstudosFundamentos()` com usuário que tenha apenas a permissão do módulo.
- Validar `alunoPertenceAoUsuario(alunoId)` com Google vinculado a um aluno e com outro aluno não vinculado.
- Validar que aluno não lê rascunho/oculto/arquivado.
- Validar que aluno não lê `estudos_gabaritos`.
- Validar que aluno não grava nota, aprovado, certificado ou qualquer campo fora de progresso simples.
- Só então configurar `firebase.json` para rules, se essa for a decisão operacional.

---

## Checklist depois do deploy

- Abrir Área do Aluno com módulo ativo e confirmar leitura de ciclos/estudos publicados.
- Confirmar que rascunho/oculto/arquivado não aparece e não pode ser lido diretamente.
- Confirmar que progresso simples é gravado no aluno correto.
- Confirmar que outro usuário autenticado não consegue ler/escrever progresso de aluno não vinculado.
- Confirmar que admin consegue gerenciar config, ciclos, estudos e perguntas.
- Confirmar que usuário sem permissão não consegue escrever em coleções administrativas.
- Somente depois disso avançar para `estudos_gabaritos`.

---

## Decisão desta fase

Não foi feito deploy.

Não foi alterado `firebase.json`.

Não foi criada coleção de gabarito.

O arquivo candidato seguro foi preparado e validado localmente apenas quanto a sintaxe/carregamento no emulador.

---

## Arquivos gerados nesta fase

- `firebase_rules_backup/firestore_producao_atual.rules`
- `firebase_rules_backup/firestore_mesclado_com_estudos_fundamentos.rules`
- `firebase_rules_test/firebase.json`
- `firebase_rules_test/firestore.rules`
- `docs/firestore_colecoes_inventario.md`
- `docs/estudos_fundamentos_validacao_rules_local.md`

---

## Validação local de sintaxe/carregamento

As Firestore Rules candidatas do módulo Estudos e Fundamentos foram carregadas com sucesso no Firestore Emulator usando Java 21.

### Comando usado

```powershell
firebase emulators:exec --project demo-uai-capoeira-rules --only firestore --config firebase_rules_test/firebase.json "cmd /c echo rules_loaded"
```

### Resultado

- O Firestore Emulator iniciou corretamente.
- As rules candidatas foram carregadas.
- O comando `rules_loaded` foi executado.
- O script finalizou com `code 0`.
- Não houve erro de sintaxe no arquivo candidato.

### Importante

Essa validação confirma que o arquivo de rules candidato tem sintaxe aceita pelo emulador.

Ela NÃO significa que:

- as rules foram publicadas;
- a produção foi alterada;
- todos os fluxos do app foram testados;
- o gabarito já pode ser criado sem revisão;
- o arquivo já pode ser usado em deploy direto.

### Arquivos temporários mantidos

```text
firebase_rules_test/firebase.json
firebase_rules_test/firestore.rules
```

Esses arquivos são apenas para validação local.

O `firebase.json` principal do projeto continua sem configuração de deploy das Firestore Rules.

### Próximos testes necessários antes de produção

Antes de qualquer deploy real das rules, ainda é necessário testar:

- login/admin;
- painel administrativo;
- permissões;
- Área do Aluno;
- módulo Estudos e Fundamentos;
- leitura de ciclos publicados;
- leitura de estudos publicados;
- progresso do aluno;
- eventos;
- turmas;
- chamadas;
- dashboard;
- avaliações de alunos;
- certificados;
- inscrições;
- estatísticas;
- fluxos públicos do site/app.

### Status de segurança

O arquivo candidato remove o fallback global público e mantém fallback final fechado.

O módulo Estudos e Fundamentos permanece protegido, especialmente:

- `estudos_gabaritos` sem leitura de aluno;
- `estudos_perguntas` sem leitura pública nesta fase;
- `alunos_estudos_progresso` limitado a progresso simples;
- sem criação de gabarito;
- sem resposta correta no cliente;
- sem quiz/prova oficial ainda.

### Status final desta documentação

```text
Rules candidatas: sintaxe validada localmente
Deploy de rules: não realizado
Produção: não alterada
Gabarito: ainda não criado
Quiz/prova: ainda não criado
```