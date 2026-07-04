import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'detalhes_evento_screen.dart';
import 'detalhes_evento_andamento_screen.dart';
import 'package:uai_capoeira/modules/campeonatos/screens/gestao_campeonato_screen.dart';

class EventosScreen extends StatefulWidget {
  const EventosScreen({super.key});

  @override
  State<EventosScreen> createState() => _EventosScreenState();
}

class _EventosScreenState extends State<EventosScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PermissaoService _permissaoService = PermissaoService();

  late Future<_EventosPermissoes> _permissoesFuture;

  // Filtros
  String _filtroCidade = 'Todas';
  String _filtroTipo = 'Todos';

  // Listas para os filtros
  List<String> _cidades = ['Todas'];
  List<String> _tipos = ['Todos'];

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
    final saturation = (hsl.saturation + 0.10).clamp(0.0, 1.0).toDouble();

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation(saturation)
        .toColor();
  }

  Color _onCard() => _readableOn(context.uai.card);

  Color _onCardMuted() => _onCard().withOpacity(0.68);

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primaryDark;

  Color _appBarFg() => _onHero(_appBarBg());

  bool _isNeonOnDark() {
    final primary = context.uai.primary;
    final background = context.uai.background;
    final hsl = HSLColor.fromColor(primary);

    return primary.computeLuminance() > 0.50 &&
        background.computeLuminance() < 0.36 &&
        hsl.saturation > 0.55;
  }

  Color _onHero(Color heroBg) {
    if (_isNeonOnDark()) return const Color(0xFFFFFFFF);
    return _readableOn(heroBg);
  }

  bool get _isWideDashboard {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 900;
  }

  bool get _isDesktopDashboard {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 1180;
  }

  double get _dashboardMaxWidth {
    final width = MediaQuery.sizeOf(context).width;

    if (width >= 1600) return 1320;
    if (width >= 1180) return 1180;
    if (width >= 900) return 1040;

    return width;
  }

  EdgeInsets get _dashboardPagePadding {
    final width = MediaQuery.sizeOf(context).width;

    if (width >= 1180) {
      return const EdgeInsets.fromLTRB(22, 18, 22, 28);
    }

    if (width >= 900) {
      return const EdgeInsets.fromLTRB(18, 16, 18, 24);
    }

    return const EdgeInsets.fromLTRB(14, 12, 14, 22);
  }

  Widget _dashboardWidthLimiter(Widget child) {
    if (!_isWideDashboard) return child;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _dashboardMaxWidth),
        child: child,
      ),
    );
  }

  Widget _dashboardResponsiveWrap({
    required List<Widget> children,
    double minItemWidth = 360,
    int maxColumns = 4,
    double spacing = 12,
    double runSpacing = 12,
    bool centerLastRow = true,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(children.length, (index) {
              final isLast = index == children.length - 1;

              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : runSpacing),
                child: SizedBox(width: double.infinity, child: children[index]),
              );
            }),
          );
        }

        final columns = (width / minItemWidth)
            .floor()
            .clamp(1, maxColumns)
            .toInt();

        final itemWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          alignment: centerLastRow ? WrapAlignment.center : WrapAlignment.start,
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
    _permissoesFuture = _carregarPermissoesTela();
  }

  Future<_EventosPermissoes> _carregarPermissoesTela() async {
    final results = await Future.wait<bool>([
      _permissaoService.temQualquerPermissao([
        'pode_acessar_eventos',
        'podeAcessarEventos',
        'pode_ver_eventos',
        'pode_criar_evento',
        'pode_editar_evento',
        'pode_gerenciar_participantes_evento',
        'pode_ver_participantes_evento',
      ]),
      _permissaoService.temQualquerPermissao([
        'pode_ver_eventos',
        'pode_acessar_eventos',
        'podeAcessarEventos',
      ]),
      _permissaoService.temQualquerPermissao([
        'pode_ver_eventos_andamento',
        'pode_acessar_eventos_andamento',
        'pode_gerenciar_eventos_andamento',
      ]),
      _permissaoService.temQualquerPermissao(['pode_editar_evento']),
      _permissaoService.temQualquerPermissao(['pode_excluir_evento']),
      _permissaoService.temQualquerPermissao(['pode_finalizar_evento']),
      _permissaoService.temQualquerPermissao(['pode_criar_evento']),
      _permissaoService.temQualquerPermissao([
        'pode_gerenciar_participantes_evento',
        'pode_ver_participantes_evento',
      ]),
    ]);

    final permissoes = _EventosPermissoes(
      podeAcessarEventos: results[0],
      podeVerEventos: results[1],
      podeVerEventosAndamento: results[2],
      podeEditarEvento: results[3],
      podeExcluirEvento: results[4],
      podeFinalizarEvento: results[5],
      podeCriarEvento: results[6],
      podeGerenciarParticipantes: results[7],
    );

    if (permissoes.podeEntrarModulo) {
      await _carregarFiltros();
      await _selecionarAbaInicial(permissoes);
    }

    return permissoes;
  }

  Future<void> _recarregarPermissoes() async {
    await _permissaoService.recarregarPermissoes();

    if (!mounted) return;

    setState(() {
      _permissoesFuture = _carregarPermissoesTela();
    });
  }

  Future<void> _selecionarAbaInicial(_EventosPermissoes permissoes) async {
    // Regra:
    // - Se existir evento em andamento E o usuário puder ver andamento, abre na aba EM ANDAMENTO.
    // - Se não existir, ou se o usuário não puder ver andamento, fica em TODOS.
    try {
      if (!permissoes.podeVerEventosAndamento) {
        _agendarTrocaAba(0);
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('eventos')
          .where('status', isEqualTo: 'andamento')
          .limit(1)
          .get();

      _agendarTrocaAba(snapshot.docs.isNotEmpty ? 1 : 0);
    } catch (e) {
      debugPrint('Erro ao selecionar aba inicial de eventos: $e');
      _agendarTrocaAba(0);
    }
  }

  void _agendarTrocaAba(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tabController.index == index) return;

      _tabController.animateTo(index);
    });
  }

  Future<void> _carregarFiltros() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('eventos')
          .get();

      final eventos = snapshot.docs
          .map((doc) => EventoModel.fromFirestore(doc))
          .toList();

      final cidadesSet = <String>{};
      final tiposSet = <String>{};

      for (var evento in eventos) {
        if (evento.cidade.isNotEmpty) {
          cidadesSet.add(evento.cidade);
        }

        if (evento.tipo.isNotEmpty) {
          tiposSet.add(evento.tipo);
        }
      }

      if (mounted) {
        setState(() {
          _cidades = ['Todas', ...cidadesSet.toList()..sort()];
          _tipos = ['Todos', ...tiposSet.toList()..sort()];
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar filtros: $e');
    }
  }

  Stream<QuerySnapshot> _getEventosStream() {
    Query query = FirebaseFirestore.instance
        .collection('eventos')
        .orderBy('data', descending: true);

    if (_filtroCidade != 'Todas') {
      query = query.where('cidade', isEqualTo: _filtroCidade);
    }

    if (_filtroTipo != 'Todos') {
      query = query.where('tipo', isEqualTo: _filtroTipo);
    }

    return query.snapshots();
  }

  void _mostrarSemPermissao(String mensagem) {
    final bg = context.uai.error;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mensagem,
          style: TextStyle(
            color: _readableOn(bg),
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  void _mostrarFiltrosDialog() {
    final sheetBg = context.uai.surface;
    final sheetOn = _readableOn(sheetBg);
    final accent = _ensureVisible(context.uai.primary, sheetBg);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0x00000000),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return SafeArea(
              child: Padding(
                padding: MediaQuery.viewInsetsOf(context),
                child: Container(
                  decoration: BoxDecoration(
                    color: sheetBg,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    border: Border(
                      top: BorderSide(color: context.uai.border),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: context.uai.border,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: Color.alphaBlend(
                                  accent.withOpacity(0.10),
                                  sheetBg,
                                ),
                                borderRadius: BorderRadius.circular(17),
                                border: Border.all(
                                  color: accent.withOpacity(0.16),
                                ),
                              ),
                              child: Icon(
                                Icons.tune_rounded,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Filtrar eventos',
                                    style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                      color: sheetOn,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Refine por cidade e tipo de evento.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: sheetOn.withOpacity(0.62),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _buildFilterDropdown(
                          value: _filtroCidade,
                          label: 'Cidade',
                          icon: Icons.location_city_rounded,
                          items: _cidades,
                          onChanged: (value) {
                            if (value == null) return;

                            setStateDialog(() {
                              _filtroCidade = value;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        _buildFilterDropdown(
                          value: _filtroTipo,
                          label: 'Tipo de evento',
                          icon: Icons.category_rounded,
                          items: _tipos,
                          onChanged: (value) {
                            if (value == null) return;

                            setStateDialog(() {
                              _filtroTipo = value;
                            });
                          },
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setStateDialog(() {
                                    _filtroCidade = 'Todas';
                                    _filtroTipo = 'Todos';
                                  });
                                },
                                icon: const Icon(Icons.cleaning_services_rounded),
                                label: const Text('LIMPAR'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: accent,
                                  side: BorderSide(
                                    color: accent.withOpacity(0.22),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      context.uai.buttonRadius,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {});
                                  Navigator.pop(context);
                                },
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('APLICAR'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: context.uai.primary,
                                  foregroundColor:
                                  _readableOn(context.uai.primary),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      context.uai.buttonRadius,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required String label,
    required IconData icon,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final base = context.uai.cardAlt;
    final accent = _ensureVisible(context.uai.primary, base);

    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: context.uai.surface,
      style: TextStyle(
        color: _readableOn(context.uai.surface),
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: context.uai.textSecondary,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(icon, color: accent),
        filled: true,
        fillColor: base,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uai.inputRadius),
          borderSide: BorderSide(color: context.uai.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uai.inputRadius),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uai.inputRadius),
        ),
      ),
      items: items.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(
            item,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  void _abrirEvento({
    required EventoModel evento,
    required String docId,
    required _EventosPermissoes permissoes,
  }) {
    final status = evento.status;
    final tipo = evento.tipo.toLowerCase().trim();
    final isCampeonato = tipo == 'campeonato';

    if (status == 'andamento' && !permissoes.podeVerEventosAndamento) {
      _mostrarSemPermissao(
        'Você não tem permissão para abrir eventos em andamento.',
      );
      return;
    }

    if (isCampeonato && status != 'finalizado') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GestaoCampeonatoScreen(
            campeonatoId: docId,
            nomeCampeonato: evento.nome,
          ),
        ),
      );
      return;
    }

    if (isCampeonato && status == 'finalizado') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              DetalhesEventoScreen(evento: evento, eventoId: docId),
        ),
      );
      return;
    }

    if (status == 'andamento') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              DetalhesEventoAndamentoScreen(evento: evento, eventoId: docId),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DetalhesEventoScreen(evento: evento, eventoId: docId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_EventosPermissoes>(
      future: _permissoesFuture,
      builder: (context, snapshot) {
        final loadingPermissoes =
            snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData;

        if (loadingPermissoes) {
          return Scaffold(
            backgroundColor: context.uai.background,
            appBar: _buildAppBar(const _EventosPermissoes()),
            body: _buildLoadingPermissoes(),
          );
        }

        final permissoes = snapshot.data ?? const _EventosPermissoes();

        if (!permissoes.podeEntrarModulo) {
          return Scaffold(
            backgroundColor: context.uai.background,
            appBar: _buildAppBar(permissoes),
            body: _buildSemAcessoEventos(),
          );
        }

        return Scaffold(
          backgroundColor: context.uai.background,
          appBar: _buildAppBar(permissoes),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildEventosGrid('todos', permissoes),
              _buildEventosGrid('andamento', permissoes),
              _buildEventosGrid('finalizado', permissoes),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(_EventosPermissoes permissoes) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 430;
    final fg = _appBarFg();

    return AppBar(
      titleSpacing: isCompact ? 4 : null,
      title: Text(
        'EVENTOS',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: isCompact ? 1.2 : 2,
          fontSize: isCompact ? 17 : 20,
          color: fg,
        ),
      ),
      backgroundColor: _appBarBg(),
      foregroundColor: fg,
      elevation: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: context.uai.primaryGradient,
        ),
      ),
      bottom: TabBar(
        controller: _tabController,
        isScrollable: isCompact,
        indicatorColor: fg,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: fg,
        unselectedLabelColor: fg.withOpacity(0.62),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        tabs: const [
          Tab(text: 'TODOS', icon: Icon(Icons.event_rounded, size: 18)),
          Tab(
            text: 'EM ANDAMENTO',
            icon: Icon(Icons.pending_actions_rounded, size: 18),
          ),
          Tab(
            text: 'FINALIZADOS',
            icon: Icon(Icons.history_rounded, size: 18),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _recarregarPermissoes,
          tooltip: 'Recarregar permissões',
        ),
        Container(
          margin: EdgeInsets.only(right: isCompact ? 4 : 8),
          decoration: BoxDecoration(
            color: fg.withOpacity(0.14),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: fg.withOpacity(0.10)),
          ),
          child: IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: _mostrarFiltrosDialog,
            tooltip: 'Filtrar eventos',
          ),
        ),
      ],
    );
  }

  Widget _buildEventosGrid(String status, _EventosPermissoes permissoes) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getEventosStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErroState('Erro ao carregar eventos');
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingEventos();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyPage(
            mensagem: 'Nenhum evento encontrado',
            icon: Icons.event_busy_rounded,
          );
        }

        final itensBase = snapshot.data!.docs.map((doc) {
          return _EventoItem(
            evento: EventoModel.fromFirestore(doc),
            docId: doc.id,
          );
        }).toList();

        final itensPermitidos = permissoes.podeVerEventosAndamento
            ? itensBase
            : itensBase
            .where((item) => item.evento.status != 'andamento')
            .toList();

        var itensVisiveis = itensPermitidos;

        if (status != 'todos') {
          itensVisiveis = itensPermitidos
              .where((item) => item.evento.status == status)
              .toList();
        }

        return _buildEventosScroll(
          status: status,
          itensPermitidos: itensPermitidos,
          itensVisiveis: itensVisiveis,
          permissoes: permissoes,
        );
      },
    );
  }

  Widget _buildEventosScroll({
    required String status,
    required List<_EventoItem> itensPermitidos,
    required List<_EventoItem> itensVisiveis,
    required _EventosPermissoes permissoes,
  }) {
    final emptyMessage = status == 'andamento'
        ? 'Nenhum evento em andamento liberado para você'
        : status == 'finalizado'
        ? 'Nenhum evento finalizado'
        : 'Nenhum evento encontrado';

    return SafeArea(
      child: ListView(
        padding: _dashboardPagePadding,
        children: [
          _dashboardWidthLimiter(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEventosHero(
                  status: status,
                  itensPermitidos: itensPermitidos,
                  itensVisiveis: itensVisiveis,
                ),
                const SizedBox(height: 12),
                _buildFilterSummaryBar(
                  totalFiltrado: itensPermitidos.length,
                  totalVisivel: itensVisiveis.length,
                ),
                const SizedBox(height: 14),
                if (itensVisiveis.isEmpty)
                  _buildInlineEmptyState(emptyMessage)
                else
                  _buildEventosCardsWrap(
                    itens: itensVisiveis,
                    permissoes: permissoes,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventosHero({
    required String status,
    required List<_EventoItem> itensPermitidos,
    required List<_EventoItem> itensVisiveis,
  }) {
    final heroBg = context.uai.primaryDark;
    final heroFg = _onHero(heroBg);

    final total = itensPermitidos.length;
    final emAndamento = itensPermitidos
        .where((item) => item.evento.status == 'andamento')
        .length;
    final finalizados = itensPermitidos
        .where((item) => item.evento.status == 'finalizado')
        .length;

    final title = switch (status) {
      'andamento' => 'Eventos em andamento',
      'finalizado' => 'Eventos finalizados',
      _ => 'Painel de eventos',
    };

    final subtitle = switch (status) {
      'andamento' =>
      'Acompanhe os eventos ativos e campeonatos que ainda estão rolando.',
      'finalizado' =>
      'Consulte o histórico dos eventos já encerrados no sistema.',
      _ =>
      'Gerencie, acompanhe e consulte os eventos cadastrados da UAI Capoeira.',
    };

    final icon = switch (status) {
      'andamento' => Icons.pending_actions_rounded,
      'finalizado' => Icons.history_rounded,
      _ => Icons.event_available_rounded,
    };

    final heroContent = Container(
      padding: EdgeInsets.all(_isDesktopDashboard ? 22 : 18),
      decoration: BoxDecoration(
        gradient: context.uai.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: _isWideDashboard
          ? Row(
        children: [
          _buildHeroIcon(icon, heroFg),
          const SizedBox(width: 16),
          Expanded(
            child: _buildHeroText(
              title: title,
              subtitle: subtitle,
              heroFg: heroFg,
            ),
          ),
          const SizedBox(width: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _buildHeroMetrics(
              heroFg: heroFg,
              total: total,
              emAndamento: emAndamento,
              finalizados: finalizados,
              visiveis: itensVisiveis.length,
            ),
          ),
        ],
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildHeroIcon(icon, heroFg),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHeroText(
                  title: title,
                  subtitle: subtitle,
                  heroFg: heroFg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildHeroMetrics(
            heroFg: heroFg,
            total: total,
            emAndamento: emAndamento,
            finalizados: finalizados,
            visiveis: itensVisiveis.length,
          ),
        ],
      ),
    );

    return heroContent;
  }

  Widget _buildHeroIcon(IconData icon, Color heroFg) {
    return Container(
      width: _isWideDashboard ? 58 : 52,
      height: _isWideDashboard ? 58 : 52,
      decoration: BoxDecoration(
        color: heroFg.withOpacity(0.14),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: heroFg.withOpacity(0.18)),
      ),
      child: Icon(icon, color: heroFg, size: _isWideDashboard ? 30 : 28),
    );
  }

  Widget _buildHeroText({
    required String title,
    required String subtitle,
    required Color heroFg,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: heroFg,
            fontSize: _isWideDashboard ? 24 : 19,
            height: 1.08,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          maxLines: _isWideDashboard ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: heroFg.withOpacity(0.78),
            fontSize: _isWideDashboard ? 13.5 : 12.2,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildHeroMetrics({
    required Color heroFg,
    required int total,
    required int emAndamento,
    required int finalizados,
    required int visiveis,
  }) {
    final metrics = [
      _HeroMetricData(
        label: 'Total',
        value: total.toString(),
        icon: Icons.event_rounded,
      ),
      _HeroMetricData(
        label: 'Andamento',
        value: emAndamento.toString(),
        icon: Icons.play_circle_outline_rounded,
      ),
      _HeroMetricData(
        label: 'Finalizados',
        value: finalizados.toString(),
        icon: Icons.check_circle_outline_rounded,
      ),
      _HeroMetricData(
        label: 'Na aba',
        value: visiveis.toString(),
        icon: Icons.visibility_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width < 360 ? 2 : 4;
        final spacing = width < 360 ? 8.0 : 9.0;
        final itemWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          alignment: WrapAlignment.center,
          children: metrics.map((metric) {
            return SizedBox(
              width: itemWidth,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: heroFg.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: heroFg.withOpacity(0.14)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(metric.icon, color: heroFg, size: 17),
                    const SizedBox(height: 4),
                    Text(
                      metric.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: heroFg,
                        fontSize: 16,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      metric.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: heroFg.withOpacity(0.72),
                        fontSize: 9.5,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildFilterSummaryBar({
    required int totalFiltrado,
    required int totalVisivel,
  }) {
    final base = context.uai.card;
    final accent = _ensureVisible(context.uai.primary, base);

    final filtrosAtivos = _filtroCidade != 'Todas' || _filtroTipo != 'Todos';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.uai.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildFilterPill(
            icon: Icons.location_on_outlined,
            label: 'Cidade',
            value: _filtroCidade,
            accent: accent,
          ),
          _buildFilterPill(
            icon: Icons.category_outlined,
            label: 'Tipo',
            value: _filtroTipo,
            accent: context.uai.info,
          ),
          _buildFilterPill(
            icon: Icons.filter_alt_outlined,
            label: 'Filtrados',
            value: '$totalVisivel de $totalFiltrado',
            accent: context.uai.success,
          ),
          if (filtrosAtivos)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _filtroCidade = 'Todas';
                  _filtroTipo = 'Todos';
                });
              },
              icon: const Icon(Icons.close_rounded, size: 17),
              label: const Text('Limpar filtros'),
              style: TextButton.styleFrom(
                foregroundColor: _ensureVisible(context.uai.error, base),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterPill({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    final base = context.uai.cardAlt;
    final visibleAccent = _ensureVisible(accent, base);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(visibleAccent.withOpacity(0.08), base),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: visibleAccent.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: visibleAccent, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              color: _onCardMuted(),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: visibleAccent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventosCardsWrap({
    required List<_EventoItem> itens,
    required _EventosPermissoes permissoes,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final spacing = width < 420 ? 10.0 : 12.0;

        final columns = width < 330
            ? 1
            : width < 470
            ? 2
            : width < 760
            ? 3
            : width < 980
            ? 3
            : width < 1220
            ? 4
            : 5;

        final itemWidth = (width - (spacing * (columns - 1))) / columns;

        final heightFactor = itemWidth < 180
            ? 1.44
            : itemWidth < 230
            ? 1.36
            : 1.30;

        final itemHeight = itemWidth * heightFactor;

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: spacing,
          runSpacing: spacing,
          children: itens.map((item) {
            return SizedBox(
              width: itemWidth,
              height: itemHeight,
              child: _buildEventoCard(
                item.evento,
                item.docId,
                permissoes,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildErroState(String mensagem) {
    return _buildStatePage(
      icon: Icons.error_outline_rounded,
      title: 'Ops, algo deu errado',
      mensagem: mensagem,
      accent: context.uai.error,
      actionLabel: 'Tentar novamente',
      onPressed: () => setState(() {}),
    );
  }

  Widget _buildLoadingEventos() {
    return _buildStatePage(
      title: 'Carregando eventos...',
      mensagem: 'Buscando os eventos cadastrados no sistema.',
      accent: context.uai.primary,
      customIcon: SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: context.uai.primary,
        ),
      ),
    );
  }

  Widget _buildLoadingPermissoes() {
    return _buildStatePage(
      title: 'Carregando permissões...',
      mensagem: 'Verificando o que está liberado para este usuário.',
      accent: context.uai.primary,
      customIcon: SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: context.uai.primary,
        ),
      ),
    );
  }

  Widget _buildSemAcessoEventos() {
    return _buildStatePage(
      icon: Icons.lock_outline_rounded,
      title: 'Acesso não liberado',
      mensagem:
      'Peça para o administrador liberar a permissão de acesso aos eventos.',
      accent: context.uai.error,
      actionLabel: 'Recarregar permissões',
      onPressed: _recarregarPermissoes,
    );
  }

  Widget _buildEmptyPage({
    required String mensagem,
    required IconData icon,
  }) {
    return _buildStatePage(
      icon: icon,
      title: 'Nada por aqui ainda',
      mensagem: mensagem,
      accent: context.uai.info,
    );
  }

  Widget _buildInlineEmptyState(String mensagem) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.uai.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                context.uai.info.withOpacity(0.08),
                context.uai.cardAlt,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: context.uai.info.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.event_busy_rounded,
              size: 34,
              color: _ensureVisible(context.uai.info, context.uai.cardAlt),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            mensagem,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _onCard(),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ajuste os filtros ou cadastre novos eventos para aparecerem aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _onCardMuted(),
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatePage({
    IconData? icon,
    Widget? customIcon,
    required String title,
    required String mensagem,
    required Color accent,
    String? actionLabel,
    VoidCallback? onPressed,
  }) {
    final cardBg = context.uai.card;
    final visibleAccent = _ensureVisible(accent, cardBg);

    return SafeArea(
      child: Center(
        child: Padding(
          padding: _dashboardPagePadding,
          child: _dashboardWidthLimiter(
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: visibleAccent.withOpacity(0.14)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.045),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        visibleAccent.withOpacity(0.10),
                        context.uai.cardAlt,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: visibleAccent.withOpacity(0.16),
                      ),
                    ),
                    child: Center(
                      child: customIcon ??
                          Icon(
                            icon ?? Icons.info_outline_rounded,
                            size: 38,
                            color: visibleAccent,
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _onCard(),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mensagem,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _onCardMuted(),
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (actionLabel != null && onPressed != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: onPressed,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(actionLabel),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: visibleAccent,
                        side: BorderSide(color: visibleAccent.withOpacity(0.25)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            context.uai.buttonRadius,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _normalizarBannerUrl(EventoModel evento) {
    final raw = evento.linkBanner?.trim();

    if (raw == null || raw.isEmpty) {
      return null;
    }

    // CachedNetworkImage só consegue abrir http/https diretamente.
    // Se algum evento estiver salvo com gs://, path local ou texto inválido,
    // a imagem não aparece nessa tela.
    final uri = Uri.tryParse(raw);

    if (uri == null || !uri.hasScheme) {
      debugPrint('🖼️ [Eventos] Banner inválido para "${evento.nome}": $raw');
      return null;
    }

    final scheme = uri.scheme.toLowerCase();

    if (scheme != 'http' && scheme != 'https') {
      debugPrint(
        '🖼️ [Eventos] Banner ignorado para "${evento.nome}". '
            'Use URL http/https. Valor atual: $raw',
      );
      return null;
    }

    return uri.toString();
  }

  Widget _buildEventoBannerImage(EventoModel evento) {
    final url = _normalizarBannerUrl(evento);

    if (url == null) {
      return _buildEventoBannerFallback(
        icon: Icons.image_not_supported_outlined,
        label: 'Sem banner',
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 100),
      useOldImageOnUrlChange: true,
      memCacheWidth: 900,
      placeholder: (context, _) {
        return Container(
          color: context.uai.cardAlt,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.uai.primary,
              ),
            ),
          ),
        );
      },
      errorWidget: (context, url, error) {
        debugPrint(
          '🖼️ [Eventos] Erro ao carregar banner de "${evento.nome}": $error | $url',
        );

        return _buildEventoBannerFallback(
          icon: Icons.broken_image_outlined,
          label: 'Imagem indisponível',
        );
      },
    );
  }

  Widget _buildEventoBannerFallback({
    required IconData icon,
    required String label,
  }) {
    final base = context.uai.cardAlt;
    final accent = _ensureVisible(context.uai.primary, base);

    return Container(
      color: base,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: context.uai.textMuted, size: 30),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accent.withOpacity(0.78),
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventoCard(
      EventoModel evento,
      String docId,
      _EventosPermissoes permissoes,
      ) {
    final status = evento.status;

    final corStatus = status == 'finalizado'
        ? _ensureVisible(context.uai.textMuted, context.uai.card)
        : status == 'andamento'
        ? context.uai.success
        : context.uai.info;

    final textoStatus = status == 'finalizado'
        ? 'Finalizado'
        : status == 'andamento'
        ? 'Andamento'
        : 'Ativo';

    final bloqueadoAndamento =
        status == 'andamento' && !permissoes.podeVerEventosAndamento;

    final borderAccent = bloqueadoAndamento
        ? context.uai.warning.withOpacity(0.28)
        : context.uai.border;

    return Material(
      color: context.uai.card,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (bloqueadoAndamento) {
            _mostrarSemPermissao(
              'Você não tem permissão para abrir eventos em andamento.',
            );
            return;
          }

          _abrirEvento(evento: evento, docId: docId, permissoes: permissoes);
        },
        child: Ink(
          decoration: BoxDecoration(
            color: context.uai.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderAccent),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth;
              final isTiny = cardWidth < 175;
              final isDesktopCard = cardWidth >= 230;

              return Column(
                children: [
                  AspectRatio(
                    aspectRatio: isTiny ? 1.10 : 1.16,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildEventoBannerImage(evento),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x22000000),
                                Color(0x00000000),
                                Color(0x55000000),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _buildCardBadge(
                            text: bloqueadoAndamento
                                ? 'Bloqueado'
                                : textoStatus,
                            color: bloqueadoAndamento
                                ? context.uai.warning
                                : corStatus,
                            maxWidth: isTiny ? 78 : 96,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: _buildCardBadge(
                            text: evento.dataFormatada,
                            color: context.uai.warning,
                            maxWidth: isTiny ? 74 : 96,
                          ),
                        ),
                        if (bloqueadoAndamento)
                          Container(
                            color: Color.alphaBlend(
                              context.uai.warning.withOpacity(0.10),
                              context.uai.card.withOpacity(0.74),
                            ),
                            child: Center(
                              child: Container(
                                width: isTiny ? 42 : 50,
                                height: isTiny ? 42 : 50,
                                decoration: BoxDecoration(
                                  color: context.uai.card.withOpacity(0.88),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: context.uai.warning.withOpacity(0.24),
                                  ),
                                ),
                                child: Icon(
                                  Icons.lock_outline_rounded,
                                  color: _ensureVisible(
                                    context.uai.warning,
                                    context.uai.card,
                                  ),
                                  size: isTiny ? 24 : 28,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isTiny ? 8 : 10,
                        isTiny ? 7 : 9,
                        isTiny ? 8 : 10,
                        isTiny ? 8 : 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Center(
                              child: Text(
                                evento.nome,
                                textAlign: TextAlign.center,
                                maxLines: isDesktopCard ? 3 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: isTiny ? 11.4 : 12.6,
                                  height: 1.08,
                                  fontWeight: FontWeight.w900,
                                  color: _onCard(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _buildCardInfoLine(
                            icon: Icons.category_outlined,
                            text: evento.tipo.isEmpty
                                ? 'Evento'
                                : evento.tipo,
                            isTiny: isTiny,
                          ),
                          const SizedBox(height: 4),
                          _buildCardInfoLine(
                            icon: Icons.location_on_outlined,
                            text: evento.cidade.isEmpty
                                ? 'Cidade não informada'
                                : evento.cidade,
                            isTiny: isTiny,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCardInfoLine({
    required IconData icon,
    required String text,
    required bool isTiny,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: isTiny ? 12 : 13,
          color: _ensureVisible(context.uai.primary, context.uai.card),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _onCardMuted(),
              fontSize: isTiny ? 9.4 : 10.3,
              height: 1.05,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardBadge({
    required String text,
    required Color color,
    required double maxWidth,
  }) {
    final bg = color;
    final fg = _readableOn(bg);

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: fg,
          fontSize: 9.2,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

class _EventoItem {
  final EventoModel evento;
  final String docId;

  const _EventoItem({
    required this.evento,
    required this.docId,
  });
}

class _HeroMetricData {
  final String label;
  final String value;
  final IconData icon;

  const _HeroMetricData({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class _EventosPermissoes {
  final bool podeAcessarEventos;
  final bool podeVerEventos;
  final bool podeVerEventosAndamento;
  final bool podeEditarEvento;
  final bool podeExcluirEvento;
  final bool podeFinalizarEvento;
  final bool podeCriarEvento;
  final bool podeGerenciarParticipantes;

  const _EventosPermissoes({
    this.podeAcessarEventos = false,
    this.podeVerEventos = false,
    this.podeVerEventosAndamento = false,
    this.podeEditarEvento = false,
    this.podeExcluirEvento = false,
    this.podeFinalizarEvento = false,
    this.podeCriarEvento = false,
    this.podeGerenciarParticipantes = false,
  });

  bool get podeEntrarModulo =>
      podeAcessarEventos ||
          podeVerEventos ||
          podeCriarEvento ||
          podeEditarEvento ||
          podeGerenciarParticipantes;
}

// ============================================================
// Tela refatorada visualmente em 03/07/2026 às 11:49
// Refatoração focada em tema dinâmico, responsividade e layout adaptativo.
// Lógica original preservada.
// ============================================================