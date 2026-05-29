import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';

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
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final DateFormat _shortDateFormat = DateFormat('dd/MM/yy');

  List<Map<String, dynamic>> _itensTimeline = [];
  DocumentSnapshot? _ultimoDocPublicacao;
  DocumentSnapshot? _ultimoDocEvento;

  bool _carregandoMais = false;
  bool _temMaisPublicacoes = true;
  bool _temMaisEventos = true;
  bool _carregandoInicial = true;
  String? _erro;

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

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      if (!_carregandoMais && (_temMaisPublicacoes || _temMaisEventos)) {
        _carregarMaisItens();
      }
    }
  }

  Future<void> _carregarPrimeirosItens() async {
    if (mounted) {
      setState(() {
        _carregandoInicial = true;
        _itensTimeline = [];
        _ultimoDocPublicacao = null;
        _ultimoDocEvento = null;
        _temMaisPublicacoes = true;
        _temMaisEventos = true;
        _erro = null;
      });
    }

    try {
      final limiteMetade = (widget.limitePorPagina ~/ 2).clamp(1, 100);

      final queryPublicacoes = _firestore
          .collection('timeline_publicacoes')
          .orderBy('data_publicacao', descending: true)
          .limit(limiteMetade);

      final queryEventos = _firestore
          .collection('eventos')
          .where('mostrarNoPortfolioWeb', isEqualTo: true)
          .where('status', isEqualTo: 'finalizado')
          .orderBy('data', descending: true)
          .limit(limiteMetade);

      final resultados = await Future.wait([
        queryPublicacoes.get(),
        queryEventos.get(),
      ]);

      final publicacoesSnapshot = resultados[0];
      final eventosSnapshot = resultados[1];

      final publicacoes = publicacoesSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final rawDate = data['data_publicacao'];

        return {
          'tipo': 'publicacao',
          'id': doc.id,
          'documento': doc,
          'data': _dateFromAny(rawDate) ?? DateTime.now(),
          'titulo': data['titulo'] ?? 'Publicação',
          'descricao': data['descricao'] ?? '',
          'imagens': List<String>.from(data['imagens'] ?? []),
          'link': data['link'] ?? '',
          'tipo_item': data['tipo'] ?? 'evento',
        };
      }).toList();

      final eventos = eventosSnapshot.docs.map((doc) {
        final evento = EventoModel.fromFirestore(doc);

        return {
          'tipo': 'evento',
          'id': doc.id,
          'documento': doc,
          'data': evento.data,
          'titulo': evento.nome,
          'descricao': evento.descricao,
          'imagens': evento.linkBanner != null ? [evento.linkBanner!] : <String>[],
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

      final todos = [...publicacoes, ...eventos]
        ..sort((a, b) => (b['data'] as DateTime).compareTo(a['data'] as DateTime));

      if (publicacoesSnapshot.docs.isNotEmpty) {
        _ultimoDocPublicacao = publicacoesSnapshot.docs.last;
        _temMaisPublicacoes = publicacoesSnapshot.docs.length == limiteMetade;
      } else {
        _temMaisPublicacoes = false;
      }

      if (eventosSnapshot.docs.isNotEmpty) {
        _ultimoDocEvento = eventosSnapshot.docs.last;
        _temMaisEventos = eventosSnapshot.docs.length == limiteMetade;
      } else {
        _temMaisEventos = false;
      }

      if (!mounted) return;

      setState(() {
        _itensTimeline = todos;
        _carregandoInicial = false;
      });
    } catch (e) {
      debugPrint('❌ Erro ao carregar timeline: $e');

      if (!mounted) return;

      setState(() {
        _erro = e.toString();
        _carregandoInicial = false;
      });
    }
  }

  Future<void> _carregarMaisItens() async {
    if (_carregandoMais) return;

    if (mounted) setState(() => _carregandoMais = true);

    try {
      final limiteMetade = (widget.limitePorPagina ~/ 2).clamp(1, 100);
      final resultados = <QuerySnapshot>[];

      if (_temMaisPublicacoes && _ultimoDocPublicacao != null) {
        final queryPublicacoes = _firestore
            .collection('timeline_publicacoes')
            .orderBy('data_publicacao', descending: true)
            .startAfterDocument(_ultimoDocPublicacao!)
            .limit(limiteMetade);

        resultados.add(await queryPublicacoes.get());
      }

      if (_temMaisEventos && _ultimoDocEvento != null) {
        final queryEventos = _firestore
            .collection('eventos')
            .where('mostrarNoPortfolioWeb', isEqualTo: true)
            .where('status', isEqualTo: 'finalizado')
            .orderBy('data', descending: true)
            .startAfterDocument(_ultimoDocEvento!)
            .limit(limiteMetade);

        resultados.add(await queryEventos.get());
      }

      final novosItens = <Map<String, dynamic>>[];

      for (final snapshot in resultados) {
        if (snapshot.docs.isEmpty) continue;

        final isPublicacao =
            snapshot.docs.first.reference.parent.path == 'timeline_publicacoes';

        if (isPublicacao) {
          for (final doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final rawDate = data['data_publicacao'];

            novosItens.add({
              'tipo': 'publicacao',
              'id': doc.id,
              'documento': doc,
              'data': _dateFromAny(rawDate) ?? DateTime.now(),
              'titulo': data['titulo'] ?? 'Publicação',
              'descricao': data['descricao'] ?? '',
              'imagens': List<String>.from(data['imagens'] ?? []),
              'link': data['link'] ?? '',
              'tipo_item': data['tipo'] ?? 'evento',
            });
          }

          _ultimoDocPublicacao = snapshot.docs.last;
          _temMaisPublicacoes = snapshot.docs.length == limiteMetade;
        } else {
          for (final doc in snapshot.docs) {
            final evento = EventoModel.fromFirestore(doc);

            novosItens.add({
              'tipo': 'evento',
              'id': doc.id,
              'documento': doc,
              'data': evento.data,
              'titulo': evento.nome,
              'descricao': evento.descricao,
              'imagens':
              evento.linkBanner != null ? [evento.linkBanner!] : <String>[],
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
          _temMaisEventos = snapshot.docs.length == limiteMetade;
        }
      }

      if (novosItens.isNotEmpty && mounted) {
        final todos = [..._itensTimeline, ...novosItens]
          ..sort((a, b) =>
              (b['data'] as DateTime).compareTo(a['data'] as DateTime));

        setState(() => _itensTimeline = todos);
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar mais itens da timeline: $e');
    } finally {
      if (mounted) setState(() => _carregandoMais = false);
    }
  }

  DateTime? _dateFromAny(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    return DateTime.tryParse(text);
  }

  String _formatarDataRelativa(DateTime data) {
    final now = DateTime.now();
    final difference = now.difference(data);

    if (difference.inDays > 30) {
      return _dateFormat.format(data);
    } else if (difference.inDays > 0) {
      return 'Há ${difference.inDays} ${difference.inDays == 1 ? 'dia' : 'dias'}';
    } else if (difference.inHours > 0) {
      return 'Há ${difference.inHours} ${difference.inHours == 1 ? 'hora' : 'horas'}';
    } else if (difference.inMinutes > 0) {
      return 'Há ${difference.inMinutes} ${difference.inMinutes == 1 ? 'minuto' : 'minutos'}';
    }

    return 'Agora mesmo';
  }

  Color _getCorPorTipo(String tipo) {
    final t = context.uai;

    switch (tipo.toLowerCase()) {
      case 'evento':
        return t.info;
      case 'treino':
        return t.success;
      case 'roda':
        return t.warning;
      case 'formatura':
        return t.associacao;
      case 'noticia':
        return t.error;
      case 'batizado':
        return t.rifas;
      default:
        return t.primary;
    }
  }

  IconData _getIconPorTipo(String tipo, {bool isEvento = false}) {
    if (isEvento) return Icons.event_rounded;

    switch (tipo.toLowerCase()) {
      case 'evento':
        return Icons.event_rounded;
      case 'treino':
        return Icons.fitness_center_rounded;
      case 'roda':
        return Icons.groups_rounded;
      case 'formatura':
        return Icons.school_rounded;
      case 'noticia':
        return Icons.newspaper_rounded;
      case 'batizado':
        return Icons.emoji_events_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  Future<void> _abrirLink(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (_carregandoInicial) return _buildLoadingState();

    if (_erro != null) return _buildErrorState();

    if (_itensTimeline.isEmpty) return _buildEmptyState(isMobile);

    return RefreshIndicator(
      color: context.uai.primary,
      backgroundColor: context.uai.surface,
      onRefresh: _carregarPrimeirosItens,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          isMobile ? 8 : 16,
          isMobile ? 14 : 18,
          isMobile ? 10 : 16,
          28,
        ),
        itemCount:
        _itensTimeline.length + (_temMaisPublicacoes || _temMaisEventos ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _itensTimeline.length) {
            return _buildCarregandoMais();
          }

          final item = _itensTimeline[index];
          final isEvento = item['tipo'] == 'evento';
          final corTipo = _getCorPorTipo(item['tipo_item']?.toString() ?? '');

          return _buildTimelineItem(item, isEvento, corTipo, index, isMobile);
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    final t = context.uai;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: _cardDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: t.primary),
            const SizedBox(height: 16),
            Text(
              'Carregando timeline...',
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final t = context.uai;
    final danger = _ensureVisible(t.error, t.card);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(24),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 72, color: danger),
              const SizedBox(height: 12),
              Text(
                'Erro ao carregar timeline',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _erro ?? 'Tente novamente mais tarde.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, height: 1.3),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _carregarPrimeirosItens,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('TENTAR NOVAMENTE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: _readableOn(t.primary),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isMobile) {
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
              Icon(Icons.timeline_rounded, size: 80, color: t.textMuted),
              const SizedBox(height: 16),
              Text(
                'Nenhuma publicação ou evento',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: isMobile ? 16 : 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Acompanhe novidades em breve!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: isMobile ? 14 : 16,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCarregandoMais() {
    final t = context.uai;

    if (!_carregandoMais) {
      return const SizedBox(height: 18);
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: CircularProgressIndicator(color: t.primary),
      ),
    );
  }

  Widget _buildTimelineItem(
      Map<String, dynamic> item,
      bool isEvento,
      Color corTipo,
      int index,
      bool isMobile,
      ) {
    final t = context.uai;
    final isUltimo = index == _itensTimeline.length - 1;
    final data = item['data'] as DateTime;
    final imagens = (item['imagens'] as List?) ?? [];
    final accent = _ensureVisible(corTipo, t.background);

    return LayoutBuilder(
      builder: (context, constraints) {
        final verySmall = constraints.maxWidth < 390;
        final lineWidth = verySmall ? 48.0 : (isMobile ? 56.0 : 80.0);
        final cardRadius = verySmall ? 18.0 : t.cardRadius;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: lineWidth,
              child: Column(
                children: [
                  Text(
                    _shortDateFormat.format(data),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: verySmall ? 9 : (isMobile ? 10 : 12),
                      fontWeight: FontWeight.w900,
                      color: t.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: verySmall ? 28 : 34,
                    height: verySmall ? 28 : 34,
                    decoration: BoxDecoration(
                      color: t.card,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accent.withOpacity(0.20),
                        width: 1.5,
                      ),
                      boxShadow: t.softShadow,
                    ),
                    child: Center(
                      child: Container(
                        width: verySmall ? 20 : 24,
                        height: verySmall ? 20 : 24,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isEvento
                              ? Icons.event_rounded
                              : _getIconPorTipo(
                            item['tipo_item']?.toString() ?? '',
                          ),
                          color: _readableOn(accent),
                          size: verySmall ? 11 : 13,
                        ),
                      ),
                    ),
                  ),
                  if (!isUltimo)
                    Container(
                      width: 2,
                      height: verySmall ? 44 : 54,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            accent.withOpacity(0.48),
                            accent.withOpacity(0.08),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: EdgeInsets.only(bottom: isMobile ? 14 : 22),
                decoration: _cardDecoration(
                  radius: cardRadius,
                  borderColor: accent.withOpacity(0.13),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(cardRadius),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildItemHeader(
                        item: item,
                        isEvento: isEvento,
                        corTipo: accent,
                        data: data,
                        verySmall: verySmall,
                        isMobile: isMobile,
                      ),
                      if (item['descricao'] != null &&
                          item['descricao'].toString().trim().isNotEmpty)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            verySmall ? 11 : 14,
                            verySmall ? 10 : 12,
                            verySmall ? 11 : 14,
                            imagens.isNotEmpty ? 8 : 12,
                          ),
                          child: Text(
                            item['descricao'].toString(),
                            style: TextStyle(
                              fontSize: verySmall ? 13.5 : (isMobile ? 14.5 : 15),
                              color: t.textPrimary,
                              height: 1.34,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (isEvento)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            verySmall ? 11 : 14,
                            0,
                            verySmall ? 11 : 14,
                            10,
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (item['cidade'] != null &&
                                  item['cidade'].toString().trim().isNotEmpty)
                                _buildInfoChip(
                                  icon: Icons.location_on_rounded,
                                  label: item['cidade'].toString(),
                                  color: t.primary,
                                  isMobile: true,
                                ),
                              if (item['horario'] != null &&
                                  item['horario'].toString().trim().isNotEmpty)
                                _buildInfoChip(
                                  icon: Icons.access_time_rounded,
                                  label: item['horario'].toString(),
                                  color: t.info,
                                  isMobile: true,
                                ),
                            ],
                          ),
                        ),
                      if (imagens.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: verySmall ? 11 : 14,
                          ),
                          child: _buildImageGrid(imagens, isMobile),
                        ),
                      _buildLinks(item, isEvento, accent, verySmall),
                      _buildFooterTime(data, verySmall),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildItemHeader({
    required Map<String, dynamic> item,
    required bool isEvento,
    required Color corTipo,
    required DateTime data,
    required bool verySmall,
    required bool isMobile,
  }) {
    final t = context.uai;

    return Container(
      padding: EdgeInsets.fromLTRB(
        verySmall ? 10 : 13,
        verySmall ? 10 : 12,
        verySmall ? 10 : 13,
        verySmall ? 9 : 11,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.alphaBlend(corTipo.withOpacity(0.11), t.cardAlt),
            t.card,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildTipoMiniPill(
                icon: isEvento
                    ? Icons.event_rounded
                    : _getIconPorTipo(item['tipo_item']?.toString() ?? ''),
                label: isEvento
                    ? 'EVENTO'
                    : item['tipo_item'].toString().toUpperCase(),
                color: corTipo,
                isMobile: isMobile,
              ),
              _buildTipoMiniPill(
                icon: Icons.calendar_month_rounded,
                label: _dateFormat.format(data),
                color: t.textSecondary,
                isMobile: isMobile,
                soft: true,
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            item['titulo']?.toString() ?? 'Publicação',
            style: TextStyle(
              fontSize: verySmall ? 17 : (isMobile ? 18 : 20),
              height: 1.12,
              fontWeight: FontWeight.w900,
              color: t.textPrimary,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildLinks(
      Map<String, dynamic> item,
      bool isEvento,
      Color corTipo,
      bool verySmall,
      ) {
    final linkPrincipal = item['link']?.toString().trim() ?? '';
    final linkPrevia = item['linkPrevia']?.toString().trim() ?? '';
    final linkPlaylist = item['linkPlaylist']?.toString().trim() ?? '';

    final hasAnyLink =
        linkPrincipal.isNotEmpty || linkPrevia.isNotEmpty || linkPlaylist.isNotEmpty;

    if (!hasAnyLink) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        verySmall ? 11 : 14,
        4,
        verySmall ? 11 : 14,
        12,
      ),
      child: isEvento
          ? Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (linkPrincipal.isNotEmpty)
            _buildLinkBotao(
              icon: Icons.photo_library_rounded,
              label: 'Fotos e vídeos',
              url: linkPrincipal,
              color: context.uai.info,
              isMobile: true,
            ),
          if (linkPrevia.isNotEmpty)
            _buildLinkBotao(
              icon: Icons.play_circle_rounded,
              label: 'Prévia do evento',
              url: linkPrevia,
              color: context.uai.error,
              isMobile: true,
            ),
          if (linkPlaylist.isNotEmpty)
            _buildLinkBotao(
              icon: Icons.playlist_play_rounded,
              label: 'Playlist',
              url: linkPlaylist,
              color: context.uai.success,
              isMobile: true,
            ),
        ],
      )
          : _buildLinkBotao(
        icon: Icons.link_rounded,
        label: 'Ver mais sobre este conteúdo',
        url: linkPrincipal,
        color: corTipo,
        isMobile: true,
      ),
    );
  }

  Widget _buildFooterTime(DateTime data, bool verySmall) {
    final t = context.uai;

    return Container(
      padding: EdgeInsets.fromLTRB(
        verySmall ? 11 : 14,
        9,
        verySmall ? 11 : 14,
        10,
      ),
      decoration: BoxDecoration(
        color: t.cardAlt,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.access_time_rounded,
            size: 14,
            color: t.textSecondary,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              _formatarDataRelativa(data),
              style: TextStyle(
                fontSize: 12,
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipoMiniPill({
    required IconData icon,
    required String label,
    required Color color,
    required bool isMobile,
    bool soft = false,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 10,
        vertical: isMobile ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: soft
            ? Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt)
            : accent,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(soft ? 0.14 : 0.0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: soft ? accent : _readableOn(accent),
            size: isMobile ? 12 : 13,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: soft ? accent : _readableOn(accent),
              fontSize: isMobile ? 10 : 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid(List imagens, bool isMobile) {
    if (imagens.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        int crossAxisCount;
        if (imagens.length == 1) {
          crossAxisCount = 1;
        } else if (width < 260) {
          crossAxisCount = 2;
        } else {
          crossAxisCount = imagens.length <= 4 ? 2 : 3;
        }

        final spacing = isMobile ? 7.0 : 9.0;
        final itemSize =
            (width - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final maxHeight = imagens.length == 1
            ? itemSize.clamp(150.0, isMobile ? 220.0 : 280.0)
            : null;

        return Container(
          margin: EdgeInsets.only(bottom: isMobile ? 10 : 14),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: imagens.length == 1 && maxHeight != null
                  ? width / maxHeight
                  : 1.0,
            ),
            itemCount: imagens.length,
            itemBuilder: (context, imgIndex) {
              final imageUrl = imagens[imgIndex]?.toString() ?? '';

              return GestureDetector(
                onTap: () => _abrirImagemGrande(
                  context,
                  imageUrl,
                  imgIndex + 1,
                  imagens.length,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => _imageLoading(),
                        errorWidget: (context, url, error) => _imageError(),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.24),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      if (imagens.length > 1)
                        Positioned(
                          bottom: 5,
                          right: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.62),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${imgIndex + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
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
      },
    );
  }

  void _abrirImagemGrande(
      BuildContext context,
      String imageUrl,
      int currentIndex,
      int totalImages,
      ) {
    final t = context.uai;

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(t.cardRadius),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(t.cardRadius),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (context, url, error) => const Center(
                      child: Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.black.withOpacity(0.52),
                  borderRadius: BorderRadius.circular(99),
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.62),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$currentIndex de $totalImages',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
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
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isMobile,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 6 : 8,
        vertical: isMobile ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.09), t.cardAlt),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isMobile ? 11 : 13, color: accent),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isMobile ? 10.5 : 11.5,
                color: accent,
                fontWeight: FontWeight.w800,
              ),
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
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _abrirLink(url),
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 11 : 13,
              vertical: isMobile ? 10 : 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: accent.withOpacity(0.14)),
            ),
            child: Row(
              children: [
                Icon(icon, color: accent, size: isMobile ? 18 : 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontSize: isMobile ? 12.5 : 13.5,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: accent,
                  size: isMobile ? 17 : 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _imageLoading() {
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

  Widget _imageError() {
    final t = context.uai;

    return Container(
      color: t.cardAlt,
      child: Icon(
        Icons.broken_image_rounded,
        color: t.textMuted,
      ),
    );
  }

  BoxDecoration _cardDecoration({
    double? radius,
    Color? borderColor,
  }) {
    final t = context.uai;

    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(radius ?? t.cardRadius),
      border: Border.all(color: borderColor ?? t.border),
      boxShadow: t.softShadow,
    );
  }
}
