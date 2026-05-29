import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'editar_usuario_screen.dart';

class UsuarioDetalheScreen extends StatefulWidget {
  final String userId;

  const UsuarioDetalheScreen({super.key, required this.userId});

  @override
  State<UsuarioDetalheScreen> createState() => _UsuarioDetalheScreenState();
}

class _UsuarioDetalheScreenState extends State<UsuarioDetalheScreen> {
  // 🔥 LOGS PARA ACOMPANHAR
  void _log(String mensagem, {dynamic dados}) {
    debugPrint('🔍 [UsuarioDetalhe] $mensagem');
    if (dados != null) {
      debugPrint('📦 Dados: $dados');
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Não informado';
    final date = timestamp.toDate();
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  String _formatStatus(String? status) {
    if (status == null) return 'Não informado';
    switch (status.toLowerCase()) {
      case 'pendente':
        return 'Pendente';
      case 'ativa':
        return 'Ativa';
      case 'bloqueada':
      case 'inativa':
        return 'Bloqueada';
      default:
        return status;
    }
  }

  Color _getStatusColor(String? status) {
    final t = context.uai;

    if (status == null) return t.textMuted;
    switch (status.toLowerCase()) {
      case 'ativa':
        return t.success;
      case 'pendente':
        return t.warning;
      case 'bloqueada':
      case 'inativa':
        return t.error;
      default:
        return t.textMuted;
    }
  }

  Color _getTipoColor(String? tipo) {
    final t = context.uai;

    if (tipo == null) return t.textMuted;
    switch (tipo.toLowerCase()) {
      case 'admin':
      case 'administrador':
        return t.error;
      case 'professor':
        return t.warning;
      case 'monitor':
        return t.info;
      case 'aluno':
        return t.success;
      case 'visitante':
        return t.associacao;
      default:
        return t.textMuted;
    }
  }

  IconData _getTipoIcon(String? tipo) {
    if (tipo == null) return Icons.person;
    switch (tipo.toLowerCase()) {
      case 'admin':
      case 'administrador':
        return Icons.admin_panel_settings;
      case 'professor':
        return Icons.school;
      case 'monitor':
        return Icons.supervised_user_circle;
      case 'aluno':
        return Icons.person;
      case 'visitante':
        return Icons.person_outline;
      default:
        return Icons.person;
    }
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _onHeroGradient() {
    // Header premium sempre precisa saltar do gradiente,
    // principalmente nos temas neon/café/tema do usuário.
    final readable = _readableOn(context.uai.primary);
    if (readable.computeLuminance() > 0.72) return readable;
    return const Color(0xFFF8FAFC);
  }

  void _showSnack(
      String mensagem,
      Color color, {
        IconData icon = Icons.info_outline_rounded,
      }) {
    final onColor = _readableOn(color);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            Icon(icon, color: onColor, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                mensagem,
                style: TextStyle(
                  color: onColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔥 MÉTODO DE DIAGNÓSTICO COMPLETO
  Future<void> _diagnosticarPermissoesCompleto(BuildContext context) async {
    _log('INICIANDO DIAGNÓSTICO COMPLETO');

    try {
      final user = FirebaseAuth.instance.currentUser;
      _log('Usuário logado:', dados: user?.uid ?? 'Ninguém logado');

      if (user == null) {
        _log('❌ ERRO: Ninguém logado!');
        if (context.mounted) {
          _showSnack(
            'Você precisa estar logado!',
            context.uai.error,
            icon: Icons.error_outline_rounded,
          );
        }
        return;
      }

      final caminho = 'usuarios/${widget.userId}/permissoes_usuario/configuracoes';
      _log('Caminho completo:', dados: caminho);

      final docRef = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(widget.userId)
          .collection('permissoes_usuario')
          .doc('configuracoes');

      _log('Tentando ler documento...');
      final doc = await docRef.get();
      _log('Documento existe:', dados: doc.exists);

      if (doc.exists) {
        final dados = doc.data();
        _log('Dados encontrados:', dados: dados);

        dados?.forEach((key, value) {
          debugPrint('   • $key: $value');
        });

        if (context.mounted) {
          _mostrarDialogDiagnostico(context, doc, dados);
        }
      } else {
        _log('⚠️ Documento NÃO existe!');
        if (context.mounted) {
          _mostrarDialogDocumentoNaoEncontrado(context, caminho);
        }
      }

      _log('Testando permissão de escrita...');
      try {
        await docRef.set({'diagnostico_timestamp': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        _log('✅ Permissão de escrita OK!');
        await docRef.update({'diagnostico_timestamp': FieldValue.delete()});
      } catch (e) {
        _log('❌ Erro ao testar escrita:', dados: e.toString());
      }
    } catch (e) {
      _log('❌ ERRO NO DIAGNÓSTICO:', dados: e.toString());
    }
  }

  // 🔥 MÉTODO DE SALVAR PERMISSÕES
  Future<void> _salvarPermissoes(BuildContext context, Map<String, bool> permissoes) async {
    _log('SALVANDO PERMISSÕES');
    _log('Permissões a salvar:', dados: permissoes);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuário não está logado');

      final docRef = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(widget.userId)
          .collection('permissoes_usuario')
          .doc('configuracoes');

      await docRef.set(permissoes, SetOptions(merge: true));
      _log('✅ Comando set executado com sucesso!');

      if (context.mounted) {
        _showSnack(
          '✅ Permissões salvas com sucesso!',
          context.uai.success,
          icon: Icons.check_circle_rounded,
        );
      }
    } catch (e) {
      _log('❌ ERRO AO SALVAR:', dados: e.toString());
      if (context.mounted) {
        _showSnack(
          '❌ Erro: $e',
          context.uai.error,
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  // 🔥 MÉTODO DE CARREGAR PERMISSÕES
  Future<Map<String, bool>> _carregarPermissoes() async {
    _log('CARREGANDO PERMISSÕES');

    try {
      final docRef = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(widget.userId)
          .collection('permissoes_usuario')
          .doc('configuracoes');

      final doc = await docRef.get();

      if (doc.exists) {
        final dados = doc.data()!;
        _log('✅ Documento encontrado!');
        return dados.map((key, value) => MapEntry(key, value as bool? ?? false));
      } else {
        _log('⚠️ Documento NÃO encontrado - retornando mapa vazio');
        return {};
      }
    } catch (e) {
      _log('❌ ERRO AO CARREGAR:', dados: e.toString());
      return {};
    }
  }

  // 🔥 LISTA CENTRAL DE PERMISSÕES
  //
  // IMPORTANTE:
  // - "chave" é a chave nova/padronizada.
  // - "aliases" mantém compatibilidade com chaves antigas que já existem no app/banco.
  // - Ao marcar/desmarcar uma permissão, a tela salva a chave nova e também os aliases.
  // - Isso evita quebrar telas antigas enquanto a refatoração avança arquivo por arquivo.
  final List<Map<String, dynamic>> _permissoesList = [
    // ===== VISIBILIDADE / TELAS =====
    {
      'titulo': 'Acessar eventos',
      'descricao': 'Mostra o menu Eventos e permite abrir a tela de eventos.',
      'chave': 'pode_acessar_eventos',
      'aliases': ['podeAcessarEventos', 'pode_ver_eventos'],
      'icone': Icons.event_rounded,
      'categoria': 'VISIBILIDADE',
    },
    {
      'titulo': 'Acessar inscrições',
      'descricao': 'Mostra o menu Inscrições no app.',
      'chave': 'pode_acessar_inscricoes',
      'aliases': ['podeAcessarInscricoes'],
      'icone': Icons.app_registration_rounded,
      'categoria': 'VISIBILIDADE',
    },
    {
      'titulo': 'Acessar uniformes',
      'descricao': 'Mostra o menu Uniformes no app.',
      'chave': 'pode_acessar_uniformes',
      'aliases': ['podeAcessarUniformes'],
      'icone': Icons.shopping_bag_rounded,
      'categoria': 'VISIBILIDADE',
    },
    {
      'titulo': 'Acessar associação',
      'descricao': 'Mostra o menu Associação no app.',
      'chave': 'pode_acessar_associacao',
      'aliases': ['podeAcessarAssociacao'],
      'icone': Icons.people_outline_rounded,
      'categoria': 'VISIBILIDADE',
    },
    {
      'titulo': 'Mostrar alunos na barra lateral',
      'descricao': 'Mostra o menu Alunos na barra lateral do app. Não substitui a permissão de ver alunos.',
      'chave': 'pode_mostrar_alunos_drawer',
      'aliases': ['podeMostrarAlunosDrawer'],
      'icone': Icons.menu_open_rounded,
      'categoria': 'VISIBILIDADE',
    },

    {
      'titulo': 'Acessar rifas',
      'descricao': 'Mostra o menu Rifas no app.',
      'chave': 'pode_acessar_rifas',
      'aliases': ['podeAcessarRifas'],
      'icone': Icons.confirmation_number_rounded,
      'categoria': 'VISIBILIDADE',
    },

    // ===== EVENTOS — GERAL =====
    {
      'titulo': 'Ver eventos',
      'descricao': 'Permite visualizar a lista de eventos.',
      'chave': 'pode_ver_eventos',
      'aliases': ['podeAcessarEventos', 'pode_acessar_eventos'],
      'icone': Icons.visibility_rounded,
      'categoria': 'EVENTOS — GERAL',
    },
    {
      'titulo': 'Ver eventos em andamento',
      'descricao': 'Permite abrir eventos em andamento.',
      'chave': 'pode_ver_eventos_andamento',
      'aliases': [],
      'icone': Icons.pending_actions_rounded,
      'categoria': 'EVENTOS — GERAL',
    },
    {
      'titulo': 'Criar evento',
      'descricao': 'Permite criar novos eventos.',
      'chave': 'pode_criar_evento',
      'aliases': [],
      'icone': Icons.add_circle_rounded,
      'categoria': 'EVENTOS — GERAL',
    },
    {
      'titulo': 'Editar evento',
      'descricao': 'Permite editar dados de eventos existentes.',
      'chave': 'pode_editar_evento',
      'aliases': [],
      'icone': Icons.edit_calendar_rounded,
      'categoria': 'EVENTOS — GERAL',
    },
    {
      'titulo': 'Excluir evento',
      'descricao': 'Permite excluir eventos.',
      'chave': 'pode_excluir_evento',
      'aliases': [],
      'icone': Icons.delete_forever_rounded,
      'categoria': 'EVENTOS — GERAL',
    },
    {
      'titulo': 'Finalizar evento',
      'descricao': 'Permite finalizar evento em andamento.',
      'chave': 'pode_finalizar_evento',
      'aliases': [],
      'icone': Icons.check_circle_rounded,
      'categoria': 'EVENTOS — GERAL',
    },

    // ===== EVENTOS — PARTICIPANTES =====
    {
      'titulo': 'Gerenciar participantes',
      'descricao': 'Permite abrir o módulo de participantes do evento.',
      'chave': 'pode_gerenciar_participantes_evento',
      'aliases': ['pode_gerenciar_participantes'],
      'icone': Icons.groups_rounded,
      'categoria': 'EVENTOS — PARTICIPANTES',
    },
    {
      'titulo': 'Adicionar participante',
      'descricao': 'Permite adicionar alunos ao evento.',
      'chave': 'pode_adicionar_participante_evento',
      'aliases': ['pode_adcionar_aluno_a_eventos', 'pode_adicionar_aluno_a_eventos'],
      'icone': Icons.person_add_alt_1_rounded,
      'categoria': 'EVENTOS — PARTICIPANTES',
    },
    {
      'titulo': 'Editar participação',
      'descricao': 'Permite editar dados de participação do aluno no evento.',
      'chave': 'pode_editar_participacao_evento',
      'aliases': ['pode_editar_participante_evento'],
      'icone': Icons.manage_accounts_rounded,
      'categoria': 'EVENTOS — PARTICIPANTES',
    },
    {
      'titulo': 'Remover participante',
      'descricao': 'Permite remover alunos do evento.',
      'chave': 'pode_remover_participante_evento',
      'aliases': ['pode_remover_alunos_de_eventos'],
      'icone': Icons.person_remove_rounded,
      'categoria': 'EVENTOS — PARTICIPANTES',
    },
    {
      'titulo': 'Concluir participação',
      'descricao': 'Permite marcar/concluir participação do aluno no evento.',
      'chave': 'pode_concluir_participacao_evento',
      'aliases': [],
      'icone': Icons.done_all_rounded,
      'categoria': 'EVENTOS — PARTICIPANTES',
    },

    // ===== EVENTOS — PAGAMENTOS =====
    {
      'titulo': 'Registrar pagamento',
      'descricao': 'Permite lançar pagamentos na participação do aluno.',
      'chave': 'pode_registrar_pagamento_evento',
      'aliases': ['pode_registrar_pagamento'],
      'icone': Icons.add_card_rounded,
      'categoria': 'EVENTOS — PAGAMENTOS',
    },
    {
      'titulo': 'Editar pagamento',
      'descricao': 'Permite corrigir valor, forma, status e observações de pagamentos já lançados.',
      'chave': 'pode_editar_pagamento_evento',
      'aliases': ['pode_editar_pagamento'],
      'icone': Icons.edit_note_rounded,
      'categoria': 'EVENTOS — PAGAMENTOS',
    },
    {
      'titulo': 'Excluir pagamento',
      'descricao': 'Permite apagar pagamentos e recalcular o saldo da participação.',
      'chave': 'pode_excluir_pagamento_evento',
      'aliases': ['pode_excluir_pagamento'],
      'icone': Icons.delete_sweep_rounded,
      'categoria': 'EVENTOS — PAGAMENTOS',
    },

    // ===== EVENTOS — FINANCEIRO / MÓDULOS =====
    {
      'titulo': 'Gerenciar gastos',
      'descricao': 'Permite adicionar, editar e excluir gastos do evento.',
      'chave': 'pode_gerenciar_gastos_evento',
      'aliases': ['pode_gerenciar_financeiro', 'pode_gerenciar_taxas'],
      'icone': Icons.payments_rounded,
      'categoria': 'EVENTOS — FINANCEIRO',
    },
    {
      'titulo': 'Gerenciar patrocinadores',
      'descricao': 'Permite gerenciar patrocinadores e apoios do evento.',
      'chave': 'pode_gerenciar_patrocinadores_evento',
      'aliases': ['pode_gerenciar_patrocinadores'],
      'icone': Icons.handshake_rounded,
      'categoria': 'EVENTOS — FINANCEIRO',
    },
    {
      'titulo': 'Gerenciar camisas',
      'descricao': 'Permite gerenciar camisas, pagamentos e entregas.',
      'chave': 'pode_gerenciar_camisas_evento',
      'aliases': ['pode_gerenciar_camisas'],
      'icone': Icons.checkroom_rounded,
      'categoria': 'EVENTOS — FINANCEIRO',
    },
    {
      'titulo': 'Ver relatórios do evento',
      'descricao': 'Permite abrir relatórios financeiros e listas do evento.',
      'chave': 'pode_ver_relatorio_evento',
      'aliases': ['pode_ver_relatorios'],
      'icone': Icons.assessment_rounded,
      'categoria': 'EVENTOS — FINANCEIRO',
    },
    {
      'titulo': 'Gerar certificados',
      'descricao': 'Permite gerar certificados do evento.',
      'chave': 'pode_gerar_certificados_evento',
      'aliases': ['pode_gerar_certificados'],
      'icone': Icons.card_membership_rounded,
      'categoria': 'EVENTOS — FINANCEIRO',
    },

    // ===== ALUNOS =====
    {
      'titulo': 'Adicionar aluno',
      'descricao': 'Permite adicionar novos alunos.',
      'chave': 'pode_adicionar_aluno',
      'aliases': [],
      'icone': Icons.person_add_rounded,
      'categoria': 'ALUNOS',
    },
    {
      'titulo': 'Visualizar alunos',
      'descricao': 'Permite ver lista de alunos.',
      'chave': 'pode_visualizar_alunos',
      'aliases': [],
      'icone': Icons.visibility_rounded,
      'categoria': 'ALUNOS',
    },
    {
      'titulo': 'Editar aluno',
      'descricao': 'Permite editar informações de alunos.',
      'chave': 'pode_editar_aluno',
      'aliases': [],
      'icone': Icons.edit_rounded,
      'categoria': 'ALUNOS',
    },
    {
      'titulo': 'Excluir aluno',
      'descricao': 'Permite excluir alunos.',
      'chave': 'pode_excluir_aluno',
      'aliases': [],
      'icone': Icons.delete_rounded,
      'categoria': 'ALUNOS',
    },
    {
      'titulo': 'Desativar aluno',
      'descricao': 'Permite tornar alunos inativos.',
      'chave': 'pode_desativar_aluno',
      'aliases': [],
      'icone': Icons.person_off_rounded,
      'categoria': 'ALUNOS',
    },
    {
      'titulo': 'Ativar aluno',
      'descricao': 'Permite reativar alunos inativos.',
      'chave': 'pode_ativar_alunos',
      'aliases': [],
      'icone': Icons.person_add_alt_rounded,
      'categoria': 'ALUNOS',
    },
    {
      'titulo': 'Mudar turma',
      'descricao': 'Permite transferir alunos entre turmas.',
      'chave': 'pode_mudar_turma',
      'aliases': [],
      'icone': Icons.switch_account_rounded,
      'categoria': 'ALUNOS',
    },
    {
      'titulo': 'Ver resumo da turma',
      'descricao': 'Libera o card “Resumo da turma” com estatísticas e relatórios dos alunos da turma.',
      'chave': 'pode_visualizar_relatorios',
      'aliases': ['pode_visualizar_relatorios_turma'],
      'icone': Icons.summarize_rounded,
      'categoria': 'ALUNOS',
    },

    // ===== CHAMADA / AVALIAÇÕES =====
    {
      'titulo': 'Fazer chamada',
      'descricao': 'Permite registrar chamada.',
      'chave': 'pode_fazer_chamada',
      'aliases': [],
      'icone': Icons.checklist_rounded,
      'categoria': 'CHAMADA E AVALIAÇÕES',
    },
    {
      'titulo': 'Editar chamada',
      'descricao': 'Permite editar chamadas.',
      'chave': 'pode_editar_chamada',
      'aliases': [],
      'icone': Icons.edit_calendar_rounded,
      'categoria': 'CHAMADA E AVALIAÇÕES',
    },
    {
      'titulo': 'Ver lista de chamada',
      'descricao': 'Permite ver histórico de chamadas.',
      'chave': 'pode_ver_lista_de_chamada',
      'aliases': [],
      'icone': Icons.list_alt_rounded,
      'categoria': 'CHAMADA E AVALIAÇÕES',
    },
    {
      'titulo': 'Avaliar aluno',
      'descricao': 'Permite avaliar comportamento, disciplina e evolução.',
      'chave': 'pode_avaliar_aluno',
      'aliases': [],
      'icone': Icons.star_rate_rounded,
      'categoria': 'CHAMADA E AVALIAÇÕES',
    },

    // ===== USUÁRIOS =====
    {
      'titulo': 'Gerenciar usuários',
      'descricao': 'Permite gerenciar usuários e permissões.',
      'chave': 'pode_gerenciar_usuarios',
      'aliases': [],
      'icone': Icons.people_rounded,
      'categoria': 'USUÁRIOS',
    },

    // ===== UNIFORMES =====
    {
      'titulo': 'Editar vendas',
      'descricao': 'Permite editar vendas de uniformes.',
      'chave': 'pode_editar_venda',
      'aliases': [],
      'icone': Icons.edit_rounded,
      'categoria': 'UNIFORMES',
    },
    {
      'titulo': 'Excluir vendas',
      'descricao': 'Permite excluir vendas de uniformes.',
      'chave': 'pode_excluir_venda',
      'aliases': [],
      'icone': Icons.delete_forever_rounded,
      'categoria': 'UNIFORMES',
    },
    {
      'titulo': 'Editar pedidos',
      'descricao': 'Permite editar pedidos.',
      'chave': 'pode_editar_pedido',
      'aliases': [],
      'icone': Icons.edit_note_rounded,
      'categoria': 'UNIFORMES',
    },
    {
      'titulo': 'Excluir pedidos',
      'descricao': 'Permite excluir pedidos.',
      'chave': 'pode_excluir_pedido',
      'aliases': [],
      'icone': Icons.delete_sweep_rounded,
      'categoria': 'UNIFORMES',
    },
    {
      'titulo': 'Gerenciar estoque',
      'descricao': 'Permite gerenciar estoque.',
      'chave': 'pode_gerenciar_estoque',
      'aliases': [],
      'icone': Icons.inventory_rounded,
      'categoria': 'UNIFORMES',
    },
  ];

  List<String> _chavesVinculadas(Map<String, dynamic> permissao) {
    final chave = permissao['chave']?.toString() ?? '';
    final aliasesRaw = permissao['aliases'];

    final aliases = aliasesRaw is List
        ? aliasesRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : <String>[];

    return {
      if (chave.isNotEmpty) chave,
      ...aliases,
    }.toList();
  }

  bool _permissaoMarcada(
      Map<String, dynamic> permissao,
      Map<String, bool> permissoesTemp,
      ) {
    return _chavesVinculadas(permissao).any((chave) => permissoesTemp[chave] == true);
  }

  void _setPermissaoMarcada(
      Map<String, dynamic> permissao,
      bool valor,
      Map<String, bool> permissoesTemp,
      ) {
    for (final chave in _chavesVinculadas(permissao)) {
      permissoesTemp[chave] = valor;
    }
  }

  // 🔥 MÉTODO PARA MOSTRAR DIÁLOGO DE PERMISSÕES
  Future<void> _mostrarDialogPermissoes(BuildContext context) async {
    _log('ABRINDO DIÁLOGO DE PERMISSÕES');

    final permissoesAtuais = await _carregarPermissoes();
    _log('Permissões atuais carregadas:', dados: permissoesAtuais);

    // Agrupa permissões por categoria
    final Map<String, List<Map<String, dynamic>>> permissoesPorCategoria = {};
    for (var permissao in _permissoesList) {
      final categoria = permissao['categoria'] as String;
      if (!permissoesPorCategoria.containsKey(categoria)) {
        permissoesPorCategoria[categoria] = [];
      }
      permissoesPorCategoria[categoria]!.add(permissao);
    }

    // Lista de categorias ordenadas
    final List<String> categorias = [
      'VISIBILIDADE',
      'ALUNOS',
      'CHAMADA E AVALIAÇÕES',
      'EVENTOS — GERAL',
      'EVENTOS — PARTICIPANTES',
      'EVENTOS — PAGAMENTOS',
      'EVENTOS — FINANCEIRO',
      'USUÁRIOS',
      'UNIFORMES',
    ];

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final t = context.uai;
        final onPrimary = _readableOn(t.primary);
        final Map<String, bool> permissoesTemp = {
          ...permissoesAtuais,
        };

        for (final p in _permissoesList) {
          final marcado = _permissaoMarcada(p, permissoesTemp);
          _setPermissaoMarcada(p, marcado, permissoesTemp);
        }

        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              backgroundColor: Colors.transparent,
              child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(t.cardRadius),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(t.cardRadius),
                  child: Column(
                    children: [
                      // Header do Dialog
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(gradient: t.primaryGradient),
                        child: Row(
                          children: [
                            Icon(Icons.security, color: onPrimary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Permissões Individuais',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: onPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: onPrimary),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),

                      // Grid de Permissões
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: GridView.builder(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: MediaQuery.of(context).size.width < 760 ? 1 : 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: MediaQuery.of(context).size.width < 760 ? 1.45 : 0.92,
                            ),
                            itemCount: categorias.length,
                            itemBuilder: (context, index) {
                              final categoria = categorias[index];
                              final permissoesDaCategoria = permissoesPorCategoria[categoria] ?? [];

                              return _buildCategoriaCard(
                                categoria: categoria,
                                permissoes: permissoesDaCategoria,
                                permissoesTemp: permissoesTemp,
                                onChanged: (chave, valor) {
                                  setState(() {
                                    final permissao = permissoesDaCategoria.firstWhere(
                                          (p) => p['chave'] == chave,
                                      orElse: () => {'chave': chave, 'aliases': []},
                                    );
                                    _setPermissaoMarcada(permissao, valor, permissoesTemp);
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ),

                      // Botão Salvar
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: t.card,
                          border: Border(top: BorderSide(color: t.border)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancelar'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                await _salvarPermissoes(context, permissoesTemp);
                              },
                              child: Text('Salvar Permissões'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 🎨 Widget para o Card de Categoria
  Widget _buildCategoriaCard({
    required String categoria,
    required List<Map<String, dynamic>> permissoes,
    required Map<String, bool> permissoesTemp,
    required Function(String, bool) onChanged,
  }) {
    final t = context.uai;

    Color getCorCategoria(String categoria) {
      if (categoria == 'VISIBILIDADE') return t.associacao;
      if (categoria == 'ALUNOS') return t.uniformes;
      if (categoria.contains('CHAMADA')) return t.warning;
      if (categoria.contains('GERAL')) return t.inscricoes;
      if (categoria.contains('PARTICIPANTES')) return t.info;
      if (categoria.contains('PAGAMENTOS')) return t.warning;
      if (categoria.contains('FINANCEIRO')) return t.success;
      if (categoria == 'USUÁRIOS') return t.error;
      if (categoria == 'UNIFORMES') return t.accent;
      return t.primary;
    }

    IconData getIconCategoria(String categoria) {
      if (categoria == 'VISIBILIDADE') return Icons.visibility_rounded;
      if (categoria.contains('GERAL')) return Icons.event_rounded;
      if (categoria.contains('PARTICIPANTES')) return Icons.groups_rounded;
      if (categoria.contains('PAGAMENTOS')) return Icons.add_card_rounded;
      if (categoria.contains('FINANCEIRO')) return Icons.payments_rounded;
      if (categoria == 'ALUNOS') return Icons.people_rounded;
      if (categoria.contains('CHAMADA')) return Icons.fact_check_rounded;
      if (categoria == 'USUÁRIOS') return Icons.admin_panel_settings_rounded;
      if (categoria == 'UNIFORMES') return Icons.shopping_bag_rounded;
      return Icons.category_rounded;
    }

    final corCategoria = getCorCategoria(categoria);

    return Card(
      color: t.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.cardRadius),
        side: BorderSide(color: t.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: corCategoria.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                    border: Border.all(color: corCategoria.withOpacity(0.20)),
                  ),
                  child: Icon(
                    getIconCategoria(categoria),
                    size: 17,
                    color: corCategoria,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getNomeCategoriaAmigavel(categoria),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: t.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: permissoes.map((permissao) {
                    final chave = permissao['chave'].toString();
                    final marcado = _permissaoMarcada(permissao, permissoesTemp);
                    final descricao = permissao['descricao']?.toString() ?? '';
                    final icon = permissao['icone'] as IconData? ?? Icons.security_rounded;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => onChanged(chave, !marcado),
                        borderRadius: BorderRadius.circular(t.buttonRadius),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                          decoration: BoxDecoration(
                            color: marcado
                                ? corCategoria.withOpacity(0.13)
                                : t.cardAlt.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                            border: Border.all(
                              color: marcado
                                  ? corCategoria.withOpacity(0.35)
                                  : t.border,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                marcado
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 17,
                                color: marcado ? corCategoria : t.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                icon,
                                size: 16,
                                color: marcado ? corCategoria : t.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      permissao['titulo'].toString(),
                                      style: TextStyle(
                                        fontSize: 11.4,
                                        height: 1.12,
                                        fontWeight:
                                        marcado ? FontWeight.w800 : FontWeight.w600,
                                        color: marcado ? corCategoria : t.textPrimary,
                                      ),
                                    ),
                                    if (descricao.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        descricao,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 9.6,
                                          height: 1.15,
                                          color: t.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getNomeCategoriaAmigavel(String categoria) {
    switch (categoria) {
      case 'VISIBILIDADE':
        return 'Telas / Acesso';
      case 'EVENTOS — GERAL':
        return 'Eventos — Geral';
      case 'EVENTOS — PARTICIPANTES':
        return 'Eventos — Participantes';
      case 'EVENTOS — PAGAMENTOS':
        return 'Eventos — Pagamentos';
      case 'EVENTOS — FINANCEIRO':
        return 'Eventos — Financeiro';
      case 'CHAMADA E AVALIAÇÕES':
        return 'Chamada / Avaliações';
      case 'USUÁRIOS':
        return 'Usuários';
      case 'UNIFORMES':
        return 'Uniformes';
      default:
        return categoria.replaceAll('AÇÕES - ', '');
    }
  }

  void _mostrarDialogDocumentoNaoEncontrado(BuildContext context, String caminho) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('🔍 Diagnóstico'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DOCUMENTO NÃO ENCONTRADO!',
                style: TextStyle(fontWeight: FontWeight.bold, color: context.uai.error)),
            const SizedBox(height: 16),
            Text('Caminho: $caminho'),
            SizedBox(height: 8),
            Text('Possíveis causas:'),
            Text('• Nunca salvou permissões para este usuário'),
            Text('• Erro ao salvar (verifique regras do Firestore)'),
            Text('• Usuário sem permissões configuradas'),
            SizedBox(height: 16),
            Text('Solução: Tente salvar as permissões primeiro!'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Fechar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _mostrarDialogPermissoes(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.primary,
            ),
            child: Text('Configurar Agora'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogDiagnostico(BuildContext context, DocumentSnapshot doc, Map<String, dynamic>? dados) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('🔍 Diagnóstico de Permissões'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('DOCUMENTO ENCONTRADO!',
                  style: TextStyle(fontWeight: FontWeight.bold, color: context.uai.success)),
              const SizedBox(height: 16),
              Text('Caminho: usuarios/${widget.userId}/permissoes_usuario/configuracoes'),
              const SizedBox(height: 8),
              Text('Existe: ${doc.exists}'),
              const SizedBox(height: 16),
              const Text('DADOS SALVOS:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              ...?dados?.entries.map((e) =>
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${e.key}:',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: e.value == true ? context.uai.success.withOpacity(0.16) : context.uai.error.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            e.value.toString(),
                            style: TextStyle(
                              color: e.value == true ? context.uai.success : context.uai.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
              ).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Fechar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _mostrarDialogPermissoes(context);
            },
            child: Text('Editar Permissões'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(
          'Detalhes do Usuário',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_rounded),
            onPressed: () => _diagnosticarPermissoesCompleto(context),
            tooltip: 'Diagnosticar permissões',
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditarUsuarioScreen(userId: widget.userId),
                ),
              );
            },
            tooltip: 'Editar usuário',
          ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('usuarios')
            .doc(widget.userId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState('Carregando usuário...');
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _buildEmptyState();
          }

          final data = snapshot.data!.data()!;
          final fotoUrl = data['foto_url'] as String?;
          final nomeCompleto =
              data['nome_completo'] ?? data['name'] ?? 'Nome não informado';
          final email = data['email'] ?? 'Email não informado';
          final tipo = data['tipo'] ?? 'Tipo não informado';
          final pesoPermissao = data['peso_permissao'] ?? 0;
          final statusConta = data['status_conta'] ?? 'pendente';
          final contato = data['contato'] ?? 'Contato não informado';
          final dataCadastro = data['data_cadastro'] as Timestamp?;
          final ultimaAtualizacao = data['ultima_atualizacao'] as Timestamp?;
          final aprovadoEm = data['aprovado_em'] as Timestamp?;
          final aprovadoPor = data['aprovado_por'] as String?;
          final aprovadoPorNome = data['aprovado_por_nome'] as String?;

          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final wide = constraints.maxWidth >= 960;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 20,
                  compact ? 12 : 18,
                  compact ? 12 : 20,
                  28,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildUserHero(
                          fotoUrl: fotoUrl,
                          nome: nomeCompleto.toString(),
                          email: email.toString(),
                          tipo: tipo.toString(),
                          status: statusConta.toString(),
                          peso: pesoPermissao,
                          compact: compact,
                        ),
                        const SizedBox(height: 14),
                        _buildActionStrip(compact),
                        const SizedBox(height: 14),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Column(
                                  children: [
                                    _buildAccessCard(
                                      tipo: tipo.toString(),
                                      peso: pesoPermissao,
                                    ),
                                    const SizedBox(height: 14),
                                    _buildContactCard(
                                      contato: contato.toString(),
                                      email: email.toString(),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 4,
                                child: Column(
                                  children: [
                                    _buildStatusCard(statusConta.toString()),
                                    const SizedBox(height: 14),
                                    _buildDatesCard(
                                      dataCadastro: dataCadastro,
                                      ultimaAtualizacao: ultimaAtualizacao,
                                      aprovadoEm: aprovadoEm,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else ...[
                          _buildStatusCard(statusConta.toString()),
                          const SizedBox(height: 14),
                          _buildAccessCard(
                            tipo: tipo.toString(),
                            peso: pesoPermissao,
                          ),
                          const SizedBox(height: 14),
                          _buildContactCard(
                            contato: contato.toString(),
                            email: email.toString(),
                          ),
                          const SizedBox(height: 14),
                          _buildDatesCard(
                            dataCadastro: dataCadastro,
                            ultimaAtualizacao: ultimaAtualizacao,
                            aprovadoEm: aprovadoEm,
                          ),
                        ],
                        if (aprovadoPor != null || aprovadoPorNome != null) ...[
                          SizedBox(height: 14),
                          _buildApprovalCard(
                            aprovadoPor: aprovadoPor,
                            aprovadoPorNome: aprovadoPorNome,
                          ),
                        ],
                        SizedBox(height: 14),
                        _buildIdCard(),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildUserHero({
    required String? fotoUrl,
    required String nome,
    required String email,
    required String tipo,
    required String status,
    required int peso,
    required bool compact,
  }) {
    final t = context.uai;
    final tipoColor = _getTipoColor(tipo);
    final statusColor = _getStatusColor(status);
    final inicial = nome.trim().isNotEmpty ? nome.trim().substring(0, 1).toUpperCase() : '?';
    final onPrimary = _onHeroGradient();

    return Container(
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(compact ? 26 : 32),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;

          final avatar = Container(
            width: compact ? 94 : 118,
            height: compact ? 94 : 118,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(compact ? 32 : 40),
              border: Border.all(color: onPrimary.withOpacity(0.20), width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(compact ? 30 : 38),
              child: fotoUrl != null && fotoUrl.isNotEmpty
                  ? CachedNetworkImage(
                imageUrl: fotoUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Center(
                  child: CircularProgressIndicator(color: onPrimary),
                ),
                errorWidget: (context, url, error) => Center(
                  child: Text(
                    inicial,
                    style: TextStyle(
                      color: onPrimary,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              )
                  : Center(
                child: Text(
                  inicial,
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          );

          final info = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                nome,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: compact ? 24 : 33,
                  height: 1.04,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                email,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: compact ? 12.5 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _whiteChip(_getTipoIcon(tipo), tipo.toUpperCase()),
                  _whiteChip(Icons.security_rounded, 'PESO $peso'),
                  _whiteChip(Icons.circle, _formatStatus(status).toUpperCase()),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [avatar, SizedBox(height: 14), info],
            );
          }

          return Row(
            children: [
              avatar,
              SizedBox(width: 18),
              Expanded(child: info),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: tipoColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.22)),
                ),
                child: Icon(_getTipoIcon(tipo), color: onPrimary, size: 30),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _whiteChip(IconData icon, String label) {
    final t = context.uai;
    final onPrimary = _onHeroGradient();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 14),
          SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionStrip(bool compact) {
    final t = context.uai;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tiny = constraints.maxWidth < 420;

        final permissions = ElevatedButton.icon(
          onPressed: () => _mostrarDialogPermissoes(context),
          icon: Icon(Icons.security_rounded),
          label: Text('PERMISSÕES'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
            foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
            padding: const EdgeInsets.symmetric(vertical: 13),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );

        final edit = OutlinedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EditarUsuarioScreen(userId: widget.userId),
              ),
            );
          },
          icon: const Icon(Icons.edit_rounded),
          label: const Text('EDITAR'),
          style: OutlinedButton.styleFrom(
            foregroundColor: t.textPrimary,
            side: BorderSide(color: t.border),
            padding: const EdgeInsets.symmetric(vertical: 13),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );

        final diagnostic = OutlinedButton.icon(
          onPressed: () => _diagnosticarPermissoesCompleto(context),
          icon: const Icon(Icons.bug_report_rounded),
          label: const Text('DIAGNÓSTICO'),
          style: OutlinedButton.styleFrom(
            foregroundColor: t.info,
            side: BorderSide(color: t.info.withOpacity(0.25)),
            padding: const EdgeInsets.symmetric(vertical: 13),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );

        if (tiny) {
          return Column(
            children: [
              SizedBox(width: double.infinity, child: permissions),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: edit),
                  const SizedBox(width: 8),
                  Expanded(child: diagnostic),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(flex: 2, child: permissions),
            const SizedBox(width: 8),
            Expanded(child: edit),
            const SizedBox(width: 8),
            Expanded(child: diagnostic),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard(String status) {
    final color = _getStatusColor(status);

    return _premiumCard(
      title: 'Status da conta',
      icon: Icons.account_circle_rounded,
      color: color,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.09),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: color.withOpacity(0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, color: color, size: 13),
              SizedBox(width: 7),
              Text(
                _formatStatus(status).toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccessCard({
    required String tipo,
    required int peso,
  }) {
    final isAdmin = peso >= 90;
    final color = isAdmin ? context.uai.error : context.uai.info;

    return _premiumCard(
      title: 'Acesso e permissões',
      icon: Icons.admin_panel_settings_rounded,
      color: color,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.08),
                  color.withOpacity(0.14),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.14)),
            ),
            child: Row(
              children: [
                Icon(
                  isAdmin ? Icons.stars_rounded : Icons.security_rounded,
                  color: color,
                  size: 38,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAdmin ? 'Acesso administrativo' : 'Permissão personalizada',
                        style: TextStyle(
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Tipo: ${tipo.toUpperCase()} • Peso $peso/100',
                        style: TextStyle(
                          color: color,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!isAdmin) ...[
            SizedBox(height: 10),
            Text(
              'Configure permissões específicas no botão “Permissões”.',
              style: TextStyle(
                color: context.uai.textSecondary,
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContactCard({
    required String contato,
    required String email,
  }) {
    return _premiumCard(
      title: 'Contato',
      icon: Icons.contact_phone_rounded,
      color: context.uai.success,
      child: Column(
        children: [
          _infoLine(Icons.phone_rounded, 'Telefone/WhatsApp', contato),
          Divider(height: 20, color: context.uai.border),
          _infoLine(Icons.email_rounded, 'E-mail', email),
        ],
      ),
    );
  }

  Widget _buildDatesCard({
    required Timestamp? dataCadastro,
    required Timestamp? ultimaAtualizacao,
    required Timestamp? aprovadoEm,
  }) {
    return _premiumCard(
      title: 'Registros',
      icon: Icons.event_note_rounded,
      color: context.uai.warning,
      child: Column(
        children: [
          _infoLine(Icons.calendar_today_rounded, 'Data de cadastro', _formatTimestamp(dataCadastro)),
          Divider(height: 20, color: context.uai.border),
          _infoLine(Icons.update_rounded, 'Última atualização', _formatTimestamp(ultimaAtualizacao)),
          if (aprovadoEm != null) ...[
            Divider(height: 20, color: context.uai.border),
            _infoLine(Icons.verified_rounded, 'Aprovado em', _formatTimestamp(aprovadoEm)),
          ],
        ],
      ),
    );
  }

  Widget _buildApprovalCard({
    required String? aprovadoPor,
    required String? aprovadoPorNome,
  }) {
    return _premiumCard(
      title: 'Aprovação',
      icon: Icons.verified_user_rounded,
      color: context.uai.associacao,
      child: Column(
        children: [
          if (aprovadoPorNome != null)
            _infoLine(Icons.person_rounded, 'Aprovado por', aprovadoPorNome),
          if (aprovadoPor != null) ...[
            if (aprovadoPorNome != null) Divider(height: 20, color: context.uai.border),
            _infoLine(Icons.fingerprint_rounded, 'ID do aprovador', '${aprovadoPor.substring(0, aprovadoPor.length > 8 ? 8 : aprovadoPor.length)}...'),
          ],
        ],
      ),
    );
  }

  Widget _buildIdCard() {
    return _premiumCard(
      title: 'Identificação',
      icon: Icons.fingerprint_rounded,
      color: context.uai.textMuted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            'ID: ${widget.userId}',
            style: TextStyle(
              color: context.uai.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Use este ID para referenciar o usuário em outros sistemas.',
            style: TextStyle(
              color: context.uai.textSecondary,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: color.withOpacity(0.18)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(title: title, icon: icon, color: color),
          SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _cardHeader({
    required String title,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.14)),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: context.uai.textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoLine(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: context.uai.textSecondary, size: 21),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: context.uai.textSecondary, fontSize: 11.5)),
              SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: context.uai.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState(String message) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: context.uai.card,
          borderRadius: BorderRadius.circular(context.uai.cardRadius),
          border: Border.all(color: context.uai.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: context.uai.primary),
            SizedBox(height: 14),
            Text(
              message,
              style: TextStyle(
                color: context.uai.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: context.uai.card,
          borderRadius: BorderRadius.circular(context.uai.cardRadius),
          border: Border.all(color: context.uai.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_rounded, size: 62, color: context.uai.textMuted),
            SizedBox(height: 12),
            Text(
              'Usuário não encontrado',
              style: TextStyle(
                color: context.uai.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusInfo(String title, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: context.uai.textSecondary,
          ),
        ),
        SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateInfo(String title, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: context.uai.info, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.uai.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}