import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/evento_model.dart';

class TimelineMistaWidget extends StatefulWidget {
  final int limitePorPagina;

  const TimelineMistaWidget({
    super.key,
    this.limitePorPagina = 20,
  });

  @override
  State<TimelineMistaWidget> createState() => _TimelineMistaWidgetState();
}

class _TimelineMistaWidgetState extends State<TimelineMistaWidget> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _itensTimeline = [];
  DocumentSnapshot? _ultimoDocPublicacao;
  DocumentSnapshot? _ultimoDocEvento;
  bool _carregandoMais = false;
  bool _temMaisPublicacoes = true;
  bool _temMaisEventos = true;
  bool _carregandoInicial = true;

  @override
  void initState() {
    super.initState();
    _carregarPrimeirosItens();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      if (!_carregandoMais && (_temMaisPublicacoes || _temMaisEventos)) {
        _carregarMaisItens();
      }
    }
  }

  Future<void> _carregarPrimeirosItens() async {
    setState(() {
      _carregandoInicial = true;
      _itensTimeline = [];
    });

    try {
      Query queryPublicacoes = _firestore
          .collection('timeline_publicacoes')
          .orderBy('data_publicacao', descending: true)
          .limit(widget.limitePorPagina ~/ 2);

      Query queryEventos = _firestore
          .collection('eventos')
          .where('mostrarNoPortfolioWeb', isEqualTo: true)
          .where('status', isEqualTo: 'finalizado')
          .orderBy('data', descending: true)
          .limit(widget.limitePorPagina ~/ 2);

      final resultados = await Future.wait([
        queryPublicacoes.get(),
        queryEventos.get(),
      ]);

      final publicacoesSnapshot = resultados[0];
      final eventosSnapshot = resultados[1];

      List<Map<String, dynamic>> publicacoes = publicacoesSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'tipo': 'publicacao',
          'id': doc.id,
          'documento': doc,
          'data': (data['data_publicacao'] as Timestamp).toDate(),
          'titulo': data['titulo'] ?? 'Publicação',
          'descricao': data['descricao'] ?? '',
          'imagens': List<String>.from(data['imagens'] ?? []),
          'link': data['link'] ?? '',
          'tipo_item': data['tipo'] ?? 'evento',
        };
      }).toList();

      List<Map<String, dynamic>> eventos = eventosSnapshot.docs.map((doc) {
        final evento = EventoModel.fromFirestore(doc);
        return {
          'tipo': 'evento',
          'id': doc.id,
          'documento': doc,
          'data': evento.data,
          'titulo': evento.nome,
          'descricao': evento.descricao,
          'imagens': evento.linkBanner != null ? [evento.linkBanner!] : [],
          'link': evento.linkFotosVideos ?? '',
          'linkPrevia': evento.previaVideo ?? '',
          'linkPlaylist': evento.linkPlaylist ?? '',
          'cidade': evento.cidade,
          'local': evento.local,
          'horario': evento.horario,
          'organizadores': evento.organizadores,
          'tipo_item': evento.tipo,
        };
      }).toList();

      List<Map<String, dynamic>> todos = [...publicacoes, ...eventos];
      todos.sort((a, b) => b['data'].compareTo(a['data']));

      if (publicacoesSnapshot.docs.isNotEmpty) {
        _ultimoDocPublicacao = publicacoesSnapshot.docs.last;
        _temMaisPublicacoes = publicacoesSnapshot.docs.length == widget.limitePorPagina ~/ 2;
      } else {
        _temMaisPublicacoes = false;
      }

      if (eventosSnapshot.docs.isNotEmpty) {
        _ultimoDocEvento = eventosSnapshot.docs.last;
        _temMaisEventos = eventosSnapshot.docs.length == widget.limitePorPagina ~/ 2;
      } else {
        _temMaisEventos = false;
      }

      setState(() {
        _itensTimeline = todos;
        _carregandoInicial = false;
      });

    } catch (e) {
      print('❌ Erro ao carregar timeline: $e');
      setState(() {
        _carregandoInicial = false;
      });
    }
  }

  Future<void> _carregarMaisItens() async {
    if (_carregandoMais) return;

    setState(() {
      _carregandoMais = true;
    });

    try {
      List<QuerySnapshot> resultados = [];

      if (_temMaisPublicacoes && _ultimoDocPublicacao != null) {
        Query queryPublicacoes = _firestore
            .collection('timeline_publicacoes')
            .orderBy('data_publicacao', descending: true)
            .startAfterDocument(_ultimoDocPublicacao!)
            .limit(widget.limitePorPagina ~/ 2);

        resultados.add(await queryPublicacoes.get());
      }

      if (_temMaisEventos && _ultimoDocEvento != null) {
        Query queryEventos = _firestore
            .collection('eventos')
            .where('mostrarNoPortfolioWeb', isEqualTo: true)
            .where('status', isEqualTo: 'finalizado')
            .orderBy('data', descending: true)
            .startAfterDocument(_ultimoDocEvento!)
            .limit(widget.limitePorPagina ~/ 2);

        resultados.add(await queryEventos.get());
      }

      List<Map<String, dynamic>> novosItens = [];

      for (var snapshot in resultados) {
        if (snapshot.docs.isEmpty) continue;

        final isPublicacao = snapshot.docs.first.reference.parent.path == 'timeline_publicacoes';

        if (isPublicacao) {
          for (var doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            novosItens.add({
              'tipo': 'publicacao',
              'id': doc.id,
              'documento': doc,
              'data': (data['data_publicacao'] as Timestamp).toDate(),
              'titulo': data['titulo'] ?? 'Publicação',
              'descricao': data['descricao'] ?? '',
              'imagens': List<String>.from(data['imagens'] ?? []),
              'link': data['link'] ?? '',
              'tipo_item': data['tipo'] ?? 'evento',
            });
          }
          _ultimoDocPublicacao = snapshot.docs.last;
          _temMaisPublicacoes = snapshot.docs.length == widget.limitePorPagina ~/ 2;
        } else {
          for (var doc in snapshot.docs) {
            final evento = EventoModel.fromFirestore(doc);
            novosItens.add({
              'tipo': 'evento',
              'id': doc.id,
              'documento': doc,
              'data': evento.data,
              'titulo': evento.nome,
              'descricao': evento.descricao,
              'imagens': evento.linkBanner != null ? [evento.linkBanner!] : [],
              'link': evento.linkFotosVideos ?? '',
              'linkPrevia': evento.previaVideo ?? '',
              'linkPlaylist': evento.linkPlaylist ?? '',
              'cidade': evento.cidade,
              'local': evento.local,
              'horario': evento.horario,
              'organizadores': evento.organizadores,
              'tipo_item': evento.tipo,
            });
          }
          _ultimoDocEvento = snapshot.docs.last;
          _temMaisEventos = snapshot.docs.length == widget.limitePorPagina ~/ 2;
        }
      }

      if (novosItens.isNotEmpty) {
        List<Map<String, dynamic>> todos = [..._itensTimeline, ...novosItens];
        todos.sort((a, b) => b['data'].compareTo(a['data']));

        setState(() {
          _itensTimeline = todos;
        });
      }

    } catch (e) {
      print('❌ Erro ao carregar mais: $e');
    } finally {
      setState(() {
        _carregandoMais = false;
      });
    }
  }

  String _formatarData(DateTime data) {
    final now = DateTime.now();
    final difference = now.difference(data);

    if (difference.inDays > 30) {
      return DateFormat('dd/MM/yyyy').format(data);
    } else if (difference.inDays > 0) {
      return 'Há ${difference.inDays} ${difference.inDays == 1 ? 'dia' : 'dias'}';
    } else if (difference.inHours > 0) {
      return 'Há ${difference.inHours} ${difference.inHours == 1 ? 'hora' : 'horas'}';
    } else if (difference.inMinutes > 0) {
      return 'Há ${difference.inMinutes} ${difference.inMinutes == 1 ? 'minuto' : 'minutos'}';
    } else {
      return 'Agora mesmo';
    }
  }

  Color _getCorPorTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'evento': return Colors.blue;
      case 'treino': return Colors.green;
      case 'roda': return Colors.orange;
      case 'formatura': return Colors.purple;
      case 'noticia': return Colors.red;
      case 'batizado': return Colors.amber;
      default: return Colors.grey;
    }
  }

  IconData _getIconPorTipo(String tipo, {bool isEvento = false}) {
    if (isEvento) return Icons.event;

    switch (tipo.toLowerCase()) {
      case 'evento': return Icons.event;
      case 'treino': return Icons.fitness_center;
      case 'roda': return Icons.people;
      case 'formatura': return Icons.school;
      case 'noticia': return Icons.newspaper;
      case 'batizado': return Icons.emoji_events;
      default: return Icons.event;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (_carregandoInicial) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.red),
            SizedBox(height: 16),
            Text('Carregando timeline...'),
          ],
        ),
      );
    }

    if (_itensTimeline.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Nenhuma publicação ou evento',
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Acompanhe novidades em breve!',
              style: TextStyle(
                fontSize: isMobile ? 14 : 16,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      itemCount: _itensTimeline.length + (_temMaisPublicacoes || _temMaisEventos ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _itensTimeline.length) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final item = _itensTimeline[index];
        final bool isEvento = item['tipo'] == 'evento';
        final corTipo = _getCorPorTipo(item['tipo_item']);

        return _buildTimelineItem(item, isEvento, corTipo, index, isMobile);
      },
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> item, bool isEvento, Color corTipo, int index, bool isMobile) {
    final isUltimo = index == _itensTimeline.length - 1;
    final data = item['data'] as DateTime;
    final imagens = item['imagens'] as List;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // COLUNA DA ESQUERDA
        SizedBox(
          width: isMobile ? 60 : 80,
          child: Column(
            children: [
              Text(
                DateFormat('dd/MM/yyyy').format(data),
                style: TextStyle(
                  fontSize: isMobile ? 10 : 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: isMobile ? 20 : 24,
                height: isMobile ? 20 : 24,
                decoration: BoxDecoration(
                  color: corTipo,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: isMobile ? 2 : 3),
                  boxShadow: [
                    BoxShadow(
                      color: corTipo.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    isEvento ? Icons.event : _getIconPorTipo(item['tipo_item']),
                    color: Colors.white,
                    size: isMobile ? 10 : 12,
                  ),
                ),
              ),
              if (!isUltimo)
                Container(
                  width: 2,
                  height: isMobile ? 40 : 50,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [corTipo, corTipo.withOpacity(0.3)],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // CARD DO CONTEÚDO
        Expanded(
          child: Container(
            margin: EdgeInsets.only(bottom: isMobile ? 16 : 24),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // HEADER
                  Container(
                    padding: EdgeInsets.all(isMobile ? 12 : 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [corTipo.withOpacity(0.1), Colors.white],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 8 : 10,
                            vertical: isMobile ? 3 : 4,
                          ),
                          decoration: BoxDecoration(color: corTipo, borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isEvento ? Icons.event : _getIconPorTipo(item['tipo_item']),
                                color: Colors.white,
                                size: isMobile ? 10 : 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isEvento ? 'EVENTO' : item['tipo_item'].toUpperCase(),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isMobile ? 9 : 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item['titulo'],
                            style: TextStyle(
                              fontSize: isMobile ? 14 : 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // DESCRIÇÃO
                  if (item['descricao'] != null && item['descricao'].toString().isNotEmpty)
                    Padding(
                      padding: EdgeInsets.all(isMobile ? 12 : 16),
                      child: Text(
                        item['descricao'],
                        style: TextStyle(
                          fontSize: isMobile ? 13 : 14,
                          color: Colors.grey.shade800,
                          height: 1.4,
                        ),
                      ),
                    ),

                  // INFO DO EVENTO
                  if (isEvento) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (item['cidade'] != null)
                            _buildInfoChip(
                              icon: Icons.location_on,
                              label: item['cidade'],
                              color: Colors.red,
                              isMobile: isMobile,
                            ),
                          if (item['horario'] != null)
                            _buildInfoChip(
                              icon: Icons.access_time,
                              label: item['horario'],
                              color: Colors.blue,
                              isMobile: isMobile,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 🆕 IMAGENS 1:1 - GRID ORGANIZADO
                  if (imagens.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
                      child: _buildImageGrid(imagens, isMobile),
                    ),

                  // LINKS
                  if (item['link'] != null && item['link'].toString().isNotEmpty)
                    Padding(
                      padding: EdgeInsets.all(isMobile ? 12 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isEvento) ...[
                            if (item['link'] != null && item['link'].toString().isNotEmpty)
                              _buildLinkBotao(
                                icon: Icons.photo_library,
                                label: '📸 Fotos e Vídeos',
                                url: item['link'],
                                color: Colors.blue,
                                isMobile: isMobile,
                              ),
                            if (item['linkPrevia'] != null && item['linkPrevia'].toString().isNotEmpty)
                              _buildLinkBotao(
                                icon: Icons.play_circle,
                                label: '▶️ Prévia do Evento',
                                url: item['linkPrevia'],
                                color: Colors.red,
                                isMobile: isMobile,
                              ),
                            if (item['linkPlaylist'] != null && item['linkPlaylist'].toString().isNotEmpty)
                              _buildLinkBotao(
                                icon: Icons.playlist_play,
                                label: '🎵 Playlist',
                                url: item['linkPlaylist'],
                                color: Colors.green,
                                isMobile: isMobile,
                              ),
                          ] else ...[
                            InkWell(
                              onTap: () async {
                                final uri = Uri.parse(item['link']);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                              child: Container(
                                padding: EdgeInsets.all(isMobile ? 10 : 12),
                                decoration: BoxDecoration(
                                  color: corTipo.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.link, color: corTipo, size: isMobile ? 16 : 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Ver mais sobre este conteúdo',
                                        style: TextStyle(
                                          color: corTipo,
                                          fontWeight: FontWeight.w500,
                                          fontSize: isMobile ? 13 : 14,
                                        ),
                                      ),
                                    ),
                                    Icon(Icons.arrow_forward, color: corTipo, size: isMobile ? 16 : 18),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                  // RODAPÉ
                  Container(
                    padding: EdgeInsets.all(isMobile ? 10 : 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.access_time, size: isMobile ? 12 : 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          _formatarData(data),
                          style: TextStyle(
                            fontSize: isMobile ? 11 : 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 🆕 GRID DE IMAGENS 1:1 - ORGANIZADO
  Widget _buildImageGrid(List imagens, bool isMobile) {
    if (imagens.isEmpty) return const SizedBox.shrink();

    // Define número de colunas
    int crossAxisCount;
    if (imagens.length == 1) {
      crossAxisCount = 1;
    } else if (imagens.length == 2) {
      crossAxisCount = 2;
    } else if (imagens.length <= 4) {
      crossAxisCount = 2;
    } else {
      crossAxisCount = 3;
    }

    // Tamanho da imagem baseado no dispositivo
    double imageSize = isMobile ? 100 : 120;

    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 12 : 16),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.0, // 👈 FORÇA 1:1
        ),
        itemCount: imagens.length,
        itemBuilder: (context, imgIndex) {
          return GestureDetector(
            onTap: () => _abrirImagemGrande(context, imagens[imgIndex], imgIndex + 1, imagens.length),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(
                  image: CachedNetworkImageProvider(imagens[imgIndex]),
                  fit: BoxFit.cover, // 👈 COBRE TODO O ESPAÇO 1:1
                ),
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black.withOpacity(0.2), Colors.transparent],
                      ),
                    ),
                  ),
                  if (imagens.length > 1)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${imgIndex + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 🆕 VISUALIZADOR DE IMAGEM EM TELA CHEIA
  void _abrirImagemGrande(BuildContext context, String imageUrl, int currentIndex, int totalImages) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Container(
                    color: Colors.black,
                    child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.black,
                    child: const Center(child: Icon(Icons.broken_image, color: Colors.white, size: 50)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            if (totalImages > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$currentIndex de $totalImages',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 8, vertical: isMobile ? 3 : 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isMobile ? 10 : 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: isMobile ? 10 : 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkBotao({
    required IconData icon,
    required String label,
    required String url,
    required Color color,
    required bool isMobile,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Container(
          padding: EdgeInsets.all(isMobile ? 10 : 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: isMobile ? 18 : 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: isMobile ? 13 : 14,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward, color: color, size: isMobile ? 16 : 18),
            ],
          ),
        ),
      ),
    );
  }
}