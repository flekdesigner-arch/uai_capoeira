# Estudos e Fundamentos - Fase 1C-2E - Admin por estudo e perguntas vinculadas

Data: 2026-07-10

## Entrega

Foi criada a tela administrativa de detalhe do estudo:

- `lib/modules/estudos_fundamentos/admin/detalhe_admin_estudo_screen.dart`

A tela permite administrar um estudo e suas perguntas vinculadas no mesmo fluxo, reduzindo o trabalho de cadastro pelo celular/APK.

## UX nova

A tela `Gerenciar estudos` recebeu uma acao `Abrir` no card do estudo. A nova tela de detalhe mostra:

- dados principais do estudo;
- acoes do estudo: preview, editar, duplicar e alterar status;
- lista de perguntas vinculadas ao estudo;
- botao `Nova pergunta neste estudo`;
- acoes por pergunta: editar, gabarito, duplicar e alterar status.

## Criacao rapida de pergunta

Ao criar pergunta por `Nova pergunta neste estudo`, o formulario abre pre-vinculado ao estudo atual com:

- ciclo preenchido;
- estudo preenchido;
- `cicloTituloSnapshot` preenchido;
- `estudoTituloSnapshot` preenchido;
- `estudoNumeroSnapshot` preenchido;
- proxima ordem livre sugerida dentro do estudo;
- status `Rascunho`;
- `podeAparecerEmAvaliacao` como `true`;
- peso `1`;
- tipo `Multipla escolha`.

## Reuso de fluxo existente

Para evitar duplicacao grande de codigo, os dialogs existentes foram expostos para reuso:

- `EstudoFormDialog`
- `PerguntaFormDialog`

A tela geral `Gerenciar perguntas` continua existindo e funcionando como visao geral de todas as perguntas.

## Gabarito

A nova tela apenas navega para a tela existente de gabarito protegido:

- `GerenciarGabaritoPerguntaScreen`

Nao houve alteracao no modelo, repositorio ou colecao de gabarito.

## Garantias

- Area do Aluno nao foi alterada nesta fase.
- Firestore Rules nao foram alteradas.
- `firebase.json` nao foi alterado.
- Nenhum deploy foi feito.
- Producao nao foi alterada.
- A tela geral de perguntas permanece disponivel.

## Validacoes executadas

Comando:

```powershell
dart analyze lib/modules/estudos_fundamentos
```

Resultado:

```text
Analyzing estudos_fundamentos...
No issues found!
```

Comando:

```powershell
powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1
```

Resultado:

```text
TODOS OS TESTES DAS RULES PASSARAM
Nenhum deploy foi feito.
Producao nao foi alterada.
```

Os logs `PERMISSION_DENIED` no final do script sao esperados nos cenarios negativos das rules.

## Teste manual recomendado

- Abrir `Gerenciar estudos`.
- Tocar/abrir um estudo pelo botao `Abrir`.
- Ver perguntas vinculadas ao estudo.
- Criar nova pergunta pelo botao `Nova pergunta neste estudo`.
- Confirmar ciclo e estudo pre-preenchidos.
- Confirmar ordem sugerida.
- Abrir gabarito de uma pergunta pela tela do estudo.
- Confirmar que `Gerenciar perguntas` geral continua funcionando.
- Confirmar que Area do Aluno nao mudou.


## Resultado final do teste manual

- Gerenciar estudos > Abrir estudo funcionando.
- Detalhe do estudo lista somente perguntas vinculadas ao estudo correto.
- Estudo 1 ficou com 3 perguntas vinculadas corretamente.
- Estudo 2 ficou com 1 pergunta vinculada corretamente apos correcao manual do vinculo.
- Botao `Nova pergunta neste estudo` testado no Estudo 1.
- Nova pergunta no Estudo 1 veio pre-preenchida com ciclo/estudo corretos e ordem sugerida correta.
- Botao `Nova pergunta neste estudo` testado no Estudo 2.
- Nova pergunta no Estudo 2 veio pre-preenchida com ciclo/estudo corretos e ordem sugerida correta.
- Tela geral Gerenciar perguntas continua funcionando.
- Gabarito continua acessivel somente pelo admin.
- Area do Aluno nao foi alterada.
- Nenhum deploy foi feito.
- Producao nao foi alterada.

## Status

Fase 1C-2E concluida e aprovada no teste manual.

Nenhum deploy foi feito.

Producao nao foi alterada.