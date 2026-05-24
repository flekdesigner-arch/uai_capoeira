import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/evento_model.dart';
import '../../widgets/timeline_mista_widget.dart';

class PortfolioWebScreen extends StatefulWidget {
  const PortfolioWebScreen({super.key});

  @override
  State<PortfolioWebScreen> createState() => _PortfolioWebScreenState();
}

class _PortfolioWebScreenState extends State<PortfolioWebScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _filtroCidade = 'Todas';
  String _filtroTipo = 'Todos';

  List<String> _cidades = ['Todas'];
  List<String> _tipos = ['Todos'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() {});
      }
    });
    _carregarFiltros();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

      if (mounted) {
        setState(() {
          _cidades = ['Todas', ...cidadesSet.toList()..sort()];
          _tipos = ['Todos', ...tiposSet.toList()..sort()];
        });
      }
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

  bool get _temFiltroAtivo =>
      _filtroCidade != 'Todas' || _filtroTipo != 'Todos';

  void _limparFiltros() {
    setState(() {
      _filtroCidade = 'Todas';
      _filtroTipo = 'Todos';
    });
  }

  void _mostrarFiltrosDialog() {
    String cidadeTemp = _filtroCidade;
    String tipoTemp = _filtroTipo;

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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.red.shade900.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(17),
                            ),
                            child: Icon(
                              Icons.tune_rounded,
                              color: Colors.red.shade900,
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
                                    color: Colors.grey.shade900,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  'Escolha cidade e tipo para encontrar eventos.',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setStateDialog(() {
                                  cidadeTemp = 'Todas';
                                  tipoTemp = 'Todos';
                                });
                              },
                              icon: const Icon(Icons.cleaning_services_rounded),
                              label: const Text('LIMPAR'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey.shade800,
                                side: BorderSide(color: Colors.grey.shade300),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _filtroCidade = cidadeTemp;
                                  _filtroTipo = tipoTemp;
                                });
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('APLICAR'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade900,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
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
    final safeItems = items.isEmpty ? [value] : items;
    final safeValue = safeItems.contains(value) ? value : safeItems.first;

    return DropdownButtonFormField<String>(
      value: safeValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.red.shade900),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.red.shade900, width: 1.4),
        ),
      ),
      items: safeItems.map((item) {
        return DropdownMenuItem<String>(
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;
    final isEventosTab = _tabController.index == 1;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'Portfólio',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: isMobile ? 18 : 20,
          ),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (isEventosTab)
            IconButton(
              tooltip: 'Filtrar eventos',
              onPressed: _mostrarFiltrosDialog,
              icon: Badge(
                isLabelVisible: _temFiltroAtivo,
                smallSize: 8,
                child: const Icon(Icons.tune_rounded),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(62),
          child: Container(
            margin: EdgeInsets.fromLTRB(isMobile ? 10 : 18, 0, isMobile ? 10 : 18, 10),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              dividerColor: Colors.transparent,
              labelColor: Colors.red.shade900,
              unselectedLabelColor: Colors.white,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: isMobile ? 11.5 : 12.5,
              ),
              unselectedLabelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: isMobile ? 11.5 : 12.5,
              ),
              tabs: const [
                Tab(
                  iconMargin: EdgeInsets.only(bottom: 2),
                  icon: Icon(Icons.timeline_rounded, size: 18),
                  text: 'Linha do tempo',
                ),
                Tab(
                  iconMargin: EdgeInsets.only(bottom: 2),
                  icon: Icon(Icons.event_available_rounded, size: 18),
                  text: 'Eventos',
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTimelineTab(),
          _buildEventosGrid(),
        ],
      ),
    );
  }

  Widget _buildTimelineTab() {
    return ColoredBox(
      color: Colors.grey.shade50,
      child: const TimelineMistaWidget(),
    );
  }

  Widget _buildEventosGrid() {
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

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isMobile = width < 700;
            final horizontal = isMobile ? 14.0 : 22.0;

            return RefreshIndicator(
              color: Colors.red.shade900,
              onRefresh: () async {
                await _carregarFiltros();
                setState(() {});
              },
              child: ListView(
                padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 26),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1160),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeroEventos(eventos.length, isMobile),
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
    return Container(
      padding: EdgeInsets.all(isMobile ? 18 : 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(isMobile ? 24 : 28),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: const Icon(
              Icons.photo_library_rounded,
              color: Colors.white,
              size: 34,
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
                  color: Colors.white,
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
                  color: Colors.white.withOpacity(0.80),
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
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(0.35)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
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
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltrosAtivos() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.filter_alt_rounded, color: Colors.red.shade900),
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
            icon: Icon(Icons.close_rounded, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChipText(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.red.shade900,
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
    final hasBanner = evento.linkBanner != null && evento.linkBanner!.isNotEmpty;

    return InkWell(
      onTap: () => _mostrarDetalhesEvento(context, evento),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        constraints: const BoxConstraints(minHeight: 260),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 7,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: AspectRatio(
                aspectRatio: 1.08,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasBanner)
                      CachedNetworkImage(
                        imageUrl: evento.linkBanner!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => _buildImagePlaceholder(),
                        errorWidget: (context, url, error) => _buildImageError(evento),
                      )
                    else
                      _buildImageError(evento),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: _buildOverlayPill(
                        icon: Icons.check_circle_rounded,
                        label: 'Concluído',
                        color: Colors.green,
                      ),
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: _buildOverlayPill(
                        icon: Icons.calendar_month_rounded,
                        label: evento.dataFormatada,
                        color: Colors.orange,
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
                          color: Colors.purple,
                        ),
                      if (evento.tipo.trim().isNotEmpty)
                        _buildMetaChip(
                          icon: evento.iconeDoTipo,
                          text: evento.tipo,
                          color: Colors.red,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'Ver detalhes',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.red.shade900,
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
    );
  }

  Widget _buildOverlayPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
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
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.red.shade900,
        ),
      ),
    );
  }

  Widget _buildImageError(EventoModel evento) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey.shade300, Colors.grey.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        evento.iconeDoTipo,
        size: 54,
        color: Colors.grey.shade500,
      ),
    );
  }

  void _mostrarDetalhesEvento(BuildContext context, EventoModel evento) {
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
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.20),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
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
                                const SizedBox(height: 14),
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
                      padding: EdgeInsets.fromLTRB(14, 10, 14, isMobile ? 14 : 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(30),
                        ),
                        border: Border(top: BorderSide(color: Colors.grey.shade200)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.045),
                            blurRadius: 8,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('FECHAR DETALHES'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade900,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              vertical: isMobile ? 14 : 15,
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
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

  Widget _buildDetalheHeaderEvento(
      EventoModel evento,
      bool hasBanner,
      bool isMobile,
      ) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: SizedBox(
            height: isMobile ? 250 : 320,
            width: double.infinity,
            child: hasBanner
                ? CachedNetworkImage(
              imageUrl: evento.linkBanner!,
              fit: BoxFit.cover,
              placeholder: (context, url) => _buildImagePlaceholder(),
              errorWidget: (context, url, error) => _buildImageError(evento),
            )
                : _buildImageError(evento),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
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
                    color: Colors.green,
                  ),
                  if (evento.tipo.trim().isNotEmpty)
                    _buildHeaderBadge(
                      icon: evento.iconeDoTipo,
                      label: evento.tipo,
                      color: Colors.orange,
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
          Icon(icon, color: color, size: 15),
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
    final links = <Widget>[
      if (evento.linkFotosVideos != null && evento.linkFotosVideos!.isNotEmpty)
        _buildLinkTopoButton(
          icon: Icons.photo_library_rounded,
          title: 'Fotos e vídeos',
          subtitle: 'Abrir galeria',
          url: evento.linkFotosVideos!,
          color: Colors.blue,
        ),
      if (evento.previaVideo != null && evento.previaVideo!.isNotEmpty)
        _buildLinkTopoButton(
          icon: Icons.play_circle_rounded,
          title: 'Prévia',
          subtitle: 'Assistir vídeo',
          url: evento.previaVideo!,
          color: Colors.red,
        ),
      if (evento.linkPlaylist != null && evento.linkPlaylist!.isNotEmpty)
        _buildLinkTopoButton(
          icon: Icons.playlist_play_rounded,
          title: 'Playlist',
          subtitle: 'Ouvir músicas',
          url: evento.linkPlaylist!,
          color: Colors.green,
        ),
    ];

    if (links.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.link_rounded,
                  color: Colors.red.shade900,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Acesse os registros do evento',
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 560 ? 1 : links.length.clamp(1, 3);
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
    return InkWell(
      onTap: () => _abrirLink(url),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.14)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color, size: 24),
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
                      color: color,
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
                      color: Colors.grey.shade600,
                      fontSize: 11.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, color: color, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildResumoEventoCard(EventoModel evento) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.09),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: Colors.green,
              size: 25,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Evento finalizado e registrado no portfólio oficial do grupo.',
              style: TextStyle(
                color: Colors.grey.shade800,
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

    if (uri == null) return;

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildStatusPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoGridEvento(EventoModel evento, bool isMobile) {
    final items = <_InfoEvento>[
      _InfoEvento(
        icon: Icons.calendar_today_rounded,
        label: 'Data',
        value: evento.dataFormatada,
        color: Colors.orange,
      ),
      _InfoEvento(
        icon: Icons.access_time_rounded,
        label: 'Horário',
        value: evento.horario,
        color: Colors.blue,
      ),
      _InfoEvento(
        icon: Icons.location_on_rounded,
        label: 'Local',
        value: evento.local,
        color: Colors.red,
      ),
      _InfoEvento(
        icon: Icons.location_city_rounded,
        label: 'Cidade',
        value: evento.cidade,
        color: Colors.purple,
      ),
      _InfoEvento(
        icon: Icons.category_rounded,
        label: 'Tipo',
        value: evento.tipo,
        color: Colors.green,
      ),
      if (evento.organizadores.isNotEmpty)
        _InfoEvento(
          icon: Icons.groups_rounded,
          label: 'Organizadores',
          value: evento.organizadores.join(', '),
          color: Colors.teal,
        ),
    ].where((item) => item.value.trim().isNotEmpty).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 680 ? 1 : 2;
        const spacing = 10.0;
        final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;

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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: item.color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: item.color.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: item.color, size: 21),
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
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.value,
                  style: TextStyle(
                    fontSize: 13.2,
                    color: Colors.grey.shade900,
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

  Widget _buildLinksEvento(EventoModel evento, bool isMobile) {
    final links = <Widget>[
      if (evento.linkFotosVideos != null && evento.linkFotosVideos!.isNotEmpty)
        _buildLinkButtonPremium(
          icon: Icons.photo_library_rounded,
          label: 'Fotos e vídeos',
          url: evento.linkFotosVideos!,
          color: Colors.blue,
        ),
      if (evento.previaVideo != null && evento.previaVideo!.isNotEmpty)
        _buildLinkButtonPremium(
          icon: Icons.play_circle_rounded,
          label: 'Prévia do evento',
          url: evento.previaVideo!,
          color: Colors.red,
        ),
      if (evento.linkPlaylist != null && evento.linkPlaylist!.isNotEmpty)
        _buildLinkButtonPremium(
          icon: Icons.playlist_play_rounded,
          label: 'Playlist',
          url: evento.linkPlaylist!,
          color: Colors.green,
        ),
    ];

    if (links.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Links do evento',
            style: TextStyle(
              color: Colors.grey.shade900,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          if (isMobile)
            Column(
              children: links
                  .map((child) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: child,
              ))
                  .toList(),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: links
                  .map((child) => SizedBox(width: 210, child: child))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildLinkButtonPremium({
    required IconData icon,
    required String label,
    required String url,
    required Color color,
  }) {
    return OutlinedButton.icon(
      onPressed: () => _abrirLink(url),
      icon: Icon(icon, color: color, size: 19),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withOpacity(0.22)),
        backgroundColor: color.withOpacity(0.04),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: CircularProgressIndicator(color: Colors.red.shade900),
    );
  }

  Widget _buildErrorState(Object? error) {
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
                color: Colors.red.shade700,
              ),
              const SizedBox(height: 12),
              const Text(
                'Erro ao carregar eventos',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
              const SizedBox(height: 8),
              Text(
                error?.toString() ?? 'Tente novamente mais tarde.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String mensagem) {
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
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 14),
              Text(
                mensagem,
                textAlign: TextAlign.center,
                style: const TextStyle(
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
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.grey.shade100),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.035),
          blurRadius: 7,
          offset: const Offset(0, 3),
        ),
      ],
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
