import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/permissions/permission_catalog.dart';
import 'package:uai_capoeira/core/permissions/permission_definition.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'usuario_admin_access.dart';

class UsuarioPermissoesScreen extends StatefulWidget {
  final String userId;
  final String? nome;
  final String? email;
  final String? tipo;
  final String? statusConta;
  final int? pesoPermissao;

  const UsuarioPermissoesScreen({
    super.key,
    required this.userId,
    this.nome,
    this.email,
    this.tipo,
    this.statusConta,
    this.pesoPermissao,
  });

  @override
  State<UsuarioPermissoesScreen> createState() =>
      _UsuarioPermissoesScreenState();
}

enum _PermissionFilter {
  todas,
  ativas,
  criticas,
  sistema,
  eventos,
  alunos,
  chamada,
  uniformes,
  dashboard,
}

class _UsuarioPermissoesScreenState extends State<UsuarioPermissoesScreen> {
  final TextEditingController _buscaController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late Future<UsuarioAdminAccess> _accessFuture;

  bool _carregando = true;
  bool _salvando = false;
  String? _erro;
  _PermissionFilter _filtro = _PermissionFilter.todas;
  Map<String, dynamic> _usuario = {};
  Map<String, bool> _permissoes = {};
  Map<String, bool> _permissoesOriginais = {};

  List<PermissionDefinition> get _catalogo => PermissionCatalog.all;

