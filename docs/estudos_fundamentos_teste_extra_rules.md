# Teste extra local das Firestore Rules - Estudos e Fundamentos

Este documento registra o teste extra local das Firestore Rules candidatas do modulo Estudos e Fundamentos.

A validacao foi feita usando o Firestore Emulator, sem deploy e sem alteracao em producao.

---

## Objetivo

Validar regras extras de seguranca antes de criar gabarito, quiz, nota ou avaliacao oficial.

O foco deste teste foi confirmar:

- usuario com permissao granular consegue gerenciar Estudos e Fundamentos;
- aluno nao consegue escrever gabarito;
- usuario com permissao consegue criar pergunta publica segura;
- usuario com permissao nao consegue criar pergunta publica contendo resposta correta;
- admin consegue ler estudo em rascunho;
- aluno consegue ler estudo em_breve quando `mostrarEmBreve=true`;
- aluno nao consegue ler estudo em_breve quando `mostrarEmBreve=false`;
- anonimo nao consegue ler config do modulo;
- aluno nao consegue escrever config do modulo;
- usuario com permissao granular consegue atualizar config do modulo.

---

## Arquivo de teste criado

O teste extra foi criado em:

```text
firebase_rules_test/functional_tests/estudos_rules_extra_test.js
```

---

## Arquivos usados no teste

Rules candidatas usadas pelo emulador:

```text
firebase_rules_test/firestore.rules
```

Arquivo candidato original:

```text
firebase_rules_backup/firestore_mesclado_com_estudos_fundamentos.rules
```

Configuracao temporaria do emulador:

```text
firebase_rules_test/firebase.json
```

---

## Comando executado

Foi executado no PowerShell:

```powershell
firebase emulators:exec --project demo-uai-capoeira-rules --only firestore --config firebase_rules_test/firebase.json "node firebase_rules_test/functional_tests/estudos_rules_extra_test.js"
```

---

## Resultado observado

O terminal exibiu:

```text
Iniciando testes extras das Firestore Rules...
Rules: C:\Dev\projects\uai_capoeira\firebase_rules_test\firestore.rules
Teste extra 1: usuario com permissao granular consegue ler gabarito...
Teste extra 2: aluno NAO consegue escrever gabarito...
Teste extra 3: usuario com permissao granular cria pergunta segura...
Teste extra 4: usuario com permissao NAO consegue criar pergunta com respostaCorreta...
Teste extra 5: admin consegue ler estudo rascunho...
Teste extra 6: aluno consegue ler estudo em_breve quando mostrarEmBreve=true...
Alterando config para mostrarEmBreve=false...
Teste extra 7: aluno NAO consegue ler estudo em_breve quando mostrarEmBreve=false...
Teste extra 8: anonimo NAO consegue ler config do modulo...
Teste extra 9: aluno NAO consegue escrever config do modulo...
Teste extra 10: usuario com permissao granular consegue atualizar config...

TODOS OS TESTES EXTRAS DAS RULES PASSARAM ✅
Nenhum deploy foi feito.
Perguntas continuam sem resposta correta no documento publico.
```

---

## Observacao sobre PERMISSION_DENIED

Durante o teste apareceram mensagens `PERMISSION_DENIED`.

Essas mensagens eram esperadas, porque alguns testes usaram `assertFails()` para confirmar que determinadas acoes seriam bloqueadas pelas rules.

Exemplos de bloqueios esperados:

- aluno tentando escrever em `estudos_gabaritos`;
- usuario tentando criar pergunta publica com `respostaCorreta`;
- aluno tentando escrever config do modulo.

Portanto, esses `PERMISSION_DENIED` nao representam erro do teste. Eles confirmam que as regras bloquearam corretamente os acessos proibidos.

---

## Testes aprovados

### Teste extra 1

Usuario com permissao granular consegue ler `estudos_gabaritos`.

Resultado: aprovado.

### Teste extra 2

Aluno nao consegue escrever em `estudos_gabaritos`.

Resultado: aprovado.

### Teste extra 3

Usuario com permissao granular consegue criar pergunta publica segura, sem resposta correta.

Resultado: aprovado.

### Teste extra 4

Usuario com permissao granular nao consegue criar pergunta publica contendo `respostaCorreta`.

Resultado: aprovado.

### Teste extra 5

Admin consegue ler estudo em rascunho.

Resultado: aprovado.

### Teste extra 6

Aluno consegue ler estudo `em_breve` quando `mostrarEmBreve=true`.

Resultado: aprovado.

### Teste extra 7

Aluno nao consegue ler estudo `em_breve` quando `mostrarEmBreve=false`.

Resultado: aprovado.

### Teste extra 8

Usuario anonimo nao consegue ler `estudos_config/global`.

Resultado: aprovado.

### Teste extra 9

Aluno nao consegue escrever `estudos_config/global`.

Resultado: aprovado.

### Teste extra 10

Usuario com permissao granular consegue atualizar `estudos_config/global`.

Resultado: aprovado.

---

## Confirmações

- Nao houve deploy.
- A producao nao foi alterada.
- O `firebase.json` principal nao foi alterado.
- Nenhuma colecao real de gabarito foi criada em producao.
- Nenhum quiz/prova foi criado.
- Nenhuma nota/aprovacao foi criada.
- Nenhum certificado foi criado.
- Nenhum emblema/trofeu foi criado.
- Nenhuma Cloud Function foi criada.

---

## Status final

```text
Rules candidatas: teste extra passou
Permissao granular: validada
Gabarito: protegido contra escrita de aluno
Pergunta publica: bloqueada se tiver resposta correta
Estudo em_breve: respeita mostrarEmBreve
Config do modulo: protegida contra aluno/anonimo
Deploy: nao realizado
Producao: nao alterada
```

---

## Proximo passo recomendado

Antes de criar gabarito no app real, ainda falta testar os fluxos principais do app com as rules candidatas em ambiente seguro.

Pontos principais:

1. Admin gerenciando config, ciclos, estudos e perguntas.
2. Aluno acessando Area do Aluno.
3. Aluno lendo ciclo/estudo publicado.
4. Aluno gravando progresso.
5. Eventos e turmas continuando funcionando.
6. Dashboard continuando funcionando.
7. Nenhum deploy de rules sem teste manual.