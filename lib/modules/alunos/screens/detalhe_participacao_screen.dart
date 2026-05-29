import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import 'package:cached_network_image/cached_network_image.dart';

class DetalheParticipacaoScreen extends StatefulWidget {
  final Map<String, dynamic> participacao;
  final String participacaoId;

  const DetalheParticipacaoScreen({
    super.key,
    required this.participacao,
    required this.participacaoId,
  });

  @override
  State<DetalheParticipacaoScreen> createState() =>
      _DetalheParticipacaoScreenState();
}

class _DetalheParticipacaoScreenState extends State<DetalheParticipacaoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _eventoDetalhes;
  Map<String, dynamic>? _alunoDetalhes;
  Map<String, dynamic>? _coresGraduacao;

  String? _svgContent;
  String? _svgColorido;
  String? _eventoDocId;

  bool _isLoading = true;

  final Map<String, Map<String, dynamic>> _cacheCoresPorNome = {};

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onCard() => _readableOn(context.uai.card);
  Color _onCardMuted() => _onCard().withOpacity(0.68);
  Color _onPrimary() => _readableOn(context.uai.primary);

  @override
  void initState() {
    super.initState();
    _carregarSvg();
    _carregarDados();
  }

  String? _stringLimpa(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    if (text.toLowerCase() == 'null') return null;
    return text;
  }

  String? _pickFirstString(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) return null;

    for (final key in keys) {
      final value = _stringLimpa(data[key]);
      if (value != null) return value;
    }

    return null;
  }

  String? _getEventoId() {
    return _pickFirstString(widget.participacao, const [
      'evento_id',
      'eventoId',
      'id_evento',
      'evento_doc_id',
      'eventoDocId',
      'idEvento',
    ]);
  }

  String? _getAlunoId() {
    return _pickFirstString(widget.participacao, const [
      'aluno_id',
      'alunoId',
      'id_aluno',
      'alunoDocId',
      'aluno_doc_id',
    ]);
  }

  String? _getEventoNome() {
    return _pickFirstString(widget.participacao, const [
      'evento_nome',
      'eventoNome',
      'nome_evento',
      'nomeEvento',
      'nome',
    ]);
  }

  String? _getEventoBannerUrl() {
    // Primeiro tenta a participação, depois o documento do evento.
    // Isso cobre participações antigas e eventos salvos em formatos diferentes.
    const campos = [
      'linkBanner', // mesmo nome usado no EventoModel/EventosScreen
      'link_banner',
      'bannerUrl',
      'banner_url',
      'urlBanner',
      'url_banner',
      'imagemBanner',
      'imagem_banner',
      'fotoBanner',
      'foto_banner',
      'banner',
      'capa',
      'imagem',
      'imagem_url',
      'imageUrl',
      'foto_url',
    ];

    return _pickFirstString(widget.participacao, campos) ??
        _pickFirstString(_eventoDetalhes, campos);
  }

  String _nomeEvento() {
    return _getEventoNome() ??
        _pickFirstString(_eventoDetalhes, const [
          'nome',
          'nome_evento',
          'evento_nome',
          'titulo',
        ]) ??
        'Evento';
  }

  String _tipoEvento() {
    return _pickFirstString(widget.participacao, const [
      'tipo_evento',
      'tipoEvento',
      'tipo',
    ]) ??
        _pickFirstString(_eventoDetalhes, const [
          'tipo',
          'tipo_evento',
          'categoria',
        ]) ??
        '';
  }

  dynamic _dataEventoRaw() {
    return widget.participacao['data_evento'] ??
        widget.participacao['dataEvento'] ??
        widget.participacao['data'] ??
        _eventoDetalhes?['data'] ??
        _eventoDetalhes?['data_evento'] ??
        _eventoDetalhes?['dataEvento'];
  }

  String _localEvento() {
    final local = _pickFirstString(_eventoDetalhes, const [
      'local',
      'local_evento',
      'endereco',
    ]);
    final cidade = _pickFirstString(_eventoDetalhes, const [
      'cidade',
      'cidade_evento',
    ]);

    if (local == null && cidade == null) return 'Local não informado';
    if (local != null && cidade != null && cidade.isNotEmpty) {
      return '$local • $cidade';
    }
    return local ?? cidade ?? 'Local não informado';
  }

  Future<void> _carregarSvg() async {
    try {
      final content =
      await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');
      if (mounted) {
        setState(() => _svgContent = content);
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar SVG da corda: $e');
    }
  }

  Future<void> _carregarDados() async {
    try {
      final eventoId = _getEventoId();
      final alunoId = _getAlunoId();
      final nomeEvento = _getEventoNome();
      final nomeGraduacao =
          _stringLimpa(widget.participacao['graduacao']) ??
              _stringLimpa(widget.participacao['graduacao_nova']) ??
              _stringLimpa(widget.participacao['graduacao_atual']);

      if (eventoId != null) {
        final eventoDoc = await _firestore.collection('eventos').doc(eventoId).get();

        if (eventoDoc.exists) {
          _eventoDocId = eventoDoc.id;
          _eventoDetalhes = eventoDoc.data();
        }
      }

      // Fallback importante: em algumas participações antigas o evento_id pode não existir
      // ou pode estar salvo com outro valor. A tela de eventos usa o doc real da coleção eventos.
      if (_eventoDetalhes == null && nomeEvento != null) {
        final query = await _firestore
            .collection('eventos')
            .where('nome', isEqualTo: nomeEvento)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          _eventoDocId = query.docs.first.id;
          _eventoDetalhes = query.docs.first.data();
        }
      }

      if (alunoId != null) {
        final alunoDoc = await _firestore.collection('alunos').doc(alunoId).get();
        if (alunoDoc.exists) {
          _alunoDetalhes = alunoDoc.data();
        }
      }

      if (nomeGraduacao != null) {
        await _buscarCoresPorNome(nomeGraduacao);
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('❌ Erro ao carregar detalhes da participação: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _buscarCoresPorNome(String nomeGraduacao) async {
    if (_cacheCoresPorNome.containsKey(nomeGraduacao)) {
      _coresGraduacao = _cacheCoresPorNome[nomeGraduacao];
      await _colorirSvg();
      return;
    }

    try {
      final querySnapshot = await _firestore
          .collection('graduacoes')
          .where('nome_graduacao', isEqualTo: nomeGraduacao)
          .limit(1)
          .get();

      Map<String, dynamic>? coresEncontradas;

      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        coresEncontradas = _mapCoresGraduacao(data);
      } else {
        final allDocs = await _firestore.collection('graduacoes').get();

        for (final doc in allDocs.docs) {
          final data = doc.data();
          final nome = data['nome_graduacao']?.toString() ?? '';

          if (nome.toLowerCase() == nomeGraduacao.toLowerCase() ||
              nome.toLowerCase().contains(nomeGraduacao.toLowerCase()) ||
              nomeGraduacao.toLowerCase().contains(nome.toLowerCase())) {
            coresEncontradas = _mapCoresGraduacao(data);
            break;
          }
        }
      }

      _coresGraduacao = coresEncontradas ?? _getCoresPadraoPorNome(nomeGraduacao);
      _cacheCoresPorNome[nomeGraduacao] = _coresGraduacao!;
      await _colorirSvg();
    } catch (e) {
      debugPrint('❌ Erro ao buscar cores da graduação: $e');
      _coresGraduacao = _getCoresPadraoPorNome(nomeGraduacao);
      await _colorirSvg();
    }
  }

  Map<String, dynamic> _mapCoresGraduacao(Map<String, dynamic> data) {
    return {
      'hex_cor1': data['hex_cor1'] ?? '#FFFFFF',
      'hex_cor2': data['hex_cor2'] ?? '#FFFFFF',
      'hex_ponta1': data['hex_ponta1'] ?? '#FFFFFF',
      'hex_ponta2': data['hex_ponta2'] ?? '#FFFFFF',
      'nome_graduacao': data['nome_graduacao'],
    };
  }

  Map<String, dynamic> _getCoresPadraoPorNome(String nome) {
    final nomeLower = nome.toLowerCase();

    if (nomeLower.contains('branco') || nomeLower.contains('branca')) {
      return {
        'hex_cor1': '#FFFFFF',
        'hex_cor2': '#F5F5F5',
        'hex_ponta1': '#E0E0E0',
        'hex_ponta2': '#BDBDBD',
        'nome_graduacao': 'Branco',
      };
    }

    if (nomeLower.contains('amarelo') || nomeLower.contains('amarela')) {
      return {
        'hex_cor1': '#FFEB3B',
        'hex_cor2': '#FDD835',
        'hex_ponta1': '#FBC02D',
        'hex_ponta2': '#F9A825',
        'nome_graduacao': 'Amarelo',
      };
    }

    if (nomeLower.contains('laranja')) {
      return {
        'hex_cor1': '#FF9800',
        'hex_cor2': '#FB8C00',
        'hex_ponta1': '#F57C00',
        'hex_ponta2': '#EF6C00',
        'nome_graduacao': 'Laranja',
      };
    }

    if (nomeLower.contains('azul')) {
      return {
        'hex_cor1': '#2196F3',
        'hex_cor2': '#1E88E5',
        'hex_ponta1': '#1976D2',
        'hex_ponta2': '#1565C0',
        'nome_graduacao': 'Azul',
      };
    }

    if (nomeLower.contains('verde')) {
      return {
        'hex_cor1': '#4CAF50',
        'hex_cor2': '#43A047',
        'hex_ponta1': '#388E3C',
        'hex_ponta2': '#2E7D32',
        'nome_graduacao': 'Verde',
      };
    }

    if (nomeLower.contains('roxo') || nomeLower.contains('roxa')) {
      return {
        'hex_cor1': '#9C27B0',
        'hex_cor2': '#8E24AA',
        'hex_ponta1': '#7B1FA2',
        'hex_ponta2': '#6A1B9A',
        'nome_graduacao': 'Roxo',
      };
    }

    if (nomeLower.contains('vermelho') || nomeLower.contains('vermelha')) {
      return {
        'hex_cor1': '#F44336',
        'hex_cor2': '#E53935',
        'hex_ponta1': '#D32F2F',
        'hex_ponta2': '#C62828',
        'nome_graduacao': 'Vermelho',
      };
    }

    if (nomeLower.contains('marrom')) {
      return {
        'hex_cor1': '#8D6E63',
        'hex_cor2': '#7B5E57',
        'hex_ponta1': '#6D4C41',
        'hex_ponta2': '#5D4037',
        'nome_graduacao': 'Marrom',
      };
    }

    if (nomeLower.contains('cinza') || nomeLower.contains('crua')) {
      return {
        'hex_cor1': '#9E9E9E',
        'hex_cor2': '#757575',
        'hex_ponta1': '#616161',
        'hex_ponta2': '#424242',
        'nome_graduacao': 'Cinza',
      };
    }

    if (nomeLower.contains('preta')) {
      return {
        'hex_cor1': '#212121',
        'hex_cor2': '#1E1E1E',
        'hex_ponta1': '#1A1A1A',
        'hex_ponta2': '#151515',
        'nome_graduacao': 'Preta',
      };
    }

    return {
      'hex_cor1': '#BDBDBD',
      'hex_cor2': '#9E9E9E',
      'hex_ponta1': '#757575',
      'hex_ponta2': '#616161',
      'nome_graduacao': nome,
    };
  }

  Future<void> _colorirSvg() async {
    if (_svgContent == null || _coresGraduacao == null) return;

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      Color colorFromHex(String hexColor) {
        var cleanHex = hexColor.replaceAll('#', '').trim();

        if (cleanHex.length == 6) cleanHex = 'FF$cleanHex';

        try {
          return Color(int.parse(cleanHex, radix: 16));
        } catch (_) {
          return context.uai.textMuted;
        }
      }

      void changeColor(String id, Color color) {
        final hex = '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toLowerCase()}';

        final element = document.rootElement.descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.getAttribute('id') == id,
          orElse: () => xml.XmlElement(xml.XmlName('')),
        );

        if (element.name.local.isEmpty) return;

        final style = element.getAttribute('style');

        if (style != null && style.isNotEmpty) {
          final newStyle =
              'fill:$hex;${style.replaceAll(RegExp(r'fill:[^;]+;?'), '').replaceAll(';', '')}';
          element.setAttribute('style', newStyle);
        } else {
          element.setAttribute('fill', hex);
        }
      }

      changeColor('cor1', colorFromHex(_coresGraduacao!['hex_cor1']));
      changeColor('cor2', colorFromHex(_coresGraduacao!['hex_cor2']));
      changeColor('corponta1', colorFromHex(_coresGraduacao!['hex_ponta1']));
      changeColor('corponta2', colorFromHex(_coresGraduacao!['hex_ponta2']));

      if (mounted) setState(() => _svgColorido = document.toXmlString());
    } catch (e) {
      debugPrint('❌ Erro ao colorir SVG: $e');
    }
  }

  Future<void> _abrirLink(String? url) async {
    final cleaned = _stringLimpa(url);
    if (cleaned == null) return;

    try {
      final uri = Uri.parse(cleaned);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir link: $e');
      _showSnack('Não foi possível abrir o link', context.uai.error);
    }
  }

  Future<void> _abrirPDF(String? url) async {
    final cleaned = _stringLimpa(url);
    if (cleaned == null) return;

    var pdfUrl = cleaned;

    if (cleaned.contains('drive.google.com')) {
      final regex = RegExp(r'/d/([a-zA-Z0-9_-]+)');
      final match = regex.firstMatch(cleaned);

      if (match != null && match.groupCount >= 1) {
        final fileId = match.group(1);
        pdfUrl = 'https://drive.google.com/file/d/$fileId/preview';
      }
    }

    try {
      final uri = Uri.parse(pdfUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir PDF: $e');
      _showSnack('Não foi possível abrir o PDF', context.uai.error);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;

    final fg = _readableOn(color);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          message,
          style: TextStyle(color: fg, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  String _formatarData(dynamic data) {
    if (data == null) return 'Não informada';

    if (data is Timestamp) {
      return DateFormat('dd/MM/yyyy').format(data.toDate());
    }

    if (data is DateTime) {
      return DateFormat('dd/MM/yyyy').format(data);
    }

    final parsed = DateTime.tryParse(data.toString());
    if (parsed != null) {
      return DateFormat('dd/MM/yyyy').format(parsed);
    }

    return data.toString();
  }

  String _statusParticipacao() {
    return _pickFirstString(widget.participacao, const [
      'status',
      'status_participacao',
      'statusParticipacao',
    ]) ??
        'Registrada';
  }

  String _graduacaoParticipacao() {
    return _stringLimpa(widget.participacao['graduacao']) ??
        _stringLimpa(widget.participacao['graduacao_nova']) ??
        _stringLimpa(widget.participacao['graduacao_atual']) ??
        'Graduação não informada';
  }

  String? _certificadoUrl() {
    return _pickFirstString(widget.participacao, const [
      'link_certificado',
      'certificadoUrl',
      'certificado_url',
      'url_certificado',
      'linkCertificado',
    ]);
  }

  String? _alunoFotoUrl() {
    return _pickFirstString(_alunoDetalhes, const [
      'foto_perfil_aluno',
      'foto_url',
      'fotoUrl',
      'photoURL',
      'avatar',
      'avatar_url',
    ]);
  }

  String _alunoNome() {
    return _pickFirstString(_alunoDetalhes, const [
      'nome',
      'nome_completo',
      'name',
    ]) ??
        _pickFirstString(widget.participacao, const [
          'aluno_nome',
          'nome_aluno',
          'alunoNome',
        ]) ??
        'Aluno';
  }

  @override
  Widget build(BuildContext context) {
    final bannerUrl = _getEventoBannerUrl();
    final certificado = _certificadoUrl();

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: const Text(
          'Participação',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor:
        Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ??
            _readableOn(
              Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
            ),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? _buildLoading()
          : RefreshIndicator(
        color: context.uai.primary,
        onRefresh: () async {
          setState(() => _isLoading = true);
          await _carregarDados();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeroEvento(bannerUrl),
                  const SizedBox(height: 14),
                  _buildParticipacaoCard(),
                  const SizedBox(height: 14),
                  _buildAlunoCard(),
                  if (certificado != null) ...[
                    const SizedBox(height: 14),
                    _buildCertificadoCard(certificado),
                  ],
                  const SizedBox(height: 18),
                  _buildActions(certificado),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: context.uai.card,
          borderRadius: BorderRadius.circular(context.uai.cardRadius),
          border: Border.all(color: context.uai.border),
          boxShadow: context.uai.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: context.uai.primary),
            const SizedBox(height: 14),
            Text(
              'Carregando participação...',
              style: TextStyle(
                color: _onCardMuted(),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroEvento(String? bannerUrl) {
    final tipo = _tipoEvento();
    final dataEvento = _formatarData(_dataEventoRaw());
    final status = _statusParticipacao();
    final onGradient = _onPrimary();

    return Container(
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(context.uai.cardRadius + 8),
        border: Border.all(color: context.uai.border),
        boxShadow: context.uai.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildBannerImage(bannerUrl),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.62),
                        Colors.transparent,
                        Colors.black.withOpacity(0.78),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (tipo.isNotEmpty)
                        _glassChip(Icons.category_rounded, tipo.toUpperCase()),
                      _glassChip(Icons.calendar_month_rounded, dataEvento),
                      if (_eventoDocId != null)
                        _glassChip(Icons.verified_rounded, 'EVENTO VINCULADO'),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nomeEvento(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onGradient,
                          fontSize: 24,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            color: onGradient.withOpacity(0.84),
                            size: 17,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _localEvento(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: onGradient.withOpacity(0.84),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: context.uai.primary.withOpacity(0.86),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: onGradient.withOpacity(0.20),
                              ),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: _readableOn(context.uai.primary),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerImage(String? bannerUrl) {
    if (bannerUrl == null) {
      return _buildBannerFallback(
        icon: Icons.event_rounded,
        title: 'Sem banner cadastrado',
        subtitle: 'Este evento ainda não possui imagem.',
      );
    }

    return CachedNetworkImage(
      imageUrl: bannerUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      placeholder: (context, url) => _buildBannerPlaceholder(),
      errorWidget: (context, url, error) {
        debugPrint('⚠️ Banner indisponível na participação: $url | $error');
        return _buildBannerFallback(
          icon: Icons.broken_image_rounded,
          title: 'Banner indisponível',
          subtitle: 'A imagem do evento não foi encontrada.',
        );
      },
    );
  }

  Widget _buildBannerPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.uai.cardAlt,
            context.uai.card,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.uai.primary,
        ),
      ),
    );
  }

  Widget _buildBannerFallback({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final accent = _ensureVisible(context.uai.primary, context.uai.card);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.alphaBlend(accent.withOpacity(0.12), context.uai.cardAlt),
            context.uai.card,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accent, size: 48),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _onCard(),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _onCardMuted(),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.34),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.94), size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.94),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipacaoCard() {
    final graduacao = _graduacaoParticipacao();

    return _premiumCard(
      title: 'Participação do aluno',
      subtitle: 'Graduação e dados registrados no evento',
      icon: Icons.military_tech_rounded,
      color: context.uai.warning,
      child: Row(
        children: [
          Container(
            width: 84,
            height: 112,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.uai.cardAlt,
              borderRadius: BorderRadius.circular(context.uai.buttonRadius),
              border: Border.all(color: context.uai.border),
            ),
            child: _svgColorido != null
                ? SvgPicture.string(
              _svgColorido!,
              fit: BoxFit.contain,
              placeholderBuilder: (context) => const SizedBox(),
            )
                : Icon(
              Icons.emoji_events_rounded,
              color: context.uai.textMuted,
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _smallLabel('Graduação na época'),
                const SizedBox(height: 4),
                Text(
                  graduacao,
                  style: TextStyle(
                    color: _onCard(),
                    fontSize: 16,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _softChip(
                      Icons.palette_rounded,
                      _coresGraduacao?['nome_graduacao']?.toString() ?? 'Corda',
                      context.uai.warning,
                    ),
                    _softChip(
                      Icons.badge_rounded,
                      'ID ${widget.participacaoId.length > 8 ? widget.participacaoId.substring(0, 8) : widget.participacaoId}',
                      context.uai.info,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlunoCard() {
    final fotoUrl = _alunoFotoUrl();
    final nome = _alunoNome();
    final inicial = nome.trim().isNotEmpty ? nome.trim()[0].toUpperCase() : '?';

    return _premiumCard(
      title: 'Aluno',
      subtitle: 'Pessoa vinculada a esta participação',
      icon: Icons.person_rounded,
      color: context.uai.info,
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.uai.cardAlt,
              border: Border.all(color: context.uai.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: fotoUrl != null
                ? CachedNetworkImage(
              imageUrl: fotoUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(color: context.uai.cardAlt),
              errorWidget: (context, url, error) => Center(
                child: Text(
                  inicial,
                  style: TextStyle(
                    color: context.uai.info,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            )
                : Center(
              child: Text(
                inicial,
                style: TextStyle(
                  color: context.uai.info,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _smallLabel('Nome do aluno'),
                const SizedBox(height: 3),
                Text(
                  nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _onCard(),
                    fontSize: 15,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (_alunoDetalhes != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _pickFirstString(_alunoDetalhes, const [
                      'turma',
                      'turma_nome',
                      'graduacao_atual',
                    ]) ??
                        'Cadastro localizado',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _onCardMuted(),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertificadoCard(String certificado) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(context.uai.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirPDF(certificado),
        splashColor: context.uai.error.withOpacity(0.12),
        highlightColor: context.uai.error.withOpacity(0.06),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              context.uai.error.withOpacity(0.08),
              context.uai.card,
            ),
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
            border: Border.all(color: context.uai.error.withOpacity(0.22)),
            boxShadow: context.uai.softShadow,
          ),
          child: Row(
            children: [
              _iconBox(Icons.picture_as_pdf_rounded, context.uai.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Certificado disponível',
                      style: TextStyle(
                        color: _onCard(),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      certificado,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _onCardMuted(),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, color: context.uai.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(String? certificado) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('VOLTAR'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              side: BorderSide(color: context.uai.border),
              foregroundColor: context.uai.textPrimary,
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(context.uai.buttonRadius),
              ),
            ),
          ),
        ),
        if (certificado != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _abrirPDF(certificado),
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('CERTIFICADO'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                Theme.of(context).appBarTheme.backgroundColor ??
                    context.uai.primary,
                foregroundColor: Theme.of(context).appBarTheme.foregroundColor ??
                    _readableOn(
                      Theme.of(context).appBarTheme.backgroundColor ??
                          context.uai.primary,
                    ),
                minimumSize: const Size(double.infinity, 50),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.uai.buttonRadius),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _premiumCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    final accent = _ensureVisible(color, context.uai.card);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        border: Border.all(color: accent.withOpacity(0.18)),
        boxShadow: context.uai.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(icon, accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _onCard(),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _onCardMuted(),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          child,
        ],
      ),
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    final accent = _ensureVisible(color, context.uai.card);

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(context.uai.buttonRadius),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Icon(icon, color: accent, size: 22),
    );
  }

  Widget _smallLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: _onCardMuted(),
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _softChip(IconData icon, String label, Color color) {
    final accent = _ensureVisible(color, context.uai.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
