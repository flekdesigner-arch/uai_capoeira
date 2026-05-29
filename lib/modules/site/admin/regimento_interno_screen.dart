import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/site/services/logo_service.dart';

class RegimentoInternoScreen extends StatefulWidget {
  const RegimentoInternoScreen({super.key});

  @override
  State<RegimentoInternoScreen> createState() => _RegimentoInternoScreenState();
}

class _RegimentoInternoScreenState extends State<RegimentoInternoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LogoService _logoService = LogoService();

  List<Map<String, dynamic>> _secoes = [];

  bool _carregando = true;
  bool _salvando = false;

  final Set<String> _secoesExpandidas = <String>{};

  final List<Map<String, dynamic>> _iconesDisponiveis = [
    {'nome': 'Gavel', 'icon': Icons.gavel_rounded, 'iconName': 'gavel', 'cor': Colors.blue},
    {'nome': 'Person Add', 'icon': Icons.person_add_rounded, 'iconName': 'person_add', 'cor': Colors.green},
    {'nome': 'School', 'icon': Icons.school_rounded, 'iconName': 'school', 'cor': Colors.orange},
    {'nome': 'Premium', 'icon': Icons.workspace_premium_rounded, 'iconName': 'workspace_premium', 'cor': Colors.purple},
    {'nome': 'Security', 'icon': Icons.security_rounded, 'iconName': 'security', 'cor': Colors.red},
    {'nome': 'Group', 'icon': Icons.group_rounded, 'iconName': 'group', 'cor': Colors.teal},
    {'nome': 'Star', 'icon': Icons.star_rounded, 'iconName': 'star', 'cor': Colors.amber},
    {'nome': 'Events', 'icon': Icons.emoji_events_rounded, 'iconName': 'emoji_events', 'cor': Colors.deepOrange},
    {'nome': 'Book', 'icon': Icons.menu_book_rounded, 'iconName': 'menu_book', 'cor': Colors.brown},
    {'nome': 'Rule', 'icon': Icons.rule_rounded, 'iconName': 'rule', 'cor': Colors.indigo},
  ];

  @override
  void initState() {
    super.initState();
    _carregarRegimento();
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

  Future<void> _carregarRegimento() async {
    try {
      final doc = await _firestore.collection('site_conteudo').doc('regimento').get();

      if (doc.exists) {
        final data = doc.data()!;

        if (data.containsKey('secoes') && data['secoes'] is List) {
          _secoes = (data['secoes'] as List).map((item) {
            if (item is Map<String, dynamic>) return item;
            if (item is Map) return Map<String, dynamic>.from(item);
            return <String, dynamic>{};
          }).where((item) => item.isNotEmpty).toList();
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
        'id': 'regras_gerais',
        'titulo': '⚖️ REGRAS GERAIS',
        'icone': 'gavel',
        'cor': Colors.blue.value,
        'conteudo': _getRegrasGeraisPadrao(),
      },
      {
        'id': 'novos_alunos',
        'titulo': '🆕 NOVOS ALUNOS',
        'icone': 'person_add',
        'cor': Colors.green.value,
        'conteudo': _getNovosAlunosPadrao(),
      },
      {
        'id': 'alunos_graduados',
        'titulo': '🎓 ALUNOS GRADUADOS',
        'icone': 'school',
        'cor': Colors.orange.value,
        'conteudo': _getAlunosGraduadosPadrao(),
      },
      {
        'id': 'formados',
        'titulo': '⭐ FORMADOS',
        'icone': 'workspace_premium',
        'cor': Colors.purple.value,
        'conteudo': _getFormadosPadrao(),
      },
    ];
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);

    try {
      await _firestore.collection('site_conteudo').doc('regimento').set({
        'secoes': _secoes,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Regimento salvo com sucesso!'),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _getRegrasGeraisPadrao() {
    return '''🚫 Proibido uso do uniforme em locais inadequados (bares, festas, baladas).
❌ Não é permitido utilizar uniformes de outros grupos.
📢 Participação em eventos externos deve ser comunicada antecipadamente.
⏰ Cumprimento rigoroso dos horários de treinos, rodas e apresentações.
👕 Em dias de roda ou apresentações é obrigatório o uniforme completo (calça branca, camisa e graduação).
🧼 Manter a higiene pessoal: unhas cortadas, roupas limpas e bom cuidado com o uniforme.
🙏 Respeitar mestres, professores, colegas e visitantes, independente de idade ou graduação.
🤝 Ao visitar outras academias ou grupos de capoeira, o aluno deve:
   • Avisar com antecedência os responsáveis do grupo
   • Utilizar sempre a camisa oficial do grupo UAI Capoeira
   • Não participar sem identificação do grupo''';
  }

  String _getNovosAlunosPadrao() {
    return '''⏳ Prazo de 2 meses para adquirir o uniforme completo.
👀 Durante esse período, o aluno será avaliado pelos professores.
🎖️ Primeira graduação possível após 6 meses de treino regular.
📅 Indicação para início das atividades: preferencialmente em uma segunda-feira.
📲 Cadastro no sistema + ingresso em grupo de WhatsApp para comunicações.
⚠️ Caso falte por mais de 3 semanas sem justificativa, será considerado desligado.
🙌 Todo aluno deve manter postura respeitosa e colaborativa dentro e fora da academia.''';
  }

  String _getAlunosGraduadosPadrao() {
    return '''🙏 Respeito, disciplina e comprometimento são indispensáveis.
👕 Uso do uniforme correto nos treinos e apresentações é obrigatório.
⏳ Graduação só pode ser trocada após no mínimo 1 ano, conforme desempenho.
🎭 Em eventos, utilizar somente o uniforme oficial (não camisas promocionais).
⚠️ Faltas por mais de 1 mês sem aviso resultam em desligamento automático.
💪 O graduado deve dar exemplo de postura, ajudando os iniciantes e fortalecendo a roda.''';
  }

  String _getFormadosPadrao() {
    return '''São considerados formados os monitores, instrutores, professores, contra-mestres e mestres.

📚 Devem estar sempre ativos nos treinos e rodas, transmitindo conhecimento.
🪘 Devem incentivar a prática dos instrumentos, cantos e fundamentos da capoeira.
🌍 Representam o grupo dentro e fora da cidade, mantendo o nome da Associação com honra e responsabilidade.

📖 ESTÁGIOS DE FORMAÇÃO:

👨‍🎓 MONITOR:
• 🔞 Ter no mínimo 18 anos
• 🎓 Ensino médio completo
• 🔵 Pelo menos 1 ano de graduação na 6ª corda (azul)
• 📖 Capacidade para ministrar aulas, com ou sem auxílio
• 🥁 Conhecimento básico dos instrumentos e toques da capoeira
• ⚔️ Conhecimento dos fundamentos e da história do grupo
• 🪪 Ser associado ativo

👨‍🏫 INSTRUTOR:
• ✅ Requisitos de monitor atendidos
• ⏳ No mínimo 4 anos como monitor
• 📖 Capacidade de ministrar e planejar aulas de forma independente
• 🔍 Habilidade de identificar e corrigir dificuldades dos alunos
• 🚀 Busca contínua por conhecimento e aprimoramento

👨‍🎓 PROFESSOR:
• ✅ Todos os requisitos anteriores
• 📜 Diploma emitido pelo grupo, com reconhecimento dos mestres e formados
• 🌍 Responsabilidade em representar o grupo oficialmente em eventos nacionais e internacionais
• 🎓 Reconhecimento como profissional da área da Capoeira, apto a ministrar aulas em academias, escolas, projetos sociais e demais espaços culturais''';
  }

  void _adicionarSecao() {
    showDialog<void>(
      context: context,
      builder: (context) => _DialogSecao(
        iconesDisponiveis: _iconesDisponiveis,
        onSalvar: (titulo, iconName, cor) {
          setState(() {
            final id = 'secao_${DateTime.now().millisecondsSinceEpoch}';
            _secoes.add({
              'id': id,
              'titulo': titulo,
              'icone': iconName,
              'cor': cor.value,
              'conteudo': 'Digite o conteúdo aqui...',
            });
            _secoesExpandidas.add(id);
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
    final t = context.uai;
    final error = _ensureVisible(t.error, t.surface);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.surface,
        insetPadding: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.cardRadius)),
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Remover seção?',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: t.textPrimary,
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
              setState(() {
                _secoesExpandidas.remove(_secaoKey(_secoes[index], index));
                _secoes.removeAt(index);
              });
              Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_rounded, size: 18),
            label: const Text('REMOVER'),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.error,
              foregroundColor: _readableOn(t.error),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconFromName(dynamic iconName) {
    switch (iconName?.toString()) {
      case 'gavel':
        return Icons.gavel_rounded;
      case 'person_add':
        return Icons.person_add_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'workspace_premium':
        return Icons.workspace_premium_rounded;
      case 'security':
        return Icons.security_rounded;
      case 'group':
        return Icons.group_rounded;
      case 'star':
        return Icons.star_rounded;
      case 'emoji_events':
        return Icons.emoji_events_rounded;
      case 'menu_book':
        return Icons.menu_book_rounded;
      case 'rule':
        return Icons.rule_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  Color _safeColor(dynamic value, {Color fallback = Colors.blue}) {
    if (value is Color) return value;
    if (value is int) return Color(value);
    return fallback;
  }

  String _secaoKey(Map<String, dynamic> secao, int index) {
    final id = secao['id']?.toString();
    if (id != null && id.trim().isNotEmpty) return id;
    return 'secao_$index';
  }

  bool _secaoEstaExpandida(Map<String, dynamic> secao, int index) {
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
    // O item 0 é o hero/header. As seções reais começam no índice 1
    // dentro do ReorderableListView, então convertemos para índice da lista _secoes.
    if (oldIndex == 0) return;

    setState(() {
      final oldSecaoIndex = oldIndex - 1;

      var targetGlobalIndex = newIndex;
      if (targetGlobalIndex > oldIndex) {
        targetGlobalIndex -= 1;
      }

      var newSecaoIndex = targetGlobalIndex - 1;
      if (newSecaoIndex < 0) newSecaoIndex = 0;
      if (newSecaoIndex > _secoes.length - 1) {
        newSecaoIndex = _secoes.length - 1;
      }

      final item = _secoes.removeAt(oldSecaoIndex);
      _secoes.insert(newSecaoIndex, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    if (_carregando) {
      return Scaffold(
        backgroundColor: t.background,
        body: Center(
          child: CircularProgressIndicator(color: t.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Regimento Interno'),
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
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adicionarSecao,
        backgroundColor: t.primary,
        foregroundColor: _onPrimary(),
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
                color: _onPrimary(),
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
            label: Text(_salvando ? 'SALVANDO...' : 'SALVAR REGIMENTO'),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _onPrimary(),
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

  Widget _buildBody() {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      onReorder: _moverSecao,
      itemCount: _secoes.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            key: const ValueKey('hero'),
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
          key: ValueKey(secao['id'] ?? itemIndex),
          padding: const EdgeInsets.only(bottom: 14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: _buildSecao(index: itemIndex, secao: secao),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHero() {
    final t = context.uai;
    final onPrimary = _onPrimary();

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
              color: Color.alphaBlend(onPrimary.withOpacity(0.92), t.primary),
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
                'Editar Regimento',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 22 : 27,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Arraste os cards fechados para ordenar. Toque em uma seção para editar o conteúdo.',
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
                    icon: Icons.article_rounded,
                    label: '${_secoes.length} seções',
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
    final onPrimary = _onPrimary();

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
    required Map<String, dynamic> secao,
  }) {
    final t = context.uai;
    final titulo = secao['titulo']?.toString() ?? 'Sem título';
    final iconName = secao['icone']?.toString() ?? 'description';
    final icone = _getIconFromName(iconName);
    final corOriginal = _safeColor(secao['cor'], fallback: t.info);
    final cor = _ensureVisible(corOriginal, t.card);
    final expanded = _secaoEstaExpandida(secao, index);
    return Container(
      decoration: _cardDecoration(borderColor: cor.withOpacity(expanded ? 0.28 : 0.18)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.cardRadius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _alternarSecao(secao, index),
                splashColor: cor.withOpacity(0.10),
                highlightColor: cor.withOpacity(0.05),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.alphaBlend(cor.withOpacity(expanded ? 0.14 : 0.08), t.card),
                        Color.alphaBlend(cor.withOpacity(0.035), t.card),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: expanded
                        ? Border(bottom: BorderSide(color: cor.withOpacity(0.12)))
                        : null,
                  ),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index + 1,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: t.cardAlt,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: t.border),
                          ),
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: t.textMuted,
                            size: 21,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: cor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(t.buttonRadius),
                          border: Border.all(color: cor.withOpacity(0.16)),
                        ),
                        child: Icon(icone, color: cor, size: 23),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 15.2,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: cor,
                          size: 25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _editarSecao(index),
                            icon: const Icon(Icons.edit_rounded, size: 18),
                            label: const Text('EDITAR SEÇÃO'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _ensureVisible(t.info, t.card),
                              side: BorderSide(color: _ensureVisible(t.info, t.card).withOpacity(0.28)),
                              textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _removerSecao(index),
                            icon: const Icon(Icons.delete_rounded, size: 18),
                            label: const Text('REMOVER'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _ensureVisible(t.error, t.card),
                              side: BorderSide(color: _ensureVisible(t.error, t.card).withOpacity(0.30)),
                              textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: secao['conteudo']?.toString() ?? '',
                      maxLines: null,
                      minLines: 5,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(color: t.textPrimary, height: 1.35),
                      onChanged: (value) {
                        _secoes[index]['conteudo'] = value;
                      },
                      decoration: InputDecoration(
                        hintText: 'Digite o conteúdo aqui...',
                        hintStyle: TextStyle(color: t.textMuted),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(bottom: 100),
                          child: Icon(Icons.notes_rounded, color: t.primary),
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
                          borderSide: BorderSide(color: t.primary, width: 1.4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 190),
              firstCurve: Curves.easeOut,
              secondCurve: Curves.easeOut,
              sizeCurve: Curves.easeOut,
            ),
          ],
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
    final primary = _ensureVisible(t.primary, t.surface);

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
                      color: primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                      border: Border.all(color: primary.withOpacity(0.16)),
                    ),
                    child: Icon(
                      _editando ? Icons.edit_rounded : Icons.add_rounded,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      _editando ? 'Editar seção' : 'Nova seção',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: t.textPrimary,
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
                  hintText: 'Ex: ⚖️ REGRAS GERAIS',
                  prefixIcon: Icon(Icons.title_rounded, color: primary),
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
                    borderSide: BorderSide(color: t.primary, width: 1.4),
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
                  final corOriginal = icone['cor'] as Color;
                  final cor = _ensureVisible(corOriginal, t.surface);

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _iconeSelecionado = index;
                        _corSelecionada = corOriginal;
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: selected
                            ? Color.alphaBlend(cor.withOpacity(0.16), t.cardAlt)
                            : t.cardAlt,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? cor : t.border,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        icone['icon'] as IconData,
                        color: cor,
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
                        backgroundColor: t.primary,
                        foregroundColor: _readableOn(t.primary),
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
