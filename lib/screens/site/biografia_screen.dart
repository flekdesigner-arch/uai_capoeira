import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BiografiaScreen extends StatefulWidget {
  const BiografiaScreen({super.key});

  @override
  State<BiografiaScreen> createState() => _BiografiaScreenState();
}

class _BiografiaScreenState extends State<BiografiaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _secoesBiografia = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarBiografia();
  }

  Future<void> _carregarBiografia() async {
    try {
      final doc =
      await _firestore.collection('site_conteudo').doc('biografia').get();

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
              _secoesBiografia = secoesConvertidas.isNotEmpty
                  ? secoesConvertidas
                  : _getSecoesBiografiaPadrao();
              _carregando = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _secoesBiografia = _getSecoesBiografiaPadrao();
              _carregando = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _secoesBiografia = _getSecoesBiografiaPadrao();
            _carregando = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar biografia: $e');

      if (mounted) {
        setState(() {
          _secoesBiografia = _getSecoesBiografiaPadrao();
          _carregando = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getSecoesBiografiaPadrao() {
    return [
      {
        'titulo': '📖 INTRODUÇÃO',
        'icone': Icons.menu_book,
        'cor': const Color(0xFF800020),
        'conteudo':
        'Em 1º de setembro de 2015, na cidade de Engenheiro Navarro, MG, um grupo de visionários se uniu para fundar o UAI Capoeira.\n\nSob a liderança de seus fundadores - Taika Altair (Mestre Grilo), Paulo Afonso (Contra Mestre Zumbi), Felipe Almeida (Professor Barrãozinho) e Admilson Pereira (Professor Didi) - o grupo nasceu com o propósito de disseminar não apenas a prática da capoeira, mas também os valores de união, amizade e inteligência.',
      },
      {
        'titulo': '🌳 RAÍZES DA FUNDAÇÃO',
        'icone': Icons.forest,
        'cor': const Color(0xFF0055aa),
        'conteudo':
        'Desde o momento da fundação, o UAI Capoeira foi enraizado na paixão pela capoeira e no compromisso com a comunidade. Os fundadores buscavam não apenas ensinar uma arte marcial, mas também compartilhar a riqueza cultural e histórica que a capoeira representa, sempre com foco na união e na força coletiva.',
      },
      {
        'titulo': '📈 EXPANSÃO E CONSOLIDAÇÃO',
        'icone': Icons.trending_up,
        'cor': const Color(0xFFcc6600),
        'conteudo':
        'O sucesso do UAI Capoeira em Engenheiro Navarro rapidamente se espalhou para além de suas fronteiras. Em junho de 2017, uma nova unidade foi estabelecida em Bocaiuva, MG, liderada por João Lucas (Professor Tico-Tico), Joaquim Filho (Professor Jacu), Warley (Professor Scorpion) e João Paulo (Monitor Bode). Essa expansão não apenas fortaleceu o grupo, mas também demonstrou o poder da união e da cooperação.',
      },
      {
        'titulo': '🎯 MISSÃO E VALORES',
        'icone': Icons.flag,
        'cor': const Color(0xFF228844),
        'conteudo':
        'Para o UAI Capoeira, a capoeira é mais do que apenas uma forma de arte marcial - é uma ferramenta para o desenvolvimento pessoal e comunitário. Os valores de união, amizade e inteligência são cultivados em cada aula e evento, preparando os membros não apenas para os desafios dentro do jogo da capoeira, mas também para os desafios da vida cotidiana.',
      },
      {
        'titulo': '⭐ LEGADO E ATUALIDADE',
        'icone': Icons.history,
        'cor': const Color(0xFFaa0066),
        'conteudo':
        'Atualmente, o UAI Capoeira continua a prosperar em Engenheiro Navarro e Bocaiuva, mantendo viva a tradição da capoeira e os valores que a acompanham. Com uma comunidade unida e dedicada, o grupo continua a inspirar aqueles ao seu redor, deixando um legado de união, amizade e inteligência para as gerações futuras.',
      },
      {
        'titulo': '✨ CONCLUSÃO',
        'icone': Icons.done_all,
        'cor': const Color(0xFF999900),
        'conteudo':
        'A história do UAI Capoeira é uma prova viva da força da união, da importância da amizade e do poder da inteligência coletiva. Enquanto o grupo continua sua jornada, seu compromisso com esses valores fundamentais permanece inabalável, inspirando todos os que têm a sorte de cruzar seu caminho.',
      },
    ];
  }

  IconData _getIconFromName(dynamic iconName) {
    switch (iconName?.toString()) {
      case 'menu_book':
        return Icons.menu_book_rounded;
      case 'forest':
        return Icons.forest_rounded;
      case 'expand':
      case 'trending_up':
        return Icons.trending_up_rounded;
      case 'flag':
        return Icons.flag_rounded;
      case 'history':
        return Icons.history_rounded;
      case 'done_all':
        return Icons.done_all_rounded;
      case 'groups':
        return Icons.groups_rounded;
      case 'public':
        return Icons.public_rounded;
      default:
        return Icons.auto_stories_rounded;
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
        case 'pink':
        case 'rosa':
          return Colors.pink;
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
        .split(RegExp(r'\n\s*\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  int get _anoFundacao => 2015;

  int get _anosHistoria {
    final atual = DateTime.now().year;
    return atual - _anoFundacao;
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
            'Biografia',
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
          onRefresh: _carregarBiografia,
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
              'Carregando biografia...',
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
    if (_secoesBiografia.isEmpty) {
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
                const SizedBox(height: 18),
                _buildTimelineHeader(isMobile),
                const SizedBox(height: 12),
                _buildTimelineBiografia(isMobile),
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
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              color: Colors.white,
              size: 40,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Nossa História',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: narrow ? 27 : 34,
                  fontWeight: FontWeight.w900,
                  height: 1.02,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A trajetória do UAI Capoeira, seus fundadores, expansão, missão e valores.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: narrow ? 13.5 : 15.5,
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
                    icon: Icons.calendar_month_rounded,
                    label: 'Desde $_anoFundacao',
                  ),
                  _buildWhiteChip(
                    icon: Icons.article_rounded,
                    label:
                    '${_secoesBiografia.length} ${_secoesBiografia.length == 1 ? 'capítulo' : 'capítulos'}',
                  ),
                  _buildWhiteChip(
                    icon: Icons.favorite_rounded,
                    label: 'União • Amizade • Inteligência',
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
    final totalParagrafos = _secoesBiografia.fold<int>(
      0,
          (total, secao) =>
      total + _paragrafos(secao['conteudo']?.toString() ?? '').length,
    );

    final cards = [
      _ResumoBiografia(
        icon: Icons.history_edu_rounded,
        label: 'História',
        value: '${_anosHistoria}+',
        color: Colors.blue,
      ),
      _ResumoBiografia(
        icon: Icons.menu_book_rounded,
        label: 'Capítulos',
        value: _secoesBiografia.length.toString(),
        color: Colors.green,
      ),
      _ResumoBiografia(
        icon: Icons.format_quote_rounded,
        label: 'Textos',
        value: totalParagrafos.toString(),
        color: Colors.orange,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 3;
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

  Widget _buildResumoCard(_ResumoBiografia card, {required bool compact}) {
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

  Widget _buildTimelineHeader(bool isMobile) {
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
            Icons.timeline_rounded,
            color: Colors.red.shade900,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Linha do tempo da biografia',
                style: TextStyle(
                  color: Colors.grey.shade900,
                  fontSize: isMobile ? 17 : 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Conheça cada etapa da história do grupo.',
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

  Widget _buildTimelineBiografia(bool isMobile) {
    return Column(
      children: List.generate(_secoesBiografia.length, (index) {
        final secao = _secoesBiografia[index];

        return _buildTimelineItem(
          secao: secao,
          index: index,
          isLast: index == _secoesBiografia.length - 1,
          isMobile: isMobile,
        );
      }),
    );
  }

  Widget _buildTimelineItem({
    required Map<String, dynamic> secao,
    required int index,
    required bool isLast,
    required bool isMobile,
  }) {
    final tituloOriginal = secao['titulo']?.toString() ?? 'Capítulo';
    final titulo = _limparTitulo(tituloOriginal);
    final icone = secao['icone'] is IconData
        ? secao['icone'] as IconData
        : _getIconFromName(secao['icone']);
    final cor = _resolveColor(
      secao['cor'],
      fallback: _fallbackColor(index),
    );
    final conteudo = secao['conteudo']?.toString() ?? '';
    final paragrafos = _paragrafos(conteudo);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: isMobile ? 42 : 58,
            child: Column(
              children: [
                Container(
                  width: 3,
                  height: 18,
                  color: index == 0 ? Colors.transparent : Colors.red.shade100,
                ),
                Container(
                  width: isMobile ? 34 : 40,
                  height: isMobile ? 34 : 40,
                  decoration: BoxDecoration(
                    color: cor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: cor.withOpacity(0.24),
                        blurRadius: 7,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    icone,
                    color: Colors.white,
                    size: isMobile ? 17 : 20,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 3,
                    color: isLast ? Colors.transparent : Colors.red.shade100,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: isMobile ? 6 : 10,
                bottom: isLast ? 0 : 14,
              ),
              child: Container(
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
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: cor.withOpacity(0.11),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: cor.withOpacity(0.12)),
                              ),
                              child: Icon(icone, color: cor, size: 24),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                titulo,
                                style: TextStyle(
                                  color: Colors.grey.shade900,
                                  fontSize: isMobile ? 16 : 18,
                                  height: 1.08,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.76),
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
                        child: paragrafos.isEmpty
                            ? Text(
                          'Conteúdo não informado.',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                            : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: List.generate(paragrafos.length, (i) {
                            return _buildParagraph(
                              text: paragrafos[i],
                              cor: cor,
                              isFirst: i == 0,
                              isMobile: isMobile,
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParagraph({
    required String text,
    required Color cor,
    required bool isFirst,
    required bool isMobile,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: isFirst ? 10 : 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isFirst ? cor.withOpacity(0.06) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isFirst ? cor.withOpacity(0.12) : Colors.grey.shade200,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey.shade800,
          fontSize: isMobile ? 13.1 : 13.8,
          height: 1.43,
          fontWeight: isFirst ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  Color _fallbackColor(int index) {
    final colors = [
      const Color(0xFF800020),
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.purple,
      Colors.teal,
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
                Icons.auto_stories_outlined,
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
                'Cadastre o conteúdo da biografia no painel administrativo.',
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

class _ResumoBiografia {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ResumoBiografia({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}
