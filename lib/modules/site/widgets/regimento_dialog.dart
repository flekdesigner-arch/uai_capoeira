import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class RegimentoDialog extends StatefulWidget {
  const RegimentoDialog({super.key});

  @override
  State<RegimentoDialog> createState() => _RegimentoDialogState();
}

class _RegimentoDialogState extends State<RegimentoDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _secoesRegimento = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarRegimento();
  }

  Future<void> _carregarRegimento() async {
    try {
      final doc = await _firestore
          .collection('site_conteudo')
          .doc('regimento')
          .get();

      if (doc.exists) {
        final data = doc.data()!;

        if (data.containsKey('secoes') && data['secoes'] is List) {
          final List<dynamic> secoesRaw = data['secoes'] as List;
          final secoesConvertidas = <Map<String, dynamic>>[];

          for (final item in secoesRaw) {
            if (item is Map<String, dynamic>) {
              secoesConvertidas.add(item);
            } else if (item is Map) {
              secoesConvertidas.add(Map<String, dynamic>.from(item));
            }
          }

          if (mounted) {
            setState(() {
              _secoesRegimento = secoesConvertidas.isNotEmpty
                  ? secoesConvertidas
                  : _getSecoesRegimentoPadrao();
              _carregando = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _secoesRegimento = _getSecoesRegimentoPadrao();
              _carregando = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _secoesRegimento = _getSecoesRegimentoPadrao();
            _carregando = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar regimento no diálogo: $e');

      if (mounted) {
        setState(() {
          _secoesRegimento = _getSecoesRegimentoPadrao();
          _carregando = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getSecoesRegimentoPadrao() {
    return [
      {
        'titulo': '⚖️ REGRAS GERAIS',
        'icone': Icons.gavel,
        'cor': Colors.blue,
        'conteudo':
            '🚫 Proibido uso do uniforme em locais inadequados (bares, festas, baladas).\n'
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
        'cor': Colors.green,
        'conteudo':
            '⏳ Prazo de 2 meses para adquirir o uniforme completo.\n'
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
        'cor': Colors.orange,
        'conteudo':
            '🙏 Respeito, disciplina e comprometimento são indispensáveis.\n'
            '👕 Uso do uniforme correto nos treinos e apresentações é obrigatório.\n'
            '⏳ Graduação só pode ser trocada após no mínimo 1 ano, conforme desempenho.\n'
            '🎭 Em eventos, utilizar somente o uniforme oficial (não camisas promocionais).\n'
            '⚠️ Faltas por mais de 1 mês sem aviso resultam em desligamento automático.\n'
            '💪 O graduado deve dar exemplo de postura, ajudando os iniciantes e fortalecendo a roda.',
      },
      {
        'titulo': '⭐ FORMADOS',
        'icone': Icons.workspace_premium,
        'cor': Colors.purple,
        'conteudo':
            'São considerados formados os monitores, instrutores, professores, contra-mestres e mestres.\n\n'
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
      case 'gavel': return Icons.gavel_rounded;
      case 'rule': return Icons.rule_rounded;
      case 'security': return Icons.security_rounded;
      case 'groups':
      case 'group': return Icons.groups_rounded;
      case 'person_add': return Icons.person_add_alt_1_rounded;
      case 'military_tech': return Icons.military_tech_rounded;
      case 'school': return Icons.school_rounded;
      case 'workspace_premium': return Icons.workspace_premium_rounded;
      case 'verified_user': return Icons.verified_user_rounded;
      case 'handshake': return Icons.handshake_rounded;
      case 'favorite': return Icons.favorite_rounded;
      case 'fact_check': return Icons.fact_check_rounded;
      case 'schedule': return Icons.schedule_rounded;
      case 'checkroom': return Icons.checkroom_rounded;
      case 'event': return Icons.event_rounded;
      case 'emoji_events': return Icons.emoji_events_rounded;
      case 'music_note': return Icons.music_note_rounded;
      case 'album': return Icons.album_rounded;
      case 'history_edu': return Icons.history_edu_rounded;
      case 'menu_book': return Icons.menu_book_rounded;
      case 'location_on': return Icons.location_on_rounded;
      case 'travel_explore': return Icons.travel_explore_rounded;
      case 'diversity_3': return Icons.diversity_3_rounded;
      case 'family_restroom': return Icons.family_restroom_rounded;
      case 'campaign': return Icons.campaign_rounded;
      case 'block': return Icons.block_rounded;
      case 'task_alt': return Icons.task_alt_rounded;
      case 'warning': return Icons.warning_amber_rounded;
      case 'badge': return Icons.badge_rounded;
      case 'volunteer_activism': return Icons.volunteer_activism_rounded;
      case 'track_changes': return Icons.track_changes_rounded;
      case 'star': return Icons.star_rounded;
      default: return Icons.description_rounded;
    }
  }

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

  Color _fallbackColor(int index) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.red,
    ];

    return colors[index % colors.length];
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

  int get _totalOrientacoes {
    return _secoesRegimento.fold<int>(
      0,
      (total, secao) =>
          total + _linhasConteudo(secao['conteudo']?.toString() ?? '').length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final t = context.uai;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      backgroundColor: Colors.transparent,
      child: SafeArea(
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: 1180,
            maxHeight: size.height * 0.94,
          ),
          decoration: BoxDecoration(
            color: t.background,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(46),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: _carregando
                      ? _buildLoadingState()
                      : _secoesRegimento.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          color: Colors.red.shade900,
                          onRefresh: _carregarRegimento,
                          child: _buildContent(),
                        ),
                ),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(gradient: t.primaryGradient),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: onPrimary.withAlpha(36),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: onPrimary.withAlpha(41)),
            ),
            child: Icon(
              Icons.gavel_rounded,
              color: t.surface,
              size: 24,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Regimento Interno',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                Text(
                  'Regras e orientações oficiais',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withAlpha(199),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: onPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    final t = context.uai;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.red.shade900),
            const SizedBox(height: 14),
            Text(
              'Carregando regimento...',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            isCompact ? 14 : 24,
            isCompact ? 14 : 22,
            isCompact ? 14 : 24,
            24,
          ),
          children: [
            _buildHero(isCompact),
            const SizedBox(height: 18),
            _buildSectionIntro(isCompact),
            const SizedBox(height: 10),
            _buildSecoesLayout(isCompact),
          ],
        );
      },
    );
  }

  Widget _buildHero(bool isCompact) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: EdgeInsets.all(isCompact ? 18 : 24),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(isCompact ? 24 : t.cardRadius + 6),
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
            child: Icon(Icons.gavel_rounded, color: onPrimary, size: 38),
          );

          final text = Column(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
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
                'Normas e orientações que preservam a identidade, a disciplina e a convivência do Grupo UAI Capoeira.',
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
                    label: '${_secoesRegimento.length} ${_secoesRegimento.length == 1 ? 'seção' : 'seções'}',
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

  Widget _buildResumoCards(bool isCompact) {
    final cards = [
      _ResumoRegimento(
        icon: Icons.article_rounded,
        label: 'Seções',
        value: _secoesRegimento.length.toString(),
        color: Colors.blue,
      ),
      _ResumoRegimento(
        icon: Icons.checklist_rounded,
        label: 'Orientações',
        value: _totalOrientacoes.toString(),
        color: Colors.green,
      ),
      _ResumoRegimento(
        icon: Icons.groups_rounded,
        label: 'Grupo',
        value: 'UAI',
        color: Colors.orange,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final itemWidth = (constraints.maxWidth - spacing * 2) / 3;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) {
            return SizedBox(
              width: itemWidth,
              child: _buildResumoCard(card, compact: isCompact),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildResumoCard(_ResumoRegimento card, {required bool compact}) {
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 82 : 92),
      padding: EdgeInsets.all(compact ? 9 : 12),
      decoration: _cardDecoration(borderColor: card.color.withAlpha(26)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(card.icon, color: card.color, size: compact ? 21 : 24),
          const SizedBox(height: 5),
          Text(
            card.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: card.color,
              fontSize: compact ? 16 : 20,
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
              color: Colors.grey.shade700,
              fontSize: compact ? 9.6 : 10.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionIntro(bool isCompact) {
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
                'Orientações do grupo',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: isCompact ? 17 : 20,
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

  Widget _buildSecoesLayout(bool isCompact) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;

        if (!wide) {
          return Column(
            children: List.generate(_secoesRegimento.length, (index) {
              return _buildSecaoLeitura(
                secao: _secoesRegimento[index],
                index: index,
                isCompact: isCompact,
                featured: index == 0,
              );
            }),
          );
        }

        const spacing = 16.0;
        final children = <Widget>[];
        if (_secoesRegimento.isNotEmpty) {
          children.add(
            _buildSecaoLeitura(
              secao: _secoesRegimento.first,
              index: 0,
              isCompact: false,
              featured: true,
            ),
          );
          if (_secoesRegimento.length > 1) {
            children.add(const SizedBox(height: spacing));
          }
        }

        if (_secoesRegimento.length > 1) {
          final itemWidth = (constraints.maxWidth - spacing) / 2;
          children.add(
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: List.generate(_secoesRegimento.length - 1, (offset) {
                final index = offset + 1;
                return SizedBox(
                  width: itemWidth,
                  child: _buildSecaoLeitura(
                    secao: _secoesRegimento[index],
                    index: index,
                    isCompact: false,
                  ),
                );
              }),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }

  Widget _buildSecaoLeitura({
    required Map<String, dynamic> secao,
    required int index,
    required bool isCompact,
    bool featured = false,
  }) {
    final tituloOriginal = secao['titulo']?.toString() ?? 'Seção';
    final titulo = _limparTitulo(tituloOriginal);
    final icone = secao['icone'] is IconData
        ? secao['icone'] as IconData
        : _getIconFromName(secao['icone']);
    final t = context.uai;
    final cor = _ensureVisible(
      _resolveColor(secao['cor'], fallback: _fallbackColor(index)),
      t.card,
    );
    final conteudo = secao['conteudo']?.toString() ?? '';
    final linhas = _linhasConteudo(conteudo);

    return Container(
      margin: EdgeInsets.only(bottom: isCompact ? 14 : 0),
      decoration: _cardDecoration(borderColor: cor.withAlpha(33)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.all(
                featured ? (isCompact ? 16 : 20) : (isCompact ? 15 : 17),
              ),
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
                    width: featured ? 54 : 48,
                    height: featured ? 54 : 48,
                    decoration: BoxDecoration(
                      color: cor.withAlpha(26),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: cor.withAlpha(31)),
                    ),
                    child: Icon(icone, color: cor, size: featured ? 28 : 25),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: featured
                            ? (isCompact ? 18 : 21)
                            : (isCompact ? 16 : 18),
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: t.cardAlt,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: cor.withAlpha(31)),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: cor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(isCompact ? 12 : 14),
              child: linhas.isEmpty
                  ? Text(
                      'Conteúdo não informado.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
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
                          isCompact: isCompact,
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
    required bool isCompact,
  }) {
    if (_isTituloInterno(linha)) {
      return Container(
        margin: const EdgeInsets.only(top: 7, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cor.withAlpha(20),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: cor.withAlpha(31)),
        ),
        child: Text(
          _limparTitulo(linha),
          style: TextStyle(
            color: cor,
            fontSize: isCompact ? 12.2 : 13.2,
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
      );
    }

    if (_isBullet(linha)) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(isCompact ? 9 : 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: isCompact ? 25 : 27,
              height: isCompact ? 25 : 27,
              decoration: BoxDecoration(
                color: cor.withAlpha(23),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _bulletIcon(linha),
                color: cor,
                size: isCompact ? 15 : 16,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _removeBulletEmoji(linha),
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: isCompact ? 12.4 : 13.2,
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
          color: Colors.grey.shade800,
          fontSize: isCompact ? 12.8 : 13.6,
          height: 1.45,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 430),
          padding: const EdgeInsets.all(22),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.description_outlined,
                size: 68,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 14),
              const Text(
                'Nenhuma seção encontrada',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              Text(
                'Cadastre o conteúdo do regimento no painel administrativo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final t = context.uai;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(11),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check_rounded),
            label: const Text('ENTENDI'),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration({Color? borderColor}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: borderColor ?? Colors.grey.shade100),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha(8),
          blurRadius: 7,
          offset: const Offset(0, 3),
        ),
      ],
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
