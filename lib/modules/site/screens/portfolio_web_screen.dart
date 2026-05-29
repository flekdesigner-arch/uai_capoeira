import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';
import 'package:uai_capoeira/modules/site/widgets/timeline_mista_widget.dart';
import 'package:uai_capoeira/modules/rastreio/services/rastreio_site.dart';

class PortfolioWebScreen extends StatefulWidget {
  const PortfolioWebScreen({super.key});

  @override
  State<PortfolioWebScreen> createState() => _PortfolioWebScreenState();
}

class _PortfolioWebScreenState extends State<PortfolioWebScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final RastreioSiteService _rastreioService = RastreioSiteService();
  final ScrollController _eventosScrollController = ScrollController();

  int _maiorPercentualEventos = 0;

  String _filtroCidade = 'Todas';
  String _filtroTipo = 'Todos';

  List<String> _cidades = ['Todas'];
  List<String> _tipos = ['Todos'];

  @override
  void initState() {
    super.initState();

    _rastreioService.iniciarTela(
      'portfolio',
      origem: 'site',
      metadata: {
        'aba_inicial': 'linha_do_tempo',
      },
    );
    _rastreioService.marcarTempo('portfolio_tempo');
    _eventosScrollController.addListener(_registrarRolagemEventos);

    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        final aba = _tabController.index == 0 ? 'linha_do_tempo' : 'eventos';

        _rastreioService.registrarClique(
          nome: 'trocar_aba_portfolio',
          origem: 'portfolio',
          metadata: {
            'aba': aba,
            'index': _tabController.index,
          },
        );

        setState(() {});
      }
    });

    _carregarFiltros();
  }

  @override
  void dispose() {
    _rastreioService.registrarTempoMarcador(
      chave: 'portfolio_tempo',
      tipo: 'tempo_tela',
      nome: 'portfolio',
      origem: 'dispose',
      metadata: {
        'aba_final': _tabController.index == 0 ? 'linha_do_tempo' : 'eventos',
        'maior_percentual_eventos': _maiorPercentualEventos,
        'filtro_cidade': _filtroCidade,
        'filtro_tipo': _filtroTipo,
      },
      limparMarcador: true,
    );
    _rastreioService.finalizarTela(destino: 'saida_portfolio');
    _eventosScrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  bool get _temFiltroAtivo =>
      _filtroCidade != 'Todas' || _filtroTipo != 'Todos';

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  void _registrarRolagemEventos() {
    if (!_eventosScrollController.hasClients) return;

    final maxScroll = _eventosScrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final percentual = ((_eventosScrollController.offset / maxScroll) * 100)
        .clamp(0, 100)
        .round();

    final marco = percentual >= 100
        ? 100
        : percentual >= 75
        ? 75
        : percentual >= 50
        ? 50
        : percentual >= 25
        ? 25
        : 0;

    if (marco > _maiorPercentualEventos) {
      _maiorPercentualEventos = marco;

      _rastreioService.registrarEvento(
        tipo: 'rolagem',
        nome: 'portfolio_eventos_$marco%',
        origem: 'portfolio_eventos',
        metadata: {
          'percentual': marco,
          'filtro_cidade': _filtroCidade,
          'filtro_tipo': _filtroTipo,
        },
      );
    }
  }

  Future<void> _carregarFiltros() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('eventos')
          .where('mostrarNoPortfolioWeb', isEqualTo: true)
          .where('status', isEqualTo: 'finalizado')
          .get();

      final eventos = snapshot.docs
          .map((doc) => EventoModel.fromFirestore(doc))
          .toList();

      final cidadesSet = <String>{};
      final tiposSet = <String>{};

      for (final evento in eventos) {
        if (evento.cidade.trim().isNotEmpty) {
          cidadesSet.add(evento.cidade.trim());
        }

        if (evento.tipo.trim().isNotEmpty) {
          tiposSet.add(evento.tipo.trim());
        }
      }

      if (!mounted) return;

      setState(() {
        _cidades = ['Todas', ...cidadesSet.toList()..sort()];
        _tipos = ['Todos', ...tiposSet.toList()..sort()];
      });
    } catch (e) {
      debugPrint('Erro ao carregar filtros do portfólio: $e');
    }
  }

  Stream<QuerySnapshot> _getEventosStream() {
    Query query = FirebaseFirestore.instance
        .collection('eventos')
        .where('mostrarNoPortfolioWeb', isEqualTo: true)
        .where('status', isEqualTo: 'finalizado')
        .orderBy('data', descending: true);

    if (_filtroCidade != 'Todas') {
      query = query.where('cidade', isEqualTo: _filtroCidade);
    }

    if (_filtroTipo != 'Todos') {
      query = query.where('tipo', isEqualTo: _filtroTipo);
    }

    return query.snapshots();
  }

  void _limparFiltros() {
    _rastreioService.registrarFiltro(
      tela: 'portfolio',
      filtro: 'limpar_filtros',
      valor: 'todos',
      origem: 'portfolio_eventos',
      metadata: {
        'cidade_anterior': _filtroCidade,
        'tipo_anterior': _filtroTipo,
      },
    );

    setState(() {
      _filtroCidade = 'Todas';
      _filtroTipo = 'Todos';
    });
  }

  void _mostrarFiltrosDialog() {
    _rastreioService.registrarClique(
      nome: 'abrir_filtros_portfolio',
      origem: 'portfolio_eventos',
      metadata: {
        'filtro_cidade': _filtroCidade,
        'filtro_tipo': _filtroTipo,
      },
    );

    String cidadeTemp = _filtroCidade;
    String tipoTemp = _filtroTipo;

    final t = context.uai;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(t.cardRadius + 4),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _dialogHandle(),
                      const SizedBox(height: 18),
                      _sectionHeader(
                        icon: Icons.tune_rounded,
                        title: 'Filtrar eventos',
                        subtitle: 'Escolha cidade e tipo para encontrar eventos.',
                        color: t.primary,
                      ),
                      const SizedBox(height: 18),
                      _buildDropdownFiltro(
                        label: 'Cidade',
                        icon: Icons.location_city_rounded,
                        value: cidadeTemp,
                        items: _cidades,
                        onChanged: (value) {
                          setStateDialog(() => cidadeTemp = value ?? 'Todas');
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildDropdownFiltro(
                        label: 'Tipo de evento',
                        icon: Icons.category_rounded,
                        value: tipoTemp,
                        items: _tipos,
                        onChanged: (value) {
                          setStateDialog(() => tipoTemp = value ?? 'Todos');
                        },
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 390;

                          final limpar = OutlinedButton.icon(
                            onPressed: () {
                              setStateDialog(() {
                                cidadeTemp = 'Todas';
                                tipoTemp = 'Todos';
                              });
                            },
                            icon: const Icon(Icons.cleaning_services_rounded),
                            label: const Text('LIMPAR'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: t.textPrimary,
                              side: BorderSide(color: t.border),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(t.buttonRadius),
                              ),
                            ),
                          );

                          final aplicar = ElevatedButton.icon(
                            onPressed: () {
                              _rastreioService.registrarFiltro(
                                tela: 'portfolio',
                                filtro: 'aplicar_filtros',
                                valor: '$cidadeTemp | $tipoTemp',
                                origem: 'portfolio_eventos',
                                metadata: {
                                  'cidade': cidadeTemp,
                                  'tipo': tipoTemp,
                                },
                              );

                              setState(() {
                                _filtroCidade = cidadeTemp;
                                _filtroTipo = tipoTemp;
                              });

                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('APLICAR'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: t.primary,
                              foregroundColor: _readableOn(t.primary),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(t.buttonRadius),
                              ),
                            ),
                          );

                          if (narrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                limpar,
                                const SizedBox(height: 10),
                                aplicar,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: limpar),
                              const SizedBox(width: 10),
                              Expanded(child: aplicar),
                            ],
                          );
                        },
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

  Widget _buildDropdownFiltro({
    required String label,
    required IconData icon,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final t = context.uai;
    final safeItems = items.isEmpty ? [value] : items;
    final safeValue = safeItems.contains(value) ? value : safeItems.first;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return DropdownButtonFormField<String>(
      value: safeValue,
      isExpanded: true,
      dropdownColor: t.surface,
      style: TextStyle(color: t.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: t.textSecondary),
        prefixIcon: Icon(icon, color: primary),
        filled: true,
        fillColor: t.cardAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
      items: safeItems.map((item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(
            item,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.textPrimary),
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;

    // IMPORTANTE:
    // Esta tela é usada dentro da LandingPage, que já possui AppBar.
    // Por isso aqui NÃO existe Scaffold/AppBar, evitando duas barras no site público.
    return ColoredBox(
      color: t.background,
      child: Column(
        children: [
          _buildTopoPortfolio(isMobile),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTimelineTab(),
                _buildEventosGrid(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopoPortfolio(bool isMobile) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 22,
        isMobile ? 12 : 16,
        isMobile ? 14 : 22,
        12,
      ),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        boxShadow: t.softShadow,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: isMobile ? 42 : 48,
                    height: isMobile ? 42 : 48,
                    decoration: BoxDecoration(
                      color: onPrimary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                      border: Border.all(color: onPrimary.withOpacity(0.16)),
                    ),
                    child: Icon(
                      Icons.photo_library_rounded,
                      color: onPrimary,
                      size: isMobile ? 23 : 27,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Portfólio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: onPrimary,
                        fontSize: isMobile ? 20 : 24,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (_tabController.index == 1)
                    IconButton(
                      tooltip: 'Filtrar eventos',
                      onPressed: _mostrarFiltrosDialog,
                      icon: Badge(
                        isLabelVisible: _temFiltroAtivo,
                        smallSize: 8,
                        child: Icon(Icons.tune_rounded, color: onPrimary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: isMobile ? 42 : 46,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: onPrimary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: onPrimary.withOpacity(0.16)),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: onPrimary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  dividerColor: Colors.transparent,
                  labelColor: t.primary,
                  unselectedLabelColor: onPrimary.withOpacity(0.88),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: isMobile ? 11.5 : 12.5,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isMobile ? 11.5 : 12.5,
                  ),
                  tabs: const [
                    Tab(
                      height: 34,
                      iconMargin: EdgeInsets.only(right: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.timeline_rounded, size: 15),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Linha do tempo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Tab(
                      height: 34,
                      iconMargin: EdgeInsets.only(right: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_available_rounded, size: 15),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Eventos',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineTab() {
    return ColoredBox(
      color: context.uai.background,
      child: const TimelineMistaWidget(),
    );
  }

  Widget _buildEventosGrid() {
    final t = context.uai;

    return StreamBuilder<QuerySnapshot>(
      stream: _getEventosStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error);
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState();
        }

        final eventos = (snapshot.data?.docs ?? [])
            .map((doc) => EventoModel.fromFirestore(doc))
            .toList();

        if (eventos.isEmpty) {
          return _buildEmptyState(
            _temFiltroAtivo
                ? 'Nenhum evento encontrado com os filtros escolhidos.'
                : 'Nenhum evento concluído encontrado.',
          );
        }

        _rastreioService.registrarBuscaOuFiltroResultado(
          tela: 'portfolio',
          nome: 'eventos_carregados',
          total: eventos.length,
          origem: 'portfolio_eventos',
          metadata: {
            'filtro_cidade': _filtroCidade,
            'filtro_tipo': _filtroTipo,
          },
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isMobile = width < 700;
            final horizontal = isMobile ? 14.0 : 22.0;

            return RefreshIndicator(
              color: t.primary,
              backgroundColor: t.surface,
              onRefresh: () async {
                _rastreioService.registrarClique(
                  nome: 'atualizar_portfolio_eventos',
                  origem: 'portfolio_eventos',
                );
                await _carregarFiltros();
                setState(() {});
              },
              child: ListView(
                controller: _eventosScrollController,
                padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 26),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1160),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeroEventos(eventos.length, isMobile),
                          const SizedBox(height: 10),
                          _buildBotaoFiltroEventosSlim(isMobile),
                          if (_temFiltroAtivo) ...[
                            const SizedBox(height: 12),
                            _buildFiltrosAtivos(),
                          ],
                          const SizedBox(height: 16),
                          _buildEventosWrap(eventos),
                        ],
                      ),
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

  Widget _buildHeroEventos(int total, bool isMobile) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(isMobile ? 24 : t.cardRadius + 4),
        boxShadow: t.softShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.photo_library_rounded,
              color: onPrimary,
              size: 28,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Eventos e memórias',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 23 : 29,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Veja registros dos eventos já realizados pelo grupo.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.80),
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildWhiteChip(
                    icon: Icons.event_available_rounded,
                    label: '$total eventos',
                  ),
                  if (_temFiltroAtivo)
                    _buildWhiteChip(
                      icon: Icons.filter_alt_rounded,
                      label: 'Filtrado',
                    ),
                ],
              ),
            ],
          );

          final button = OutlinedButton.icon(
            onPressed: _mostrarFiltrosDialog,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('FILTRAR'),
            style: OutlinedButton.styleFrom(
              foregroundColor: onPrimary,
              side: BorderSide(color: onPrimary.withOpacity(0.35)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 14),
                text,
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: button),
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }

  Widget _buildWhiteChip({
    required IconData icon,
    required String label,
  }) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

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
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotaoFiltroEventosSlim(bool isMobile) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _mostrarFiltrosDialog,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 14,
            vertical: isMobile ? 10 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: primary.withOpacity(0.15)),
            boxShadow: t.softShadow,
          ),
          child: Row(
            children: [
              Badge(
                isLabelVisible: _temFiltroAtivo,
                smallSize: 8,
                child: Icon(Icons.tune_rounded, color: primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _temFiltroAtivo
                      ? 'Filtros ativos: $_filtroCidade • $_filtroTipo'
                      : 'Filtrar eventos por cidade e tipo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: isMobile ? 12.5 : 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.keyboard_arrow_up_rounded, color: primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFiltrosAtivos() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Icon(Icons.filter_alt_rounded, color: primary),
          const SizedBox(width: 9),
          Expanded(
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if (_filtroCidade != 'Todas')
                  _buildFilterChipText('Cidade: $_filtroCidade'),
                if (_filtroTipo != 'Todos')
                  _buildFilterChipText('Tipo: $_filtroTipo'),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Limpar filtros',
            onPressed: _limparFiltros,
            icon: Icon(Icons.close_rounded, color: t.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChipText(String text) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(primary.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: primary.withOpacity(0.15)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: primary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildEventosWrap(List<EventoModel> eventos) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        int columns;
        if (width < 430) {
          columns = 1;
        } else if (width < 760) {
          columns = 2;
        } else if (width < 1080) {
          columns = 3;
        } else {
          columns = 4;
        }

        const spacing = 12.0;
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: eventos.map((evento) {
            return SizedBox(
              width: itemWidth,
              child: _buildEventoCard(evento),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildEventoCard(EventoModel evento) {
    final t = context.uai;
    final hasBanner = evento.linkBanner != null && evento.linkBanner!.isNotEmpty;

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _rastreioService.registrarItemVisualizado(
            tela: 'portfolio',
            itemTipo: 'evento',
            itemNome: evento.nome,
            itemId: null,
            origem: 'card_evento',
            metadata: {
              'cidade': evento.cidade,
              'tipo': evento.tipo,
              'data': evento.dataFormatada,
            },
          );
          _mostrarDetalhesEvento(context, evento);
        },
        borderRadius: BorderRadius.circular(t.cardRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: 260),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(t.cardRadius),
                ),
                child: AspectRatio(
                  aspectRatio: 1.08,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (hasBanner)
                        CachedNetworkImage(
                          imageUrl: evento.linkBanner!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              _buildImagePlaceholder(),
                          errorWidget: (context, url, error) =>
                              _buildImageError(evento),
                        )
                      else
                        _buildImageError(evento),
                      Positioned(
                        left: 10,
                        top: 10,
                        child: _buildOverlayPill(
                          icon: Icons.check_circle_rounded,
                          label: 'Concluído',
                          color: t.success,
                        ),
                      ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: _buildOverlayPill(
                          icon: Icons.calendar_month_rounded,
                          label: evento.dataFormatada,
                          color: t.warning,
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.58),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Text(
                          evento.nome,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        if (evento.cidade.trim().isNotEmpty)
                          _buildMetaChip(
                            icon: Icons.location_city_rounded,
                            text: evento.cidade,
                            color: t.associacao,
                          ),
                        if (evento.tipo.trim().isNotEmpty)
                          _buildMetaChip(
                            icon: evento.iconeDoTipo,
                            text: evento.tipo,
                            color: t.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          'Ver detalhes',
                          style: TextStyle(
                            color: _ensureVisible(t.primary, t.card),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: _ensureVisible(t.primary, t.card),
                          size: 17,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final accent = _ensureVisible(color, Colors.black);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.56),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 13),
          const SizedBox(width: 4),
          const Text(
            '',
            style: TextStyle(fontSize: 0),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.07), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 13),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    final t = context.uai;

    return Container(
      color: t.cardAlt,
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: t.primary,
        ),
      ),
    );
  }

  Widget _buildImageError(EventoModel evento) {
    final t = context.uai;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.cardAlt, t.card],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        evento.iconeDoTipo,
        size: 54,
        color: t.textMuted,
      ),
    );
  }

  void _mostrarDetalhesEvento(BuildContext context, EventoModel evento) {
    _rastreioService.registrarEvento(
      tipo: 'detalhe',
      nome: 'abrir_detalhes_evento',
      origem: 'portfolio',
      metadata: {
        'evento_nome': evento.nome,
        'cidade': evento.cidade,
        'tipo': evento.tipo,
      },
    );

    final t = context.uai;
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;
    final hasBanner = evento.linkBanner != null && evento.linkBanner!.isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: isMobile ? 0.92 : 0.88,
            minChildSize: 0.58,
            maxChildSize: 0.96,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.background,
                  borderRadius: BorderRadius.circular(t.cardRadius + 8),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        children: [
                          _buildDetalheHeaderEvento(evento, hasBanner, isMobile),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              isMobile ? 14 : 18,
                              14,
                              isMobile ? 14 : 18,
                              22,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildLinksTopoEvento(evento, isMobile),
                                if (_hasAnyLink(evento)) const SizedBox(height: 14),
                                _buildResumoEventoCard(evento),
                                const SizedBox(height: 14),
                                _buildInfoGridEvento(evento, isMobile),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        10,
                        14,
                        isMobile ? 14 : 16,
                      ),
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(t.cardRadius + 8),
                        ),
                        border: Border(top: BorderSide(color: t.border)),
                        boxShadow: t.softShadow,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('FECHAR DETALHES'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t.primary,
                            foregroundColor: _readableOn(t.primary),
                            padding: EdgeInsets.symmetric(
                              vertical: isMobile ? 14 : 15,
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(t.buttonRadius),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  bool _hasAnyLink(EventoModel evento) {
    return (evento.linkFotosVideos != null &&
        evento.linkFotosVideos!.trim().isNotEmpty) ||
        (evento.previaVideo != null && evento.previaVideo!.trim().isNotEmpty) ||
        (evento.linkPlaylist != null && evento.linkPlaylist!.trim().isNotEmpty);
  }

  Widget _buildDetalheHeaderEvento(
      EventoModel evento,
      bool hasBanner,
      bool isMobile,
      ) {
    final t = context.uai;

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(t.cardRadius + 8),
          ),
          child: SizedBox(
            height: isMobile ? 250 : 320,
            width: double.infinity,
            child: hasBanner
                ? CachedNetworkImage(
              imageUrl: evento.linkBanner!,
              fit: BoxFit.cover,
              placeholder: (context, url) => _buildImagePlaceholder(),
              errorWidget: (context, url, error) =>
                  _buildImageError(evento),
            )
                : _buildImageError(evento),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(t.cardRadius + 8),
              ),
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.12),
                  Colors.black.withOpacity(0.42),
                  Colors.black.withOpacity(0.86),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.55),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
        Positioned(
          top: 18,
          right: 12,
          child: Material(
            color: Colors.black.withOpacity(0.36),
            shape: const CircleBorder(),
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        Positioned(
          left: isMobile ? 14 : 18,
          right: isMobile ? 14 : 18,
          bottom: isMobile ? 16 : 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildHeaderBadge(
                    icon: Icons.check_circle_rounded,
                    label: 'Evento concluído',
                    color: t.success,
                  ),
                  if (evento.tipo.trim().isNotEmpty)
                    _buildHeaderBadge(
                      icon: evento.iconeDoTipo,
                      label: evento.tipo,
                      color: t.warning,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                evento.nome,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isMobile ? 24 : 32,
                  height: 1.02,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (evento.dataFormatada.trim().isNotEmpty)
                    _buildHeaderMeta(
                      icon: Icons.calendar_month_rounded,
                      text: evento.dataFormatada,
                    ),
                  if (evento.cidade.trim().isNotEmpty)
                    _buildHeaderMeta(
                      icon: Icons.location_city_rounded,
                      text: evento.cidade,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final accent = _ensureVisible(color, Colors.black);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.42),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMeta({
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinksTopoEvento(EventoModel evento, bool isMobile) {
    final t = context.uai;

    final links = <Widget>[
      if (evento.linkFotosVideos != null &&
          evento.linkFotosVideos!.trim().isNotEmpty)
        _buildLinkTopoButton(
          icon: Icons.photo_library_rounded,
          title: 'Fotos e vídeos',
          subtitle: 'Abrir galeria',
          url: evento.linkFotosVideos!,
          color: t.info,
        ),
      if (evento.previaVideo != null && evento.previaVideo!.trim().isNotEmpty)
        _buildLinkTopoButton(
          icon: Icons.play_circle_rounded,
          title: 'Prévia',
          subtitle: 'Assistir vídeo',
          url: evento.previaVideo!,
          color: t.error,
        ),
      if (evento.linkPlaylist != null &&
          evento.linkPlaylist!.trim().isNotEmpty)
        _buildLinkTopoButton(
          icon: Icons.playlist_play_rounded,
          title: 'Playlist',
          subtitle: 'Ouvir músicas',
          url: evento.linkPlaylist!,
          color: t.success,
        ),
    ];

    if (links.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            icon: Icons.link_rounded,
            title: 'Acesse os registros do evento',
            subtitle: 'Links externos cadastrados para este evento.',
            color: t.primary,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 560
                  ? 1
                  : links.length.clamp(1, 3);
              const spacing = 10.0;
              final itemWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: links
                    .map((child) => SizedBox(width: itemWidth, child: child))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLinkTopoButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Material(
      color: Color.alphaBlend(accent.withOpacity(0.07), t.cardAlt),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirLink(url),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withOpacity(0.14)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, color: accent, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumoEventoCard(EventoModel evento) {
    final t = context.uai;
    final success = _ensureVisible(t.success, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: success.withOpacity(0.09),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.verified_rounded,
              color: success,
              size: 25,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Evento finalizado e registrado no portfólio oficial do grupo.',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                height: 1.28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirLink(String url) async {
    final uri = Uri.tryParse(url);

    _rastreioService.registrarClique(
      nome: 'abrir_link_portfolio',
      origem: 'portfolio_evento',
      metadata: {
        'url': url,
        'host': uri?.host,
      },
    );

    if (uri == null) return;

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildInfoGridEvento(EventoModel evento, bool isMobile) {
    final t = context.uai;

    final items = <_InfoEvento>[
      _InfoEvento(
        icon: Icons.calendar_today_rounded,
        label: 'Data',
        value: evento.dataFormatada,
        color: t.warning,
      ),
      _InfoEvento(
        icon: Icons.access_time_rounded,
        label: 'Horário',
        value: evento.horario,
        color: t.info,
      ),
      _InfoEvento(
        icon: Icons.location_on_rounded,
        label: 'Local',
        value: evento.local,
        color: t.primary,
      ),
      _InfoEvento(
        icon: Icons.location_city_rounded,
        label: 'Cidade',
        value: evento.cidade,
        color: t.associacao,
      ),
      _InfoEvento(
        icon: Icons.category_rounded,
        label: 'Tipo',
        value: evento.tipo,
        color: t.success,
      ),
      if (evento.organizadores.isNotEmpty)
        _InfoEvento(
          icon: Icons.groups_rounded,
          label: 'Organizadores',
          value: evento.organizadores.join(', '),
          color: t.inscricoes,
        ),
    ].where((item) => item.value.trim().isNotEmpty).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 680 ? 1 : 2;
        const spacing = 10.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items.map((item) {
            return SizedBox(
              width: itemWidth,
              child: _buildInfoItemPremium(item),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildInfoItemPremium(_InfoEvento item) {
    final t = context.uai;
    final accent = _ensureVisible(item.color, t.card);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.06), t.cardAlt),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: accent, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 10.8,
                    color: t.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.value,
                  style: TextStyle(
                    fontSize: 13.2,
                    color: t.textPrimary,
                    height: 1.18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    final t = context.uai;

    return Center(
      child: CircularProgressIndicator(color: t.primary),
    );
  }

  Widget _buildErrorState(Object? error) {
    final t = context.uai;
    final danger = _ensureVisible(t.error, t.card);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(24),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 72,
                color: danger,
              ),
              const SizedBox(height: 12),
              Text(
                'Erro ao carregar eventos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error?.toString() ?? 'Tente novamente mais tarde.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String mensagem) {
    final t = context.uai;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(24),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_busy_rounded,
                size: 74,
                color: t.textMuted,
              ),
              const SizedBox(height: 14),
              Text(
                mensagem,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (_temFiltroAtivo) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _limparFiltros,
                  icon: const Icon(Icons.cleaning_services_rounded),
                  label: const Text('LIMPAR FILTROS'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ensureVisible(t.primary, t.card),
                    side: BorderSide(color: t.border),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(t.buttonRadius),
            border: Border.all(color: accent.withOpacity(0.16)),
          ),
          child: Icon(icon, color: accent),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 15.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 11.8,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dialogHandle() {
    final t = context.uai;

    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: t.border,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  BoxDecoration _cardDecoration({Color? borderColor}) {
    final t = context.uai;

    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      border: Border.all(color: borderColor ?? t.border),
      boxShadow: t.softShadow,
    );
  }
}

class _InfoEvento {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoEvento({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}
