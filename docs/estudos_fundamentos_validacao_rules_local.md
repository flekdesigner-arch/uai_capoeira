# Validação Local de Firestore Rules - Estudos e Fundamentos

Este documento registra a validação local, sem deploy, do arquivo candidato de Firestore Rules do módulo **Estudos e Fundamentos**.

---

## Fase 1C-2A.6 - Primeira tentativa de validação local

### Objetivo

Carregar o arquivo candidato de Firestore Rules no emulador local para validar se ele possui erro de sintaxe ou carregamento.

### Comando executado

```bash
firebase emulators:exec --project demo-uai-capoeira-rules --only firestore --config firebase_rules_test/firebase.json "cmd /c echo rules_loaded"
```

### Resultado

O `firebase emulators:exec` não chegou a carregar as rules porque o `firebase-tools` deste ambiente exigia Java 21 ou superior.

Mensagem principal observada:

```text
firebase-tools no longer supports Java version before 21. Please install a JDK at version 21 or above to get a compatible runtime.
```

### Observações

- O objetivo era apenas carregar e validar a sintaxe das rules candidatas no emulador.
- Nenhuma rule de produção foi alterada.
- O `firebase.json` principal do projeto não foi tocado.
- A falha ocorreu antes da validação da sintaxe das rules, por bloqueio de runtime Java.

### Próximos passos definidos naquele momento

1. Instalar ou apontar um JDK 21+ localmente.
2. Reexecutar o comando de validação local com o mesmo `firebase_rules_test/firebase.json`.
3. Confirmar se o emulador carregou o arquivo candidato.
4. Se houvesse erro de sintaxe, corrigir apenas o arquivo mesclado candidato.
5. Registrar o resultado final neste documento.

---

## Fase 1C-2A.6.1 - Validação local bem-sucedida das rules candidatas

### Objetivo

Registrar a validação local bem-sucedida do arquivo candidato de Firestore Rules do módulo **Estudos e Fundamentos**.

Essa fase teve apenas finalidade de documentação/validação local.

Não houve deploy.

Não houve alteração em produção.

Não houve criação de gabarito, quiz, nota, certificado, emblema ou Cloud Functions.

---

### Java instalado e usado

Foi executado no PowerShell:

```powershell
java -version
```

Resultado:

```text
openjdk version "21.0.11" 2026-04-21 LTS
OpenJDK Runtime Environment Temurin-21.0.11+10
OpenJDK 64-Bit Server VM Temurin-21.0.11+10
```

Isso confirmou que o ambiente passou a usar Java 21.

---

### Comando de validação local executado

Foi executado no PowerShell:

```powershell
firebase emulators:exec --project demo-uai-capoeira-rules --only firestore --config firebase_rules_test/firebase.json "cmd /c echo rules_loaded"
```

Resultado observado no terminal:

```text
i  emulators: Starting emulators: firestore
i  emulators: Detected demo project ID "demo-uai-capoeira-rules", emulated services will use a demo configuration and attempts to access non-emulated services for this project will fail.
i  firestore: downloading cloud-firestore-emulator-v1.21.0.jar...
Progress: ==================================================================================================================================================================================================> (100% of 139MB)
i  firestore: Firestore Emulator logging to firestore-debug.log
+  firestore: Firestore Emulator was started in standard edition.
+  firestore: Firestore Emulator UI websocket is running on 9150.
i  Running script: cmd /c echo rules_loaded
rules_loaded
+  Script exited successfully (code 0)
i  emulators: Shutting down emulators.
i  firestore: Stopping Firestore Emulator
!  Firestore Emulator has exited upon receiving signal: SIGINT
i  hub: Stopping emulator hub
i  logging: Stopping Logging Emulator
```

---

### Resultado da validação

A validação local foi concluída com sucesso.

O resultado importante foi:

```text
rules_loaded
+  Script exited successfully (code 0)
```

Isso indica que:

- O emulador Firestore iniciou corretamente.
- O arquivo `cloud-firestore-emulator-v1.21.0.jar` foi baixado.
- As rules candidatas foram carregadas pelo emulador.
- O comando `rules_loaded` foi executado.
- O script saiu com `code 0`.
- O emulador encerrou normalmente.
- Não houve erro de sintaxe nas rules candidatas.

---

### Arquivo validado

O arquivo temporário usado pelo emulador foi:

```text
firebase_rules_test/firestore.rules
```

Esse arquivo é uma cópia local temporária do candidato:

```text
firebase_rules_backup/firestore_mesclado_com_estudos_fundamentos.rules
```

---

### Configuração temporária usada

O arquivo de configuração temporária usado para o emulador foi:

```text
firebase_rules_test/firebase.json
```

Esse arquivo existe apenas para validação local e não deve ser confundido com o `firebase.json` principal do projeto.

O `firebase.json` principal do projeto não foi alterado.

---

### Confirmações importantes

- Não houve deploy.
- Nenhuma rule foi publicada.
- A produção não foi alterada.
- O `firebase.json` principal não foi alterado.
- Nenhuma coleção de gabarito foi criada.
- Nenhum campo de resposta correta foi criado.
- Nenhum quiz/prova foi criado.
- Nenhuma nota/aprovação foi criada.
- Nenhuma Cloud Function foi criada.
- Nenhum certificado foi criado.
- Nenhum emblema/troféu foi criado.

---

### Limite dessa validação

Essa validação confirma apenas que o arquivo candidato de Firestore Rules carrega no emulador sem erro de sintaxe.

Ela NÃO significa que:

- as rules já podem ser publicadas direto;
- todos os fluxos do app já foram testados;
- o gabarito já pode ser criado em produção;
- as rules foram validadas com dados reais;
- o app inteiro já foi testado com fallback global fechado.

Antes de qualquer deploy real das rules, ainda será necessário testar os fluxos principais do app.

---

### Próximos testes necessários antes de produção

Antes de publicar qualquer nova rule, ainda é necessário testar:

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

---

### Status final

As Firestore Rules candidatas passaram na validação local de carregamento/sintaxe pelo Firestore Emulator.

O status após esta fase é:

```text
Rules candidatas: sintaxe validada localmente
Deploy de rules: não realizado
Produção: não alterada
Gabarito: ainda não criado
Quiz/prova: ainda não criado
```