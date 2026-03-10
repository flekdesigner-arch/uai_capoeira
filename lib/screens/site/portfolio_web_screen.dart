import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/evento_model.dart';
import '../../widgets/timeline_mista_widget.dart';

class PortfolioWebScreen extends StatefulWidget {
  const PortfolioWebScreen({super.key});

  @override
  State<PortfolioWebScreen> createState() => _PortfolioWebScreenState();
}

class _PortfolioWebScreenState extends State<PortfolioWebScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  // Filtros para eventos
  String _filtroCidade = 'Todas';
  String _filtroTipo = 'Todos';

  // Listas para os filtros
  List<String> _cidades = ['Todas'];
  List<String> _tipos = ['Todos'];

  @override
  void initState() {
    super.initState();
    // 🔄 ALTERADO: Agora inicia na Linha do Tempo (índice 0)
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _carregarFiltros();
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

      Set<String> cidadesSet = {};
      Set<String> tiposSet = {};

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

  void _mostrarFiltrosDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Filtrar Eventos',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  value: _filtroCidade,
                  decoration: InputDecoration(
                    labelText: 'Cidade',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.location_city, color: Colors.red),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: _cidades.map((cidade) {
                    return DropdownMenuItem(
                      value: cidade,
                      child: Text(cidade),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setStateDialog(() {
                      _filtroCidade = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _filtroTipo,
                  decoration: InputDecoration(
                    labelText: 'Tipo de Evento',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.category, color: Colors.red),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: _tipos.map((tipo) {
                    return DropdownMenuItem(
                      value: tipo,
                      child: Text(tipo),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setStateDialog(() {
                      _filtroTipo = value!;
                    });
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setStateDialog(() {
                            _filtroCidade = 'Todas';
                            _filtroTipo = 'Todos';
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('LIMPAR'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {});
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('APLICAR'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'PORTFÓLIO',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            fontSize: isMobile ? 18 : 20,
          ),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.6),
          labelStyle: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isMobile ? 11 : 12,
          ),
          unselectedLabelStyle: TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: isMobile ? 11 : 12,
          ),
          isScrollable: isMobile ? true : false,
          // 🔄 ALTERADO: Ordem das tabs invertida
          tabs: const [
            Tab(text: 'LINHA DO TEMPO', icon: Icon(Icons.timeline, size: 18)),
            Tab(text: 'EVENTOS', icon: Icon(Icons.event, size: 18)),
          ],
        ),
      ),
      // 🔄 ALTERADO: Ordem do TabBarView invertida (linha do tempo primeiro)
      body: TabBarView(
        controller: _tabController,
        children: [
          const TimelineMistaWidget(), // Primeira tab: Linha do Tempo
          _buildEventosGrid(), // Segunda tab: Eventos
        ],
      ),
    );
  }

  Widget _buildEventosGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getEventosStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.error_outline,
                    size: 60,
                    color: Colors.red.shade200,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Erro ao carregar eventos',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.red),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('Nenhum evento concluído encontrado');
        }

        final List<EventoModel> eventos = snapshot.data!.docs
            .map((doc) => EventoModel.fromFirestore(doc))
            .toList();

        final screenWidth = MediaQuery.of(context).size.width;
        int crossAxisCount;
        double childAspectRatio;
        double horizontalPadding;

        if (screenWidth > 1200) {
          crossAxisCount = 4;
          childAspectRatio = 0.75;
          horizontalPadding = 24;
        } else if (screenWidth > 900) {
          crossAxisCount = 3;
          childAspectRatio = 0.78;
          horizontalPadding = 20;
        } else if (screenWidth > 600) {
          crossAxisCount = 2;
          childAspectRatio = 0.8;
          horizontalPadding = 16;
        } else {
          crossAxisCount = 2;
          childAspectRatio = 0.9;
          horizontalPadding = 8;
        }

        return Container(
          color: Colors.transparent,
          child: GridView.builder(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 16,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: childAspectRatio,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: eventos.length,
            itemBuilder: (context, index) {
              final evento = eventos[index];
              return _buildEventoCard(evento);
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String mensagem) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_busy,
              size: 60,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            mensagem,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventoCard(EventoModel evento) {
    final hasBanner = evento.linkBanner != null && evento.linkBanner!.isNotEmpty;

    return GestureDetector(
      onTap: () {
        _mostrarDetalhesEvento(context, evento);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Imagem (mantém proporção 1:1)
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: hasBanner
                        ? CachedNetworkImage(
                      imageUrl: evento.linkBanner!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: (context, url) => Container(
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.red,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey.shade200,
                        child: Icon(
                          Icons.broken_image,
                          size: 40,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    )
                        : Container(
                      color: Colors.grey.shade200,
                      child: Icon(
                        evento.iconeDoTipo,
                        size: 40,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                  // Data do evento
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade700,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.shade900.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today, size: 8, color: Colors.white.withOpacity(0.9)),
                          const SizedBox(width: 4),
                          Text(
                            evento.dataFormatada,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Apenas o nome do evento
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    constraints: const BoxConstraints(
                      maxHeight: 40,
                      minHeight: 36,
                    ),
                    child: Text(
                      evento.nome,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDetalhesEvento(BuildContext context, EventoModel evento) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                color: Colors.white,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.all(isMobile ? 16 : 20),
                      children: [
                        if (evento.linkBanner != null && evento.linkBanner!.isNotEmpty)
                          Container(
                            height: isMobile ? 180 : 250,
                            width: double.infinity,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: CachedNetworkImage(
                                imageUrl: evento.linkBanner!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey.shade200,
                                  child: Icon(Icons.broken_image, size: 50, color: Colors.grey.shade400),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          evento.nome,
                          style: TextStyle(
                            fontSize: isMobile ? 20 : 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, size: 14, color: Colors.green.shade300),
                              const SizedBox(width: 6),
                              const Text(
                                'EVENTO CONCLUÍDO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoItemPremium(
                          icon: Icons.calendar_today,
                          label: 'Data',
                          value: evento.dataFormatada,
                          color: Colors.orange,
                          isMobile: isMobile,
                        ),
                        _buildInfoItemPremium(
                          icon: Icons.access_time,
                          label: 'Horário',
                          value: evento.horario,
                          color: Colors.blue,
                          isMobile: isMobile,
                        ),
                        _buildInfoItemPremium(
                          icon: Icons.location_on,
                          label: 'Local',
                          value: evento.local,
                          color: Colors.red,
                          isMobile: isMobile,
                        ),
                        _buildInfoItemPremium(
                          icon: Icons.location_city,
                          label: 'Cidade',
                          value: evento.cidade,
                          color: Colors.purple,
                          isMobile: isMobile,
                        ),
                        _buildInfoItemPremium(
                          icon: Icons.category,
                          label: 'Tipo',
                          value: evento.tipo,
                          color: Colors.green,
                          isMobile: isMobile,
                        ),
                        if (evento.organizadores.isNotEmpty)
                          _buildInfoItemPremium(
                            icon: Icons.people,
                            label: 'Organizadores',
                            value: evento.organizadores.join(', '),
                            color: Colors.teal,
                            isMobile: isMobile,
                          ),
                        const SizedBox(height: 16),
                        if (evento.linkFotosVideos != null && evento.linkFotosVideos!.isNotEmpty)
                          _buildLinkButtonPremium(
                            icon: Icons.photo_library,
                            label: '📸 Fotos e Vídeos',
                            url: evento.linkFotosVideos!,
                            color: Colors.blue,
                            isMobile: isMobile,
                          ),
                        if (evento.previaVideo != null && evento.previaVideo!.isNotEmpty)
                          _buildLinkButtonPremium(
                            icon: Icons.play_circle,
                            label: '▶️ Prévia do Evento',
                            url: evento.previaVideo!,
                            color: Colors.red,
                            isMobile: isMobile,
                          ),
                        if (evento.linkPlaylist != null && evento.linkPlaylist!.isNotEmpty)
                          _buildLinkButtonPremium(
                            icon: Icons.playlist_play,
                            label: '🎵 Playlist',
                            url: evento.linkPlaylist!,
                            color: Colors.green,
                            isMobile: isMobile,
                          ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.all(isMobile ? 16 : 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade900,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'FECHAR',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isMobile ? 14 : 16,
                          ),
                        ),
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

  Widget _buildInfoItemPremium({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isMobile,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 6 : 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: isMobile ? 16 : 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isMobile ? 10 : 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isMobile ? 13 : 14,
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

  Widget _buildLinkButtonPremium({
    required IconData icon,
    required String label,
    required String url,
    required Color color,
    required bool isMobile,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        onPressed: () async {
          final Uri uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        icon: Icon(icon, color: color, size: isMobile ? 18 : 20),
        label: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: isMobile ? 13 : 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withOpacity(0.3)),
          padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: color.withOpacity(0.02),
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