  @override
  void initState() {
    super.initState();
    _buscaController.addListener(() => setState(() {}));
    _accessFuture = _carregarAcessoInicial();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<UsuarioAdminAccess> _carregarAcessoInicial() async {
    final access = await carregarAcessoGestaoUsuarios();
    if (access.liberado) {
      await _carregarTudoProtegido(acessoJaValidado: true);
    } else if (mounted) {
      setState(() => _carregando = false);
    }
    return access;
  }

  Future<void> _carregarTudo() async {
    return _carregarTudoProtegido();
  }

  Future<void> _carregarTudoProtegido({bool acessoJaValidado = false}) async {
    if (!acessoJaValidado) {
      final access = await carregarAcessoGestaoUsuarios();
      if (!access.liberado) {
        if (mounted) setState(() => _carregando = false);
        return;
      }
    }

    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final results =
          await Future.wait<DocumentSnapshot<Map<String, dynamic>>>([
            _firestore.collection('usuarios').doc(widget.userId).get(),
            _permissoesRef().get(),
          ]);

      final userDoc = results[0];
      final permissionsDoc = results[1];

      final userData = userDoc.data() ?? {};
      final permissionsData = permissionsDoc.data() ?? {};

      final carregadas = <String, bool>{};
      permissionsData.forEach((key, value) {
        if (value is bool) carregadas[key] = value;
      });

      for (final permissao in _catalogo) {
        final ativa = _permissaoAtivaEmMapa(permissao, carregadas);
        for (final chave in permissao.linkedKeys) {
          carregadas[chave] = ativa;
        }
      }

      if (!mounted) return;
      setState(() {
        _usuario = userData;
        _permissoes = Map<String, bool>.from(carregadas);
        _permissoesOriginais = Map<String, bool>.from(carregadas);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  DocumentReference<Map<String, dynamic>> _permissoesRef() {
    return _firestore
        .collection('usuarios')
        .doc(widget.userId)
        .collection('permissoes_usuario')
        .doc('configuracoes');
  }

  String get _nome =>
      widget.nome ??
      _usuario['nome_completo']?.toString() ??
      _usuario['name']?.toString() ??
      'Usuário';

  String get _email =>
      widget.email ?? _usuario['email']?.toString() ?? 'Email não informado';

  String get _tipo =>
      widget.tipo ?? _usuario['tipo']?.toString() ?? 'Não informado';

  String get _status =>
      widget.statusConta ??
      _usuario['status_conta']?.toString() ??
      'Não informado';

  int get _peso {
    final raw = widget.pesoPermissao ?? _usuario['peso_permissao'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  bool get _temAlteracoes {
    for (final chave in _chavesControladas) {
      if ((_permissoes[chave] ?? false) !=
          (_permissoesOriginais[chave] ?? false)) {
        return true;
      }
    }
    return false;
  }

  Set<String> get _chavesControladas {
    return {for (final permissao in _catalogo) ...permissao.linkedKeys};
  }

  bool _permissaoAtiva(PermissionDefinition permissao) {
    return _permissaoAtivaEmMapa(permissao, _permissoes);
  }

  bool _permissaoAtivaOriginalmente(PermissionDefinition permissao) {
    return _permissaoAtivaEmMapa(permissao, _permissoesOriginais);
  }

  bool _permissaoAtivaEmMapa(
    PermissionDefinition permissao,
    Map<String, bool> mapa,
  ) {
    return permissao.linkedKeys.any((chave) => mapa[chave] == true);
  }

  Future<bool> _confirmarCriticas({
    required String titulo,
    required String mensagem,
    required List<PermissionDefinition> permissoes,
  }) async {
    if (permissoes.isEmpty) return true;

    final t = context.uai;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: t.error),
              const SizedBox(width: 10),
              Expanded(child: Text(titulo)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(mensagem),
              const SizedBox(height: 14),
              ...permissoes
                  .take(6)
                  .map(
                    (permissao) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(permissao.icon, size: 16, color: t.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              permissao.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (permissoes.length > 6)
                Text('+ ${permissoes.length - 6} permissões críticas'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    return confirm == true;
  }

  Future<void> _alterarPermissao(
    PermissionDefinition permissao,
    bool valor,
  ) async {
    if (valor && permissao.critical && !_permissaoAtiva(permissao)) {
      final ok = await _confirmarCriticas(
        titulo: 'Permissão crítica',
        mensagem:
            'Você está ativando permissões críticas. Isso pode liberar áreas sensíveis do sistema para este usuário.',
        permissoes: [permissao],
      );
      if (!ok) return;
    }

    setState(() {
      for (final chave in permissao.linkedKeys) {
        _permissoes[chave] = valor;
      }
    });
  }

  Future<void> _alterarCategoria(String categoria, bool valor) async {
    final permissoesCategoria = _catalogo
        .where((permissao) => permissao.category == categoria)
        .toList(growable: false);
    final criticas = permissoesCategoria
        .where(
          (permissao) =>
              valor && permissao.critical && !_permissaoAtiva(permissao),
        )
        .toList(growable: false);

    if (criticas.isNotEmpty) {
      final ok = await _confirmarCriticas(
        titulo: 'Permissões críticas na categoria',
        mensagem:
            'Você está ativando permissões críticas. Isso pode liberar áreas sensíveis do sistema para este usuário.',
        permissoes: criticas,
      );
      if (!ok) return;
    }

    setState(() {
      for (final permissao in permissoesCategoria) {
        for (final chave in permissao.linkedKeys) {
          _permissoes[chave] = valor;
        }
      }
    });
  }

  Future<void> _salvar() async {
    final access = await carregarAcessoGestaoUsuarios();
    if (!access.liberado) {
      if (mounted) {
        _snack('Você não tem permissão para gerenciar usuários.');
      }
      return;
    }

    final criticasNovas = _catalogo
        .where(
          (permissao) =>
              permissao.critical &&
              _permissaoAtiva(permissao) &&
              !_permissaoAtivaOriginalmente(permissao),
        )
        .toList(growable: false);

    if (criticasNovas.isNotEmpty) {
      final ok = await _confirmarCriticas(
        titulo: 'Salvar permissões críticas',
        mensagem:
            'Você está ativando permissões críticas. Isso pode liberar áreas sensíveis do sistema para este usuário.',
        permissoes: criticasNovas,
      );
      if (!ok) return;
    }

    setState(() => _salvando = true);
    try {
      final update = <String, bool>{};
      for (final permissao in _catalogo) {
        final ativa = _permissaoAtiva(permissao);
        for (final chave in permissao.linkedKeys) {
          update[chave] = ativa;
        }
      }

      await _permissoesRef().set(update, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _permissoesOriginais = Map<String, bool>.from(_permissoes);
        _salvando = false;
      });
      _snack('Permissões salvas com sucesso.', success: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      _snack('Erro ao salvar permissões: $e');
    }
  }

  void _descartarAlteracoes() {
    setState(() {
      _permissoes = Map<String, bool>.from(_permissoesOriginais);
    });
    _snack('Alterações descartadas.');
  }

  Future<bool> _confirmarSaida() async {
    if (!_temAlteracoes) return true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Descartar alterações?'),
          content: const Text(
            'Existem permissões alteradas que ainda não foram salvas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Continuar editando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Descartar'),
            ),
          ],
        );
      },
    );
    return confirm == true;
  }

  void _snack(String mensagem, {bool success = false}) {
    final t = context.uai;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? t.success : t.warning,
      ),
    );
  }

  List<PermissionDefinition> _permissoesFiltradas() {
    final query = _buscaController.text.trim().toLowerCase();
    return _catalogo
        .where((permissao) {
          final matchesSearch =
              query.isEmpty ||
              permissao.title.toLowerCase().contains(query) ||
              permissao.description.toLowerCase().contains(query) ||
              permissao.key.toLowerCase().contains(query) ||
              permissao.category.toLowerCase().contains(query) ||
              permissao.aliases.any(
                (alias) => alias.toLowerCase().contains(query),
              );

          if (!matchesSearch) return false;

          return switch (_filtro) {
            _PermissionFilter.todas => true,
            _PermissionFilter.ativas => _permissaoAtiva(permissao),
            _PermissionFilter.criticas => permissao.critical,
            _PermissionFilter.sistema =>
              permissao.category == PermissionCatalog.categorySystemAdmin,
            _PermissionFilter.eventos => permissao.category.startsWith(
              'EVENTOS',
            ),
            _PermissionFilter.alunos =>
              permissao.category == PermissionCatalog.categoryStudents,
            _PermissionFilter.chamada =>
              permissao.category == PermissionCatalog.categoryAttendance,
            _PermissionFilter.uniformes =>
              permissao.category == PermissionCatalog.categoryUniforms,
            _PermissionFilter.dashboard =>
              permissao.category == PermissionCatalog.categoryDashboardTurma,
          };
        })
        .toList(growable: false);
  }

  Map<String, List<PermissionDefinition>> _agrupadasPorCategoria() {
    final filtradas = _permissoesFiltradas();
    return {
      for (final categoria in PermissionCatalog.categoriesForUserDetails)
        categoria: filtradas
            .where((permissao) => permissao.category == categoria)
            .toList(growable: false),
    }..removeWhere((_, permissoes) => permissoes.isEmpty);
  }

  int get _ativas => _catalogo.where(_permissaoAtiva).length;

  int get _criticasAtivas => _catalogo
      .where((permissao) => permissao.critical && _permissaoAtiva(permissao))
      .length;

  int get _categoriasAtivas => _catalogo
      .where(_permissaoAtiva)
      .map((permissao) => permissao.category)
      .toSet()
      .length;

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
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

        return _buildConteudoAutorizado(context);
      },
    );
  }

  Widget _buildConteudoAutorizado(BuildContext context) {
    final t = context.uai;

    return PopScope(
      canPop: !_temAlteracoes,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmarSaida() && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: t.background,
        appBar: AppBar(
          title: Row(
            children: [
              const Flexible(
                child: Text(
                  'Permissões do Usuário',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (_temAlteracoes) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Alterações não salvas',
                  child: Icon(Icons.circle, size: 10, color: t.warning),
                ),
              ],
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              if (await _confirmarSaida() && context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            IconButton(
              tooltip: 'Recarregar permissões',
              onPressed: _salvando ? null : _carregarTudo,
              icon: const Icon(Icons.refresh_rounded),
            ),
            TextButton.icon(
              onPressed: _temAlteracoes && !_salvando ? _salvar : null,
              icon: _salvando
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.primary,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Salvar'),
            ),
          ],
        ),
        body: _buildScaffoldBody(context),
      ),
    );
  }

  Widget _buildScaffoldBody(BuildContext context) {
    if (_carregando || _erro != null) {
      return _buildBody();
    }

    return Column(
      children: [
        Expanded(child: _buildBody()),
        _buildBottomActions(context),
      ],
    );
  }

  Widget _buildBody() {
    final t = context.uai;

    if (_carregando) {
      return Center(child: CircularProgressIndicator(color: t.primary));
    }

    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: t.error, size: 54),
              const SizedBox(height: 12),
              Text(
                'Não foi possível carregar permissões',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _erro!,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _carregarTudo,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final agrupadas = _agrupadasPorCategoria();

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 980;
        final horizontal = constraints.maxWidth < 640 ? 14.0 : 22.0;
        final bottomPadding = constraints.maxWidth < 620 ? 24.0 : 22.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            14,
            horizontal,
            bottomPadding,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1160),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildUserHeader(context),
                    const SizedBox(height: 14),
                    _buildSummary(context),
                    const SizedBox(height: 14),
                    if (desktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 260,
                            child: _buildFilterPanel(context),
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: _buildPermissionsList(agrupadas)),
                        ],
                      )
                    else ...[
                      _buildSearch(context),
                      const SizedBox(height: 10),
                      _buildFilterChips(context),
                      const SizedBox(height: 14),
                      _buildPermissionsList(agrupadas),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUserHeader(BuildContext context) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;
          final avatar = Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: onPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(t.cardRadius - 2),
              border: Border.all(color: onPrimary.withValues(alpha: 0.18)),
            ),
            child: Icon(Icons.manage_accounts_rounded, color: onPrimary),
          );

          final content = Column(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                _nome,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: narrow ? 22 : 27,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroChip(Icons.badge_rounded, _tipo.toUpperCase()),
                  _heroChip(Icons.circle, _status.toUpperCase()),
                  _heroChip(Icons.security_rounded, 'PESO $_peso'),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: onPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: onPrimary.withValues(alpha: 0.14)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: onPrimary,
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Permissões de gestão não têm relação com vínculo da Área do Aluno.',
                        style: TextStyle(
                          color: onPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [avatar, const SizedBox(height: 12), content],
            );
          }

          return Row(
            children: [
              avatar,
              const SizedBox(width: 14),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  Widget _heroChip(IconData icon, String label) {
    final onPrimary = _readableOn(context.uai.primary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final t = context.uai;
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth < 720;
        final cards = [
          _SummaryData(
            'Total',
            _catalogo.length.toString(),
            Icons.list_alt_rounded,
            t.info,
          ),
          _SummaryData(
            'Ativas',
            _ativas.toString(),
            Icons.check_circle_rounded,
            t.success,
          ),
          _SummaryData(
            'Críticas ativas',
            _criticasAtivas.toString(),
            Icons.warning_amber_rounded,
            _criticasAtivas > 0 ? t.error : t.textMuted,
          ),
          _SummaryData(
            'Categorias ativas',
            _categoriasAtivas.toString(),
            Icons.category_rounded,
            t.associacao,
          ),
        ];

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards.map((card) {
            final width = twoColumns
                ? (constraints.maxWidth - 10) / 2
                : (constraints.maxWidth - 30) / 4;
            return SizedBox(width: width, child: _summaryCard(context, card));
          }).toList(),
        );
      },
    );
  }

  Widget _summaryCard(BuildContext context, _SummaryData data) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        border: Border.all(color: data.color.withValues(alpha: 0.18)),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(t.buttonRadius),
            ),
            child: Icon(data.icon, color: data.color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.value,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel(BuildContext context) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSearch(context),
          const SizedBox(height: 14),
          Text(
            'Filtros',
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          ..._PermissionFilter.values.map(
            (filter) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _filterButton(filter),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch(BuildContext context) {
    final t = context.uai;
    return TextField(
      controller: _buscaController,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _buscaController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpar busca',
                onPressed: _buscaController.clear,
                icon: const Icon(Icons.close_rounded),
              ),
        labelText: 'Buscar permissão',
        hintText: 'Título, descrição, chave, alias ou categoria',
        filled: true,
        fillColor: t.cardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
          borderSide: BorderSide(color: t.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
          borderSide: BorderSide(color: t.border),
        ),
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _PermissionFilter.values
            .map(
              (filter) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _filterChip(filter),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _filterButton(_PermissionFilter filter) {
    final t = context.uai;
    final selected = _filtro == filter;
    final color = _filterColor(filter);
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : t.cardAlt,
      borderRadius: BorderRadius.circular(t.buttonRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _filtro = filter),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.buttonRadius),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.35) : t.border,
            ),
          ),
          child: Row(
            children: [
              Icon(_filterIcon(filter), color: selected ? color : t.textMuted),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _filterLabel(filter),
                  style: TextStyle(
                    color: selected ? color : t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(_PermissionFilter filter) {
    final selected = _filtro == filter;
    final color = _filterColor(filter);
    return FilterChip(
      selected: selected,
      onSelected: (_) => setState(() => _filtro = filter),
      avatar: Icon(
        _filterIcon(filter),
        size: 17,
        color: selected ? color : context.uai.textSecondary,
      ),
      label: Text(_filterLabel(filter)),
      selectedColor: color.withValues(alpha: 0.14),
      checkmarkColor: color,
      side: BorderSide(
        color: selected ? color.withValues(alpha: 0.35) : context.uai.border,
      ),
    );
  }

  String _filterLabel(_PermissionFilter filter) {
    return switch (filter) {
      _PermissionFilter.todas => 'Todas',
      _PermissionFilter.ativas => 'Ativas',
      _PermissionFilter.criticas => 'Críticas',
      _PermissionFilter.sistema => 'Sistema/Admin',
      _PermissionFilter.eventos => 'Eventos',
      _PermissionFilter.alunos => 'Alunos',
      _PermissionFilter.chamada => 'Chamada',
      _PermissionFilter.uniformes => 'Uniformes',
      _PermissionFilter.dashboard => 'Dashboard',
    };
  }

  IconData _filterIcon(_PermissionFilter filter) {
    return switch (filter) {
      _PermissionFilter.todas => Icons.grid_view_rounded,
      _PermissionFilter.ativas => Icons.check_circle_rounded,
      _PermissionFilter.criticas => Icons.warning_amber_rounded,
      _PermissionFilter.sistema => Icons.admin_panel_settings_rounded,
      _PermissionFilter.eventos => Icons.event_rounded,
      _PermissionFilter.alunos => Icons.people_rounded,
      _PermissionFilter.chamada => Icons.fact_check_rounded,
      _PermissionFilter.uniformes => Icons.shopping_bag_rounded,
      _PermissionFilter.dashboard => Icons.analytics_rounded,
    };
  }

  Color _filterColor(_PermissionFilter filter) {
    final t = context.uai;
    return switch (filter) {
      _PermissionFilter.todas => t.primary,
      _PermissionFilter.ativas => t.success,
      _PermissionFilter.criticas => t.error,
      _PermissionFilter.sistema => t.primary,
      _PermissionFilter.eventos => t.eventos,
      _PermissionFilter.alunos => t.uniformes,
      _PermissionFilter.chamada => t.warning,
      _PermissionFilter.uniformes => t.accent,
      _PermissionFilter.dashboard => t.info,
    };
  }

  Widget _buildPermissionsList(
    Map<String, List<PermissionDefinition>> agrupadas,
  ) {
    final t = context.uai;
    if (agrupadas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
        ),
        child: Column(
          children: [
            Icon(Icons.search_off_rounded, color: t.textMuted, size: 48),
            const SizedBox(height: 10),
            Text(
              'Nenhuma permissão encontrada',
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: agrupadas.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildCategorySection(entry.key, entry.value),
        );
      }).toList(),
    );
  }

  Widget _buildCategorySection(
    String categoria,
    List<PermissionDefinition> permissoes,
  ) {
    final t = context.uai;
    final activeCount = permissoes.where(_permissaoAtiva).length;
    final criticalCount = permissoes.where((p) => p.critical).length;
    final color = _categoryColor(categoria);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.cardRadius),
        boxShadow: t.softShadow,
      ),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(t.buttonRadius),
                      ),
                      child: Icon(_categoryIcon(categoria), color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _categoryLabel(categoria),
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$activeCount/${permissoes.length} ativas'
                            '${criticalCount > 0 ? ' • $criticalCount críticas' : ''}',
                            style: TextStyle(
                              color: t.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Marcar todas',
                      child: IconButton(
                        onPressed: () => _alterarCategoria(categoria, true),
                        icon: Icon(Icons.done_all_rounded, color: color),
                      ),
                    ),
                    Tooltip(
                      message: 'Limpar todas',
                      child: IconButton(
                        onPressed: () => _alterarCategoria(categoria, false),
                        icon: Icon(
                          Icons.remove_done_rounded,
                          color: t.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (categoria == PermissionCatalog.categoryDashboardTurma)
                _buildDashboardQuickPackages(context),
              Divider(height: 1, color: t.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Column(
                  children: permissoes
                      .map(
                        (permissao) => _PermissionTile(
                          permission: permissao,
                          active: _permissaoAtiva(permissao),
                          onChanged: (value) =>
                              _alterarPermissao(permissao, value),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _categoryColor(String categoria) {
    final t = context.uai;
    if (categoria == PermissionCatalog.categoryVisibility) {
      return t.associacao;
    }
    if (categoria == PermissionCatalog.categoryStudents) {
      return t.uniformes;
    }
    if (categoria == PermissionCatalog.categoryAttendance) {
      return t.warning;
    }
    if (categoria == PermissionCatalog.categoryEventsGeneral) {
      return t.eventos;
    }
    if (categoria == PermissionCatalog.categoryEventsParticipants) {
      return t.info;
    }
    if (categoria == PermissionCatalog.categoryEventsPayments) {
      return t.warning;
    }
    if (categoria == PermissionCatalog.categoryEventsFinancial) {
      return t.success;
    }
    if (categoria == PermissionCatalog.categoryUsers) {
      return t.error;
    }
    if (categoria == PermissionCatalog.categoryUniforms) {
      return t.accent;
    }
    if (categoria == PermissionCatalog.categoryDashboardTurma) {
      return t.info;
    }
    return t.primary;
  }

  IconData _categoryIcon(String categoria) {
    if (categoria == PermissionCatalog.categoryVisibility) {
      return Icons.visibility_rounded;
    }
    if (categoria == PermissionCatalog.categoryStudents) {
      return Icons.people_rounded;
    }
    if (categoria == PermissionCatalog.categoryAttendance) {
      return Icons.fact_check_rounded;
    }
    if (categoria.startsWith('EVENTOS')) {
      return Icons.event_rounded;
    }
    if (categoria == PermissionCatalog.categoryUsers) {
      return Icons.admin_panel_settings_rounded;
    }
    if (categoria == PermissionCatalog.categoryUniforms) {
      return Icons.shopping_bag_rounded;
    }
    if (categoria == PermissionCatalog.categoryDashboardTurma) {
      return Icons.analytics_rounded;
    }
    return Icons.admin_panel_settings_rounded;
  }

  String _categoryLabel(String categoria) {
    if (categoria == PermissionCatalog.categoryVisibility) {
      return 'Telas / Acesso';
    }
    if (categoria == PermissionCatalog.categoryAttendance) {
      return 'Chamada / Avaliações';
    }
    if (categoria == PermissionCatalog.categorySystemAdmin) {
      return 'Sistema / Admin';
    }
    if (categoria == PermissionCatalog.categoryDashboardTurma) {
      return 'Dashboard / Resumo';
    }
    return categoria
        .replaceAll('EVENTOS — ', 'Eventos — ')
        .replaceAll('ALUNOS', 'Alunos')
        .replaceAll('USUÁRIOS', 'Usuários')
        .replaceAll('UNIFORMES', 'Uniformes');
  }

  Widget _buildDashboardQuickPackages(BuildContext context) {
    final t = context.uai;
    return Container(
      color: t.cardAlt.withOpacity(0.42),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 14, color: t.warning),
              const SizedBox(width: 6),
              Text(
                'Ações Rápidas (Pacotes)',
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _quickPackageButton(
                  label: 'Professor básico',
                  icon: Icons.school_rounded,
                  onTap: () => _aplicarPacoteDashboard('professor_basico'),
                ),
                const SizedBox(width: 8),
                _quickPackageButton(
                  label: 'Somente frequência',
                  icon: Icons.query_stats_rounded,
                  onTap: () => _aplicarPacoteDashboard('somente_frequencia'),
                ),
                const SizedBox(width: 8),
                _quickPackageButton(
                  label: 'Só agregados',
                  icon: Icons.analytics_rounded,
                  onTap: () => _aplicarPacoteDashboard('so_agregados'),
                ),
                const SizedBox(width: 8),
                _quickPackageButton(
                  label: 'Admin Full',
                  icon: Icons.security_rounded,
                  onTap: () => _aplicarPacoteDashboard('admin_full'),
                  color: t.error,
                ),
                const SizedBox(width: 8),
                _quickPackageButton(
                  label: 'Limpar',
                  icon: Icons.clear_all_rounded,
                  onTap: () => _aplicarPacoteDashboard('limpar'),
                  color: t.textMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickPackageButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    final t = context.uai;
    final activeColor = color ?? t.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: activeColor.withOpacity(0.24)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: activeColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: activeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _aplicarPacoteDashboard(String pacote) async {
    final Map<String, bool> updates = {};

    final allDashboardKeys = _catalogo
        .where((p) => p.category == PermissionCatalog.categoryDashboardTurma)
        .expand((p) => p.linkedKeys)
        .toSet();

    if (pacote == 'limpar') {
      for (final key in allDashboardKeys) {
        updates[key] = false;
      }
    } else if (pacote == 'admin_full') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ativar Admin Dashboard?'),
          content: const Text(
            'Isso liberará todas as funções, incluindo recalcular cache, exportar PDF e logs de debug.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ativar tudo'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      for (final key in allDashboardKeys) {
        updates[key] = true;
      }
    } else {
      // Começa limpando para garantir estado do pacote
      for (final key in allDashboardKeys) {
        updates[key] = false;
      }

      final Set<String> keysParaAtivar = {
        'pode_visualizar_dashboard_turma',
        'pode_ver_dashboard_frequencia',
        'pode_ver_dashboard_filtro_semana',
        'pode_ver_dashboard_filtro_mes',
        'pode_ver_dashboard_filtro_ano',
        'pode_ver_dashboard_filtro_total',
        'pode_ver_dashboard_top5_frequencia',
        'pode_ver_dashboard_lista_frequencia',
        'pode_ver_dashboard_metricas_frequencia',
        'pode_ver_dashboard_nomes_alunos',
        'pode_ver_dashboard_detalhes_aluno',
        'pode_ver_dashboard_fotos_alunos',
      };

      if (pacote == 'professor_basico') {
        keysParaAtivar.addAll([
          'pode_ver_dashboard_graduacao',
          'pode_ver_dashboard_idade',
          'pode_ver_dashboard_sexo',
          'pode_ver_dashboard_chip_cache',
        ]);
      } else if (pacote == 'so_agregados') {
        keysParaAtivar.addAll([
          'pode_ver_dashboard_graduacao',
          'pode_ver_dashboard_idade',
          'pode_ver_dashboard_sexo',
          'pode_ver_dashboard_chip_cache',
        ]);
        // Remove individuais
        keysParaAtivar.removeAll([
          'pode_ver_dashboard_nomes_alunos',
          'pode_ver_dashboard_detalhes_aluno',
          'pode_ver_dashboard_fotos_alunos',
          'pode_ver_dashboard_lista_frequencia',
        ]);
      }

      for (final key in keysParaAtivar) {
        updates[key] = true;
      }
    }

    setState(() {
      _permissoes.addAll(updates);
    });
  }

  Widget _buildBottomActions(BuildContext context) {
    final t = context.uai;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(top: BorderSide(color: t.border)),
          boxShadow: t.softShadow,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 620;
                final discard = OutlinedButton.icon(
                  onPressed: _temAlteracoes && !_salvando
                      ? _descartarAlteracoes
                      : null,
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Descartar'),
                );
                final reload = OutlinedButton.icon(
                  onPressed: _salvando ? null : _carregarTudo,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Recarregar'),
                );
                final save = FilledButton.icon(
                  onPressed: _temAlteracoes && !_salvando ? _salvar : null,
                  icon: _salvando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('Salvar alterações'),
                );

                if (narrow) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: double.infinity, child: save),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: discard),
                          const SizedBox(width: 8),
                          Expanded(child: reload),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        _temAlteracoes
                            ? 'Existem alterações não salvas.'
                            : 'Permissões sincronizadas.',
                        style: TextStyle(
                          color: _temAlteracoes ? t.warning : t.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    discard,
                    const SizedBox(width: 8),
                    reload,
                    const SizedBox(width: 8),
                    save,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final PermissionDefinition permission;
  final bool active;
  final ValueChanged<bool> onChanged;

  const _PermissionTile({
    required this.permission,
    required this.active,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final color = permission.critical
        ? t.error
        : active
        ? t.success
        : t.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active
            ? color.withValues(alpha: 0.07)
            : t.cardAlt.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(t.buttonRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(!active),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(
                color: active ? color.withValues(alpha: 0.28) : t.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                  child: Icon(permission.icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            permission.title,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          if (permission.critical)
                            _SmallChip(
                              label: 'Crítica',
                              color: t.error,
                              icon: Icons.warning_amber_rounded,
                            ),
                          if (permission.adminOnlySuggested)
                            _SmallChip(
                              label: 'Admin sugerido',
                              color: t.warning,
                              icon: Icons.admin_panel_settings_rounded,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        permission.description,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _CodeChip(permission.key),
                          ...permission.aliases.take(3).map(_CodeChip.new),
                          if (permission.aliases.length > 3)
                            _CodeChip(
                              '+${permission.aliases.length - 3} aliases',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Switch(
                  value: active,
                  onChanged: onChanged,
                  activeThumbColor: color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _SmallChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  final String text;

  const _CodeChip(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: t.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: t.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SummaryData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryData(this.label, this.value, this.icon, this.color);
}
