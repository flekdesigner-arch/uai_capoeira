# Estudos e Fundamentos - Fase 1C-2B - Gabarito administrativo protegido

Data: 2026-07-10

## Entrega

Foi criada a tela administrativa `GerenciarGabaritoPerguntaScreen` em:

- `lib/modules/estudos_fundamentos/admin/gerenciar_gabarito_pergunta_screen.dart`

A tela recebe uma `PerguntaEstudoModel`, mostra os dados publicos da pergunta e permite administrar o gabarito protegido sem alterar o documento publico da pergunta.

## Modelo e repository usados

A implementacao usa:

- `GabaritoEstudoModel`
- `GabaritosEstudosRepository`

As operacoes de leitura, salvamento, ativacao/desativacao e exclusao usam a colecao protegida:

- `estudos_gabaritos/{perguntaId}`

## Separacao de seguranca

O gabarito nao aparece para alunos.

A pergunta publica continua em:

- `estudos_perguntas/{perguntaId}`

Nenhuma resposta correta foi salva em `estudos_perguntas`.

A tela administrativa exibe o aviso:

> Gabarito protegido. Nao aparece para alunos. Nao e salvo na pergunta publica.

## Integracao admin

A tela `GerenciarPerguntasEstudoScreen` recebeu o botao `Gabarito` no card da pergunta, dentro das acoes administrativas.

O botao abre:

- `GerenciarGabaritoPerguntaScreen(pergunta: pergunta)`

A Area do Aluno nao foi alterada.

## Validacoes implementadas

- Bloqueia abertura/salvamento quando `pergunta.id` esta vazio.
- Bloqueia salvamento quando `cicloId` ou `estudoId` estao vazios.
- Para multipla escolha e verdadeiro/falso, exige alternativa correta marcada.
- Para resposta textual futura, exige texto quando o tipo nao usa alternativas.
- Exige peso maior que zero.
- Nao permite salvar gabarito sem resposta correta ou resposta esperada.

## Validacao local

Comando executado:

```powershell
dart analyze lib/modules/estudos_fundamentos
```

Resultado:

```text
Analyzing estudos_fundamentos...
No issues found!
```

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

## Deploy

Nenhum deploy foi feito.

Producao nao foi alterada.