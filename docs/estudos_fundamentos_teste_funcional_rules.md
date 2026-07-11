# Teste funcional local das Firestore Rules - Estudos e Fundamentos

Este documento registra o teste funcional local das Firestore Rules candidatas do módulo **Estudos e Fundamentos**.

A validação foi feita usando o Firestore Emulator, sem deploy e sem alteração em produção.

---

## Objetivo

Validar localmente, no emulador, se as rules candidatas protegem corretamente as coleções sensíveis do módulo Estudos e Fundamentos.

O foco do teste foi confirmar que:

- admin consegue acessar dados administrativos;
- aluno não consegue ler gabarito;
- aluno não consegue ler perguntas nesta fase;
- aluno consegue ler estudo publicado;
- aluno não consegue ler estudo rascunho;
- anônimo não consegue ler estudo publicado;
- aluno consegue gravar progresso próprio;
- aluno não consegue gravar progresso de outro aluno;
- aluno não consegue gravar campo proibido como `nota`;
- outro usuário não consegue acessar progresso de aluno não vinculado.

---

## Arquivo de teste criado

O teste funcional foi criado em:

```text
firebase_rules_test/functional_tests/estudos_rules_test.js
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

Configuração temporária do emulador:

```text
firebase_rules_test/firebase.json
```

Pacotes instalados apenas na pasta de teste:

```text
firebase_rules_test/functional_tests/package.json
firebase_rules_test/functional_tests/package-lock.json
firebase_rules_test/functional_tests/node_modules
```

---

## Ajuste de encoding

Antes do teste passar, apareceu erro por caractere invisível BOM no início do arquivo de rules:

```text
L1:1 token recognition error at: '﻿'
```

O arquivo foi regravado em UTF-8 sem BOM:

```powershell
$content = Get-Content firebase_rules_test\firestore.rules -Raw
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText("C:\Dev\projects\uai_capoeira\firebase_rules_test\firestore.rules", $content, $utf8NoBom)
```

O mesmo ajuste também foi aplicado ao candidato principal:

```powershell
$content = Get-Content firebase_rules_backup\firestore_mesclado_com_estudos_fundamentos.rules -Raw
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText("C:\Dev\projects\uai_capoeira\firebase_rules_backup\firestore_mesclado_com_estudos_fundamentos.rules", $content, $utf8NoBom)
```

---

## Comando executado

Foi executado no PowerShell:

```powershell
firebase emulators:exec --project demo-uai-capoeira-rules --only firestore --config firebase_rules_test/firebase.json "node firebase_rules_test/functional_tests/estudos_rules_test.js"
```

---

## Resultado observado

O terminal exibiu:

```text
Iniciando testes funcionais das Firestore Rules...
Rules: C:\Dev\projects\uai_capoeira\firebase_rules_test\firestore.rules
Teste 1: admin consegue ler gabarito...
Teste 2: aluno NÃO consegue ler gabarito...
Teste 3: aluno NÃO consegue ler perguntas nesta fase...
Teste 4: aluno consegue ler estudo publicado...
Teste 5: aluno NÃO consegue ler estudo rascunho...
Teste 6: anônimo NÃO consegue ler estudo publicado...
Teste 7: aluno consegue gravar progresso dele...
Teste 8: aluno NÃO consegue gravar progresso de outro aluno...
Teste 9: aluno NÃO consegue gravar campo proibido nota...
Teste 10: outro usuário NÃO consegue acessar progresso do aluno_001...

TODOS OS TESTES FUNCIONAIS DAS RULES PASSARAM ✅
Nenhum deploy foi feito.
Gabarito continua sem acesso para aluno.
```

---

## Observação sobre PERMISSION_DENIED

Durante o teste apareceram mensagens `PERMISSION_DENIED`.

Essas mensagens eram esperadas, porque alguns testes usaram `assertFails()` para confirmar que determinadas ações seriam bloqueadas pelas rules.

Exemplos de bloqueios esperados:

- aluno tentando gravar progresso de outro aluno;
- aluno tentando gravar campo proibido `nota`;
- outro usuário tentando acessar progresso de aluno não vinculado.

Portanto, esses `PERMISSION_DENIED` não representam erro do teste. Eles confirmam que as regras bloquearam corretamente os acessos proibidos.

---

## Testes aprovados

### Teste 1

Admin consegue ler `estudos_gabaritos`.

Resultado: aprovado.

### Teste 2

Aluno não consegue ler `estudos_gabaritos`.

Resultado: aprovado.

### Teste 3

Aluno não consegue ler `estudos_perguntas` nesta fase.

Resultado: aprovado.

### Teste 4

Aluno consegue ler estudo publicado.

Resultado: aprovado.

### Teste 5

Aluno não consegue ler estudo em rascunho.

Resultado: aprovado.

### Teste 6

Usuário anônimo não consegue ler estudo publicado.

Resultado: aprovado.

### Teste 7

Aluno consegue gravar progresso do próprio aluno vinculado.

Resultado: aprovado.

### Teste 8

Aluno não consegue gravar progresso de outro aluno.

Resultado: aprovado.

### Teste 9

Aluno não consegue gravar campo proibido `nota`.

Resultado: aprovado.

### Teste 10

Outro usuário não consegue acessar progresso de `aluno_001`.

Resultado: aprovado.

---

## Confirmações

- Não houve deploy.
- A produção não foi alterada.
- O `firebase.json` principal não foi alterado.
- Nenhuma coleção real de gabarito foi criada em produção.
- Nenhum quiz/prova foi criado.
- Nenhuma nota/aprovação foi criada.
- Nenhum certificado foi criado.
- Nenhum emblema/troféu foi criado.
- Nenhuma Cloud Function foi criada.

---

## Status final

```text
Rules candidatas: teste funcional básico passou
Gabarito: protegido contra leitura de aluno no emulador
Perguntas: admin-only nesta fase
Progresso: limitado ao aluno vinculado
Campo nota: bloqueado para aluno
Deploy: não realizado
Produção: não alterada
```

---

## Próximos passos antes de produção

Antes de qualquer deploy real das rules, ainda será necessário:

1. Testar fluxos reais do app usando as rules candidatas.
2. Validar login/admin.
3. Validar permissões administrativas.
4. Validar Área do Aluno.
5. Validar eventos.
6. Validar turmas.
7. Validar chamadas.
8. Validar dashboard.
9. Validar certificados.
10. Validar inscrições.
11. Validar estatísticas.
12. Só depois decidir se o `firebase.json` principal será configurado para deploy de rules.