import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/utils/responsive_utils.dart';
import 'package:uai_capoeira/modules/rastreio/services/rastreio_site.dart';

class GraduacoesScreen extends StatefulWidget {
  const GraduacoesScreen({super.key});

  @override
  State<GraduacoesScreen> createState() => _GraduacoesScreenState();
}

class _GraduacoesScreenState extends State<GraduacoesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final RastreioSiteService _rastreioService = RastreioSiteService();
  final ScrollController _scrollController = ScrollController();

  int _maiorPercentualRolagem = 0;

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

    _rastreioService.iniciarTela(
      'graduacoes',
      origem: 'site',
      metadata: {
        'descricao': 'Tela pública de graduações',
      },
    );
    _rastreioService.marcarTempo('graduacoes_tempo');
    _scrollController.addListener(_registrarRolagem);
    _carregarDados();
  }

  @override
  void dispose() {
    _rastreioService.registrarTempoMarcador(
      chave: 'graduacoes_tempo',
      tipo: 'tempo_tela',
      nome: 'graduacoes',
      origem: 'dispose',
      metadata: {
        'maior_percentual_rolagem': _maiorPercentualRolagem,
        'total_graduacoes': _graduacoes.length,
      },
      limparMarcador: true,
    );
    _rastreioService.finalizarTela(destino: 'saida_graduacoes');
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
        nome: 'graduacoes_$marco%',
        origem: 'graduacoes',
        metadata: {
          'percentual': marco,
          'total_graduacoes': _graduacoes.length,
        },
      );
    }
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

        _rastreioService.registrarBuscaOuFiltroResultado(
          tela: 'graduacoes',
          nome: 'dados_carregados',
          total: _graduacoes.length,
          metadata: {
            'total_alunos': _totalAlunos,
            'alunos_ativos': _alunosAtivos,
            'alunos_inativos': _alunosInativos,
            'usando_cache': _usandoCache,
          },
        );
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

      final graduacoesConvertidas = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
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
          final diasDesdeAtualizacao =
              DateTime.now().difference(lastUpdate.toDate()).inDays;

          if (diasDesdeAtualizacao < CACHE_DURATION_DAYS) {
            debugPrint(
              '✅ Usando cache de estatísticas ($diasDesdeAtualizacao dias atrás)',
            );

            setState(() {
              _totalAlunos = data['total_alunos'] ?? 0;
              _alunosAtivos = data['alunos_ativos'] ?? 0;
              _alunosInativos = data['alunos_inativos'] ?? 0;
              _totalAlunosGraduados = data['total_alunos_graduados'] ?? 0;
              _contagemAlunosPorGraduacao = Map<String, int>.from(
                data['contagem_por_graduacao'] ?? {},
              );
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

      final contagemTemp = <String, int>{};
      var ativosTemp = 0;
      var inativosTemp = 0;
      var totalTemp = 0;

      for (final aluno in alunosSnapshot.docs) {
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

      final totalGraduados =
      contagemTemp.values.fold<int>(0, (sum, count) => sum + count);

      final statsData = {
        'total_alunos': totalTemp,
        'alunos_ativos': ativosTemp,
        'alunos_inativos': inativosTemp,
        'total_alunos_graduados': totalGraduados,
        'contagem_por_graduacao': contagemTemp,
        'last_update': FieldValue.serverTimestamp(),
        'cache_expira_em': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: CACHE_DURATION_DAYS)),
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
      final content = await DefaultAssetBundle.of(context)
          .loadString('assets/images/corda.svg');

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
          return Color(
            int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16),
          );
        } catch (_) {
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
            final hex =
                '#${color.value.toRadixString(16).substring(2).toUpperCase()}';

            String newStyle;
            if (style.contains('fill:')) {
              newStyle = style.replaceAll(
                RegExp(r'fill:#[0-9a-fA-F]{6}'),
                'fill:$hex',
              );
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
    final t = context.uai;
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;

    // IMPORTANTE:
    // Esta tela é usada dentro da LandingPage, que já tem AppBar.
    // Então aqui NÃO existe Scaffold/AppBar, evitando duas barras.
    return PopScope(
      canPop: true,
      child: ColoredBox(
        color: t.background,
        child: _carregando
            ? _buildLoadingState()
            : _erroMensagem != null
            ? _buildErrorState()
            : RefreshIndicator(
          onRefresh: () async {
            _rastreioService.registrarClique(
              nome: 'atualizar_graduacoes',
              origem: 'graduacoes',
            );
            await _atualizarDados();
          },
          color: t.primary,
          backgroundColor: t.surface,
          child: ListView(
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
                        _buildEmptyState()
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
    final t = context.uai;

    _rastreioService.registrarClique(
      nome: 'atualizar_dados_graduacoes',
      origem: 'graduacoes',
      metadata: {
        'usando_cache': _usandoCache,
      },
    );

    setState(() {
      _carregando = true;
      _erroMensagem = null;
    });

    try {
      await _buscarDadosReaisESalvar();

      if (mounted) {
        setState(() => _carregando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Dados atualizados!'),
            backgroundColor: t.success,
            behavior: SnackBarBehavior.floating,
          ),
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
              'Carregando graduações...',
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroGraduacoes(bool isMobile) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(isMobile ? 24 : t.cardRadius + 6),
        boxShadow: t.softShadow,
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
          const SizedBox(width: 12),
          _buildRefreshHeroButton(onPrimary),
        ],
      ),
    );
  }

  Widget _buildRefreshHeroButton(Color onPrimary) {
    final t = context.uai;

    return Tooltip(
      message: 'Atualizar dados',
      child: Material(
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(t.buttonRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _carregando ? null : _atualizarDados,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.refresh_rounded,
              color: onPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroIcon() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: Icon(
        Icons.workspace_premium_rounded,
        color: onPrimary,
        size: 38,
      ),
    );
  }

  Widget _buildHeroTexts(bool isMobile, {required bool centered}) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Column(
      crossAxisAlignment:
      centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          'Sistema de Graduações',
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: onPrimary,
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
            color: onPrimary.withOpacity(0.82),
            fontSize: isMobile ? 13.5 : 15,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: centered ? WrapAlignment.center : WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_usandoCache) _buildCacheInfoChip(),
            if (isMobile)
              Material(
                color: onPrimary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(99),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _carregando ? null : _atualizarDados,
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: onPrimary.withOpacity(0.16)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          color: onPrimary,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Atualizar',
                          style: TextStyle(
                            color: onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCacheInfoChip() {
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
          Icon(Icons.offline_bolt_rounded, color: onPrimary, size: 15),
          const SizedBox(width: 5),
          Text(
            'Dados em cache',
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

  Widget _buildDashboardCardsModernos(bool isMobile) {
    final t = context.uai;

    final cards = [
      _GraduacaoStatCard(
        titulo: 'Total',
        valor: _totalAlunos,
        subtitulo: 'Alunos',
        icone: Icons.groups_rounded,
        cor: t.info,
      ),
      _GraduacaoStatCard(
        titulo: 'Ativos',
        valor: _alunosAtivos,
        subtitulo: 'Treinando',
        icone: Icons.fitness_center_rounded,
        cor: t.success,
      ),
      _GraduacaoStatCard(
        titulo: 'Inativos',
        valor: _alunosInativos,
        subtitulo: 'Ausentes',
        icone: Icons.person_off_rounded,
        cor: t.error,
      ),
      _GraduacaoStatCard(
        titulo: 'Graduados',
        valor: _totalAlunosGraduados,
        subtitulo: 'Cordas',
        icone: Icons.school_rounded,
        cor: t.warning,
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
    final t = context.uai;
    final accent = _ensureVisible(card.cor, t.card);

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 98 : 112),
      padding: EdgeInsets.all(compact ? 11 : 14),
      decoration: _cardDecoration(borderColor: accent.withOpacity(0.13)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(card.icone, color: accent, size: compact ? 24 : 28),
          const SizedBox(height: 7),
          Text(
            card.valor.toString(),
            style: TextStyle(
              color: accent,
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
              color: t.textPrimary,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            card.subtitulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineHeader(bool isMobile) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.background);

    return Container(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
      child: Row(
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
              Icons.timeline_rounded,
              color: primary,
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
                    color: t.textPrimary,
                    fontSize: isMobile ? 17 : 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${_graduacoes.length} graduações cadastradas',
                  style: TextStyle(
                    color: t.textSecondary,
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
          fallback: context.uai.primary,
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
    final t = context.uai;
    final isFirst = index == 0;
    final isLast = index == total - 1;
    final lineColor = _ensureVisible(t.primary, t.background);

    return GestureDetector(
      onTap: () {
        _rastreioService.registrarItemVisualizado(
          tela: 'graduacoes',
          itemTipo: 'graduacao',
          itemNome: nome,
          itemId: corda,
          metadata: {
            'index': index,
            'titulo': titulo,
            'tipo_publico': tipoPublico,
            'quantidade_alunos': quantidadeAlunos,
          },
        );
      },
      child: IntrinsicHeight(
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
                      color: isFirst
                          ? Colors.transparent
                          : lineColor.withOpacity(0.18),
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
                      border: Border.all(color: t.card, width: 3),
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
                      color: isLast
                          ? Colors.transparent
                          : lineColor.withOpacity(0.18),
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
                  decoration: _cardDecoration(
                    borderColor: _ensureVisible(color1, t.card)
                        .withOpacity(0.16),
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
      ),
    );
  }

  Widget _buildTimelineCordaPreview({
    required String? modifiedSvg,
    required Color color1,
    required Color color2,
    required bool isMobile,
  }) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxWidth: isMobile ? 260 : 210,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Container(
            height: isMobile ? 92 : 104,
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.border),
            ),
            child: modifiedSvg != null && modifiedSvg.isNotEmpty
                ? SvgPicture.string(modifiedSvg, fit: BoxFit.contain)
                : Icon(
              Icons.image_not_supported_rounded,
              color: t.textMuted,
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
    final t = context.uai;

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
            color: t.textPrimary,
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
              color: t.textSecondary,
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
              color: t.cardAlt,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.border),
            ),
            child: Text(
              descricao.trim(),
              textAlign: centered ? TextAlign.center : TextAlign.left,
              style: TextStyle(
                color: t.textPrimary,
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
              label:
              '$quantidadeAlunos ${quantidadeAlunos == 1 ? 'aluno' : 'alunos'}',
              color: t.primary,
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
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
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

  Widget _buildErrorState() {
    final t = context.uai;
    final danger = _ensureVisible(t.error, t.card);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(22),
          decoration: _cardDecoration(borderColor: danger.withOpacity(0.18)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 72,
                color: danger,
              ),
              const SizedBox(height: 14),
              Text(
                'Erro ao carregar os dados',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _erroMensagem ?? 'Tente novamente mais tarde',
                style: TextStyle(color: t.textSecondary),
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
                  backgroundColor: t.primary,
                  foregroundColor: _readableOn(t.primary),
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

  Widget _buildEmptyState() {
    final t = context.uai;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: _cardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium_outlined,
            size: 70,
            color: t.textMuted,
          ),
          const SizedBox(height: 14),
          Text(
            'Nenhuma graduação encontrada',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(
                context,
                baseSize: 18,
              ),
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Adicione graduações no painel administrativo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: t.textSecondary),
          ),
        ],
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
