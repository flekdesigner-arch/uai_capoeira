# Fase 2D - Flutter para responder perguntas dos Estudos

## Objetivo

Criar o fluxo do aluno para responder perguntas de um estudo usando somente Cloud Functions. O Flutter nao le `estudos_perguntas`, nao le `estudos_gabaritos` e nao calcula nota ou aprovacao localmente.

## Telas criadas

- `ResponderEstudoScreen`: carrega perguntas pela Function `buscarPerguntasEstudo`, permite selecao unica e envia respostas para `finalizarTentativaEstudo`.
- `ResultadoEstudoScreen`: exibe somente o resumo retornado pela Function oficial.

A tela `DetalheEstudoScreen` recebeu o botao `Fazer atividade` para abrir o fluxo de resposta quando o estudo esta disponivel para o aluno.

## Models criados

- `PerguntaAvaliacaoEstudoModel`
- `AlternativaAvaliacaoEstudoModel`
- `ResultadoTentativaEstudoModel`

Esses models representam apenas DTOs seguros retornados pelas Functions.

## Service criado

- `AvaliacaoEstudosService`

Functions chamadas:

- `buscarPerguntasEstudo`
  - entrada: `alunoId`, `estudoId`
  - retorno: lista de perguntas sanitizadas
- `finalizarTentativaEstudo`
  - entrada: `alunoId`, `estudoId`, `clientAttemptId`, `respostas`
  - retorno: resumo oficial da tentativa

## Fluxo do aluno

1. Aluno abre o detalhe do estudo.
2. Toca em `Fazer atividade`.
3. Flutter chama `buscarPerguntasEstudo`.
4. A tela exibe loading, erro, vazio ou perguntas.
5. O aluno seleciona uma alternativa por pergunta.
6. O app bloqueia envio se faltar resposta objetiva.
7. Flutter gera `clientAttemptId` seguro com timestamp e random.
8. Flutter chama `finalizarTentativaEstudo`.
9. A tela de resultado mostra percentual, acertos, respondidas, status, aprovacao ou pendencia manual.

## Seguranca

O Flutter nao faz:

- leitura direta de `estudos_perguntas`;
- leitura de `estudos_gabaritos`;
- calculo de nota;
- definicao de `aprovado`;
- escrita em `estudos_tentativas`;
- escrita em `alunos_estudos_resultados`.

A correcao oficial continua exclusivamente na Cloud Function `finalizarTentativaEstudo`.

## Limitacoes MVP

- Suporta somente os tipos atuais `multipla_escolha` e `verdadeiro_falso` como selecao unica.
- Nao implementa questoes discursivas na UI.
- Nao exibe historico completo de tentativas.
- Nao le o resultado resumido via Firestore no detalhe do estudo.
- Nao ha paginacao de perguntas.

## Como testar manualmente

1. Entrar pela Area do Aluno com conta Google vinculada.
2. Abrir Estudos e Fundamentos.
3. Abrir um estudo publicado.
4. Tocar em `Fazer atividade`.
5. Confirmar que as perguntas carregam pela Function.
6. Tentar enviar sem responder todas e confirmar bloqueio local.
7. Responder todas e enviar.
8. Confirmar tela de resultado com dados retornados pelo servidor.
9. Confirmar que o app nao acessa `estudos_perguntas` nem `estudos_gabaritos` diretamente.

## Confirmacao

Nenhum firebase deploy foi executado.
Nenhum APK foi gerado.
Rules nao foram alteradas.
Functions nao foram alteradas.
