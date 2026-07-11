# Estudos e Fundamentos - Fase 1C: Perguntas e Gabarito

Este documento prepara a proxima fase do modulo Estudos e Fundamentos.
Ele nao cria perguntas, gabaritos, quiz, nota, certificado ou Cloud Functions.

## Pergunta principal do estudo x perguntas de avaliacao

O campo `perguntaPrincipal` do estudo e pedagogico. Ele orienta a leitura do artigo e aparece como parte do conteudo.

Perguntas de avaliacao sao outra coisa:

- ficam em colecao propria;
- podem existir em grande quantidade por estudo ou ciclo;
- podem ser sorteadas futuramente;
- podem ter dificuldade, peso, tags e status;
- podem aparecer ou nao em avaliacao oficial;
- nao devem carregar resposta correta no documento publico.

Um estudo pode ter varias perguntas de avaliacao porque uma aula pode avaliar conceitos diferentes:

- contexto historico;
- personagens;
- termos importantes;
- relacao cronologica;
- interpretacao do texto;
- fundamentos culturais.

## Estrutura recomendada

### Colecao publica de perguntas

`estudos_perguntas/{perguntaId}`

Campos permitidos para leitura futura do aluno:

- `estudoId`
- `cicloId`
- `enunciado`
- `tipo`
- `alternativasPublicas`
- `dificuldade`
- `peso`
- `ordem`
- `status`
- `tags`
- `podeAparecerEmAvaliacao`
- `criadoEm`
- `atualizadoEm`
- `criadoPor`
- `atualizadoPor`

Campos proibidos nessa colecao:

- `correta`
- `isCorrect`
- `respostaCorreta`
- `alternativaCorretaId`
- `justificativaCorreta`
- `feedbackCorreto`
- `score`
- `nota`

Exemplo conceitual:

```json
{
  "estudoId": "estudo_001",
  "cicloId": "ciclo_001",
  "enunciado": "Por que a expressao 'Africa nao e um pais' e importante?",
  "tipo": "multipla_escolha",
  "alternativasPublicas": [
    {"id": "a", "texto": "Porque destaca a diversidade de povos, linguas e culturas."},
    {"id": "b", "texto": "Porque a Africa nao teve relacao com o Brasil."},
    {"id": "c", "texto": "Porque todos os povos africanos tinham a mesma cultura."}
  ],
  "dificuldade": "facil",
  "peso": 1,
  "ordem": 1,
  "status": "ativa",
  "tags": ["africa", "diversidade", "historia"],
  "podeAparecerEmAvaliacao": true
}
```

### Colecao privada de gabarito

`estudos_gabaritos/{perguntaId}`

Campos:

- `perguntaId`
- `estudoId`
- `cicloId`
- `alternativaCorretaId`
- `justificativaCorreta`
- `explicacaoPedagogica`
- `criadoEm`
- `atualizadoEm`
- `criadoPor`
- `atualizadoPor`

Regra desejada:

- aluno nunca le `estudos_gabaritos`;
- admin pode ler/escrever;
- Cloud Functions futuramente le para corrigir.

## Por que separar gabarito

Se a resposta correta ficar junto da pergunta, qualquer aluno com acesso ao app ou ao trafego do Firestore pode inspecionar o documento e descobrir o gabarito.

Mesmo que o Flutter esconda o campo visualmente, o dado continua entregue ao cliente. Isso nao e seguro para avaliacao oficial.

Separar o gabarito permite:

- mostrar perguntas ao aluno sem resposta correta;
- manter justificativas privadas ate a correcao;
- corrigir no backend futuramente;
- permitir revisao pedagogica por admin;
- impedir que rules publicas liberem dados sensiveis por acidente.

## Por que Flutter nao deve corrigir avaliacao oficial

O Flutter roda no dispositivo do aluno. Qualquer regra de correcao presente no cliente pode ser analisada, alterada ou simulada.

Para estudo livre, o cliente pode mostrar feedback simples. Para avaliacao oficial, a correcao precisa ficar no backend.

Modelo recomendado:

1. Flutter envia tentativa sem gabarito.
2. Cloud Function valida aluno, estudo, ciclo e tentativa.
3. Cloud Function le `estudos_gabaritos` com Admin SDK.
4. Cloud Function calcula acertos, nota e status.
5. Cloud Function grava resultado em `avaliacoes_tentativas`.
6. Flutter apenas exibe o resultado autorizado.

## Fase 1C-1 recomendada

Escopo seguro:

- criar model administrativo de pergunta sem campos de resposta correta;
- criar model administrativo de gabarito separado, mas sem liberar ao aluno;
- criar CRUD admin de perguntas;
- criar CRUD admin de gabarito vinculado;
- impedir que `estudos_perguntas` receba campos proibidos;
- manter aluno sem quiz ativo;
- manter sem nota, certificado ou aprovacao.

Antes de implementar:

- versionar Firestore Rules ou definir processo claro de aplicacao;
- decidir como `isAdmin()` e `alunoPertenceAoUsuario(alunoId)` serao representados nas rules;
- definir tipos iniciais de pergunta: `multipla_escolha` e `verdadeiro_falso`;
- decidir se discursiva fica fora da primeira versao.

## Fase 2 recomendada

Escopo backend/avaliacao:

- criar Cloud Function para iniciar tentativa;
- criar Cloud Function para enviar respostas;
- criar Cloud Function para corrigir multipla escolha e verdadeiro/falso;
- bloquear nota/aprovacao no cliente;
- registrar tentativa, duracao, respostas e resultado;
- liberar revisao manual apenas para admin/professor;
- so depois pensar em certificados.

## Estado atual seguro

Ate esta fase:

- nao existe gabarito;
- nao existe resposta correta;
- nao existe nota;
- nao existe aprovado/reprovado;
- nao existe certificado;
- progresso e apenas leitura;
- aluno escreve somente progresso simples em `alunos_estudos_progresso/{alunoId}/estudos/{estudoId}`.
