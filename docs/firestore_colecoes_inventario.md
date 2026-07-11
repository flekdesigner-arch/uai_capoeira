# Inventário de Coleções Firestore

Este inventário lista as coleções e subcoleções detectadas na varredura do repositório que são relevantes para a mesclagem das Firestore Rules.

Legenda:
- `Tem regra explícita`: existe bloco no arquivo `firebase_rules_backup/firestore_mesclado_com_estudos_fundamentos.rules`.
- `Comportamento preservado`: a proposta mesclada tenta manter o comportamento atual conhecido.
- `Risco restante`: o que ainda pode quebrar ou merece revisão mais fina.
- `Endurecer depois`: indica se a colecao ainda precisa de regras mais restritivas no futuro.

| Coleção / subcoleção | Arquivos onde aparece | Tem regra explícita | Comportamento preservado | Risco restante | Endurecer depois |
| --- | --- | --- | --- | --- | --- |
| `estatisticas` | `functions/index.js`, `lib/modules/rastreio/screens/dashboard_estatisticas_screen.dart`, `lib/modules/rastreio/widgets/arvore_visitas_dialog.dart`, `lib/modules/turmas/screens/dashboard_turmas_page.dart`, `lib/modules/site/screens/landing_page.dart`, `lib/modules/site/screens/graduacoes_screen.dart` | Sim | Sim | Médio: mantém leitura/escrita amplas herdadas | Sim |
| `estatisticas/graduacoes` | `functions/index.js` | Sim | Sim | Médio: cache agregado segue aberto | Sim |
| `estatisticas/visitas` | `lib/modules/site/screens/landing_page.dart` | Sim | Sim | Baixo/médio | Sim |
| `estatisticas_acessos` | `functions/index.js`, `lib/modules/rastreio/services/rastreio_site.dart`, `lib/modules/rastreio/screens/dashboard_estatisticas_screen.dart` | Sim | Sim | Médio: cria/atualiza continuam amplos | Sim |
| `graduacoes` | `functions/index.js`, `lib/modules/graduacoes/*`, `lib/modules/alunos/*`, `lib/modules/turmas/*`, `lib/modules/site/*`, `lib/modules/eventos/*`, `lib/modules/area_aluno/*` | Sim | Sim | Médio: leitura/escrita continuam amplas | Sim |
| `alunos` | `functions/index.js`, `lib/modules/alunos/*`, `lib/modules/chamadas/*`, `lib/modules/eventos/*`, `lib/modules/turmas/*`, `lib/modules/area_aluno/*`, `lib/modules/inscricoes/*`, `lib/modules/site/screens/graduacoes_screen.dart` | Sim | Sim | Médio: leitura pública e escrita autenticada seguem legadas | Sim |
| `alunos/{alunoId}/contadores` | `functions/index.js` | Sim | Sim | Baixo/médio: contadores legados | Sim |
| `usuarios` | `lib/core/permissions/*`, `lib/modules/usuarios/*`, `lib/modules/sistema/admin/admin_screen.dart` | Sim | Sim | Médio: leitura pública de `usuarios/{userId}` é mais aberta que o ideal | Sim |
| `usuarios/{uid}/permissoes_usuario` | `lib/core/permissions/permissao_service.dart`, `lib/modules/usuarios/admin/*`, `lib/modules/chamadas/screens/listas_chamada_screen.dart`, `lib/modules/uniformes/screens/uniformes_screen.dart`, `lib/modules/turmas/*` | Sim | Parcial | Médio: subcolecao explicitada de forma generica | Sim |
| `campeonato_inscricoes` | `functions/index.js`, `lib/modules/inscricoes/*`, `lib/modules/campeonatos/services/campeonato_service.dart` | Sim | Sim | Médio: leitura pública e escrita autenticada seguem legadas | Sim |
| `inscricoes` | `functions/index.js`, `lib/modules/inscricoes/*` | Sim | Sim | Médio: comportamento legado preservado | Sim |
| `configuracoes` | `functions/index.js` indireto, telas de site/admin | Sim | Sim | Médio: regras amplas continuam legadas | Sim |
| `config_graduacoes` | `functions/index.js`, telas de site/admin | Sim | Sim | Médio: regras amplas continuam legadas | Sim |
| `participacoes_eventos_em_andamento` | `functions/index.js` | Sim | Sim | Médio: acesso amplo continua legado | Sim |
| `eventos` | `functions/index.js`, `lib/modules/eventos/*`, `lib/modules/area_aluno/*`, `lib/modules/campeonatos/*`, `lib/modules/site/*`, `lib/modules/uniformes/*` | Sim | Sim | Médio: colecao muito usada e ainda aberta | Sim |
| `eventos/{eventoId}/participantes_cache` | `functions/index.js`, `lib/modules/eventos/services/evento_participantes_cache_service.dart`, `lib/modules/eventos/screens/detalhes_evento_screen.dart`, `lib/modules/eventos/admin/*` | Sim | Sim | Médio: cache de participantes ainda segue legado | Sim |
| `turmas` | `functions/index.js`, `lib/modules/turmas/*`, `lib/modules/alunos/*`, `lib/modules/chamadas/*`, `lib/modules/inscricoes/*`, `lib/shared/services/assistente_chat_service.dart` | Sim | Sim | Alto: colecao central de turma ainda aberta | Sim |
| `turmas/{turmaId}/dashboard_cache` | `functions/index.js`, `lib/modules/turmas/services/dashboard_turma_cache_service.dart` | Sim | Sim | Médio: cache do dashboard segue aberto | Sim |
| `turmas/{turmaId}/dashboard_cache_alunos` | `functions/index.js` | Sim | Sim | Médio: cache de alunos do dashboard segue aberto | Sim |
| `turmas/{turmaId}/avaliacoes_alunos` | `functions/index.js`, `lib/modules/turmas/screens/avaliacao_alunos_turma_screen.dart` | Sim | Sim | Médio: avaliações da turma ainda abertas | Sim |
| `estudos_config` | `lib/modules/estudos_fundamentos/*`, `lib/modules/area_aluno/*` | Sim | Sim | Baixo/médio | Sim |
| `estudos_ciclos` | `lib/modules/estudos_fundamentos/*` | Sim | Sim | Baixo/médio | Sim |
| `estudos` | `lib/modules/estudos_fundamentos/*` | Sim | Sim | Baixo/médio | Sim |
| `estudos_perguntas` | `lib/modules/estudos_fundamentos/*` | Sim | Sim | Baixo agora, alto no futuro | Sim |
| `alunos_estudos_progresso` | `lib/modules/estudos_fundamentos/*` | Sim | Sim | Baixo/médio | Sim |
| `estudos_gabaritos` | Proposta de rules e docs do módulo | Sim | Protegido | Não habilitado ainda | Não até a fase 2 |
| `avaliacoes_tentativas` | Proposta de rules e docs do módulo | Sim | Protegido | Não habilitado ainda | Sim |

## Leitura do inventário

- As coleções marcadas como `Tem regra explícita: Sim` já foram adicionadas ao arquivo mesclado seguro.
- As coleções com `Comportamento preservado: Sim` mantêm a intenção do legado, mesmo quando a proteção ainda é fraca.
- As coleções com `Endurecer depois: Sim` ainda precisam de revisão futura, principalmente quando o app for migrado para regras mais restritivas.
- `eventos` e `turmas` agora deixaram de depender do fallback global fechado.
- O modulo Estudos e Fundamentos ficou separado das coleções legadas e nao depende do fallback global.

## Contagem da varredura

Total de entradas listadas: 29.
