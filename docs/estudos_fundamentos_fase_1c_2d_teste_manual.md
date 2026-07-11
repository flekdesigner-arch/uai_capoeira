# Estudos e Fundamentos - Fase 1C-2D - Teste manual e ajuste de acesso Google

Data: 2026-07-10

## Status do teste manual

O teste manual dos 13 itens da fase 1C-2D passou, com um ajuste encontrado durante a validacao da Area do Aluno.

## Ajuste encontrado

Na Area do Aluno, o card `Estudos e Fundamentos` aparecia para aluno que tinha conta Google vinculada, mas ainda estava acessando pela sessao basica.

O estado observado mostrava:

- Conta Google vinculada.
- Botao `Entrar com Google` ainda disponivel.

Isso indicava que o aluno tinha vinculo Google, mas a sessao atual nao era uma sessao Google completa/validada.

## Correcao aplicada

Arquivo alterado:

- `lib/modules/area_aluno/screens/area_aluno_dashboard_screen.dart`

A exibicao do card `Estudos e Fundamentos` agora depende de:

- modulo Estudos e Fundamentos disponivel pela config (`ativo` e `mostrarCardAreaAluno`);
- `authPayload['modo_acesso'] == 'google'`;
- `authPayload['google_uid']` preenchido;
- `FirebaseAuth.instance.currentUser.uid` igual ao `google_uid` do payload;
- aluno do payload compatível com o aluno aberto no dashboard.

A regra foi implementada no getter `_sessaoGoogleValidada`, e o card usa `_podeMostrarEstudosFundamentos`.

## UX escolhida

Foi escolhida a opcao preferencial: ocultar o card quando a sessao Google nao esta validada.

Tambem foi mantida uma defesa extra na abertura: se algum fluxo chamar `_abrirEstudosFundamentos` sem sessao Google validada, a tela nao abre e mostra a mensagem:

```text
Entre com Google para acessar os Estudos e Fundamentos.
```

## Garantias mantidas

- Area do Aluno nao mostra Estudos em acesso basico.
- Area do Aluno nao abre Estudos em acesso basico.
- Aluno com Google vinculado, mas sem sessao Google atual validada, nao acessa Estudos.
- Aluno com sessao Google validada pode abrir Estudos normalmente.
- Gabarito nao foi alterado.
- `estudos_gabaritos` nao foi alterado.
- Firestore Rules nao foram alteradas.
- `firebase.json` nao foi alterado.
- Nenhum deploy foi feito.
- Producao nao foi alterada.

## Validacoes executadas

### Analyze combinado solicitado

Comando executado:

```powershell
dart analyze lib/modules/area_aluno lib/modules/estudos_fundamentos
```

Resultado: falhou por issues preexistentes no modulo `area_aluno`, fora da alteracao desta fase, principalmente warnings/infos em telas admin e frequencia.

Exemplos do resultado:

```text
warning - lib\modules\area_aluno\admin\area_aluno_admin_screen.dart:210:18 - The declaration '_accentGradient' isn't referenced.
warning - lib\modules\area_aluno\admin\area_aluno_admin_screen.dart:1736:10 - The declaration '_buildWhiteChip' isn't referenced.
warning - lib\modules\area_aluno\screens\area_aluno_frequencia_screen.dart:1023:10 - The declaration '_formatDataCurta' isn't referenced.
285 issues found.
```

Esses pontos nao foram corrigidos para nao ampliar escopo e nao alterar fluxos fora da fase 1C-2D.

### Analyze do arquivo alterado + Estudos

Comando executado:

```powershell
dart analyze lib/modules/area_aluno/screens/area_aluno_dashboard_screen.dart lib/modules/estudos_fundamentos
```

Resultado: sem erros ou warnings bloqueantes; apenas infos preexistentes no dashboard (`withOpacity`, underscores e `use_build_context_synchronously`).

### Analyze de Estudos e Fundamentos

Comando executado:

```powershell
dart analyze lib/modules/estudos_fundamentos
```

Resultado:

```text
Analyzing estudos_fundamentos...
No issues found!
```

### Testes locais das Firestore Rules

Comando executado:

```powershell
powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1
```

Resultado:

```text
TODOS OS TESTES DAS RULES PASSARAM
Nenhum deploy foi feito.
Producao nao foi alterada.
```

Os logs `PERMISSION_DENIED` no final sao esperados nos cenarios negativos dos testes.


## Resultado final do teste manual

- Admin > Estudos e Fundamentos: OK
- Gerenciar ciclos: OK
- Gerenciar estudos: OK
- Gerenciar perguntas: OK
- Botao Gabarito admin: OK
- Area do Aluno em acesso basico: Estudos e Fundamentos oculto corretamente
- Area do Aluno com sessao Google validada: Estudos e Fundamentos aparece e abre corretamente
- Gabarito nao aparece para aluno
- Resposta correta nao aparece para aluno
- Justificativa correta nao aparece para aluno
- Turmas: OK
- Dashboard de turmas: OK
- Chamadas: OK
- Alunos: OK
- Eventos: OK

## Status final

Fase 1C-2D concluida.

Nenhum deploy foi feito.

Producao nao foi alterada.

Ainda nao liberar producao antes do plano final de publicacao/rollback.

## Confirmacoes

Nenhum deploy foi feito.

Producao nao foi alterada.

Nao houve alteracao em Firestore Rules.

Nao houve alteracao em `firebase.json`.

Nao houve alteracao no gabarito ou em `estudos_gabaritos`.