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
    final isMobile = ResponsiveUtils.isMobile(context);
    final isTablet = ResponsiveUtils.isTablet(context);
    final isDesktop = ResponsiveUtils.isDesktop(context);
    final padding = ResponsiveUtils.getResponsivePadding(context);
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('🥋 GRADUAÇÕES'),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          actions: [
            if (_usandoCache && !_carregando)
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '📦 CACHE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                setState(() {
                  _carregando = true;
                });
                await _buscarDadosReaisESalvar();
                if (mounted) {
                  setState(() {
                    _carregando = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Dados atualizados!')),
                  );
                }
              },
              tooltip: 'Atualizar dados',
            ),
          ],
        ),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorScheme.primaryContainer.withOpacity(0.3),
                colorScheme.surface,
              ],
            ),
          ),
          child: _carregando
              ? const Center(child: CircularProgressIndicator())
              : _erroMensagem != null
              ? _buildErrorState(colorScheme)
              : SingleChildScrollView(
            padding: padding,
            child: SizedBox(
              width: double.infinity,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 24),
                      _buildHeader(colorScheme, context),
                      const SizedBox(height: 24),
                      _buildDashboardCards(colorScheme, isMobile, isTablet, isDesktop),
                      const SizedBox(height: 32),
                      _buildSectionTitle(colorScheme, context),
                      const SizedBox(height: 20),
                      _graduacoes.isEmpty
                          ? _buildEmptyState(colorScheme)
                          : _svgContent == null
                          ? _buildGraduacoesSemSvg(colorScheme, isMobile, isTablet, isDesktop)
                          : _buildGraduacoesGrid(colorScheme, isMobile, isTablet, isDesktop),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme, BuildContext context) {
    final isMobile = ResponsiveUtils.isMobile(context);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: isMobile ? 12 : 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emoji_events,
            size: isMobile ? 40 : 60,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            'Sistema de Graduações',
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, baseSize: isMobile ? 22 : 28),
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Acompanhe o progresso e evolução dos alunos',
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, baseSize: isMobile ? 12 : 14),
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (_usandoCache) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '📦 Dados em cache (atualizado há menos de 3 dias)',
                style: TextStyle(
                  fontSize: isMobile ? 9 : 10,
                  color: Colors.green.shade700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ColorScheme colorScheme, BuildContext context) {
    final isMobile = ResponsiveUtils.isMobile(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: isMobile ? 20 : 40,
            height: 3,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            'TODAS AS GRADUAÇÕES',
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, baseSize: isMobile ? 16 : 20),
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
              letterSpacing: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(width: 12),
          Container(
            width: isMobile ? 20 : 40,
            height: 3,
            color: colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCards(ColorScheme colorScheme, bool isMobile, bool isTablet, bool isDesktop) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount;
        double childAspectRatio;

        if (isDesktop) {
          crossAxisCount = 4;
          childAspectRatio = 1.0; // Quadrado
        } else if (isTablet) {
          crossAxisCount = 2;
          childAspectRatio = 1.0; // Quadrado
        } else {
          // Mobile
          if (constraints.maxWidth < 400) {
            crossAxisCount = 1;
            childAspectRatio = 1.2;
          } else {
            crossAxisCount = 2;
            childAspectRatio = 1.0; // Quadrado
          }
        }

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: childAspectRatio,
          children: [
            _buildDashboardCard(
              context, colorScheme, 'Total', _totalAlunos,
              Icons.people_alt, Colors.blue, 'Alunos',
              isMobile,
            ),
            _buildDashboardCard(
              context, colorScheme, 'Ativos', _alunosAtivos,
              Icons.fitness_center, Colors.green, 'Treinando',
              isMobile,
            ),
            _buildDashboardCard(
              context, colorScheme, 'Inativos', _alunosInativos,
              Icons.person_off, Colors.red, 'Ausentes',
              isMobile,
            ),
            _buildDashboardCard(
              context, colorScheme, 'Graduados', _totalAlunosGraduados,
              Icons.school, Colors.orange, 'Cordas',
              isMobile,
            ),
          ],
        );
      },
    );
  }

  Widget _buildDashboardCard(
      BuildContext context,
      ColorScheme colorScheme,
      String titulo,
      int valor,
      IconData icone,
      Color cor,
      String subtitulo,
      bool isMobile,
      ) {
    final fontSizeIcon = isMobile ? 28.0 : 36.0;
    final fontSizeTitulo = isMobile ? 13.0 : 15.0;
    final fontSizeValor = isMobile ? 24.0 : 32.0;
    final fontSizeSubtitulo = isMobile ? 10.0 : 11.0;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 10 : 14),
              decoration: BoxDecoration(
                color: cor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icone,
                size: fontSizeIcon,
                color: cor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              titulo,
              style: TextStyle(
                fontSize: fontSizeTitulo,
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              valor.toString(),
              style: TextStyle(
                fontSize: fontSizeValor,
                fontWeight: FontWeight.bold,
                color: cor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitulo,
              style: TextStyle(
                fontSize: fontSizeSubtitulo,
                color: colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraduacoesGrid(ColorScheme colorScheme, bool isMobile, bool isTablet, bool isDesktop) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount;
        double childAspectRatio = 1.0; // Cards quadrados

        if (isDesktop) {
          crossAxisCount = 4;
          childAspectRatio = 0.9;
        } else if (isTablet) {
          crossAxisCount = 3;
          childAspectRatio = 0.85;
        } else {
          // Mobile - cards mais quadrados
          if (constraints.maxWidth < 400) {
            crossAxisCount = 2;
            childAspectRatio = 0.85;
          } else {
            crossAxisCount = 2;
            childAspectRatio = 0.9;
          }
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: _graduacoes.length,
          itemBuilder: (context, index) {
            final graduacao = _graduacoes[index];
            final modifiedSvg = _getModifiedSvg(graduacao, _svgContent!);
            final quantidadeAlunos = _contagemAlunosPorGraduacao[graduacao['id']] ?? 0;
            final nivel = graduacao['nivel_graduacao'] ?? 0;
            final tipoPublico = graduacao['tipo_publico'] ?? '';

            return _buildGraduacaoCard(
              context,
              colorScheme,
              graduacao['nome_graduacao'] ?? 'Sem nome',
              modifiedSvg,
              quantidadeAlunos,
              nivel,
              tipoPublico,
              isMobile,
            );
          },
        );
      },
    );
  }

  Widget _buildGraduacaoCard(
      BuildContext context,
      ColorScheme colorScheme,
      String nome,
      String modifiedSvg,
      int quantidadeAlunos,
      int nivel,
      String tipoPublico,
      bool isMobile,
      ) {
    final fontSizeNivel = isMobile ? 10.0 : 12.0;
    final fontSizeNome = isMobile ? 12.0 : 14.0;
    final fontSizeAlunos = isMobile ? 11.0 : 13.0;
    final svgHeight = isMobile ? 70.0 : 90.0;
    final paddingCard = isMobile ? 8.0 : 12.0;

    // Formata o texto do nível com o tipo público
    String nivelText = 'NÍVEL $nivel';
    if (tipoPublico.isNotEmpty && tipoPublico != 'GERAL') {
      nivelText = '$nivelText • ${tipoPublico.toUpperCase()}';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: EdgeInsets.all(paddingCard),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Header com nível e tipo
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: isMobile ? 6 : 8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  nivelText,
                  style: TextStyle(
                    fontSize: fontSizeNivel,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // SVG da corda
            Expanded(
              child: Center(
                child: SvgPicture.string(
                  modifiedSvg,
                  fit: BoxFit.contain,
                  height: svgHeight,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Nome da graduação
            Text(
              nome,
              style: TextStyle(
                fontSize: fontSizeNome,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            // Contador de alunos
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: isMobile ? 6 : 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.primary.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people,
                    size: fontSizeAlunos,
                    color: colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    quantidadeAlunos.toString(),
                    style: TextStyle(
                      fontSize: fontSizeAlunos,
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    quantidadeAlunos == 1 ? 'ALUNO' : 'ALUNOS',
                    style: TextStyle(
                      fontSize: fontSizeAlunos * 0.8,
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraduacoesSemSvg(ColorScheme colorScheme, bool isMobile, bool isTablet, bool isDesktop) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount;
        double childAspectRatio = 1.0;

        if (isDesktop) {
          crossAxisCount = 4;
          childAspectRatio = 0.9;
        } else if (isTablet) {
          crossAxisCount = 3;
          childAspectRatio = 0.85;
        } else {
          if (constraints.maxWidth < 400) {
            crossAxisCount = 2;
            childAspectRatio = 0.85;
          } else {
            crossAxisCount = 2;
            childAspectRatio = 0.9;
          }
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: _graduacoes.length,
          itemBuilder: (context, index) {
            final graduacao = _graduacoes[index];
            final quantidadeAlunos = _contagemAlunosPorGraduacao[graduacao['id']] ?? 0;
            final nivel = graduacao['nivel_graduacao'] ?? 0;
            final tipoPublico = graduacao['tipo_publico'] ?? '';

            return _buildGraduacaoCardSemSvg(
              context,
              colorScheme,
              graduacao['nome_graduacao'] ?? 'Sem nome',
              quantidadeAlunos,
              nivel,
              tipoPublico,
              isMobile,
            );
          },
        );
      },
    );
  }

  Widget _buildGraduacaoCardSemSvg(
      BuildContext context,
      ColorScheme colorScheme,
      String nome,
      int quantidadeAlunos,
      int nivel,
      String tipoPublico,
      bool isMobile,
      ) {
    final fontSizeNivel = isMobile ? 10.0 : 12.0;
    final fontSizeNome = isMobile ? 12.0 : 14.0;
    final fontSizeAlunos = isMobile ? 11.0 : 13.0;
    final paddingCard = isMobile ? 8.0 : 12.0;

    String nivelText = 'NÍVEL $nivel';
    if (tipoPublico.isNotEmpty && tipoPublico != 'GERAL') {
      nivelText = '$nivelText • ${tipoPublico.toUpperCase()}';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: EdgeInsets.all(paddingCard),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: isMobile ? 6 : 8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  nivelText,
                  style: TextStyle(
                    fontSize: fontSizeNivel,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: Icon(
                  Icons.image_not_supported,
                  size: isMobile ? 50 : 70,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              nome,
              style: TextStyle(
                fontSize: fontSizeNome,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: isMobile ? 6 : 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.primary.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people,
                    size: fontSizeAlunos,
                    color: colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    quantidadeAlunos.toString(),
                    style: TextStyle(
                      fontSize: fontSizeAlunos,
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    quantidadeAlunos == 1 ? 'ALUNO' : 'ALUNOS',
                    style: TextStyle(
                      fontSize: fontSizeAlunos * 0.8,
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error, size: 80, color: colorScheme.error),
          const SizedBox(height: 16),
          Text(
            'Erro ao carregar os dados',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.error),
          ),
          const SizedBox(height: 8),
          Text(
            _erroMensagem ?? 'Tente novamente mais tarde',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _carregando = true;
                _erroMensagem = null;
                _carregarDados();
              });
            },
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events, size: 80, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'Nenhuma graduação encontrada',
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, baseSize: 18),
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Adicione graduações no painel administrativo',
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}