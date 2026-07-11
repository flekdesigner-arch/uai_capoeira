# Estudos e Fundamentos - Fase 1C-2G - Plano final de publicacao segura e handoff tecnico

Data: 2026-07-10

## Status atual

O modulo Estudos e Fundamentos esta funcional nas fases entregues ate aqui:

- config global do modulo;
- ciclos admin;
- estudos/artigos admin;
- visualizacao inicial na Area do Aluno;
- progresso simples de leitura;
- perguntas publicas sem gabarito;
- gabarito administrativo protegido;
- preparacao segura das rules locais;
- organizacao admin por estudo e perguntas vinculadas;
- testes Android/emulador local e manual aprovados;
- docs de fase e handoff atualizados.

## O que ja esta pronto

- Tela admin de ciclos.
- Tela admin de estudos.
- Tela admin de perguntas geral.
- Tela admin de detalhe do estudo com lista de perguntas vinculadas.
- Criacao rapida de pergunta ja vinculada ao estudo.
- Tela admin de gabarito protegido.
- Area do Aluno com Estudos condicionados a sessao Google validada.
- Repositorios e modelos separados para pergunta publica e gabarito.
- Rules locais candidatas e testes locais no emulador.

## O que ainda nao esta pronto

- Publicacao das Firestore Rules em producao.
- Handoff humano final de publicacao.
- Backup formal do estado atual das rules no Console antes de qualquer deploy.
- Plano operacional de rollback executado em ambiente real.
- Publicacao de APK.
- Quiz, prova, emblemas e certificado do modulo Estudos.
- Cloud Functions para fluxo de quiz/prova.

## Riscos principais antes de producao

- Publicar rules sem backup completo do estado atual no Console.
- Perder acesso a um comportamento legado se a mesclagem final das rules nao for revisada manualmente.
- Confundir os arquivos locais de rules candidatas com rules de producao.
- Liberar em producao sem revalidar Area do Aluno, admin e fluxo de gabarito com dados reais.
- Misturar dados antigos de estudos/perguntas com o novo formato de gabarito protegido.

## Checklist antes de qualquer deploy

- Revisar manualmente o diff final das rules candidatas contra as rules vigentes no Console.
- Confirmar que o `firebase.json` principal nao aponta para rules de producao ainda.
- Confirmar backup local e externo das rules atuais do Console.
- Rodar `dart analyze lib/modules/estudos_fundamentos`.
- Rodar `powershell -ExecutionPolicy Bypass -File firebase_rules_test\run_estudos_rules_tests.ps1`.
- Testar admin, Area do Aluno e gabarito em ambiente local.
- Confirmar que nao existe `firestore.rules` na raiz do projeto.
- Confirmar que nao ha alteracao nao intencional em arquivos fora do modulo.

## Checklist de backup das Firestore Rules atuais do Console

- Exportar a regra atual publicada no Console para um arquivo datado.
- Guardar copia em um local separado do repositorio.
- Registrar hash ou identificador da copia de backup.
- Validar se o backup cobre exatamente o estado em producao antes de qualquer alteracao.
- Preservar uma copia do arquivo mesclado local usado como candidato.

## Plano de rollback

- Restaurar o arquivo de rules do Console a partir do backup salvo antes do deploy.
- Reverter qualquer publicacao parcial de rules caso o Console aceite rollback pontual.
- Validar novamente via Emulator que a versao restaurada libera apenas o comportamento esperado.
- Reaplicar somente se o resultado de validacao humana mostrar regressao.

## Ordem segura de publicacao

1. Revisao humana final do plano e das rules.
2. Backup das rules atuais do Console.
3. Confirmacao final do `firebase.json` principal.
4. Publicacao das rules em janela controlada.
5. Validacao imediata no app e no emulator/ambiente de verificacao.
6. Manter monitoramento e ter rollback pronto antes de qualquer ampliacao de escopo.

## Checklist pos-deploy futuro

- Validar login basico da Area do Aluno.
- Validar acesso Google completo.
- Validar lista de estudos e leitura de conteudo.
- Validar gabarito visivel somente para admin.
- Validar criacao/edicao de pergunta vinculada ao estudo.
- Validar progresso de leitura.
- Validar negacao de acesso de aluno a `estudos_gabaritos`.
- Validar negacao de gravacao indevida em progresso e colecoes administrativas.

## Confirmacoes

Ainda nao e para publicar.

Nenhum deploy foi feito.

Producao nao foi alterada.

