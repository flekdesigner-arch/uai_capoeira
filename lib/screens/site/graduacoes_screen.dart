import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import 'package:uai_capoeira/core/utils/responsive_utils.dart';

class GraduacoesScreen extends StatefulWidget {
  const GraduacoesScreen({super.key});

  @override
  State<GraduacoesScreen> createState() => _GraduacoesScreenState();
}

class _GraduacoesScreenState extends State<GraduacoesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache de 3 dias
  static const int CACHE_DURATION_DAYS = 3;

  List<Map<String, dynamic>> _graduacoes = [];
  Map<String, int> _contagemAlunosPorGraduacao = {};
  int _totalAlunosGraduados = 0;
  int _alunosAtivos = 0;
  int _alunosInativos = 0;
  int _totalAlunos = 0;
  bool _carregando = true;
  String? _svgContent;
  bool _usandoCache = false;
  String? _erroMensagem;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    try {
      await _loadSvgFromAssets();
      await _carregarListaGraduacoes();
      await _carregarEstatisticas();

      if (mounted) {
        setState(() {
          _carregando = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar dados: $e');
      if (mounted) {
        setState(() {
          _erroMensagem = e.toString();
          _carregando = false;
        });
      }
    }
  }

  Future<void> _carregarListaGraduacoes() async {
    try {
      final snapshot = await _firestore
          .collection('graduacoes')
          .orderBy('nivel_graduacao')
          .get();

      List<Map<String, dynamic>> graduacoesConvertidas = [];
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        graduacoesConvertidas.add(data);
      }

      if (mounted) {
        setState(() {
          _graduacoes = graduacoesConvertidas;
        });
      }

      debugPrint('✅ Carregadas ${graduacoesConvertidas.length} graduações');
    } catch (e) {
      debugPrint('❌ Erro ao carregar graduações: $e');
      rethrow;
    }
  }

  Future<void> _carregarEstatisticas() async {
    try {
      final statsDoc = await _firestore
          .collection('estatisticas')
          .doc('graduacoes')
          .get();

      if (statsDoc.exists) {
        final data = statsDoc.data()!;
        final lastUpdate = data['last_update'] as Timestamp?;

        if (lastUpdate != null) {
          final diasDesdeAtualizacao = DateTime.now().difference(lastUpdate.toDate()).inDays;

          if (diasDesdeAtualizacao < CACHE_DURATION_DAYS) {
            debugPrint('✅ Usando cache de estatísticas (${diasDesdeAtualizacao} dias atrás)');

            setState(() {
              _totalAlunos = data['total_alunos'] ?? 0;
              _alunosAtivos = data['alunos_ativos'] ?? 0;
              _alunosInativos = data['alunos_inativos'] ?? 0;
              _totalAlunosGraduados = data['total_alunos_graduados'] ?? 0;
              _contagemAlunosPorGraduacao = Map<String, int>.from(data['contagem_por_graduacao'] ?? {});
              _usandoCache = true;
            });
            return;
          }
        }
      }

      await _buscarDadosReaisESalvar();

    } catch (e) {
      debugPrint('❌ Erro ao carregar estatísticas: $e');
      await _buscarDadosReaisESalvar();
    }
  }

  Future<void> _buscarDadosReaisESalvar() async {
    try {
      debugPrint('📊 Buscando dados reais dos alunos...');

      final alunosSnapshot = await _firestore.collection('alunos').get();

      Map<String, int> contagemTemp = {};
      int ativosTemp = 0;
      int inativosTemp = 0;
      int totalTemp = 0;

      for (var aluno in alunosSnapshot.docs) {
        final data = aluno.data();
        final graduacaoId = data['graduacao_id'] as String?;
        final statusAtividade = data['status_atividade'] as String?;

        totalTemp++;

        if (graduacaoId != null && graduacaoId.isNotEmpty) {
          contagemTemp[graduacaoId] = (contagemTemp[graduacaoId] ?? 0) + 1;
        }

        if (statusAtividade != null &&
            (statusAtividade.toUpperCase() == 'ATIVO' ||
                statusAtividade.toUpperCase() == 'ATIVO(A)')) {
          ativosTemp++;
        } else if (statusAtividade != null &&
            statusAtividade.toUpperCase().contains('INATIVO')) {
          inativosTemp++;
        }
      }

      final totalGraduados = contagemTemp.values.fold(0, (sum, count) => sum + count);

      final statsData = {
        'total_alunos': totalTemp,
        'alunos_ativos': ativosTemp,
        'alunos_inativos': inativosTemp,
        'total_alunos_graduados': totalGraduados,
        'contagem_por_graduacao': contagemTemp,
        'last_update': FieldValue.serverTimestamp(),
        'cache_expira_em': Timestamp.fromDate(
            DateTime.now().add(Duration(days: CACHE_DURATION_DAYS))
        ),
      };

      await _firestore
          .collection('estatisticas')
          .doc('graduacoes')
          .set(statsData);

      debugPrint('💾 Estatísticas salvas em estatisticas/graduacoes');

      if (mounted) {
        setState(() {
          _totalAlunos = totalTemp;
          _alunosAtivos = ativosTemp;
          _alunosInativos = inativosTemp;
          _totalAlunosGraduados = totalGraduados;
          _contagemAlunosPorGraduacao = contagemTemp;
          _usandoCache = false;
        });
      }

    } catch (e) {
      debugPrint('❌ Erro ao buscar dados reais: $e');
      rethrow;
    }
  }

  Future<void> _loadSvgFromAssets() async {
    try {
      debugPrint('🖼️ Carregando SVG...');
      final content = await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');
      if (mounted) {
        setState(() {
          _svgContent = content;
        });
        debugPrint('✅ SVG carregado com sucesso');
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar SVG: $e');
      if (mounted) {
        setState(() {
          _svgContent = null;
        });
      }
    }
  }

  String _getModifiedSvg(Map<String, dynamic> data, String svgContent) {
    if (svgContent.isEmpty) return '';

    try {
      final document = xml.XmlDocument.parse(svgContent);

      Color colorFromHex(String? hexColor) {
        if (hexColor == null || hexColor.length < 7) return Colors.grey;
        try {
          return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
        } catch (e) {
          return Colors.grey;
        }
      }

      void changeColor(String id, Color color) {
        try {
          final element = document.rootElement.descendants
              .whereType<xml.XmlElement>()
              .firstWhere(
                (e) => e.getAttribute('id') == id,
            orElse: () => xml.XmlElement(xml.XmlName('')),
          );

          if (element.name.local.isNotEmpty) {
            final style = element.getAttribute('style') ?? '';
            final hex = '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
            String newStyle;
            if (style.contains('fill:')) {
              newStyle = style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), 'fill:$hex');
            } else {
              newStyle = 'fill:$hex;$style';
            }
            element.setAttribute('style', newStyle);
          }
        } catch (e) {
          debugPrint('Erro ao mudar cor da parte $id: $e');
        }
      }

      changeColor('cor1', colorFromHex(data['hex_cor1']));
      changeColor('cor2', colorFromHex(data['hex_cor2']));
      changeColor('corponta1', colorFromHex(data['hex_ponta1']));
      changeColor('corponta2', colorFromHex(data['hex_ponta2']));

      return document.toXmlString();
    } catch (e) {
      debugPrint('Erro ao modificar SVG: $e');
      return svgContent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text(
            'Graduações',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          actions: [
            if (_usandoCache && !_carregando)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                  ),
                  child: const Text(
                    'CACHE',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _carregando ? null : _atualizarDados,
              tooltip: 'Atualizar dados',
            ),
          ],
        ),
        body: _carregando
            ? _buildLoadingState()
            : _erroMensagem != null
            ? _buildErrorState(colorScheme)
            : RefreshIndicator(
          onRefresh: _atualizarDados,
          color: Colors.red.shade900,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 14 : 24,
              isMobile ? 14 : 22,
              isMobile ? 14 : 24,
              30,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeroGraduacoes(isMobile),
                      const SizedBox(height: 14),
                      _buildDashboardCardsModernos(isMobile),
                      const SizedBox(height: 20),
                      _buildTimelineHeader(isMobile),
                      const SizedBox(height: 14),
                      if (_graduacoes.isEmpty)
                        _buildEmptyState(colorScheme)
                      else
                        _buildGraduacoesTimeline(isMobile),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _atualizarDados() async {
    setState(() {
      _carregando = true;
      _erroMensagem = null;
    });

    try {
      await _buscarDadosReaisESalvar();

      if (mounted) {
        setState(() => _carregando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dados atualizados!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _erroMensagem = e.toString();
          _carregando = false;
        });
      }
    }
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.red.shade900),
          const SizedBox(height: 14),
          Text(
            'Carregando graduações...',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroGraduacoes(bool isMobile) {
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
      child: isMobile
          ? Column(
        children: [
          _buildHeroIcon(),
          const SizedBox(height: 14),
          _buildHeroTexts(isMobile, centered: true),
        ],
      )
          : Row(
        children: [
          _buildHeroIcon(),
          const SizedBox(width: 16),
          Expanded(child: _buildHeroTexts(isMobile, centered: false)),
        ],
      ),
    );
  }

  Widget _buildHeroIcon() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: const Icon(
        Icons.workspace_premium_rounded,
        color: Colors.white,
        size: 38,
      ),
    );
  }

  Widget _buildHeroTexts(bool isMobile, {required bool centered}) {
    return Column(
      crossAxisAlignment:
      centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          'Sistema de Graduações',
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: Colors.white,
            fontSize: isMobile ? 23 : 30,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'A evolução na capoeira contada pelas cordas, suas cores e seus significados.',
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: Colors.white.withOpacity(0.82),
            fontSize: isMobile ? 13.5 : 15,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (_usandoCache) ...[
          const SizedBox(height: 12),
          _buildCacheInfoChip(),
        ],
      ],
    );
  }

  Widget _buildCacheInfoChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.offline_bolt_rounded, color: Colors.white, size: 15),
          SizedBox(width: 5),
          Text(
            'Dados em cache',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCardsModernos(bool isMobile) {
    final cards = [
      _GraduacaoStatCard(
        titulo: 'Total',
        valor: _totalAlunos,
        subtitulo: 'Alunos',
        icone: Icons.groups_rounded,
        cor: Colors.blue,
      ),
      _GraduacaoStatCard(
        titulo: 'Ativos',
        valor: _alunosAtivos,
        subtitulo: 'Treinando',
        icone: Icons.fitness_center_rounded,
        cor: Colors.green,
      ),
      _GraduacaoStatCard(
        titulo: 'Inativos',
        valor: _alunosInativos,
        subtitulo: 'Ausentes',
        icone: Icons.person_off_rounded,
        cor: Colors.red,
      ),
      _GraduacaoStatCard(
        titulo: 'Graduados',
        valor: _totalAlunosGraduados,
        subtitulo: 'Cordas',
        icone: Icons.school_rounded,
        cor: Colors.orange,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final largura = constraints.maxWidth;
        final colunas = largura < 760 ? 2 : 4;
        const spacing = 10.0;
        final itemWidth = (largura - spacing * (colunas - 1)) / colunas;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) {
            return SizedBox(
              width: itemWidth,
              child: _buildStatCard(card, compact: isMobile),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildStatCard(_GraduacaoStatCard card, {required bool compact}) {
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 98 : 112),
      padding: EdgeInsets.all(compact ? 11 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: card.cor.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(card.icone, color: card.cor, size: compact ? 24 : 28),
          const SizedBox(height: 7),
          Text(
            card.valor.toString(),
            style: TextStyle(
              color: card.cor,
              fontSize: compact ? 20 : 25,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            card.titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade900,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            card.subtitulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineHeader(bool isMobile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
      child: Row(
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
              size: 23,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SISTEMA DE GRADUAÇÃO',
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontSize: isMobile ? 17 : 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${_graduacoes.length} graduações cadastradas',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraduacoesTimeline(bool isMobile) {
    return Column(
      children: List.generate(_graduacoes.length, (index) {
        final graduacao = _graduacoes[index];
        final id = graduacao['id']?.toString() ?? '';
        final quantidadeAlunos = _contagemAlunosPorGraduacao[id] ?? 0;
        final nome = graduacao['nome_graduacao']?.toString() ?? 'Sem nome';
        final titulo = graduacao['titulo_graduacao']?.toString() ?? '';
        final corda = graduacao['corda']?.toString() ?? '';
        final tipoPublico = graduacao['tipo_publico']?.toString() ?? '';
        final descricao = _descricaoGraduacao(graduacao);
        final modifiedSvg = _svgContent == null
            ? null
            : _getModifiedSvg(graduacao, _svgContent!);
        final color1 = _safeColor(
          graduacao['hex_cor1'],
          fallback: Colors.red.shade900,
        );
        final color2 = _safeColor(graduacao['hex_cor2'], fallback: color1);

        return _buildTimelineItem(
          index: index,
          total: _graduacoes.length,
          nome: nome,
          titulo: titulo,
          corda: corda,
          tipoPublico: tipoPublico,
          descricao: descricao,
          modifiedSvg: modifiedSvg,
          quantidadeAlunos: quantidadeAlunos,
          color1: color1,
          color2: color2,
          isMobile: isMobile,
        );
      }),
    );
  }

  Widget _buildTimelineItem({
    required int index,
    required int total,
    required String nome,
    required String titulo,
    required String corda,
    required String tipoPublico,
    required String descricao,
    required String? modifiedSvg,
    required int quantidadeAlunos,
    required Color color1,
    required Color color2,
    required bool isMobile,
  }) {
    final isFirst = index == 0;
    final isLast = index == total - 1;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: isMobile ? 42 : 58,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 3,
                    color: isFirst ? Colors.transparent : Colors.red.shade100,
                  ),
                ),
                Container(
                  width: isMobile ? 32 : 38,
                  height: isMobile ? 32 : 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color1, color2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: color1.withOpacity(0.22),
                        blurRadius: 7,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: _contrastingTextColor(color1),
                        fontSize: isMobile ? 11 : 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
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
                padding: EdgeInsets.all(isMobile ? 14 : 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: color1.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.035),
                      blurRadius: 7,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: isMobile
                    ? Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildTimelineCordaPreview(
                      modifiedSvg: modifiedSvg,
                      color1: color1,
                      color2: color2,
                      isMobile: true,
                    ),
                    const SizedBox(height: 12),
                    _buildTimelineTextContent(
                      nome: nome,
                      titulo: titulo,
                      corda: corda,
                      tipoPublico: tipoPublico,
                      descricao: descricao,
                      quantidadeAlunos: quantidadeAlunos,
                      centered: true,
                    ),
                  ],
                )
                    : Row(
                  children: [
                    SizedBox(
                      width: 210,
                      child: _buildTimelineCordaPreview(
                        modifiedSvg: modifiedSvg,
                        color1: color1,
                        color2: color2,
                        isMobile: false,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _buildTimelineTextContent(
                        nome: nome,
                        titulo: titulo,
                        corda: corda,
                        tipoPublico: tipoPublico,
                        descricao: descricao,
                        quantidadeAlunos: quantidadeAlunos,
                        centered: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCordaPreview({
    required String? modifiedSvg,
    required Color color1,
    required Color color2,
    required bool isMobile,
  }) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxWidth: isMobile ? 260 : 210,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            height: isMobile ? 92 : 104,
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: modifiedSvg != null && modifiedSvg.isNotEmpty
                ? SvgPicture.string(modifiedSvg, fit: BoxFit.contain)
                : Icon(
              Icons.image_not_supported_rounded,
              color: Colors.grey.shade300,
              size: 48,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 7,
            width: 92,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(colors: [color1, color2]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineTextContent({
    required String nome,
    required String titulo,
    required String corda,
    required String tipoPublico,
    required String descricao,
    required int quantidadeAlunos,
    required bool centered,
  }) {
    final subtitulo = [
      if (titulo.trim().isNotEmpty) titulo.trim(),
      if (corda.trim().isNotEmpty) corda.trim(),
      if (tipoPublico.trim().isNotEmpty &&
          tipoPublico.trim().toUpperCase() != 'GERAL')
        tipoPublico.trim().toUpperCase(),
    ].join(' • ');

    return Column(
      crossAxisAlignment:
      centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          nome,
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: Colors.grey.shade900,
            fontSize: 16.2,
            height: 1.08,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.1,
          ),
        ),
        if (subtitulo.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            subtitulo,
            textAlign: centered ? TextAlign.center : TextAlign.left,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              height: 1.22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (descricao.trim().isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              descricao.trim(),
              textAlign: centered ? TextAlign.center : TextAlign.left,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 13.2,
                height: 1.36,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          alignment: centered ? WrapAlignment.center : WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildInfoChip(
              icon: Icons.groups_rounded,
              label: '$quantidadeAlunos ${quantidadeAlunos == 1 ? 'aluno' : 'alunos'}',
              color: Colors.red.shade900,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  String _descricaoGraduacao(Map<String, dynamic> graduacao) {
    final candidatos = [
      graduacao['descricao_site'],
      graduacao['descricao_graduacao'],
      graduacao['descricao'],
      graduacao['frase_descricao'],
    ];

    for (final value in candidatos) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }

    return '';
  }

  Color _safeColor(dynamic hex, {required Color fallback}) {
    final value = hex?.toString().trim();

    if (value == null || value.isEmpty) return fallback;

    try {
      final cleaned = value.replaceAll('#', '').toUpperCase();

      if (cleaned.length == 6) {
        return Color(int.parse('FF$cleaned', radix: 16));
      }

      if (cleaned.length == 8) {
        return Color(int.parse(cleaned, radix: 16));
      }
    } catch (_) {}

    return fallback;
  }

  Color _contrastingTextColor(Color color) {
    final luminance = color.computeLuminance();
    return luminance > 0.52 ? Colors.black87 : Colors.white;
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.red.shade100),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 72,
                color: Colors.red.shade700,
              ),
              const SizedBox(height: 14),
              Text(
                'Erro ao carregar os dados',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.red.shade900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _erroMensagem ?? 'Tente novamente mais tarde',
                style: TextStyle(color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _carregando = true;
                    _erroMensagem = null;
                  });
                  _carregarDados();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium_outlined,
            size: 70,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 14),
          Text(
            'Nenhuma graduação encontrada',
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(
                context,
                baseSize: 18,
              ),
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Adicione graduações no painel administrativo.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _GraduacaoStatCard {
  final String titulo;
  final int valor;
  final String subtitulo;
  final IconData icone;
  final Color cor;

  const _GraduacaoStatCard({
    required this.titulo,
    required this.valor,
    required this.subtitulo,
    required this.icone,
    required this.cor,
  });
}
