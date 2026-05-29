import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/rastreio/services/rastreio_site.dart';

class RegimentoScreen extends StatefulWidget {
  const RegimentoScreen({super.key});

  @override
  State<RegimentoScreen> createState() => _RegimentoScreenState();
}

class _RegimentoScreenState extends State<RegimentoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final RastreioSiteService _rastreioService = RastreioSiteService();
  final ScrollController _scrollController = ScrollController();

  int _maiorPercentualRolagem = 0;

  List<Map<String, dynamic>> _secoesRegimento = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();

    _rastreioService.iniciarTela(
      'regimento',
      origem: 'site',
      metadata: {
        'descricao': 'Tela pública regimento',
      },
    );
    _rastreioService.marcarTempo('regimento_tempo');
    _scrollController.addListener(_registrarRolagem);
    _carregarRegimento();
  }

  @override
  void dispose() {
    _rastreioService.registrarTempoMarcador(
      chave: 'regimento_tempo',
      tipo: 'tempo_tela',
      nome: 'regimento',
      origem: 'dispose',
      metadata: {
        'maior_percentual_rolagem': _maiorPercentualRolagem,
        'total_secoes': _secoesRegimento.length,
      },
      limparMarcador: true,
    );
    _rastreioService.finalizarTela(destino: 'saida_regimento');
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
        nome: 'regimento_$marco%',
        origem: 'regimento',
        metadata: {
          'percentual': marco,
          'total_secoes': _secoesRegimento.length,
        },
      );
    }
  }

  Future<void> _carregarRegimento() async {
    try {
      final doc =
      await _firestore.collection('site_conteudo').doc('regimento').get();

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
            _secoesRegimento = secoesConvertidas.isNotEmpty
                ? secoesConvertidas
                : _getSecoesRegimentoPadrao();
            _carregando = false;
          });
        } else {
          if (!mounted) return;

          setState(() {
            _secoesRegimento = _getSecoesRegimentoPadrao();
            _carregando = false;
          });
        }
      } else {
        if (!mounted) return;

        setState(() {
          _secoesRegimento = _getSecoesRegimentoPadrao();
          _carregando = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar regimento: $e');

      if (!mounted) return;

      setState(() {
        _secoesRegimento = _getSecoesRegimentoPadrao();
        _carregando = false;
      });
    }
  }

  List<Map<String, dynamic>> _getSecoesRegimentoPadrao() {
    return [
      {
        'titulo': '⚖️ REGRAS GERAIS',
        'icone': Icons.gavel,
        'cor': 'info',
        'conteudo': '🚫 Proibido uso do uniforme em locais inadequados (bares, festas, baladas).\n'
            '❌ Não é permitido utilizar uniformes de outros grupos.\n'
            '📢 Participação em eventos externos deve ser comunicada antecipadamente.\n'
            '⏰ Cumprimento rigoroso dos horários de treinos, rodas e apresentações.\n'
            '👕 Em dias de roda ou apresentações é obrigatório o uniforme completo (calça branca, camisa e graduação).\n'
            '🧼 Manter a higiene pessoal: unhas cortadas, roupas limpas e bom cuidado com o uniforme.\n'
            '🙏 Respeitar mestres, professores, colegas e visitantes, independente de idade ou graduação.\n'
            '🤝 Ao visitar outras academias ou grupos de capoeira, o aluno deve:\n'
            '   • Avisar com antecedência os responsáveis do grupo\n'
            '   • Utilizar sempre a camisa oficial do grupo UAI Capoeira\n'
            '   • Não participar sem identificação do grupo',
      },
      {
        'titulo': '🆕 NOVOS ALUNOS',
        'icone': Icons.person_add,
        'cor': 'success',
        'conteudo': '⏳ Prazo de 2 meses para adquirir o uniforme completo.\n'
            '👀 Durante esse período, o aluno será avaliado pelos professores.\n'
            '🎖️ Primeira graduação possível após 6 meses de treino regular.\n'
            '📅 Indicação para início das atividades: preferencialmente em uma segunda-feira.\n'
            '📲 Cadastro no sistema + ingresso em grupo de WhatsApp para comunicações.\n'
            '⚠️ Caso falte por mais de 3 semanas sem justificativa, será considerado desligado.\n'
            '🙌 Todo aluno deve manter postura respeitosa e colaborativa dentro e fora da academia.',
      },
      {
        'titulo': '🎓 ALUNOS GRADUADOS',
        'icone': Icons.school,
        'cor': 'warning',
        'conteudo': '🙏 Respeito, disciplina e comprometimento são indispensáveis.\n'
            '👕 Uso do uniforme correto nos treinos e apresentações é obrigatório.\n'
            '⏳ Graduação só pode ser trocada após no mínimo 1 ano, conforme desempenho.\n'
            '🎭 Em eventos, utilizar somente o uniforme oficial (não camisas promocionais).\n'
            '⚠️ Faltas por mais de 1 mês sem aviso resultam em desligamento automático.\n'
            '💪 O graduado deve dar exemplo de postura, ajudando os iniciantes e fortalecendo a roda.',
      },
      {
        'titulo': '⭐ FORMADOS',
        'icone': Icons.workspace_premium,
        'cor': 'associacao',
        'conteudo': 'São considerados formados os monitores, instrutores, professores, contra-mestres e mestres.\n\n'
            '📚 Devem estar sempre ativos nos treinos e rodas, transmitindo conhecimento.\n'
            '🪘 Devem incentivar a prática dos instrumentos, cantos e fundamentos da capoeira.\n'
            '🌍 Representam o grupo dentro e fora da cidade, mantendo o nome da Associação com honra e responsabilidade.\n\n'
            '📖 ESTÁGIOS DE FORMAÇÃO:\n\n'
            '👨‍🎓 MONITOR:\n'
            '• 🔞 Ter no mínimo 18 anos\n'
            '• 🎓 Ensino médio completo\n'
            '• 🔵 Pelo menos 1 ano de graduação na 6ª corda (azul)\n'
            '• 📖 Capacidade para ministrar aulas, com ou sem auxílio\n'
            '• 🥁 Conhecimento básico dos instrumentos e toques da capoeira\n'
            '• ⚔️ Conhecimento dos fundamentos e da história do grupo\n'
            '• 🪪 Ser associado ativo\n\n'
            '👨‍🏫 INSTRUTOR:\n'
            '• ✅ Requisitos de monitor atendidos\n'
            '• ⏳ No mínimo 4 anos como monitor\n'
            '• 📖 Capacidade de ministrar e planejar aulas de forma independente\n'
            '• 🔍 Habilidade de identificar e corrigir dificuldades dos alunos\n'
            '• 🚀 Busca contínua por conhecimento e aprimoramento\n\n'
            '👨‍🎓 PROFESSOR:\n'
            '• ✅ Todos os requisitos anteriores\n'
            '• 📜 Diploma emitido pelo grupo, com reconhecimento dos mestres e formados\n'
            '• 🌍 Responsabilidade em representar o grupo oficialmente em eventos nacionais e internacionais\n'
            '• 🎓 Reconhecimento como profissional da área da Capoeira',
      },
    ];
  }

  IconData _getIconFromName(dynamic iconName) {
    if (iconName is IconData) return iconName;

    switch (iconName?.toString()) {
      case 'gavel':
        return Icons.gavel;
      case 'person_add':
        return Icons.person_add;
      case 'school':
        return Icons.school;
      case 'workspace_premium':
        return Icons.workspace_premium;
      case 'groups':
        return Icons.groups_rounded;
      case 'shield':
        return Icons.shield_rounded;
      case 'warning':
        return Icons.warning_rounded;
      case 'info':
        return Icons.info_rounded;
      default:
        return Icons.description_rounded;
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
        case 'red':
        case 'vermelho':
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

  List<String> _linhasConteudo(String conteudo) {
    return conteudo
        .split('\n')
        .map((e) => e.trimRight())
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  bool _isTituloInterno(String linha) {
    final clean = linha.trim();

    if (clean.endsWith(':')) return true;

    final semEmoji = clean.replaceAll(RegExp(r'^[^\wÀ-ÖØ-öø-ÿ]+'), '').trim();

    return semEmoji.length > 3 &&
        semEmoji == semEmoji.toUpperCase() &&
        semEmoji.contains(RegExp(r'[A-ZÁ-Ú]'));
  }

  bool _isBullet(String linha) {
    final clean = linha.trimLeft();

    return clean.startsWith('•') ||
        clean.startsWith('-') ||
        clean.startsWith('–') ||
        clean.startsWith('✅') ||
        clean.startsWith('❌') ||
        clean.startsWith('🚫') ||
        clean.startsWith('📢') ||
        clean.startsWith('⏰') ||
        clean.startsWith('👕') ||
        clean.startsWith('🧼') ||
        clean.startsWith('🙏') ||
        clean.startsWith('🤝') ||
        clean.startsWith('⏳') ||
        clean.startsWith('👀') ||
        clean.startsWith('🎖️') ||
        clean.startsWith('📅') ||
        clean.startsWith('📲') ||
        clean.startsWith('⚠️') ||
        clean.startsWith('🙌') ||
        clean.startsWith('🎭') ||
        clean.startsWith('💪') ||
        clean.startsWith('📚') ||
        clean.startsWith('🪘') ||
        clean.startsWith('🌍') ||
        clean.startsWith('🔞') ||
        clean.startsWith('🎓') ||
        clean.startsWith('🔵') ||
        clean.startsWith('📖') ||
        clean.startsWith('🥁') ||
        clean.startsWith('⚔️') ||
        clean.startsWith('🪪') ||
        clean.startsWith('🔍') ||
        clean.startsWith('🚀') ||
        clean.startsWith('📜');
  }

  IconData _bulletIcon(String linha) {
    final clean = linha.trimLeft();

    if (clean.startsWith('❌') || clean.startsWith('🚫')) {
      return Icons.block_rounded;
    }

    if (clean.startsWith('⚠️')) return Icons.warning_rounded;
    if (clean.startsWith('✅')) return Icons.check_circle_rounded;

    if (clean.startsWith('⏰') || clean.startsWith('⏳')) {
      return Icons.schedule_rounded;
    }

    if (clean.startsWith('👕') || clean.startsWith('🧼')) {
      return Icons.checkroom_rounded;
    }

    if (clean.startsWith('📅')) return Icons.event_rounded;
    if (clean.startsWith('📲')) return Icons.phone_android_rounded;

    if (clean.startsWith('🎓') || clean.startsWith('🎖️')) {
      return Icons.school_rounded;
    }

    if (clean.startsWith('📚') || clean.startsWith('📖')) {
      return Icons.menu_book_rounded;
    }

    if (clean.startsWith('🌍')) return Icons.public_rounded;

    if (clean.startsWith('🤝') ||
        clean.startsWith('🙏') ||
        clean.startsWith('🙌')) {
      return Icons.handshake_rounded;
    }

    return Icons.check_rounded;
  }

  String _removeBulletEmoji(String linha) {
    return linha
        .trim()
        .replaceFirst(RegExp(r'^(•|-|–)\s*'), '')
        .replaceFirst(RegExp(r'^[^\wÀ-ÖØ-öø-ÿ]+\s*'), '')
        .trim();
  }

  Color _fallbackColor(int index) {
    final t = context.uai;

    final colors = [
      t.info,
      t.success,
      t.warning,
      t.associacao,
      t.inscricoes,
      t.error,
      t.rifas,
      t.eventos,
    ];

    return colors[index % colors.length];
  }

  int _totalLinhas() {
    return _secoesRegimento.fold<int>(
      0,
          (total, secao) {
        final conteudo = secao['conteudo']?.toString() ?? '';
        return total + _linhasConteudo(conteudo).length;
      },
    );
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
            nome: 'atualizar_regimento',
            origem: 'regimento',
          );
          await _carregarRegimento();
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
              'Carregando regimento...',
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
    if (_secoesRegimento.isEmpty) {
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
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHero(isMobile),
                const SizedBox(height: 14),
                _buildResumoCards(isMobile),
                const SizedBox(height: 16),
                _buildSectionIntro(isMobile),
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
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.gavel_rounded,
              color: onPrimary,
              size: 38,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Regimento Interno',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 25 : 32,
                  fontWeight: FontWeight.w900,
                  height: 1.03,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Normas, orientações e valores que fortalecem a organização do Grupo UAI Capoeira.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
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
                    '${_secoesRegimento.length} ${_secoesRegimento.length == 1 ? 'seção' : 'seções'}',
                  ),
                  _buildWhiteChip(
                    icon: Icons.verified_rounded,
                    label: 'Leitura oficial',
                  ),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 14),
                text,
              ],
            );
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

  Widget _buildResumoCards(bool isMobile) {
    final t = context.uai;

    final cards = [
      _ResumoRegimento(
        icon: Icons.article_rounded,
        label: 'Seções',
        value: _secoesRegimento.length.toString(),
        color: t.info,
      ),
      _ResumoRegimento(
        icon: Icons.checklist_rounded,
        label: 'Orientações',
        value: _totalLinhas().toString(),
        color: t.success,
      ),
      _ResumoRegimento(
        icon: Icons.groups_rounded,
        label: 'Grupo',
        value: 'UAI',
        color: t.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final itemWidth = (constraints.maxWidth - spacing * 2) / 3;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) {
            return SizedBox(
              width: itemWidth,
              child: _buildResumoCard(card, compact: isMobile),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildResumoCard(_ResumoRegimento card, {required bool compact}) {
    final t = context.uai;
    final accent = _ensureVisible(card.color, t.card);

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 94 : 104),
      padding: EdgeInsets.all(compact ? 10 : 13),
      decoration: _cardDecoration(borderColor: accent.withOpacity(0.13)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(card.icon, color: accent, size: compact ? 23 : 26),
          const SizedBox(height: 6),
          Text(
            card.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: compact ? 18 : 22,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            card.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: compact ? 10.5 : 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionIntro(bool isMobile) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.background);

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Color.alphaBlend(primary.withOpacity(0.09), t.cardAlt),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: primary.withOpacity(0.14)),
          ),
          child: Icon(
            Icons.menu_book_rounded,
            color: primary,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Orientações do grupo',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: isMobile ? 17 : 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Leia com atenção cada seção do regimento.',
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
        final wide = constraints.maxWidth >= 920;

        if (!wide) {
          return Column(
            children: List.generate(_secoesRegimento.length, (index) {
              return _buildSecaoLeitura(
                secao: _secoesRegimento[index],
                index: index,
                isMobile: isMobile,
              );
            }),
          );
        }

        const spacing = 14.0;
        final itemWidth = (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: List.generate(_secoesRegimento.length, (index) {
            return SizedBox(
              width: itemWidth,
              child: _buildSecaoLeitura(
                secao: _secoesRegimento[index],
                index: index,
                isMobile: false,
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildSecaoLeitura({
    required Map<String, dynamic> secao,
    required int index,
    required bool isMobile,
  }) {
    final t = context.uai;

    final tituloOriginal = secao['titulo']?.toString() ?? 'Seção';
    final titulo = _limparTitulo(tituloOriginal);
    final icone = _getIconFromName(secao['icone']);
    final cor = _ensureVisible(
      _resolveColor(
        secao['cor'],
        fallback: _fallbackColor(index),
      ),
      t.card,
    );
    final conteudo = secao['conteudo']?.toString() ?? '';
    final linhas = _linhasConteudo(conteudo);

    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 14 : 0),
      decoration: _cardDecoration(borderColor: cor.withOpacity(0.13)),
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
                    Color.alphaBlend(cor.withOpacity(0.11), t.cardAlt),
                    t.card,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border(
                  bottom: BorderSide(color: cor.withOpacity(0.10)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: cor.withOpacity(0.13)),
                    ),
                    child: Icon(icone, color: cor, size: 25),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      titulo,
                      style: TextStyle(
                        fontSize: isMobile ? 16 : 18,
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
                      border: Border.all(color: cor.withOpacity(0.14)),
                    ),
                    child: Text(
                      '${index + 1}',
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
              child: linhas.isEmpty
                  ? Text(
                'Conteúdo não informado.',
                style: TextStyle(
                  color: t.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(linhas.length, (i) {
                  final linha = linhas[i];
                  return _buildLinhaRegimento(
                    linha: linha,
                    cor: cor,
                    isMobile: isMobile,
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinhaRegimento({
    required String linha,
    required Color cor,
    required bool isMobile,
  }) {
    final t = context.uai;

    if (_isTituloInterno(linha)) {
      return Container(
        margin: const EdgeInsets.only(top: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: Color.alphaBlend(cor.withOpacity(0.09), t.cardAlt),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cor.withOpacity(0.14)),
        ),
        child: Text(
          _limparTitulo(linha),
          style: TextStyle(
            color: cor,
            fontSize: isMobile ? 12.5 : 13.5,
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
      );
    }

    if (_isBullet(linha)) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: t.cardAlt,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: t.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 27,
              height: 27,
              decoration: BoxDecoration(
                color: Color.alphaBlend(cor.withOpacity(0.10), t.card),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cor.withOpacity(0.12)),
              ),
              child: Icon(_bulletIcon(linha), color: cor, size: 16),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _removeBulletEmoji(linha),
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: isMobile ? 12.8 : 13.5,
                  height: 1.34,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        linha,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: isMobile ? 13.2 : 14,
          height: 1.45,
          fontWeight: FontWeight.w500,
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
              Icon(
                Icons.description_outlined,
                size: 74,
                color: t.textMuted,
              ),
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
                'Cadastre o conteúdo do regimento no painel administrativo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textSecondary,
                  height: 1.3,
                ),
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

class _ResumoRegimento {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ResumoRegimento({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}
