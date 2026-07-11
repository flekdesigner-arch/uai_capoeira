# Estudos e Fundamentos - Status Geral

Data: 2026-07-10

## Resumo

O modulo Estudos e Fundamentos v1 esta consolidado em desenvolvimento e preparado para a etapa final de publicacao segura.

## Fases concluidas

- 1A: config global do modulo.
- 1B-1: ciclos admin.
- 1B-2: estudos/artigos admin.
- 1B-3: visualizacao inicial na Area do Aluno.
- 1B-4: progresso simples de leitura.
- 1C-1: perguntas publicas sem gabarito.
- 1C-2A: rules candidatas locais + testes no emulador.
- 1C-2B: gabarito administrativo protegido.
- 1C-2C: preparacao segura das rules.
- 1C-2D: teste manual completo.
- 1C-2E: organizacao admin estudo > perguntas.
- 1C-2F: teste Android/emulador local aprovado.
- 1C-2G: plano final de publicacao segura e handoff tecnico.
- 1C-2H: preparacao final para publicacao das rules e APK.

## Funcionalidades disponiveis

- Admin de ciclos.
- Admin de estudos.
- Admin de perguntas geral.
- Tela de detalhe do estudo com perguntas vinculadas.
- Criacao rapida de pergunta por estudo.
- Gabarito administrativo protegido.
- Area do Aluno com Estudos condicionado a sessao Google validada.
- Progresso simples de leitura.
- Visao publica inicial do modulo.

## Arquivos principais criados

- `lib/modules/estudos_fundamentos/models/gabarito_estudo_model.dart`
- `lib/modules/estudos_fundamentos/repositories/gabaritos_estudos_repository.dart`
- `lib/modules/estudos_fundamentos/admin/gerenciar_gabarito_pergunta_screen.dart`
- `lib/modules/estudos_fundamentos/admin/detalhe_admin_estudo_screen.dart`

## Colecoes Firestore usadas

- `estudos_config/global`
- `estudos_ciclos`
- `estudos`
- `estudos_perguntas`
- `estudos_gabaritos`
- `alunos_estudos_progresso/{alunoId}/estudos/{estudoId}`

## Regras de seguranca conceituais

- Perguntas publicas nao carregam resposta correta.
- Gabarito fica somente em `estudos_gabaritos/{perguntaId}`.
- Aluno nao deve ler `estudos_gabaritos`.
- Aluno nao deve gravar gabarito.
- Progresso fica isolado por aluno.
- Admin continua com os fluxos previstos.

## Estado de producao

- Nenhum deploy foi feito.
- Produção nao foi alterada.
- O `firebase.json` principal segue sem apontar para rules de producao.
- Nao existe `firestore.rules` na raiz do projeto.

## O que falta para Estudos v1

- Revisao humana final antes de publicar rules.
- Backup operacional das rules atuais do Firebase Console.
- Plano de rollback validado em janela real.
- Publicacao das rules em producao.
- Geracao de APK depois da publicacao segura.

## O que falta para quiz/prova/certificado/emblemas

- Modelo final de quiz/prova.
- Fluxo de resposta, pontuacao e revisao.
- Persistencia e exibicao de resultados.
- Geracao de certificados.
- Emblemas ou conquistas.
- Regras especificas para esses fluxos.
- Eventuais Cloud Functions de suporte.

