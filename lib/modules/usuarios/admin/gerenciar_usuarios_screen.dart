import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/modules/usuarios/admin/central_identidades_screen.dart';
import 'package:uai_capoeira/modules/usuarios/admin/editar_usuario_screen.dart';
import 'package:uai_capoeira/modules/usuarios/admin/usuario_detalhe_screen.dart';
import 'package:uai_capoeira/modules/usuarios/admin/predefinicoes_permissoes_screen.dart';
import 'package:uai_capoeira/modules/usuarios/admin/solicitacoes_acesso_screen.dart';
import 'package:uai_capoeira/modules/usuarios/services/usuario_identidade_service.dart';
import 'package:uai_capoeira/modules/usuarios/services/usuario_status_service.dart';
import 'usuario_admin_access.dart';

class GerenciarUsuariosScreen extends StatefulWidget {
  const GerenciarUsuariosScreen({super.key});

  @override
  State<GerenciarUsuariosScreen> createState() =>
      _GerenciarUsuariosScreenState();
}

class _GerenciarUsuariosScreenState extends State<GerenciarUsuariosScreen> with TickerProviderStateMixin {
  late Future<UsuarioAdminAccess> _accessFuture;
  final UsuarioIdentidadeService _identidadeService = UsuarioIdentidadeService();
  final TextEditingController _buscaController = TextEditingController();
  bool _identificandoAreaAluno = false;
  String _filtroUsuarios = 'todos';
  Timer? _searchDebounce;
  late final AnimationController _entryController;
  late final AnimationController _shimmerController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _fadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _entryController.forward();
    _accessFuture = carregarAcessoGestaoUsuarios();
    _accessFuture.then((access) {
      if (!mounted || !access.liberado) return;
      _identificarContasAreaAluno(mostrarResultado: false);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _buscaController.dispose();
    _entryController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _identificarContasAreaAluno({bool mostrarResultado = true}) async {
    if (_identificandoAreaAluno) return;
    if (mounted) setState(() => _identificandoAreaAluno = true);
    try {
      final resultado = mostrarResultado
          ? await _identidadeService.forcarSincronizacao()
          : await _identidadeService.sincronizarSeNecessario();
      if (!mounted || !mostrarResultado || resultado == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resultado.vinculadosAreaAluno == 0
                ? 'Nenhum vínculo da Área do Aluno foi encontrado.'
                : '${resultado.somenteAreaAluno} conta(s) somente de aluno separada(s) da gestão e ${resultado.hibridos} conta(s) híbrida(s) preservada(s).',
          ),
          backgroundColor: context.uai.success,
        ),
      );
    } catch (e) {
      if (!mounted || !mostrarResultado) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível identificar as contas da Área do Aluno: $e',
          ),
          backgroundColor: context.uai.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _identificandoAreaAluno = false);
    }
  }

  Future<void> _marcarComoAreaAluno(
    BuildContext dialogContext,
    QueryDocumentSnapshot usuario,
  ) async {
    final data = usuario.data() as Map<String, dynamic>;
    final nome = _textoUsuario(data, ['nome_completo', 'nome', 'name'], 'Usuário');
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar como Área do Aluno'),
        content: Text(
          'A conta de $nome deixará de aparecer como solicitação administrativa. '
          'O vínculo do aluno não será excluído nem alterado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.school_rounded),
            label: const Text('É Área do Aluno'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _identidadeService.marcarComoAreaAluno(usuario.id);
      if (!mounted) return;
      if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$nome foi separado da gestão e mantido na Área do Aluno.'),
          backgroundColor: context.uai.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao classificar a conta: $e'),
          backgroundColor: context.uai.error,
        ),
      );
    }
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onHeroGradient() {
    // Header premium sempre precisa saltar do gradiente,
    // principalmente nos temas neon/café/tema do usuário.
    final readable = _readableOn(context.uai.primary);
    if (readable.computeLuminance() > 0.72) return readable;
    return const Color(0xFFF8FAFC);
  }

  String? _fotoUrlFromData(Map<String, dynamic> data) {
    final campos = [
      'foto_url',
      'fotoUrl',
      'photoURL',
      'photoUrl',
      'url_foto',
      'imagem_url',
      'imagemUrl',
      'foto_perfil',
      'foto_perfil_url',
      'fotoPerfilUrl',
      'foto_perfil_aluno',
      'avatar',
      'avatar_url',
    ];

    for (final campo in campos) {
      final raw = data[campo];
      if (raw == null) continue;

      final value = raw.toString().trim();
      if (value.isEmpty) continue;
      if (value.toLowerCase() == 'null') continue;

      return value;
    }

    return null;
  }

  DateTime? _dataCriacaoFromData(Map<String, dynamic> data) {
    const campos = [
      'criado_em',
      'createdAt',
      'data_criacao',
      'criadoEm',
      'data_cadastro',
    ];
    for (final campo in campos) {
      final value = data[campo];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String && value.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  String _formatarDataCriacao(Map<String, dynamic> data) {
    final date = _dataCriacaoFromData(data);
    if (date == null) return 'Data de criacao nao informada';
    final local = date.toLocal();
    final now = DateTime.now();
    final hora =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return 'Criado hoje as $hora';
    }
    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');
    return 'Criado em $dia/$mes/${local.year} as $hora';
  }

  String _textoUsuario(
    Map<String, dynamic> data,
    List<String> campos,
    String fallback,
  ) {
    for (final campo in campos) {
      final value = data[campo]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return fallback;
  }

  List<QueryDocumentSnapshot> _usuariosList = [];
  int _pendentesCount = 0;

  // Exclusão física de usuários foi removida.
  // Contas administrativas devem ser bloqueadas/inativadas para preservar
  // histórico, vínculos e referências de auditoria.

  // Função para mostrar usuários pendentes
  void _showPendingUsersDialog(
    BuildContext context,
    List<QueryDocumentSnapshot> pendentes,
    bool canApprove,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SolicitacoesAcessoScreen(canApprove: canApprove),
      ),
    );
  }

  // Função para confirmar rejeição
  void _showRejectConfirmation(
    BuildContext context,
    String userId,
    String nome,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Rejeitar Usuário'),
          content: Text(
            "Deseja realmente rejeitar o usuário \"$nome\"?\n\nA solicitação será encerrada sem apagar a identidade, vínculos ou histórico.",
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: context.uai.error),
              child: Text('Rejeitar'),
              onPressed: () async {
                // Fecha o diálogo de confirmação
                Navigator.of(context).pop();

                try {
                  await UsuarioStatusService.alterarStatus(
                    userId: userId,
                    novoStatus: 'rejeitada',
                    atorNome: 'Administrador',
                  );

                  // Mostrar mensagem de sucesso
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Usuário "$nome" rejeitado com sucesso!'),
                        backgroundColor: context.uai.error,
                      ),
                    );
                  }

                  // Fecha o diálogo de pendentes se ainda estiver aberto
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao rejeitar usuário: $e'),
                        backgroundColor: context.uai.error,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showInactiveUsersDialog(BuildContext context) {
    final inactiveUsers = _usuariosList.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status_conta']?.toString().toLowerCase() ?? '';
      return status == 'inativa' || status == 'bloqueada';
    }).toList();

    if (inactiveUsers.isEmpty) {
      _showPremiumSnack(
        'Nenhum usuário inativo ou bloqueado.',
        icon: Icons.verified_user_rounded,
        color: context.uai.success,
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: context.uai.background,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                border: Border.all(color: context.uai.border.withAlpha(140)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.uai.textMuted.withAlpha(89),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: context.uai.error.withAlpha(26),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.person_off_rounded, color: context.uai.error),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Inativos e bloqueados',
                                style: TextStyle(
                                  color: context.uai.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                '${inactiveUsers.length} conta${inactiveUsers.length == 1 ? '' : 's'} preservada${inactiveUsers.length == 1 ? '' : 's'}',
                                style: TextStyle(
                                  color: context.uai.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                      itemCount: inactiveUsers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final usuario = inactiveUsers[index];
                        final data = usuario.data() as Map<String, dynamic>;
                        final nome = _textoUsuario(data, ['nome_completo', 'nome', 'name'], 'Usuário');
                        final email = _textoUsuario(data, ['email'], 'E-mail não informado');
                        final status = data['status_conta']?.toString() ?? 'inativa';
                        final color = _getStatusColor(status);
                        return Material(
                          color: context.uai.card,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => UsuarioDetalheScreen(userId: usuario.id),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  _buildUserAvatar(
                                    nome: nome,
                                    fotoUrl: _fotoUrlFromData(data),
                                    color: color,
                                    size: 44,
                                    inicial: nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(nome, style: TextStyle(color: context.uai.textPrimary, fontWeight: FontWeight.w900)),
                                        const SizedBox(height: 2),
                                        Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.uai.textSecondary, fontSize: 11.5)),
                                      ],
                                    ),
                                  ),
                                  _buildMiniBadge(
                                    label: status.toUpperCase(),
                                    color: color,
                                    icon: Icons.block_rounded,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showPremiumSnack(
    String message, {
    required IconData icon,
    required Color color,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: Colors.transparent,
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: context.uai.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withAlpha(71)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(31),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: context.uai.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ativa':
        return context.uai.success;
      case 'pendente':
        return context.uai.warning;
      case 'bloqueada':
      case 'inativa':
        return context.uai.error;
      default:
        return context.uai.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UsuarioAdminAccess>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return buildLoadingGestaoUsuarios(context);
        }

        final access = snapshot.data;
        if (snapshot.hasError || access == null || !access.liberado) {
          return buildAcessoNegadoGestaoUsuarios(context);
        }

        return FadeTransition(
          opacity: _fadeAnimation,
          child: _buildConteudoAutorizado(context, access),
        );
      },
    );
  }

  Widget _buildConteudoAutorizado(
    BuildContext context,
    UsuarioAdminAccess access,
  ) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text('Usuários', style: TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: true,
        backgroundColor:
            Theme.of(context).appBarTheme.backgroundColor ??
            context.uai.primary,
        foregroundColor:
            Theme.of(context).appBarTheme.foregroundColor ??
            _readableOn(
              Theme.of(context).appBarTheme.backgroundColor ??
                  context.uai.primary,
            ),
        elevation: 0,
        actions: [
          _buildPendingActionButton(access.adminMaster),
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              switch (value) {
                case 'predefinicoes':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PredefinicoesPermissoesScreen(),
                    ),
                  );
                  break;
                case 'identidades':
                  if (!_identificandoAreaAluno) {
                    _identificarContasAreaAluno();
                  }
                  break;
                case 'inativos':
                  _showInactiveUsersDialog(context);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'predefinicoes',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.tune_rounded),
                  title: Text('Predefinições'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'identidades',
                enabled: !_identificandoAreaAluno,
                child: ListTile(
                  dense: true,
                  leading: _identificandoAreaAluno
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.manage_search_rounded),
                  title: const Text('Revisar identidades'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'inativos',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.people_outline_rounded),
                  title: Text('Inativos e bloqueados'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_add_usuario',
        tooltip: 'Novo usuário',
        backgroundColor:
            Theme.of(context).appBarTheme.backgroundColor ??
            context.uai.primary,
        foregroundColor:
            Theme.of(context).appBarTheme.foregroundColor ??
            _readableOn(
              Theme.of(context).appBarTheme.backgroundColor ??
                  context.uai.primary,
            ),
        child: const Icon(Icons.person_add_alt_1_rounded),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const EditarUsuarioScreen(),
            ),
          );
        },
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('usuarios')
            .doc(currentUser!.uid)
            .snapshots(),
        builder: (context, adminSnapshot) {
          if (!adminSnapshot.hasData) {
            return _buildLoadingState('Carregando permissões...');
          }

          final adminData =
              adminSnapshot.data!.data() as Map<String, dynamic>? ?? {};
          final adminPesoPermissao = adminData['peso_permissao'] ?? 0;
          final adminTipo = adminData['tipo'] ?? '';
          final bool isAdmin =
              adminPesoPermissao >= 90 ||
              adminTipo == 'admin' ||
              adminTipo == 'administrador';
          final podeAdministrarAlvosCriticos = access.adminMaster && isAdmin;

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('usuarios')
                .orderBy('nome_completo')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildUsersSkeleton();
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'Nenhum usuário encontrado',
                  subtitle:
                      'Quando houver usuários cadastrados, eles aparecerão aqui.',
                );
              }

              final todosUsuarios = snapshot.data!.docs;
              final usuarios = todosUsuarios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return UsuarioIdentidadeService.deveExibirNaGestao(data);
              }).toList();
              _usuariosList = usuarios;

              final pendentes = usuarios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final status =
                    (data['status_conta'] ?? '').toString().toLowerCase();
                return status == 'pendente' &&
                    data['aprovado_em'] == null &&
                    data['solicitacao_acesso_gestao'] == true;
              }).toList();

              _pendentesCount = pendentes.length;

              final aprovados = usuarios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return UsuarioStatusService.normalizar(data['status_conta']) ==
                        'ativa' &&
                    data['aprovado_em'] != null;
              }).toList();

              final bloqueados = usuarios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final status =
                    data['status_conta']?.toString().toLowerCase() ?? '';
                return status == 'bloqueada' || status == 'inativa';
              }).length;

              final textoBusca = _buscaController.text.trim().toLowerCase();
              final filtrados = usuarios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if (!_usuarioPassaFiltro(data, _filtroUsuarios)) return false;
                if (textoBusca.isEmpty) return true;
                final nome = _textoUsuario(
                  data,
                  ['nome_completo', 'nome', 'name', 'displayName'],
                  '',
                ).toLowerCase();
                final email = _textoUsuario(data, ['email'], '').toLowerCase();
                final tipo = _textoUsuario(data, ['tipo'], '').toLowerCase();
                return nome.contains(textoBusca) ||
                    email.contains(textoBusca) ||
                    tipo.contains(textoBusca);
              }).toList();

              return RefreshIndicator(
                color: context.uai.primary,
                onRefresh: () async {
                  await _identificarContasAreaAluno(mostrarResultado: false);
                  if (mounted) setState(() {});
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 920;
                    final isCompact = constraints.maxWidth < 620;

                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        isCompact ? 12 : 18,
                        isCompact ? 12 : 16,
                        isCompact ? 12 : 18,
                        96,
                      ),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildPremiumHero(
                                  total: usuarios.length,
                                  ativos: aprovados.length,
                                  pendentes: pendentes.length,
                                  bloqueados: bloqueados,
                                  compact: isCompact,
                                ),
                                const SizedBox(height: 10),
                                _buildQuickActionChips(
                                  pendentes: pendentes.length,
                                  inativos: bloqueados,
                                  canApprove: access.adminMaster,
                                ),
                                const SizedBox(height: 10),
                                _buildSearchAndFilters(
                                  compact: isCompact,
                                  totalFiltrado: filtrados.length,
                                  usuarios: usuarios,
                                ),
                                const SizedBox(height: 14),
                                _buildSectionHeaderPremium(
                                  title: _tituloFiltroUsuarios(_filtroUsuarios),
                                  count: filtrados.length,
                                  icon: Icons.manage_accounts_rounded,
                                  color: context.uai.primary,
                                ),
                                if (filtrados.isNotEmpty)
                                  _buildUserGrid(
                                    usuarios: filtrados,
                                    isWide: isWide,
                                    isAdmin: podeAdministrarAlvosCriticos,
                                    adminData: adminData,
                                  )
                                else
                                  _buildEmptyState(
                                    icon: Icons.person_search_rounded,
                                    title: 'Nenhum usuário encontrado',
                                    subtitle: textoBusca.isNotEmpty
                                        ? 'Tente outro nome, e-mail ou perfil.'
                                        : 'Não há usuários neste filtro.',
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }


  bool _usuarioPassaFiltro(Map<String, dynamic> data, String filtro) {
    final status = (data['status_conta'] ?? '').toString().toLowerCase();
    final tipo = (data['tipo'] ?? '').toString().toLowerCase();
    final aprovado = data['aprovado_em'] != null;
    switch (filtro) {
      case 'ativos':
        return status == 'ativa' && aprovado;
      case 'pendentes':
        return status == 'pendente' && !aprovado && data['solicitacao_acesso_gestao'] == true;
      case 'administradores':
        return tipo == 'admin' || tipo == 'administrador';
      case 'professores':
        return tipo == 'professor';
      case 'monitores':
        return tipo == 'monitor';
      case 'inativos':
        return status == 'inativa' || status == 'bloqueada';
      default:
        return true;
    }
  }

  String _tituloFiltroUsuarios(String filtro) {
    switch (filtro) {
      case 'ativos':
        return 'Usuários ativos';
      case 'pendentes':
        return 'Solicitações pendentes';
      case 'administradores':
        return 'Administradores';
      case 'professores':
        return 'Professores';
      case 'monitores':
        return 'Monitores';
      case 'inativos':
        return 'Inativos e bloqueados';
      default:
        return 'Todos os usuários';
    }
  }

  Widget _buildQuickActionChips({
    required int pendentes,
    required int inativos,
    required bool canApprove,
  }) {
    Widget chip({
      required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap,
    }) {
      return ActionChip(
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label, style: TextStyle(color: context.uai.textPrimary, fontWeight: FontWeight.w800, fontSize: 11.5)),
        onPressed: onTap,
        backgroundColor: context.uai.card,
        side: BorderSide(color: color.withAlpha(61)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(
            icon: Icons.pending_actions_rounded,
            label: pendentes == 0 ? 'Sem pendências' : '$pendentes pendente${pendentes == 1 ? '' : 's'}',
            color: pendentes == 0 ? context.uai.success : context.uai.warning,
            onTap: () => _showPendingUsersDialog(context, const [], canApprove),
          ),
          const SizedBox(width: 7),
          chip(
            icon: Icons.hub_rounded,
            label: 'Central de identidades',
            color: context.uai.info,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CentralIdentidadesScreen()),
            ),
          ),
          const SizedBox(width: 7),
          chip(
            icon: Icons.tune_rounded,
            label: 'Predefinições',
            color: context.uai.primary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PredefinicoesPermissoesScreen()),
            ),
          ),
          const SizedBox(width: 7),
          chip(
            icon: _identificandoAreaAluno ? Icons.sync_rounded : Icons.manage_search_rounded,
            label: _identificandoAreaAluno ? 'Revisando...' : 'Revisar identidades',
            color: context.uai.info,
            onTap: () {
              if (!_identificandoAreaAluno) _identificarContasAreaAluno();
            },
          ),
          const SizedBox(width: 7),
          chip(
            icon: Icons.person_off_rounded,
            label: '$inativos inativo${inativos == 1 ? '' : 's'}',
            color: context.uai.error,
            onTap: () => _showInactiveUsersDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersSkeleton() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, _) {
        final t = 0.35 + (_shimmerController.value * 0.25);
        final base = context.uai.border.withAlpha((255.0 * (t)).round());
        Widget line(double width, double height) => Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(99),
              ),
            );
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 96),
          children: [
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < 5; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.uai.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.uai.border.withAlpha(140)),
                ),
                child: Row(
                  children: [
                    Container(width: 52, height: 52, decoration: BoxDecoration(color: base, shape: BoxShape.circle)),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        line(160, 12),
                        const SizedBox(height: 8),
                        line(220, 9),
                        const SizedBox(height: 9),
                        line(110, 9),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSlimDashboardSummary({
    required int total,
    required int ativos,
    required int pendentes,
    required int bloqueados,
    required bool compact,
  }) {
    final primary = context.uai.primary;

    Widget metric({
      required IconData icon,
      required int value,
      required String label,
      required Color color,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              '$value',
              style: TextStyle(
                color: context.uai.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: context.uai.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.manage_accounts_rounded,
                  color: primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gestão de acessos',
                      style: TextStyle(
                        color: context.uai.textPrimary,
                        fontSize: compact ? 17 : 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$total usuário${total == 1 ? '' : 's'} administrativo${total == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: context.uai.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              metric(
                icon: Icons.check_circle_rounded,
                value: ativos,
                label: 'ativos',
                color: context.uai.success,
              ),
              metric(
                icon: Icons.pending_actions_rounded,
                value: pendentes,
                label: 'pendentes',
                color: context.uai.warning,
              ),
              metric(
                icon: Icons.block_rounded,
                value: bloqueados,
                label: 'inativos',
                color: context.uai.error,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlimStat({
    required IconData icon,
    required int value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 5),
              Text(
                '$value',
                style: TextStyle(
                  color: context.uai.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.uai.textSecondary,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDashboardHeader({
    required int total,
    required int ativos,
    required int pendentes,
    required int bloqueados,
    required bool compact,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final stats = <Widget>[
      _buildCompactStat(
        icon: Icons.people_alt_rounded,
        value: total,
        label: 'Gestão',
        color: context.uai.primary,
      ),
      _buildCompactStat(
        icon: Icons.verified_user_rounded,
        value: ativos,
        label: 'Ativos',
        color: context.uai.success,
      ),
      _buildCompactStat(
        icon: Icons.pending_actions_rounded,
        value: pendentes,
        label: 'Pendentes',
        color: context.uai.warning,
      ),
      _buildCompactStat(
        icon: Icons.block_rounded,
        value: bloqueados,
        label: 'Inativos',
        color: context.uai.error,
      ),
    ];

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(179)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.uai.primary.withAlpha(31),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  color: context.uai.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Usuários da gestão',
                      style: TextStyle(
                        color: context.uai.textPrimary,
                        fontSize: compact ? 19 : 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Acessos administrativos, funções e permissões.',
                      style: TextStyle(
                        color: context.uai.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact)
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EditarUsuarioScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Novo usuário'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (compact)
            Wrap(spacing: 8, runSpacing: 8, children: stats)
          else
            Row(
              children: stats
                  .map((e) => Expanded(child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: e,
                      )))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactStat({
    required IconData icon,
    required int value,
    required String label,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(41)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: context.uai.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: context.uai.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters({
    required bool compact,
    required int totalFiltrado,
    required List<QueryDocumentSnapshot> usuarios,
  }) {
    final filtros = <String, String>{
      'todos': 'Todos',
      'ativos': 'Ativos',
      'administradores': 'Admins',
      'professores': 'Professores',
      'monitores': 'Monitores',
      'pendentes': 'Pendentes',
      'inativos': 'Inativos',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _buscaController,
          onChanged: (_) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 300), () {
              if (mounted) setState(() {});
            });
          },
          decoration: InputDecoration(
            hintText: 'Buscar por nome, e-mail ou função...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _buscaController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar busca',
                    onPressed: () {
                      _buscaController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: context.uai.card,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.uai.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.uai.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.uai.primary, width: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: filtros.entries.map((entry) {
                    final selecionado = _filtroUsuarios == entry.key;
                    final count = usuarios.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return _usuarioPassaFiltro(data, entry.key);
                    }).length;
                    return Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: FilterChip(
                        selected: selecionado,
                        label: Text('${entry.value}  $count'),
                        onSelected: (_) => setState(() => _filtroUsuarios = entry.key),
                        avatar: selecionado ? const Icon(Icons.check_rounded, size: 16) : null,
                        showCheckmark: false,
                        selectedColor: context.uai.primary.withAlpha(36),
                        side: BorderSide(
                          color: selecionado
                              ? context.uai.primary.withAlpha(115)
                              : context.uai.border.withAlpha(191),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '$totalFiltrado resultado${totalFiltrado == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: context.uai.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildCompactQuickActions({
    required List<QueryDocumentSnapshot> pendentes,
    required bool compact,
    required bool canApprove,
  }) {
    final actions = <Widget>[
      _buildCompactActionButton(
        icon: Icons.pending_actions_rounded,
        label: pendentes.isEmpty
            ? 'Sem pendências'
            : '${pendentes.length} pendente${pendentes.length == 1 ? '' : 's'}',
        color: context.uai.warning,
        onTap: () => _showPendingUsersDialog(context, pendentes, canApprove),
      ),
      _buildCompactActionButton(
        icon: Icons.hub_rounded,
        label: 'Central de identidades',
        color: context.uai.info,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CentralIdentidadesScreen()),
        ),
      ),
      _buildCompactActionButton(
        icon: Icons.tune_rounded,
        label: 'Predefinições',
        color: context.uai.primary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PredefinicoesPermissoesScreen(),
          ),
        ),
      ),
      _buildCompactActionButton(
        icon: Icons.manage_search_rounded,
        label: _identificandoAreaAluno ? 'Identificando...' : 'Revisar identidades',
        color: context.uai.success,
        onTap: _identificandoAreaAluno ? null : () => _identificarContasAreaAluno(),
      ),
    ];
    if (compact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: actions
              .map((e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: e,
                  ))
              .toList(),
        ),
      );
    }
    return Row(
      children: actions
          .map((e) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: e,
                ),
              ))
          .toList(),
    );
  }

  Widget _buildCompactActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        side: BorderSide(color: color.withAlpha(64)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildPendingActionButton(bool canApprove) {
    return Stack(
      children: [
        IconButton(
          icon: Icon(Icons.notifications_rounded),
          onPressed: () {
            final visiveis = _usuariosList.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final status =
                  (data['status_conta'] ?? '').toString().toLowerCase();
              return status == 'pendente' &&
                  data['solicitacao_acesso_gestao'] == true &&
                  UsuarioIdentidadeService.deveExibirNaGestao(data);
            }).toList();
            _showPendingUsersDialog(context, visiveis, canApprove);
          },
          tooltip: 'Usuários pendentes',
        ),
        if (_pendentesCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: context.uai.warning,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: context.uai.textPrimary, width: 1.5),
              ),
              child: Text(
                _pendentesCount > 99 ? '99+' : '$_pendentesCount',
                style: TextStyle(
                  color: _readableOn(context.uai.primary),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPremiumHero({
    required int total,
    required int ativos,
    required int pendentes,
    required int bloqueados,
    required bool compact,
  }) {
    return Container(
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        gradient: context.uai.primaryGradient,
        borderRadius: BorderRadius.circular(compact ? 24 : 30),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withAlpha(36),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 650;
          final onHero = _onHeroGradient();

          final icon = Container(
            width: compact ? 58 : 70,
            height: compact ? 58 : 70,
            decoration: BoxDecoration(
              color: onHero.withAlpha(36),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: onHero.withAlpha(41)),
            ),
            child: Icon(Icons.groups_rounded, color: onHero, size: 36),
          );

          final text = Column(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                'Gerenciar Usuários',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: _readableOn(context.uai.primary),
                  fontSize: compact ? 25 : 34,
                  fontWeight: FontWeight.w900,
                  height: 1.02,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Controle usuários, permissões, status de conta e aprovações do sistema.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onHero.withAlpha(209),
                  fontSize: compact ? 12.8 : 15,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildHeroChip(Icons.people_alt_rounded, '$total usuários'),
                  _buildHeroChip(Icons.verified_rounded, '$ativos ativos'),
                  if (pendentes > 0)
                    _buildHeroChip(
                      Icons.pending_actions_rounded,
                      '$pendentes pendentes',
                    ),
                  if (bloqueados > 0)
                    _buildHeroChip(
                      Icons.block_rounded,
                      '$bloqueados bloqueados',
                    ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EditarUsuarioScreen(),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: onHero.withAlpha(36),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: onHero.withAlpha(41),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 15,
                              color: onHero,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Novo usuário',
                              style: TextStyle(
                                color: onHero,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(children: [icon, SizedBox(height: 12), text]);
          }

          return Row(
            children: [
              icon,
              SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroChip(IconData icon, String label) {
    final onHero = _onHeroGradient();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onHero.withAlpha(36),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onHero.withAlpha(41)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onHero, size: 14),
          SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: onHero,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsRow({
    required List<QueryDocumentSnapshot> pendentes,
    required bool compact,
    required bool canApprove,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final actions = [
          _buildActionCard(
            icon: Icons.pending_actions_rounded,
            title: 'Pendentes',
            subtitle: pendentes.isEmpty
                ? 'Nenhum aguardando'
                : '${pendentes.length} aguardando aprovação',
            color: context.uai.warning,
            onTap: () =>
                _showPendingUsersDialog(context, pendentes, canApprove),
          ),
          _buildActionCard(
            icon: Icons.people_outline_rounded,
            title: 'Inativos',
            subtitle: 'Bloqueados e inativos',
            color: context.uai.error,
            onTap: () => _showInactiveUsersDialog(context),
          ),
          _buildActionCard(
            icon: Icons.person_add_alt_1_rounded,
            title: 'Novo usuário',
            subtitle: 'Cadastrar usuário',
            color: context.uai.success,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const EditarUsuarioScreen(),
              ),
            ),
          ),
        ];

        if (!wide) {
          return Column(
            children: actions
                .map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: w,
                  ),
                )
                .toList(),
          );
        }

        return Row(
          children: [
            Expanded(child: actions[0]),
            SizedBox(width: 10),
            Expanded(child: actions[1]),
            SizedBox(width: 10),
            Expanded(child: actions[2]),
          ],
        );
      },
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: context.uai.card,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(46)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(6),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withAlpha(26),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.uai.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.uai.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserGrid({
    required List<QueryDocumentSnapshot> usuarios,
    required bool isWide,
    required bool isAdmin,
    required Map<String, dynamic> adminData,
  }) {
    if (!isWide) {
      return Column(
        children: usuarios
            .map(
              (usuario) =>
                  _buildUserCard(context, usuario, false, isAdmin, adminData),
            )
            .toList(),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: usuarios.map((usuario) {
        return SizedBox(
          width: 370,
          child: _buildUserCard(context, usuario, false, isAdmin, adminData),
        );
      }).toList(),
    );
  }

  Widget _buildSectionHeaderPremium({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withAlpha(26),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: context.uai.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: color.withAlpha(26),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: color.withAlpha(46)),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(
    BuildContext context,
    QueryDocumentSnapshot usuario,
    bool isPendente,
    bool isAdmin,
    Map<String, dynamic> adminData,
  ) {
    final data = usuario.data() as Map<String, dynamic>;
    final userId = usuario.id;
    final nome = data['nome_completo'] ?? data['name'] ?? 'Nome não informado';
    final email = data['email'] ?? 'Email não informado';
    final fotoUrl = _fotoUrlFromData(data);
    final statusConta = data['status_conta'] ?? '';
    final pesoPermissao = data['peso_permissao'] ?? 0;
    final tipo = data['tipo'] ?? '';
    final ultimoAcesso = data['ultimo_acesso'];
    final criadoEm = _dataCriacaoFromData(data);
    final now = DateTime.now();
    final ultimoAcessoDate = _dateTimeFromValue(ultimoAcesso);
    final online = ultimoAcessoDate != null && now.difference(ultimoAcessoDate.toLocal()).inMinutes.abs() <= 5;
    final novo = criadoEm != null && now.difference(criadoEm.toLocal()).inDays >= 0 && now.difference(criadoEm.toLocal()).inDays <= 3;
    final bool podeEditarRapido = isAdmin && pesoPermissao < 90;
    final tipoColor = _ensureVisible(_getTipoColor(tipo), context.uai.card);
    final statusColor = _ensureVisible(
      _getStatusColor(statusConta),
      context.uai.card,
    );
    final inicial = nome.toString().trim().isNotEmpty
        ? nome.toString().trim().substring(0, 1).toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.uai.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: statusColor.withAlpha(statusConta == 'ativa' ? 41 : 82)),
          boxShadow: [
            BoxShadow(
              color: statusColor.withAlpha(statusConta == 'ativa' ? 14 : 28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UsuarioDetalheScreen(userId: userId),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _buildUserAvatar(
                        nome: nome.toString(),
                        fotoUrl: fotoUrl,
                        color: tipoColor,
                        size: 52,
                        inicial: inicial,
                      ),
                      Positioned(
                        right: -1,
                        bottom: 1,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: online ? context.uai.success : context.uai.textMuted,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.uai.card, width: 2.2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                nome.toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.uai.textPrimary,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (novo) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: context.uai.info.withAlpha(26),
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(color: context.uai.info.withAlpha(51)),
                                ),
                                child: Text(
                                  'NOVO',
                                  style: TextStyle(
                                    color: _ensureVisible(context.uai.info, context.uai.card),
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          email.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.uai.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildMiniBadge(
                              label: tipo.toString().isEmpty
                                  ? 'TIPO'
                                  : tipo.toString().toUpperCase(),
                              color: tipoColor,
                              icon: Icons.badge_rounded,
                            ),
                            if (statusConta != 'ativa')
                              _buildMiniBadge(
                                label: statusConta.toString().toUpperCase(),
                                color: statusColor,
                                icon: Icons.info_rounded,
                              ),
                            if (UsuarioIdentidadeService.ehContaHibrida(data))
                              _buildMiniBadge(
                                label: 'GESTÃO + ALUNO',
                                color: _ensureVisible(
                                  context.uai.info,
                                  context.uai.card,
                                ),
                                icon: Icons.hub_rounded,
                              ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        _buildLastAccessLine(ultimoAcesso),
                      ],
                    ),
                  ),
                  if (podeEditarRapido)
                    PopupMenuButton<String>(
                      tooltip: 'Ações',
                      color: context.uai.card,
                      iconColor: context.uai.textMuted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onSelected: (value) {
                        if (value == 'editar') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  EditarUsuarioScreen(userId: userId),
                            ),
                          );
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'editar',
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit_rounded,
                                size: 18,
                                color: context.uai.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Editar',
                                style: TextStyle(
                                  color: context.uai.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      color: context.uai.textMuted,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserAvatar({
    required String nome,
    required String? fotoUrl,
    required Color color,
    required double size,
    required String inicial,
  }) {
    final avatarBg = Color.alphaBlend(
      color.withAlpha(31),
      context.uai.cardAlt,
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: avatarBg,
        shape: BoxShape.circle,
        border: Border.all(color: color.withAlpha(71)),
      ),
      child: ClipOval(
        child: fotoUrl != null && fotoUrl.trim().isNotEmpty
            ? CachedNetworkImage(
                imageUrl: fotoUrl.trim(),
                fit: BoxFit.cover,
                width: size,
                height: size,
                placeholder: (context, url) => Center(
                  child: SizedBox(
                    width: size * 0.34,
                    height: size * 0.34,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Center(
                  child: Text(
                    inicial,
                    style: TextStyle(
                      fontSize: size * 0.36,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  inicial,
                  style: TextStyle(
                    fontSize: size * 0.36,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildMiniBadge({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withAlpha(31)),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, color: color, size: 11),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _dateTimeFromValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  Widget _buildLastAccessLine(dynamic value) {
    final texto = _formatLastAccessCard(value);
    final semRegistro = texto == 'Nunca acessou';
    final dt = _dateTimeFromValue(value);
    final online = dt != null && DateTime.now().difference(dt.toLocal()).inMinutes.abs() <= 5;
    return Row(
      children: [
        Icon(
          online ? Icons.circle : (semRegistro ? Icons.schedule_rounded : Icons.access_time_filled_rounded),
          size: online ? 9 : 13,
          color: online ? context.uai.success : (semRegistro ? context.uai.textMuted : context.uai.textSecondary),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            online ? 'Online agora' : 'Último acesso: $texto',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: semRegistro ? context.uai.textMuted : context.uai.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _formatLastAccessCard(dynamic value) {
    DateTime? dt;
    if (value is Timestamp) {
      dt = value.toDate();
    } else if (value is DateTime) {
      dt = value;
    } else if (value is String && value.trim().isNotEmpty) {
      dt = DateTime.tryParse(value.trim());
    }
    if (dt == null) return 'Nunca acessou';

    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(local.year, local.month, local.day);
    final diff = today.difference(date).inDays;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');

    if (diff == 0) return 'Hoje, $hh:$mm';
    if (diff == 1) return 'Ontem, $hh:$mm';
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd/$mo/${local.year} às $hh:$mm';
  }

  Widget _buildLoadingState(String message) {
    return Center(
      child: Container(
        padding: EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: context.uai.card,
          borderRadius: BorderRadius.circular(24),
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

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.uai.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 58, color: context.uai.border),
          SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.uai.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.uai.textSecondary, height: 1.3),
          ),
        ],
      ),
    );
  }

  Color _getTipoColor(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'admin':
      case 'administrador':
        return context.uai.error;
      case 'professor':
        return context.uai.warning;
      case 'monitor':
        return context.uai.info;
      case 'aluno':
        return context.uai.success;
      case 'visitante':
        return context.uai.associacao;
      case 'pendente':
        return context.uai.warning;
      default:
        return context.uai.textMuted;
    }
  }
}
