# Script local de teste das Firestore Rules - Estudos e Fundamentos

Este documento registra o script criado para rodar automaticamente os testes locais das Firestore Rules do modulo Estudos e Fundamentos.

---

## Arquivo criado

firebase_rules_test/run_estudos_rules_tests.ps1

---

## Objetivo

Rodar os testes locais das rules no Firestore Emulator com apenas um comando.

O script faz isto:

- configura temporariamente o Java 21;
- confere se os arquivos de teste existem;
- roda o teste funcional basico;
- roda o teste funcional extra;
- confirma que nenhum deploy foi feito;
- confirma que a producao nao foi alterada.

---

## Comando para executar

powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1

---

## Resultado esperado

Ao final, o terminal deve exibir:

TODOS OS TESTES DAS RULES PASSARAM
Nenhum deploy foi feito.
Producao nao foi alterada.

---

## Observacao sobre PERMISSION_DENIED

Durante os testes podem aparecer mensagens PERMISSION_DENIED.

Essas mensagens sao esperadas nos testes que usam assertFails().

Elas confirmam que as regras bloquearam corretamente acessos proibidos, como:

- aluno tentando acessar ou escrever gabarito;
- aluno tentando gravar progresso de outro aluno;
- aluno tentando gravar campo proibido como nota;
- usuario tentando criar pergunta publica com resposta correta;
- anonimo tentando acessar config protegida.

---

## Status

Script local: criado e testado
Teste funcional basico: aprovado
Teste funcional extra: aprovado
Deploy: nao realizado
Producao: nao alterada

---

## Importante

Este script nao deve ser confundido com deploy.

Ele serve somente para teste local das rules no emulador.

Nao rodar firebase deploy sem revisao manual das rules e sem testar os fluxos reais do app.