import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/site/services/logo_service.dart';

class BiografiaScreen extends StatefulWidget {
  const BiografiaScreen({super.key});

  @override
  State<BiografiaScreen> createState() => _BiografiaScreenState();
}

class _BiografiaScreenState extends State<BiografiaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LogoService _logoService = LogoService();

  List<Map<String, dynamic>> _secoes = [];
  final Set<String> _secoesExpandidas = <String>{};

  bool _carregando = true;
  bool _salvando = false;

  final List<Map<String, dynamic>> _iconesDisponiveis = [
    {
      'nome': 'Introdução',
      'icon': Icons.menu_book_rounded,
      'iconName': 'menu_book',
      'cor': const Color(0xFF800020),
    },
    {
      'nome': 'Raízes',
      'icon': Icons.forest_rounded,
      'iconName': 'forest',
      'cor': const Color(0xFF0055AA),
    },
    {
      'nome': 'Expansão',
      'icon': Icons.expand_rounded,
      'iconName': 'expand',
      'cor': const Color(0xFFCC6600),
    },
    {
      'nome': 'Missão',
      'icon': Icons.flag_rounded,
      'iconName': 'flag',
      'cor': const Color(0xFF228844),
    },
    {
      'nome': 'Legado',
      'icon': Icons.history_rounded,
      'iconName': 'history',
      'cor': const Color(0xFFAA0066),
    },
    {
      'nome': 'Conclusão',
      'icon': Icons.done_all_rounded,
      'iconName': 'done_all',
      'cor': const Color(0xFF8A8A00),
    },
    {
      'nome': 'História',
      'icon': Icons.auto_stories_rounded,
      'iconName': 'auto_stories',
      'cor': Colors.purple,
    },
    {
      'nome': 'Fotos',
      'icon': Icons.photo_library_rounded,
      'iconName': 'photo_library',
      'cor': Colors.teal,
    },
    {
      'nome': 'Fundadores',
      'icon': Icons.group_rounded,
      'iconName': 'group',
      'cor': Colors.orange,
    },
    {
      'nome': 'Eventos',
      'icon': Icons.event_rounded,
      'iconName': 'event',
      'cor': Colors.red,
    },
  ];

  @override
  void initState() {
    super.initState();
    _carregarBiografia();
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

  Color _onPrimary() => _readableOn(context.uai.primary);

  IconData _getIconFromName(dynamic iconName) {
    switch (iconName?.toString()) {
      case 'menu_book':
        return Icons.menu_book_rounded;
      case 'forest':
        return Icons.forest_rounded;
      case 'expand':
        return Icons.expand_rounded;
      case 'flag':
        return Icons.flag_rounded;
      case 'history':
        return Icons.history_rounded;
      case 'done_all':
        return Icons.done_all_rounded;
      case 'auto_stories':
        return Icons.auto_stories_rounded;
      case 'photo_library':
        return Icons.photo_library_rounded;
      case 'group':
        return Icons.group_rounded;
      case 'event':
        return Icons.event_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  Color _safeColor(dynamic value, {Color? fallback}) {
    if (value is Color) return value;
    if (value is int) return Color(value);
    return fallback ?? context.uai.primary;
  }

  String _secaoKey(Map<String, dynamic> secao, int index) {
    final id = secao['id']?.toString().trim() ?? '';
    return id.isNotEmpty ? id : 'secao_index_$index';
  }

  bool _secaoExpandida(Map<String, dynamic> secao, int index) {
    return _secoesExpandidas.contains(_secaoKey(secao, index));
  }

  void _alternarSecao(Map<String, dynamic> secao, int index) {
    final key = _secaoKey(secao, index);
    setState(() {
      if (_secoesExpandidas.contains(key)) {
        _secoesExpandidas.remove(key);
      } else {
        _secoesExpandidas.add(key);
      }
    });
  }

  void _moverSecao(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;

      final item = _secoes.removeAt(oldIndex);
      _secoes.insert(newIndex, item);
    });
  }

  Future<void> _carregarBiografia() async {
    try {
      final doc = await _firestore.collection('site_conteudo').doc('biografia').get();

      if (doc.exists) {
        final data = doc.data()!;
        if (data.containsKey('secoes') && data['secoes'] is List) {
          _secoes = (data['secoes'] as List)
              .map((item) {
            if (item is Map<String, dynamic>) return item;
            if (item is Map) return Map<String, dynamic>.from(item);
            return <String, dynamic>{};
          })
              .where((item) => item.isNotEmpty)
              .toList();
        } else {
          _secoes = _getSecoesPadrao();
        }
      } else {
        _secoes = _getSecoesPadrao();
      }
    } catch (e) {
      _mostrarErro('Erro ao carregar: $e');
      _secoes = _getSecoesPadrao();
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<Map<String, dynamic>> _getSecoesPadrao() {
    return [
      {
        'id': 'introducao',
        'titulo': '📖 INTRODUÇÃO',
        'icone': 'menu_book',
        'cor': const Color(0xFF800020).value,
        'conteudo': _getIntroducaoPadrao(),
      },
      {
        'id': 'raizes',
        'titulo': '🌳 RAÍZES DA FUNDAÇÃO',
        'icone': 'forest',
        'cor': const Color(0xFF0055AA).value,
        'conteudo': _getRaizesPadrao(),
      },
      {
        'id': 'expansao',
        'titulo': '📈 EXPANSÃO E CONSOLIDAÇÃO',
        'icone': 'expand',
        'cor': const Color(0xFFCC6600).value,
        'conteudo': _getExpansaoPadrao(),
      },
      {
        'id': 'missao',
        'titulo': '🎯 MISSÃO E VALORES',
        'icone': 'flag',
        'cor': const Color(0xFF228844).value,
        'conteudo': _getMissaoPadrao(),
      },
      {
        'id': 'legado',
        'titulo': '⭐ LEGADO E ATUALIDADE',
        'icone': 'history',
        'cor': const Color(0xFFAA0066).value,
        'conteudo': _getLegadoPadrao(),
      },
      {
        'id': 'conclusao',
        'titulo': '✨ CONCLUSÃO',
        'icone': 'done_all',
        'cor': const Color(0xFF8A8A00).value,
        'conteudo': _getConclusaoPadrao(),
      },
    ];
  }

  String _getIntroducaoPadrao() {
    return '''Em 1º de setembro de 2015, na cidade de Engenheiro Navarro, MG, um grupo de visionários se uniu para fundar o UAI Capoeira. 

Sob a liderança de seus fundadores - Taika Altair (Mestre Grilo), Paulo Afonso (Contra Mestre Zumbi), Felipe Almeida (Professor Barrãozinho) e Admilson Pereira (Professor Didi) - o grupo nasceu com o propósito de disseminar não apenas a prática da capoeira, mas também os valores de união, amizade e inteligência.''';
  }

  String _getRaizesPadrao() {
    return '''Desde o momento da fundação, o UAI Capoeira foi enraizado na paixão pela capoeira e no compromisso com a comunidade. Os fundadores buscavam não apenas ensinar uma arte marcial, mas também compartilhar a riqueza cultural e histórica que a capoeira representa, sempre com foco na união e na força coletiva.''';
  }

  String _getExpansaoPadrao() {
    return '''O sucesso do UAI Capoeira em Engenheiro Navarro rapidamente se espalhou para além de suas fronteiras. Em junho de 2017, uma nova unidade foi estabelecida em Bocaiuva, MG, liderada por João Lucas (Professor Tico-Tico), Joaquim Filho (Professor Jacu), Warley (Professor Scorpion) e João Paulo (Monitor Bode). Essa expansão não apenas fortaleceu o grupo, mas também demonstrou o poder da união e da cooperação.''';
  }

  String _getMissaoPadrao() {
    return '''Para o UAI Capoeira, a capoeira é mais do que apenas uma forma de arte marcial - é uma ferramenta para o desenvolvimento pessoal e comunitário. Os valores de união, amizade e inteligência são cultivados em cada aula e evento, preparando os membros não apenas para os desafios dentro do jogo da capoeira, mas também para os desafios da vida cotidiana.''';
  }

  String _getLegadoPadrao() {
    return '''Atualmente, o UAI Capoeira continua a prosperar em Engenheiro Navarro e Bocaiuva, mantendo viva a tradição da capoeira e os valores que a acompanham. Com uma comunidade unida e dedicada, o grupo continua a inspirar aqueles ao seu redor, deixando um legado de união, amizade e inteligência para as gerações futuras.''';
  }

  String _getConclusaoPadrao() {
    return '''A história do UAI Capoeira é uma prova viva da força da união, da importância da amizade e do poder da inteligência coletiva. Enquanto o grupo continua sua jornada, seu compromisso com esses valores fundamentais permanece inabalável, inspirando todos os que têm a sorte de cruzar seu caminho.''';
  }

  Future<void> _salvar() async {
    if (!mounted) return;
    setState(() => _salvando = true);

    try {
      await _firestore.collection('site_conteudo').doc('biografia').set({
        'secoes': _secoes,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Biografia salva com sucesso!'),
            backgroundColor: context.uai.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _mostrarErro('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _adicionarSecao() {
    showDialog<void>(
      context: context,
      builder: (context) => _DialogSecao(
        iconesDisponiveis: _iconesDisponiveis,
        onSalvar: (titulo, iconName, cor) {
          final novoId = 'secao_${DateTime.now().millisecondsSinceEpoch}';

          setState(() {
            _secoes.add({
              'id': novoId,
              'titulo': titulo,
              'icone': iconName,
              'cor': cor.value,
              'conteudo': 'Digite o conteúdo aqui...',
            });
            _secoesExpandidas.add(novoId);
          });
        },
      ),
    );
  }

  void _editarSecao(int index) {
    final secao = _secoes[index];

    showDialog<void>(
      context: context,
      builder: (context) => _DialogSecao(
        secao: secao,
        iconesDisponiveis: _iconesDisponiveis,
        onSalvar: (titulo, iconName, cor) {
          setState(() {
            _secoes[index]['titulo'] = titulo;
            _secoes[index]['icone'] = iconName;
            _secoes[index]['cor'] = cor.value;
          });
        },
      ),
    );
  }

  void _removerSecao(int index) {
    final titulo = _secoes[index]['titulo']?.toString() ?? 'esta seção';

    showDialog<void>(
      context: context,
      builder: (context) {
        final t = context.uai;
        final danger = _ensureVisible(t.error, t.surface);

        return AlertDialog(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_rounded, color: danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Remover seção?',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Tem certeza que deseja remover "$titulo"?',
            style: TextStyle(color: t.textSecondary, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final key = _secaoKey(_secoes[index], index);
                setState(() {
                  _secoes.removeAt(index);
                  _secoesExpandidas.remove(key);
                });
                Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_rounded, size: 18),
              label: const Text('REMOVER'),
              style: ElevatedButton.styleFrom(
                backgroundColor: danger,
                foregroundColor: _readableOn(danger),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    if (_carregando) {
      return Scaffold(
        backgroundColor: t.background,
        body: Center(child: CircularProgressIndicator(color: t.primary)),
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Biografia do Grupo',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: _adicionarSecao,
            tooltip: 'Adicionar seção',
          ),
          IconButton(
            icon: _salvando
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: _onPrimary(),
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
            onPressed: _salvando ? null : _salvar,
            tooltip: 'Salvar',
          ),
        ],
      ),
      body: RefreshIndicator(
        color: t.primary,
        backgroundColor: t.surface,
        onRefresh: _carregarBiografia,
        child: ReorderableListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 112),
          onReorder: (oldIndex, newIndex) {
            if (oldIndex == 0 || newIndex == 0) return;
            _moverSecao(oldIndex - 1, newIndex - 1);
          },
          itemCount: _secoes.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                key: const ValueKey('hero_biografia'),
                padding: const EdgeInsets.only(bottom: 14),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: _buildHero(),
                  ),
                ),
              );
            }

            final itemIndex = index - 1;
            final secao = _secoes[itemIndex];

            return Padding(
              key: ValueKey(_secaoKey(secao, itemIndex)),
              padding: const EdgeInsets.only(bottom: 14),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: _buildSecao(
                    index: itemIndex,
                    reorderIndex: index,
                    secao: secao,
                  ),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adicionarSecao,
        backgroundColor: t.primary,
        foregroundColor: _readableOn(t.primary),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'SEÇÃO',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(top: BorderSide(color: t.border)),
            boxShadow: t.softShadow,
          ),
          child: ElevatedButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: _readableOn(t.primary),
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
            label: Text(_salvando ? 'SALVANDO...' : 'SALVAR BIOGRAFIA'),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _readableOn(t.primary),
              minimumSize: const Size.fromHeight(50),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final logo = Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.95),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withOpacity(0.18)),
            ),
            child: _logoService.buildLogo(height: 58),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'UAI CAPOEIRA',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 23 : 28,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'União, Amizade e Inteligência',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.92),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Edite a história do grupo, organize as seções e salve o conteúdo exibido no site.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _whiteChip(
                    icon: Icons.auto_stories_rounded,
                    label: '${_secoes.length} seções',
                  ),
                  _whiteChip(
                    icon: Icons.edit_note_rounded,
                    label: 'Toque para editar',
                  ),
                  _whiteChip(
                    icon: Icons.drag_indicator_rounded,
                    label: 'Arraste para ordenar',
                  ),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                logo,
                const SizedBox(height: 14),
                text,
              ],
            );
          }

          return Row(
            children: [
              logo,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _whiteChip({
    required IconData icon,
    required String label,
  }) {
    final onPrimary = _readableOn(context.uai.primary);

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

  Widget _buildSecao({
    required int index,
    required int reorderIndex,
    required Map<String, dynamic> secao,
  }) {
    final t = context.uai;
    final titulo = secao['titulo']?.toString() ?? 'Sem título';
    final conteudo = secao['conteudo']?.toString() ?? '';
    final icone = _getIconFromName(secao['icone']);
    final cor = _safeColor(secao['cor']);
    final accent = _ensureVisible(cor, t.card);
    final expanded = _secaoExpandida(secao, index);
    final controller = TextEditingController(text: conteudo);

    final preview = conteudo
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: _cardDecoration(borderColor: accent.withOpacity(expanded ? 0.28 : 0.16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.cardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _alternarSecao(secao, index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.alphaBlend(accent.withOpacity(expanded ? 0.14 : 0.09), t.card),
                        t.card,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: expanded
                        ? Border(bottom: BorderSide(color: accent.withOpacity(0.14)))
                        : null,
                  ),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: reorderIndex,
                        child: Container(
                          width: 36,
                          height: 44,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: t.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(t.buttonRadius),
                          border: Border.all(color: accent.withOpacity(0.16)),
                        ),
                        child: Icon(icone, color: accent, size: 24),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titulo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 15.5,
                                height: 1.08,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              expanded
                                  ? 'Editando conteúdo da seção'
                                  : (preview.isEmpty ? 'Toque para abrir e editar' : preview),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 11.5,
                                height: 1.18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: accent.withOpacity(0.14)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                              color: accent,
                              size: 16,
                            ),
                            Text(
                              expanded ? 'ABERTA' : 'FECHADA',
                              style: TextStyle(
                                color: accent,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
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
            if (expanded) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _sectionActionButton(
                      icon: Icons.edit_rounded,
                      label: 'Editar seção',
                      color: t.info,
                      onTap: () => _editarSecao(index),
                    ),
                    _sectionActionButton(
                      icon: Icons.delete_rounded,
                      label: 'Remover',
                      color: t.error,
                      onTap: () => _removerSecao(index),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  minLines: 4,
                  keyboardType: TextInputType.multiline,
                  onChanged: (value) {
                    _secoes[index]['conteudo'] = value;
                  },
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: t.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Digite o conteúdo aqui...',
                    hintStyle: TextStyle(color: t.textMuted),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(bottom: 76),
                      child: Icon(Icons.notes_rounded, color: accent),
                    ),
                    filled: true,
                    fillColor: t.cardAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(t.inputRadius),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(t.inputRadius),
                      borderSide: BorderSide(color: t.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(t.inputRadius),
                      borderSide: BorderSide(color: accent, width: 1.4),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final visible = _ensureVisible(color, t.card);

    return Material(
      color: Color.alphaBlend(visible.withOpacity(0.10), t.cardAlt),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: visible.withOpacity(0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: visible, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: visible,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
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

class _DialogSecao extends StatefulWidget {
  final Map<String, dynamic>? secao;
  final List<Map<String, dynamic>> iconesDisponiveis;
  final Function(String titulo, String iconName, Color cor) onSalvar;

  const _DialogSecao({
    this.secao,
    required this.iconesDisponiveis,
    required this.onSalvar,
  });

  @override
  State<_DialogSecao> createState() => _DialogSecaoState();
}

class _DialogSecaoState extends State<_DialogSecao> {
  late final TextEditingController _tituloController;
  late int _iconeSelecionado;
  late Color _corSelecionada;

  bool get _editando => widget.secao != null;

  @override
  void initState() {
    super.initState();

    _tituloController = TextEditingController(
      text: widget.secao?['titulo']?.toString() ?? '',
    );

    final iconName = widget.secao?['icone']?.toString();

    _iconeSelecionado = widget.iconesDisponiveis.indexWhere(
          (icone) => icone['iconName'] == iconName,
    );

    if (_iconeSelecionado == -1) _iconeSelecionado = 0;

    final corRaw = widget.secao?['cor'];

    if (corRaw is int) {
      _corSelecionada = Color(corRaw);
    } else if (corRaw is Color) {
      _corSelecionada = corRaw;
    } else {
      _corSelecionada = widget.iconesDisponiveis[_iconeSelecionado]['cor'] as Color;
    }
  }

  @override
  void dispose() {
    _tituloController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.surface);

    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.cardRadius + 2),
          border: Border.all(color: t.border),
          boxShadow: t.cardShadow,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                      border: Border.all(color: accent.withOpacity(0.16)),
                    ),
                    child: Icon(
                      _editando ? Icons.edit_rounded : Icons.add_rounded,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      _editando ? 'Editar seção' : 'Nova seção',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _tituloController,
                style: TextStyle(color: t.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Título da seção',
                  hintText: 'Ex: 📖 INTRODUÇÃO',
                  labelStyle: TextStyle(color: t.textSecondary),
                  hintStyle: TextStyle(color: t.textMuted),
                  prefixIcon: Icon(Icons.title_rounded, color: accent),
                  filled: true,
                  fillColor: t.cardAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(t.inputRadius),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(t.inputRadius),
                    borderSide: BorderSide(color: t.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(t.inputRadius),
                    borderSide: BorderSide(color: accent, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Escolha o ícone',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.iconesDisponiveis.asMap().entries.map((entry) {
                  final index = entry.key;
                  final icone = entry.value;
                  final selected = _iconeSelecionado == index;
                  final cor = icone['cor'] as Color;
                  final visible = _ensureVisible(cor, t.surface);

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _iconeSelecionado = index;
                        _corSelecionada = cor;
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: selected
                            ? visible.withOpacity(0.14)
                            : t.cardAlt,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? visible : t.border,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        icone['icon'] as IconData,
                        color: visible,
                        size: 28,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCELAR'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final titulo = _tituloController.text.trim();

                        if (titulo.isEmpty) return;

                        final icone = widget.iconesDisponiveis[_iconeSelecionado];

                        widget.onSalvar(
                          titulo,
                          icone['iconName'] as String,
                          _corSelecionada,
                        );

                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: _readableOn(accent),
                      ),
                      child: Text(_editando ? 'SALVAR' : 'ADICIONAR'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
