import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegimentoScreen extends StatefulWidget {
  const RegimentoScreen({super.key});

  @override
  State<RegimentoScreen> createState() => _RegimentoScreenState();
}

class _RegimentoScreenState extends State<RegimentoScreen> {
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
      final doc =
      await _firestore.collection('site_conteudo').doc('regimento').get();

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
      debugPrint('❌ Erro ao carregar regimento: $e');

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
        'cor': Colors.green,
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
        'cor': Colors.orange,
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
        'cor': Colors.purple,
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
          return Colors.blue;
        case 'green':
        case 'verde':
          return Colors.green;
        case 'orange':
        case 'laranja':
          return Colors.orange;
        case 'purple':
        case 'roxo':
          return Colors.purple;
        case 'red':
        case 'vermelho':
          return Colors.red;
        case 'teal':
          return Colors.teal;
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
    if (clean.startsWith('🤝') || clean.startsWith('🙏') || clean.startsWith('🙌')) {
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text(
            'Regimento Interno',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _carregando
            ? _buildLoadingState()
            : RefreshIndicator(
          color: Colors.red.shade900,
          onRefresh: _carregarRegimento,
          child: _buildContent(isMobile),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
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

  Widget _buildContent(bool isMobile) {
    if (_secoesRegimento.isEmpty) {
      return _buildEmptyState();
    }

    return ListView(
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
    return Container(
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(isMobile ? 24 : 30),
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
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: const Icon(
              Icons.gavel_rounded,
              color: Colors.white,
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
                  color: Colors.white,
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
                  color: Colors.white.withOpacity(0.82),
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

  Widget _buildResumoCards(bool isMobile) {
    final totalLinhas = _secoesRegimento.fold<int>(
      0,
          (total, secao) =>
      total + _linhasConteudo(secao['conteudo']?.toString() ?? '').length,
    );

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
        value: totalLinhas.toString(),
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
        final columns = constraints.maxWidth < 520 ? 3 : 3;
        const spacing = 10.0;
        final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;

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
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 94 : 104),
      padding: EdgeInsets.all(compact ? 10 : 13),
      decoration: _cardDecoration(borderColor: card.color.withOpacity(0.10)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(card.icon, color: card.color, size: compact ? 23 : 26),
          const SizedBox(height: 6),
          Text(
            card.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: card.color,
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
              color: Colors.grey.shade700,
              fontSize: compact ? 10.5 : 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionIntro(bool isMobile) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.red.shade900.withOpacity(0.08),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            Icons.menu_book_rounded,
            color: Colors.red.shade900,
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
                  color: Colors.grey.shade900,
                  fontSize: isMobile ? 17 : 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Leia com atenção cada seção do regimento.',
                style: TextStyle(
                  color: Colors.grey.shade600,
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
    final tituloOriginal = secao['titulo']?.toString() ?? 'Seção';
    final titulo = _limparTitulo(tituloOriginal);
    final icone = secao['icone'] is IconData
        ? secao['icone'] as IconData
        : _getIconFromName(secao['icone']);
    final cor = _resolveColor(
      secao['cor'],
      fallback: _fallbackColor(index),
    );
    final conteudo = secao['conteudo']?.toString() ?? '';

    final linhas = _linhasConteudo(conteudo);

    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 14 : 0),
      decoration: _cardDecoration(borderColor: cor.withOpacity(0.12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 15 : 17),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cor.withOpacity(0.13), cor.withOpacity(0.05)],
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
                      border: Border.all(color: cor.withOpacity(0.12)),
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
                        color: Colors.grey.shade900,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: cor.withOpacity(0.12)),
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
    if (_isTituloInterno(linha)) {
      return Container(
        margin: const EdgeInsets.only(top: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cor.withOpacity(0.12)),
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
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 27,
              height: 27,
              decoration: BoxDecoration(
                color: cor.withOpacity(0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_bulletIcon(linha), color: cor, size: 16),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _removeBulletEmoji(linha),
                style: TextStyle(
                  color: Colors.grey.shade800,
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
          color: Colors.grey.shade800,
          fontSize: isMobile ? 13.2 : 14,
          height: 1.45,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
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

  Widget _buildEmptyState() {
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
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 14),
              const Text(
                'Nenhuma seção encontrada',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
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

  BoxDecoration _cardDecoration({Color? borderColor}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: borderColor ?? Colors.grey.shade100),
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
