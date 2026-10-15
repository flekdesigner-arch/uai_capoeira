import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/rastreio/services/rastreio_site.dart';

class BiografiaScreen extends StatefulWidget {
  const BiografiaScreen({super.key});

  @override
  State<BiografiaScreen> createState() => _BiografiaScreenState();
}

class _BiografiaScreenState extends State<BiografiaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final RastreioSiteService _rastreioService = RastreioSiteService();
  final ScrollController _scrollController = ScrollController();

  int _maiorPercentualRolagem = 0;

  List<Map<String, dynamic>> _secoesBiografia = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();

    _rastreioService.iniciarTela(
      'biografia',
      origem: 'site',
      metadata: {'descricao': 'Tela pública biografia'},
    );
    _rastreioService.marcarTempo('biografia_tempo');
    _scrollController.addListener(_registrarRolagem);
    _carregarBiografia();
  }

  @override
  void dispose() {
    _rastreioService.registrarTempoMarcador(
      chave: 'biografia_tempo',
      tipo: 'tempo_tela',
      nome: 'biografia',
      origem: 'dispose',
      metadata: {
        'maior_percentual_rolagem': _maiorPercentualRolagem,
        'total_secoes': _secoesBiografia.length,
      },
      limparMarcador: true,
    );
    _rastreioService.finalizarTela(destino: 'saida_biografia');
    _scrollController.dispose();
    super.dispose();
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

  void _registrarRolagem() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final percentual = ((_scrollController.offset / maxScroll) * 100)
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

    if (marco > _maiorPercentualRolagem) {
      _maiorPercentualRolagem = marco;

      _rastreioService.registrarEvento(
        tipo: 'rolagem',
        nome: 'biografia_$marco%',
        origem: 'biografia',
        metadata: {
          'percentual': marco,
          'total_secoes': _secoesBiografia.length,
        },
      );
    }
  }

  Future<void> _carregarBiografia() async {
    try {
      final doc = await _firestore
          .collection('site_conteudo')
          .doc('biografia')
          .get();

      if (doc.exists) {
        final data = doc.data()!;

        if (data.containsKey('secoes') && data['secoes'] is List) {
          final secoesRaw = data['secoes'] as List<dynamic>;
          final secoesConvertidas = <Map<String, dynamic>>[];

          for (final item in secoesRaw) {
            if (item is Map<String, dynamic>) {
              secoesConvertidas.add(item);
            } else if (item is Map) {
              secoesConvertidas.add(Map<String, dynamic>.from(item));
            }
          }

          if (!mounted) return;

          setState(() {
            _secoesBiografia = secoesConvertidas.isNotEmpty
                ? secoesConvertidas
                : _getSecoesBiografiaPadrao();
            _carregando = false;
          });
        } else {
          if (!mounted) return;

          setState(() {
            _secoesBiografia = _getSecoesBiografiaPadrao();
            _carregando = false;
          });
        }
      } else {
        if (!mounted) return;

        setState(() {
          _secoesBiografia = _getSecoesBiografiaPadrao();
          _carregando = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar biografia: $e');

      if (!mounted) return;

      setState(() {
        _secoesBiografia = _getSecoesBiografiaPadrao();
        _carregando = false;
      });
    }
  }

  List<Map<String, dynamic>> _getSecoesBiografiaPadrao() {
    return [
      {
        'titulo': 'Nossa História',
        'icone': Icons.auto_stories_rounded,
        'cor': 'primary',
        'conteudo':
            'O Grupo UAI Capoeira nasceu com o propósito de fortalecer a capoeira como instrumento de educação, cultura, disciplina e transformação social.\n\n'
            'Através dos treinos, rodas, eventos e projetos, buscamos formar não apenas capoeiristas, mas cidadãos conscientes, respeitosos e comprometidos com a comunidade.',
      },
      {
        'titulo': 'Missão',
        'icone': Icons.flag_rounded,
        'cor': 'success',
        'conteudo':
            'Promover a capoeira de forma organizada, acessível e responsável, valorizando seus fundamentos, sua musicalidade, sua história e seu papel social.\n\n'
            'Nosso compromisso é acolher alunos de diferentes idades, respeitando o tempo de cada um e incentivando a evolução dentro e fora da roda.',
      },
      {
        'titulo': 'Valores',
        'icone': Icons.favorite_rounded,
        'cor': 'warning',
        'conteudo':
            'União, amizade, inteligência, respeito, disciplina, humildade, responsabilidade e amor pela capoeira.\n\n'
            'Cada treino é uma oportunidade de aprender, ensinar, superar limites e fortalecer os laços entre alunos, professores, famílias e comunidade.',
      },
      {
        'titulo': 'Capoeira e Comunidade',
        'icone': Icons.groups_rounded,
        'cor': 'info',
        'conteudo':
            'A capoeira é cultura viva. Por isso, o Grupo UAI Capoeira busca estar presente em eventos, apresentações, ações sociais, rodas e atividades educativas.\n\n'
            'Nosso trabalho valoriza a tradição da capoeira e, ao mesmo tempo, utiliza a organização e a tecnologia para melhorar a gestão, a comunicação e o acompanhamento dos alunos.',
      },
    ];
  }

  IconData _getIconFromName(dynamic iconName) {
    if (iconName is IconData) return iconName;

    switch (iconName?.toString()) {
      case 'auto_stories':
      case 'auto_stories_rounded':
        return Icons.auto_stories_rounded;
      case 'history':
      case 'history_edu':
        return Icons.history_edu_rounded;
      case 'flag':
      case 'flag_rounded':
        return Icons.flag_rounded;
      case 'favorite':
      case 'favorite_rounded':
        return Icons.favorite_rounded;
      case 'groups':
      case 'groups_rounded':
        return Icons.groups_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'sports_martial_arts':
        return Icons.sports_martial_arts_rounded;
      case 'public':
        return Icons.public_rounded;
      case 'emoji_events':
        return Icons.emoji_events_rounded;
      case 'lightbulb': return Icons.lightbulb_rounded;
      case 'menu_book': return Icons.menu_book_rounded;
      case 'park': return Icons.park_rounded;
      case 'eco': return Icons.eco_rounded;
      case 'timeline': return Icons.timeline_rounded;
      case 'trending_up': return Icons.trending_up_rounded;
      case 'diversity_3': return Icons.diversity_3_rounded;
      case 'person': return Icons.person_rounded;
      case 'theater_comedy': return Icons.theater_comedy_rounded;
      case 'music_note': return Icons.music_note_rounded;
      case 'location_on': return Icons.location_on_rounded;
      case 'explore': return Icons.explore_rounded;
      case 'handshake': return Icons.handshake_rounded;
      case 'volunteer_activism': return Icons.volunteer_activism_rounded;
      case 'accessibility_new': return Icons.accessibility_new_rounded;
      case 'family_restroom': return Icons.family_restroom_rounded;
      case 'hub': return Icons.hub_rounded;
      case 'shield': return Icons.shield_rounded;
      case 'track_changes': return Icons.track_changes_rounded;
      case 'star': return Icons.star_rounded;
      case 'workspace_premium': return Icons.workspace_premium_rounded;
      case 'favorite_border': return Icons.favorite_border_rounded;
      case 'article': return Icons.article_rounded;
      case 'format_quote': return Icons.format_quote_rounded;
      case 'photo_library': return Icons.photo_library_rounded;
      case 'event': return Icons.event_rounded;
      case 'done_all': return Icons.done_all_rounded;
      default:
        return Icons.auto_stories_rounded;
    }
  }

  Color _resolveColor(dynamic value, {required Color fallback}) {
    final t = context.uai;

    if (value is Color) return value;

    if (value is int) {
      try {
        return Color(value);
      } catch (_) {
        return fallback;
      }
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();

      switch (normalized) {
        case 'primary':
        case 'vermelho':
        case 'red':
          return t.primary;
        case 'blue':
        case 'azul':
        case 'info':
          return t.info;
        case 'green':
        case 'verde':
        case 'success':
          return t.success;
        case 'orange':
        case 'laranja':
        case 'warning':
          return t.warning;
        case 'purple':
        case 'roxo':
        case 'associacao':
        case 'associação':
          return t.associacao;
        case 'error':
          return t.error;
        case 'teal':
        case 'inscricoes':
        case 'inscrições':
          return t.inscricoes;
        case 'rifas':
          return t.rifas;
        case 'eventos':
          return t.eventos;
        case 'uniformes':
          return t.uniformes;
      }

      try {
        final cleaned = normalized
            .replaceAll('#', '')
            .replaceAll('0x', '')
            .toUpperCase();

        if (cleaned.length == 6) {
          return Color(int.parse('FF$cleaned', radix: 16));
        }

        if (cleaned.length == 8) {
          return Color(int.parse(cleaned, radix: 16));
        }
      } catch (_) {
        return fallback;
      }
    }

    return fallback;
  }

  String _limparTitulo(String titulo) {
    return titulo.replaceAll(RegExp(r'^[^\wÀ-ÖØ-öø-ÿ]+'), '').trim();
  }

  List<String> _paragrafos(String conteudo) {
    return conteudo
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Color _fallbackColor(int index) {
    final t = context.uai;

    final colors = [
      t.primary,
      t.success,
      t.warning,
      t.info,
      t.associacao,
      t.inscricoes,
      t.rifas,
      t.eventos,
    ];

    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    // IMPORTANTE:
    // Esta tela é usada dentro da LandingPage, que já tem AppBar.
    // Então aqui não existe Scaffold/AppBar para não duplicar barras.
    return ColoredBox(
      color: t.background,
      child: _carregando
          ? _buildLoadingState()
          : RefreshIndicator(
              color: t.primary,
              backgroundColor: t.surface,
              onRefresh: () async {
                _rastreioService.registrarClique(
                  nome: 'atualizar_biografia',
                  origem: 'biografia',
                );
                await _carregarBiografia();
              },
              child: _buildContent(),
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
            const SizedBox(height: 14),
            Text(
              'Carregando biografia...',
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

  Widget _buildContent() {
    if (_secoesBiografia.isEmpty) {
      return _buildEmptyState();
    }

    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 24,
        isMobile ? 14 : 22,
        isMobile ? 14 : 24,
        30,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHero(isMobile),
                const SizedBox(height: 16),
                _buildIntro(isMobile),
                const SizedBox(height: 10),
                _buildSecoesLayout(isMobile),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero(bool isMobile) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(isMobile ? 24 : t.cardRadius + 6),
        boxShadow: t.softShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: onPrimary.withAlpha(36),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: onPrimary.withAlpha(41)),
            ),
            child: Icon(Icons.auto_stories_rounded, color: onPrimary, size: 38),
          );

          final text = Column(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                'Biografia',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 27 : 34,
                  fontWeight: FontWeight.w900,
                  height: 1.03,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Uma história construída em capítulos: pessoas, propósito, cultura e transformação por meio da capoeira.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withAlpha(209),
                  fontSize: narrow ? 13.5 : 15,
                  height: 1.38,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildWhiteChip(
                    icon: Icons.article_rounded,
                    label:
                        '${_secoesBiografia.length} ${_secoesBiografia.length == 1 ? 'seção' : 'seções'}',
                  ),
                  _buildWhiteChip(
                    icon: Icons.favorite_rounded,
                    label: 'Cultura e valores',
                  ),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(children: [icon, const SizedBox(height: 14), text]);
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWhiteChip({required IconData icon, required String label}) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withAlpha(36),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withAlpha(41)),
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

  Widget _buildIntro(bool isMobile) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.background);

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Color.alphaBlend(primary.withAlpha(23), t.cardAlt),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: primary.withAlpha(36)),
          ),
          child: Icon(Icons.menu_book_rounded, color: primary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nossa trajetória',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: isMobile ? 17 : 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'História, propósito e identidade do grupo.',
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecoesLayout(bool isMobile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final children = <Widget>[];
        for (var index = 0; index < _secoesBiografia.length; index++) {
          final featured = index == 0;
          final card = _buildSecaoLeitura(
            secao: _secoesBiografia[index],
            index: index,
            isMobile: isMobile,
            featured: featured,
          );
          if (featured || !wide) {
            children.add(SizedBox(width: constraints.maxWidth, child: card));
          } else {
            const gap = 14.0;
            children.add(SizedBox(width: (constraints.maxWidth - gap) / 2, child: card));
          }
        }
        return Wrap(spacing: 14, runSpacing: 14, children: children);
      },
    );
  }

  Widget _buildSecaoLeitura({
    required Map<String, dynamic> secao,
    required int index,
    required bool isMobile,
    bool featured = false,
  }) {
    final t = context.uai;

    final tituloOriginal = secao['titulo']?.toString() ?? 'Seção';
    final titulo = _limparTitulo(tituloOriginal);
    final icone = _getIconFromName(secao['icone']);
    final cor = _ensureVisible(
      _resolveColor(secao['cor'], fallback: _fallbackColor(index)),
      t.card,
    );
    final conteudo = secao['conteudo']?.toString() ?? '';
    final paragrafos = _paragrafos(conteudo);

    return Container(
      margin: EdgeInsets.zero,
      decoration: _cardDecoration(borderColor: cor.withAlpha(33)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.cardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 15 : 17),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.alphaBlend(cor.withAlpha(28), t.cardAlt),
                    t.card,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border(
                  bottom: BorderSide(color: cor.withAlpha(26)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: featured ? 54 : 46,
                    height: featured ? 54 : 46,
                    decoration: BoxDecoration(
                      color: cor.withAlpha(26),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: cor.withAlpha(33)),
                    ),
                    child: Icon(icone, color: cor, size: featured ? 29 : 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      titulo,
                      style: TextStyle(
                        fontSize: featured ? (isMobile ? 18 : 22) : (isMobile ? 15.5 : 17.5),
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: t.cardAlt,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: cor.withAlpha(36)),
                    ),
                    child: Text(
                      featured ? 'CAPÍTULO ${index + 1}' : '${index + 1}',
                      style: TextStyle(
                        color: cor,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(isMobile ? 14 : 16),
              child: paragrafos.isEmpty
                  ? Text(
                      'Conteúdo não informado.',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List.generate(paragrafos.length, (i) {
                        return _buildParagrafo(
                          texto: paragrafos[i],
                          cor: cor,
                          isMobile: isMobile,
                          isFirst: i == 0,
                        );
                      }),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParagrafo({
    required String texto,
    required Color cor,
    required bool isMobile,
    required bool isFirst,
  }) {
    final t = context.uai;
    if (texto.trim().endsWith(':')) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(
          _limparTitulo(texto),
          style: TextStyle(color: cor, fontSize: isMobile ? 13 : 14, fontWeight: FontWeight.w900, height: 1.25),
        ),
      );
    }
    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 10 : 12),
      padding: EdgeInsets.only(left: isFirst ? 13 : 0),
      decoration: isFirst
          ? BoxDecoration(border: Border(left: BorderSide(color: cor, width: 3)))
          : null,
      child: Text(
        texto,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: isMobile ? 13.4 : 14.4,
          height: 1.58,
          fontWeight: isFirst ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
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
              Icon(Icons.auto_stories_outlined, size: 74, color: t.textMuted),
              const SizedBox(height: 14),
              Text(
                'Nenhuma seção encontrada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Cadastre o conteúdo da biografia no painel administrativo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, height: 1.3),
              ),
            ],
          ),
        ),
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
