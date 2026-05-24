// screens/turmas/dashboard_turmas_page.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import '../../widgets/card_frequencia_moderno.dart';

class DashboardTurmasPage extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;

  const DashboardTurmasPage({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
  });

  @override
  State<DashboardTurmasPage> createState() => _DashboardTurmasPageState();
}

class _DashboardTurmasPageState extends State<DashboardTurmasPage>
    with
        AutomaticKeepAliveClientMixin,
        TickerProviderStateMixin,
        WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  // Cache
  static const int _CACHE_VALIDADE_HORAS = 1;
  static const int _CACHE_VALIDADE_MINUTOS = _CACHE_VALIDADE_HORAS * 60;
  static const int _CACHE_VALIDADE_MS = _CACHE_VALIDADE_HORAS * 60 * 60 * 1000;

  // Filtros
  String filtroAtivo = 'Frequência';
  String? filtroSexo;
  String filtroTemporalFrequencia = 'Ano';
  String? anoSelecionado;
  List<String> anosDisponiveis = [];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _alunosDaTurma = [];

  // Cache de graduações (nome → dados)
  final Map<String, Map<String, dynamic>> _graduacoesCache = {};

  // Cache de SVG colorido (pré‑colorido durante o carregamento)
  final Map<String, String> _svgCache = {};
  String? _svgContent;

  List<Map<String, dynamic>> _alunosOrdenadosPorFrequencia = [];
  List<Map<String, dynamic>> _alunosFrequentes = [];
  Map<String, Map<String, dynamic>> _avaliacoesAlunos = {};
  List<Map<String, dynamic>> _alunosDestaque = [];
  Map<String, int> _distribuicaoGraduacao = {};
  Map<String, List<Map<String, dynamic>>> _alunosPorGraduacao = {};
  List<Map<String, dynamic>> _alunosOrdenadosPorIdade = [];
  Map<String, int> _distribuicaoIdade = {};
  int _totalMeninos = 0;
  int _totalMeninas = 0;

  bool _isLoading = true;
  String? _erro;
  bool _isAtualizando = false;
  bool _isGerandoImagemDestaque = false;
  bool _isGerandoPdfDestaque = false;
  bool _isGerandoPdfCompletoDestaque = false;

  Map<String, Map<String, int>> _tiposAulaPdfCache = {};

  DateTime? _ultimaAtualizacao;
  DateTime? _ultimaSyncLogs;
  Timer? _timerCache;

  final ScrollController _scrollController = ScrollController();
  final ScrollController _tabsScrollController = ScrollController();
  final Map<String, GlobalKey> _tabKeys = {
    'Aluno Destaque': GlobalKey(),
    'Frequência': GlobalKey(),
    'Graduação': GlobalKey(),
    'Idade': GlobalKey(),
    'Sexo': GlobalKey(),
  };
  bool _centralizouAbaInicial = false;
  int _visibleItems = 20;

  final Map<String, Color> _colorCache = {};

  final Map<String, int> _faixasEtarias = {
    '4-7 anos': 0,
    '8-12 anos': 0,
    '13-17 anos': 0,
    '18-25 anos': 0,
    '26-35 anos': 0,
    '36-50 anos': 0,
    '50+ anos': 0,
  };
  final Map<String, IconData> _iconesFaixa = {
    '4-7 anos': Icons.child_care,
    '8-12 anos': Icons.child_friendly,
    '13-17 anos': Icons.face_3,
    '18-25 anos': Icons.face,
    '26-35 anos': Icons.person,
    '36-50 anos': Icons.person_2,
    '50+ anos': Icons.elderly,
  };

  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _rotateAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rotateController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    _inicializarDados();
    _scrollController.addListener(_onScroll);
    _iniciarTimerCache();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _agendarCentralizacaoAbaInicial();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _tabsScrollController.dispose();
    _timerCache?.cancel();
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _verificarEAtualizarCache();
  }

  void _iniciarTimerCache() {
    _timerCache = Timer.periodic(const Duration(minutes: 30), (_) {
      if (mounted) _verificarEAtualizarCache();
    });
  }

  Future<void> _verificarEAtualizarCache() async {
    if (!mounted || _isAtualizando) return;
    if (_ultimaAtualizacao == null) {
      await _atualizarDadosReais();
      return;
    }
    final diferenca = DateTime.now().difference(_ultimaAtualizacao!);
    if (diferenca.inMilliseconds > _CACHE_VALIDADE_MS)
      await _atualizarDadosReais();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      setState(() => _visibleItems += 20);
    }
  }

  // ============ PARSING ============
  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    return 0;
  }

  Map<String, int> _parseFrequenciaTemporal(dynamic frequencia) {
    if (frequencia == null) return {};
    if (frequencia is Map) {
      final result = <String, int>{};
      result['total'] = _parseInt(frequencia['total']);
      result['semana'] = _parseInt(frequencia['semana']);
      result['mes'] = _parseInt(frequencia['mes']);
      frequencia.forEach((key, value) {
        if (key is String &&
            key.length == 4 &&
            int.tryParse(key) != null &&
            !['total', 'semana', 'mes'].contains(key)) {
          result[key] = _parseInt(value);
        }
      });
      return result;
    }
    return {};
  }

  List<Map<String, dynamic>> _parseAlunos(dynamic alunosData) {
    if (alunosData == null) return [];
    if (alunosData is List) {
      return alunosData.map<Map<String, dynamic>>((aluno) {
        if (aluno is Map) {
          final Map<String, dynamic> alunoMap = Map<String, dynamic>.from(
            aluno,
          );
          if (alunoMap.containsKey('frequencia_temporal')) {
            alunoMap['frequencia_temporal'] = _parseFrequenciaTemporal(
              alunoMap['frequencia_temporal'],
            );
          }
          if (alunoMap.containsKey('total_presencas')) {
            alunoMap['total_presencas'] = _parseInt(
              alunoMap['total_presencas'],
            );
          }
          return alunoMap;
        }
        return <String, dynamic>{};
      }).toList();
    }
    return [];
  }

  // ============ CARREGAMENTO ============
  Future<void> _inicializarDados() async {
    setState(() {
      _isLoading = true;
      _erro = null;
    });
    try {
      await _carregarSvg(); // carrega o SVG bruto primeiro
      await _preloadGraduacoes(); // carrega as cores e já colore
      await _carregarAlunosDaTurma();
    } catch (e) {
      setState(() {
        _erro = 'Erro ao carregar: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _carregarSvg() async {
    _svgContent = await DefaultAssetBundle.of(
      context,
    ).loadString('assets/images/corda.svg');
    if (mounted) setState(() {});
  }

  Future<void> _preloadGraduacoes() async {
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;

      // Primeiro tenta cache. Se vier vazio/incompleto, busca do servidor.
      snapshot = await _firestore
          .collection('graduacoes')
          .limit(100)
          .get(const GetOptions(source: Source.cache));

      if (snapshot.docs.isEmpty) {
        snapshot = await _firestore
            .collection('graduacoes')
            .limit(100)
            .get(const GetOptions(source: Source.server));
      }

      _graduacoesCache.clear();
      _svgCache.clear();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final nomeGraduacao = data['nome_graduacao']?.toString().trim();

        if (nomeGraduacao != null && nomeGraduacao.isNotEmpty) {
          _graduacoesCache[nomeGraduacao] = {
            'id': doc.id,
            'hex_cor1': data['hex_cor1'],
            'hex_cor2': data['hex_cor2'],
            'hex_ponta1': data['hex_ponta1'],
            'hex_ponta2': data['hex_ponta2'],
            'nome_graduacao': nomeGraduacao,
            'nivel_graduacao': data['nivel_graduacao'] ?? 0,
          };
        }
      }

      await _preColorirSvg();

      debugPrint(
        '✅ Dashboard: ${_graduacoesCache.length} graduações carregadas e ${_svgCache.length} SVGs coloridos',
      );
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar graduações no dashboard: $e');
    }
  }

  Future<void> _preColorirSvg() async {
    if (_svgContent == null) return;

    for (final entry in _graduacoesCache.entries) {
      final nomeGraduacao = entry.key;
      final cores = entry.value;
      final svg = _montarSvgGraduacao(cores);

      if (svg != null) {
        _svgCache['svg_$nomeGraduacao'] = svg;
      }
    }
  }

  Color _colorFromHexSeguro(dynamic hexColor) {
    if (hexColor == null) return Colors.grey;

    String hex = hexColor.toString().replaceAll('#', '').trim();

    if (hex.length == 8) {
      hex = hex.substring(2);
    }

    if (hex.length != 6) return Colors.grey;

    try {
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }

  String _colorToSvgHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toLowerCase()}';
  }

  String? _montarSvgGraduacao(Map<String, dynamic> coresGraduacao) {
    if (_svgContent == null) return null;

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      void changeColor(String id, Color color) {
        final element = document.rootElement.descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.getAttribute('id') == id,
          orElse: () => xml.XmlElement(xml.XmlName('')),
        );

        if (element.name.local.isEmpty) return;

        final hex = _colorToSvgHex(color);
        final style = element.getAttribute('style') ?? '';

        String newStyle = style
            .replaceAll(RegExp(r'fill\s*:\s*#[0-9a-fA-F]{6}\s*;?'), '')
            .trim();

        if (newStyle.isNotEmpty && !newStyle.endsWith(';')) {
          newStyle = '$newStyle;';
        }

        element.setAttribute('style', 'fill:$hex;$newStyle');
        element.setAttribute('fill', hex);
      }

      changeColor('cor1', _colorFromHexSeguro(coresGraduacao['hex_cor1']));
      changeColor('cor2', _colorFromHexSeguro(coresGraduacao['hex_cor2']));
      changeColor('corponta1', _colorFromHexSeguro(coresGraduacao['hex_ponta1']));
      changeColor('corponta2', _colorFromHexSeguro(coresGraduacao['hex_ponta2']));

      return document.toXmlString();
    } catch (e) {
      debugPrint('⚠️ Erro ao montar SVG da graduação: $e');
      return null;
    }
  }

  Future<String?> _getSvgGraduacaoPorNome(String nomeGraduacao) async {
    if (nomeGraduacao.isEmpty ||
        nomeGraduacao == 'SEM GRADUAÇÃO' ||
        _svgContent == null) {
      return null;
    }

    final cacheKey = 'svg_$nomeGraduacao';
    final svgCacheado = _svgCache[cacheKey];

    if (svgCacheado != null && svgCacheado.isNotEmpty) {
      return svgCacheado;
    }

    Map<String, dynamic>? coresGraduacao = _graduacoesCache[nomeGraduacao];

    // Se não achou no cache do dashboard, busca igual a tela de alunos/turmas.
    if (coresGraduacao == null) {
      try {
        QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
            .collection('graduacoes')
            .where('nome_graduacao', isEqualTo: nomeGraduacao)
            .limit(1)
            .get(const GetOptions(source: Source.cache));

        if (snapshot.docs.isEmpty) {
          snapshot = await _firestore
              .collection('graduacoes')
              .where('nome_graduacao', isEqualTo: nomeGraduacao)
              .limit(1)
              .get(const GetOptions(source: Source.server));
        }

        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          final data = doc.data();

          coresGraduacao = {
            'id': doc.id,
            'hex_cor1': data['hex_cor1'],
            'hex_cor2': data['hex_cor2'],
            'hex_ponta1': data['hex_ponta1'],
            'hex_ponta2': data['hex_ponta2'],
            'nome_graduacao': nomeGraduacao,
            'nivel_graduacao': data['nivel_graduacao'] ?? 0,
          };

          _graduacoesCache[nomeGraduacao] = coresGraduacao;
        }
      } catch (e) {
        debugPrint('⚠️ Erro ao buscar graduação "$nomeGraduacao": $e');
      }
    }

    if (coresGraduacao == null) return null;

    final svg = _montarSvgGraduacao(coresGraduacao);

    if (svg != null && svg.isNotEmpty) {
      _svgCache[cacheKey] = svg;
    }

    return svg;
  }

  String _obterNomeGraduacaoAluno(Map<String, dynamic> aluno) {
    final gradId = aluno['graduacao_id']?.toString();
    if (gradId != null && gradId.isNotEmpty) {
      for (var entry in _graduacoesCache.entries) {
        if (entry.value['id'] == gradId) return entry.key;
      }
    }
    final gradNome = aluno['graduacao_nome']?.toString();
    if (gradNome != null && gradNome.isNotEmpty) return gradNome;
    final gradAtual = aluno['graduacao_atual']?.toString();
    if (gradAtual != null && gradAtual.isNotEmpty) return gradAtual;
    return 'SEM GRADUAÇÃO';
  }

  int _getNivelGraduacao(String nome) {
    if (nome == 'SEM GRADUAÇÃO') return 0;
    final cache = _graduacoesCache[nome];
    if (cache != null) {
      return _parseInt(cache['nivel_graduacao']);
    }
    return 999;
  }

  Future<void> _carregarAvaliacoesAlunos() async {
    try {
      final snapshot = await _firestore
          .collection('turmas')
          .doc(widget.turmaId)
          .collection('avaliacoes_alunos')
          .get(const GetOptions(source: Source.server));

      final avaliacoes = <String, Map<String, dynamic>>{};
      for (final doc in snapshot.docs) {
        avaliacoes[doc.id] = {
          'id': doc.id,
          ...doc.data(),
        };
      }

      _avaliacoesAlunos = avaliacoes;
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar avaliações dos alunos: $e');
      _avaliacoesAlunos = {};
    }
  }

  Future<void> _carregarAlunosDaTurma() async {
    try {
      DocumentSnapshot<Map<String, dynamic>> turmaDoc;
      try {
        turmaDoc = await _firestore
            .collection('turmas')
            .doc(widget.turmaId)
            .collection('estatisticas')
            .doc('dashboard')
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        turmaDoc = await _firestore
            .collection('turmas')
            .doc(widget.turmaId)
            .collection('estatisticas')
            .doc('dashboard')
            .get();
      }
      if (!turmaDoc.exists) {
        await _criarDocumentoDashboard();
        await _carregarAlunosDaTurma();
        return;
      }
      final data = turmaDoc.data()!;
      final timestamp = data['ultima_atualizacao'] as Timestamp?;
      if (timestamp != null) _ultimaAtualizacao = timestamp.toDate();
      _ultimaSyncLogs = _toDateTime(data['ultima_sync_logs']);
      _alunosDaTurma = _parseAlunos(data['alunos']);
      anosDisponiveis = List<String>.from(data['anos_disponiveis'] ?? []);
      if (anosDisponiveis.isEmpty)
        anosDisponiveis = [DateTime.now().year.toString()];
      if (anoSelecionado == null && anosDisponiveis.isNotEmpty)
        anoSelecionado = anosDisponiveis.first;
      await _carregarAvaliacoesAlunos();
      _processarTodosDados();
      setState(() {
        _isLoading = false;
      });
      // Atualiza em segundo plano com dados reais do servidor.
      // Isso evita dashboard antigo/cacheado mostrando frequência zerada.
      Future.microtask(() {
        if (mounted) _atualizarDadosReais();
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao carregar dados';
        _isLoading = false;
      });
    }
  }

  // ============ ATUALIZAÇÃO REAL / CONTADORES FIREBASE ============
  Future<void> _atualizarDadosReais({bool recalcularTudo = false}) async {
    if (_isAtualizando) return;
    setState(() {
      _isAtualizando = true;
      _erro = null;
    });
    _rotateController.repeat();
    HapticFeedback.mediumImpact();

    try {
      final alunosSnapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .get(const GetOptions(source: Source.server));

      final alunosAtuais = alunosSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();

      //  PIKA DAS GALÁXIAS:
      // Em vez de varrer todos os logs sempre, sincroniza contadores por aluno:
      // alunos/{alunoId}/contadores/frequencia_dashboard
      // Se o contador já existe, busca só logs depois da última sincronização dele.
      // Se não existe, faz a carga completa apenas daquele aluno.
      final processados = await _sincronizarContadoresFrequenciaAlunos(
        alunosAtuais,
        forcarRecalculoCompleto: recalcularTudo,
      );

      final anosList = _extrairAnosDisponiveis(processados);
      final agora = DateTime.now();

      await _dashboardDocRef.set({
        'alunos': processados,
        'anos_disponiveis': anosList,
        'total_alunos': processados.length,
        'ultima_atualizacao': Timestamp.fromDate(agora),
        'ultima_sync_logs': Timestamp.fromDate(agora),
        'ultima_atualizacao_iso': agora.toIso8601String(),
        'cache_versao': 5,
        'modelo_cache': recalcularTudo
            ? 'contadores_por_aluno_recalculado_dos_logs_reais_v5'
            : 'contadores_por_aluno_incremental_v5',
        'recalculado_completo': recalcularTudo,
      });

      setState(() {
        _ultimaAtualizacao = agora;
        _ultimaSyncLogs = agora;
        _alunosDaTurma = processados;
        anosDisponiveis = anosList;
        if (anoSelecionado == null || !anosDisponiveis.contains(anoSelecionado)) {
          anoSelecionado = anosDisponiveis.isNotEmpty
              ? anosDisponiveis.first
              : DateTime.now().year.toString();
        }
      });

      await _preloadGraduacoes();
      await _carregarAvaliacoesAlunos();
      _processarTodosDados();
      _rotateController.stop();
      _rotateController.reset();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.speed_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recalcularTudo
                        ? '✅ ${processados.length} alunos recalculados pelos logs reais'
                        : '✅ ${processados.length} alunos sincronizados com contadores inteligentes',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      _rotateController.stop();
      _rotateController.reset();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('❌ Erro: $e')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAtualizando = false;
        });
      }
    }
  }

  DocumentReference<Map<String, dynamic>> get _dashboardDocRef => _firestore
      .collection('turmas')
      .doc(widget.turmaId)
      .collection('estatisticas')
      .doc('dashboard');

  DocumentReference<Map<String, dynamic>> _contadorAlunoRef(String alunoId) {
    return _firestore
        .collection('alunos')
        .doc(alunoId)
        .collection('contadores')
        .doc('frequencia_dashboard');
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _mesKey(DateTime data) {
    final mes = data.month.toString().padLeft(2, '0');
    return '${data.year}-$mes';
  }

  String _semanaKey(DateTime data) {
    // Mesmo padrão usado na Cloud Function com Luxon: weekYear-WweekNumber.
    // Isso evita diferença em chamadas especiais perto da virada do ano.
    final dia = DateTime(data.year, data.month, data.day);
    final quintaDaSemana = dia.add(Duration(days: 4 - dia.weekday));
    final weekYear = quintaDaSemana.year;
    final primeiraQuintaBase = DateTime(weekYear, 1, 4);
    final primeiraQuinta = primeiraQuintaBase.add(
      Duration(days: 4 - primeiraQuintaBase.weekday),
    );
    final weekNumber = 1 + (quintaDaSemana.difference(primeiraQuinta).inDays ~/ 7);
    return '$weekYear-W${weekNumber.toString().padLeft(2, '0')}';
  }

  DateTime _inicioSemanaAtual(DateTime now) {
    final inicio = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(inicio.year, inicio.month, inicio.day);
  }

  DateTime _inicioMesAtual(DateTime now) => DateTime(now.year, now.month, 1);

  Map<String, int> _parseMapStringInt(dynamic value) {
    final result = <String, int>{};
    if (value is Map) {
      value.forEach((k, v) {
        if (k != null) result[k.toString()] = _parseInt(v);
      });
    }
    return result;
  }

  Map<String, dynamic> _contadorVazio(String alunoId) {
    final now = DateTime.now();
    return {
      'aluno_id': alunoId,
      'total': 0,
      'semana': 0,
      'mes': 0,
      'porAno': <String, int>{},
      'porMes': <String, int>{},
      'porSemana': <String, int>{},
      'porDiaSemana': <String, int>{
        'seg': 0,
        'ter': 0,
        'qua': 0,
        'qui': 0,
        'sex': 0,
        'sab': 0,
        'dom': 0,
      },
      'seg': 0,
      'ter': 0,
      'qua': 0,
      'qui': 0,
      'sex': 0,
      'sab': 0,
      'dom': 0,
      'mes_key': _mesKey(now),
      'semana_key': _semanaKey(now),
      'ultima_sync_logs': null,
      'total_logs_processados': 0,
      'cache_versao': 4,
    };
  }

  Map<String, dynamic> _normalizarContador(
      String alunoId,
      Map<String, dynamic>? data,
      ) {
    final now = DateTime.now();
    final contador = _contadorVazio(alunoId);
    if (data == null) return contador;

    final mesAtual = _mesKey(now);
    final semanaAtual = _semanaKey(now);

    final porAno = _parseMapStringInt(data['porAno']);
    final porMes = _parseMapStringInt(data['porMes']);
    final porSemana = _parseMapStringInt(data['porSemana']);
    final porDiaSemana = _parseMapStringInt(data['porDiaSemana']);

    // Compatibilidade com contadores antigos que salvavam seg/ter/qua... no topo.
    for (final dia in ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom']) {
      porDiaSemana[dia] = porDiaSemana[dia] ?? _parseInt(data[dia]);
    }

    contador['total'] = _parseInt(data['total']);
    contador['porAno'] = porAno;
    contador['porMes'] = porMes;
    contador['porSemana'] = porSemana;
    contador['porDiaSemana'] = porDiaSemana;
    for (final dia in ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom']) {
      contador[dia] = porDiaSemana[dia] ?? 0;
    }

    //  Compatibilidade total:
    // - contador novo da Cloud Function: porMes / porSemana
    // - contador antigo: mes / semana
    contador['mes'] = porMes[mesAtual] ?? _parseInt(data['mes']);
    contador['semana'] = porSemana[semanaAtual] ?? _parseInt(data['semana']);

    contador['mes_key'] = mesAtual;
    contador['semana_key'] = semanaAtual;
    contador['ultima_sync_logs'] = _toDateTime(data['ultima_sync_logs']);
    contador['total_logs_processados'] = _parseInt(data['total_logs_processados']);
    contador['cache_versao'] = _parseInt(data['cache_versao']);
    return contador;
  }

  void _garantirPeriodoAtual(Map<String, dynamic> contador, DateTime now) {
    final mesAtual = _mesKey(now);
    final semanaAtual = _semanaKey(now);

    final porMes = _parseMapStringInt(contador['porMes']);
    final porSemana = _parseMapStringInt(contador['porSemana']);
    final porDiaSemana = _parseMapStringInt(contador['porDiaSemana']);

    contador['mes'] = porMes[mesAtual] ?? 0;
    contador['semana'] = porSemana[semanaAtual] ?? 0;
    contador['mes_key'] = mesAtual;
    contador['semana_key'] = semanaAtual;
    contador['porMes'] = porMes;
    contador['porSemana'] = porSemana;
    contador['porDiaSemana'] = porDiaSemana;
    for (final dia in ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom']) {
      contador[dia] = porDiaSemana[dia] ?? _parseInt(contador[dia]);
    }
  }

  bool _logEstaNoMesAtual(DateTime dataLog, DateTime now) {
    final inicio = _inicioMesAtual(now);
    final fim = DateTime(now.year, now.month + 1, 1);
    return !dataLog.isBefore(inicio) && dataLog.isBefore(fim);
  }

  bool _logEstaNaSemanaAtual(DateTime dataLog, DateTime now) {
    final inicio = _inicioSemanaAtual(now);
    return !dataLog.isBefore(inicio);
  }

  void _incrementarContadorComLog(
      Map<String, dynamic> contador,
      Map<String, dynamic> log,
      DateTime now,
      ) {
    final presente = log['presente'] == true;
    if (!presente) return;

    final dataLog = _toDateTime(log['data_aula']);
    if (dataLog == null) return;

    contador['total'] = _parseInt(contador['total']) + 1;
    contador['total_logs_processados'] =
        _parseInt(contador['total_logs_processados']) + 1;

    final porAno = _parseMapStringInt(contador['porAno']);
    final porMes = _parseMapStringInt(contador['porMes']);
    final porSemana = _parseMapStringInt(contador['porSemana']);
    final porDiaSemana = _parseMapStringInt(contador['porDiaSemana']);

    final ano = dataLog.year.toString();
    final mes = _mesKey(dataLog);
    final semana = _semanaKey(dataLog);
    final diaSemana = (log['dia_semana_abrev']?.toString().toLowerCase() ?? '').replaceAll('.', '');

    porAno[ano] = (porAno[ano] ?? 0) + 1;
    porMes[mes] = (porMes[mes] ?? 0) + 1;
    porSemana[semana] = (porSemana[semana] ?? 0) + 1;
    if (['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'].contains(diaSemana)) {
      porDiaSemana[diaSemana] = (porDiaSemana[diaSemana] ?? 0) + 1;
    }

    contador['porAno'] = porAno;
    contador['porMes'] = porMes;
    contador['porSemana'] = porSemana;
    contador['porDiaSemana'] = porDiaSemana;
    for (final dia in ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom']) {
      contador[dia] = porDiaSemana[dia] ?? 0;
    }

    final mesAtual = _mesKey(now);
    final semanaAtual = _semanaKey(now);

    contador['mes'] = porMes[mesAtual] ?? 0;
    contador['semana'] = porSemana[semanaAtual] ?? 0;
    contador['mes_key'] = mesAtual;
    contador['semana_key'] = semanaAtual;
  }

  Map<String, int> _frequenciaFromContador(Map<String, dynamic> contador) {
    final now = DateTime.now();
    final porAno = _parseMapStringInt(contador['porAno']);
    final porMes = _parseMapStringInt(contador['porMes']);
    final porSemana = _parseMapStringInt(contador['porSemana']);
    final porDiaSemana = _parseMapStringInt(contador['porDiaSemana']);
    final mesAtual = _mesKey(now);
    final semanaAtual = _semanaKey(now);

    return {
      'total': _parseInt(contador['total']),
      'semana': porSemana[semanaAtual] ?? _parseInt(contador['semana']),
      'mes': porMes[mesAtual] ?? _parseInt(contador['mes']),
      ...porAno,
      'seg': porDiaSemana['seg'] ?? _parseInt(contador['seg']),
      'ter': porDiaSemana['ter'] ?? _parseInt(contador['ter']),
      'qua': porDiaSemana['qua'] ?? _parseInt(contador['qua']),
      'qui': porDiaSemana['qui'] ?? _parseInt(contador['qui']),
      'sex': porDiaSemana['sex'] ?? _parseInt(contador['sex']),
      'sab': porDiaSemana['sab'] ?? _parseInt(contador['sab']),
      'dom': porDiaSemana['dom'] ?? _parseInt(contador['dom']),
    };
  }

  Future<Map<String, Map<String, dynamic>>> _buscarContadoresAlunos(
      List<String> idsAlunos,
      ) async {
    final result = <String, Map<String, dynamic>>{};
    if (idsAlunos.isEmpty) return result;

    // Uma leitura pequena por aluno. Bem mais leve que varrer todos os logs sempre.
    final futures = idsAlunos.map((alunoId) async {
      final doc = await _contadorAlunoRef(alunoId).get(
        const GetOptions(source: Source.server),
      );
      result[alunoId] = _normalizarContador(
        alunoId,
        doc.exists ? doc.data() : null,
      );
    });

    await Future.wait(futures);
    return result;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _buscarLogsParaContadores({
    required List<String> idsAlunos,
    required Map<String, Map<String, dynamic>> contadores,
    required bool cargaCompleta,
  }) async {
    final logsMap = <String, List<Map<String, dynamic>>>{};
    if (idsAlunos.isEmpty) return logsMap;

    for (var i = 0; i < idsAlunos.length; i += 10) {
      final end = i + 10 < idsAlunos.length ? i + 10 : idsAlunos.length;
      final batchIds = idsAlunos.sublist(i, end);

      Query<Map<String, dynamic>> query = _firestore
          .collection('log_presenca_alunos')
          .where('aluno_id', whereIn: batchIds);

      DateTime? menorUltimaSync;
      if (!cargaCompleta) {
        for (final id in batchIds) {
          final sync = contadores[id]?['ultima_sync_logs'];
          if (sync is DateTime) {
            if (menorUltimaSync == null || sync.isBefore(menorUltimaSync)) {
              menorUltimaSync = sync;
            }
          }
        }

        if (menorUltimaSync != null) {
          query = query.where(
            'data_aula',
            isGreaterThan: Timestamp.fromDate(menorUltimaSync),
          );
        }
      }

      final snapshot = await query.get(const GetOptions(source: Source.server));

      for (final doc in snapshot.docs) {
        final data = {'id': doc.id, ...doc.data()};
        final alunoId = data['aluno_id']?.toString();
        if (alunoId == null || alunoId.isEmpty) continue;

        // Na busca incremental por lote, o lote usa a menor última sync.
        // Então aqui filtramos de novo por aluno para não duplicar log de quem já estava atualizado.
        if (!cargaCompleta) {
          final syncAluno = contadores[alunoId]?['ultima_sync_logs'];
          final dataLog = _toDateTime(data['data_aula']);
          if (syncAluno is DateTime && dataLog != null && !dataLog.isAfter(syncAluno)) {
            continue;
          }
        }

        logsMap.putIfAbsent(alunoId, () => []);
        logsMap[alunoId]!.add(data);
      }
    }

    return logsMap;
  }

  Future<List<Map<String, dynamic>>> _sincronizarContadoresFrequenciaAlunos(
      List<Map<String, dynamic>> alunos, {
        bool forcarRecalculoCompleto = false,
      }) async {
    final now = DateTime.now();
    final idsAlunos = alunos
        .map((a) => a['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    final contadores = await _buscarContadoresAlunos(idsAlunos);

    final idsCargaCompleta = <String>[];
    final idsIncremental = <String>[];

    for (final alunoId in idsAlunos) {
      final contador = contadores[alunoId] ?? _contadorVazio(alunoId);
      _garantirPeriodoAtual(contador, now);
      contadores[alunoId] = contador;

      final ultimaSync = contador['ultima_sync_logs'];

      // CORREÇÃO IMPORTANTE:
      // Quando o usuário toca em atualizar/arrasta para atualizar,
      // precisa recalcular do ZERO pelos logs reais.
      // Se o contador antigo nasceu errado com 0 ou 1 presença,
      // o modo incremental nunca corrigiria o passado.
      final precisaCargaCompleta = forcarRecalculoCompleto ||
          ultimaSync == null ||
          _parseInt(contador['cache_versao']) < 5;

      if (precisaCargaCompleta) {
        idsCargaCompleta.add(alunoId);

        // Quando vai fazer carga completa, começa do zero para não duplicar.
        contadores[alunoId] = _contadorVazio(alunoId);
        _garantirPeriodoAtual(contadores[alunoId]!, now);
      } else {
        idsIncremental.add(alunoId);
      }
    }

    debugPrint(
      '📊 Dashboard ${widget.turmaNome}: ${idsCargaCompleta.length} alunos em carga completa, '
          '${idsIncremental.length} alunos incremental. Forçado: $forcarRecalculoCompleto',
    );

    final logsCargaCompleta = await _buscarLogsParaContadores(
      idsAlunos: idsCargaCompleta,
      contadores: contadores,
      cargaCompleta: true,
    );

    final logsIncrementais = await _buscarLogsParaContadores(
      idsAlunos: idsIncremental,
      contadores: contadores,
      cargaCompleta: false,
    );

    void aplicarLogs(Map<String, List<Map<String, dynamic>>> logsMap) {
      logsMap.forEach((alunoId, logs) {
        final contador = contadores[alunoId] ?? _contadorVazio(alunoId);
        _garantirPeriodoAtual(contador, now);
        for (final log in logs) {
          _incrementarContadorComLog(contador, log, now);
        }
        contadores[alunoId] = contador;
      });
    }

    aplicarLogs(logsCargaCompleta);
    aplicarLogs(logsIncrementais);

    final batch = _firestore.batch();
    for (final alunoId in idsAlunos) {
      final contador = contadores[alunoId] ?? _contadorVazio(alunoId);
      contador['ultima_sync_logs'] = now;
      contador['updatedAt'] = FieldValue.serverTimestamp();
      contador['cache_versao'] = 5;
      contador['modelo'] = forcarRecalculoCompleto
          ? 'contador_recalculado_dos_logs_reais_v5'
          : 'contador_incremental_por_aluno_v5';
      contador['recalculado_completo'] = forcarRecalculoCompleto;
      batch.set(_contadorAlunoRef(alunoId), {
        ...contador,
        'ultima_sync_logs': Timestamp.fromDate(now),
      });
    }
    await batch.commit();

    return alunos.map((aluno) {
      final alunoId = aluno['id']?.toString() ?? '';
      final contador = contadores[alunoId] ?? _contadorVazio(alunoId);
      final freq = _frequenciaFromContador(contador);
      final porDiaSemana = _parseMapStringInt(contador['porDiaSemana']);
      return {
        ...aluno,
        'frequencia_temporal': freq,
        'total_presencas': freq['total'] ?? 0,
        'porDiaSemana': porDiaSemana,
        'seg': porDiaSemana['seg'] ?? freq['seg'] ?? 0,
        'ter': porDiaSemana['ter'] ?? freq['ter'] ?? 0,
        'qua': porDiaSemana['qua'] ?? freq['qua'] ?? 0,
        'qui': porDiaSemana['qui'] ?? freq['qui'] ?? 0,
        'sex': porDiaSemana['sex'] ?? freq['sex'] ?? 0,
        'sab': porDiaSemana['sab'] ?? freq['sab'] ?? 0,
        'dom': porDiaSemana['dom'] ?? freq['dom'] ?? 0,
        'contador_frequencia_atualizado_em': Timestamp.fromDate(now),
      };
    }).toList();
  }

  List<String> _extrairAnosDisponiveis(List<Map<String, dynamic>> alunos) {
    final Set<String> anosSet = {};
    for (final a in alunos) {
      final f = a['frequencia_temporal'];
      if (f is Map) {
        f.forEach((k, v) {
          final key = k.toString();
          if (key.length == 4 && int.tryParse(key) != null && _parseInt(v) > 0) {
            anosSet.add(key);
          }
        });
      }
    }
    if (anosSet.isEmpty) anosSet.add(DateTime.now().year.toString());
    return anosSet.toList()..sort((a, b) => b.compareTo(a));
  }

  Future<void> _criarDocumentoDashboard() async {
    final alunosSnapshot = await _firestore
        .collection('alunos')
        .where('turma_id', isEqualTo: widget.turmaId)
        .get(const GetOptions(source: Source.server));

    final alunos = alunosSnapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList();

    final dados = await _sincronizarContadoresFrequenciaAlunos(alunos, forcarRecalculoCompleto: true);
    final anosList = _extrairAnosDisponiveis(dados);
    final agora = DateTime.now();

    await _dashboardDocRef.set({
      'alunos': dados,
      'anos_disponiveis': anosList,
      'ultima_atualizacao': Timestamp.fromDate(agora),
      'ultima_sync_logs': Timestamp.fromDate(agora),
      'ultima_atualizacao_iso': agora.toIso8601String(),
      'total_alunos': alunos.length,
      'cache_versao': 5,
      'modelo_cache': 'contadores_por_aluno_recalculado_dos_logs_reais_v5',
      'recalculado_completo': true,
    });
  }

  double _getNotaAvaliacaoAluno(Map<String, dynamic> aluno) {
    final alunoId = aluno['id']?.toString() ?? '';
    final avaliacao = _avaliacoesAlunos[alunoId];
    return _parseDouble(avaliacao?['nota_final']);
  }

  String _getConceitoAvaliacaoAluno(Map<String, dynamic> aluno) {
    final alunoId = aluno['id']?.toString() ?? '';
    final avaliacao = _avaliacoesAlunos[alunoId];
    return avaliacao?['conceito']?.toString() ?? 'Sem avaliação';
  }

  double _calcularScoreFrequencia(Map<String, dynamic> aluno, int maiorFrequencia) {
    if (maiorFrequencia <= 0) return 0;
    final freq = _getFrequenciaPorFiltro(aluno);
    return ((freq / maiorFrequencia) * 10).clamp(0.0, 10.0);
  }

  double _calcularNotaDestaque({
    required double notaAvaliacao,
    required double scoreFrequencia,
  }) {
    // Na capoeira, disciplina/comportamento/evolução precisam pesar mais
    // do que só presença. Por isso: 60% avaliação + 40% frequência.
    return ((notaAvaliacao * 0.60) + (scoreFrequencia * 0.40)).clamp(0.0, 10.0);
  }

  Color _corNotaDestaque(double nota) {
    if (nota >= 9) return Colors.green.shade800;
    if (nota >= 8) return Colors.lightGreen.shade700;
    if (nota >= 7) return Colors.blue.shade700;
    if (nota >= 6) return Colors.orange.shade800;
    return Colors.red.shade800;
  }

  String _conceitoDestaque(double nota) {
    if (nota >= 9) return 'Destaque máximo';
    if (nota >= 8) return 'Muito destaque';
    if (nota >= 7) return 'Bom destaque';
    if (nota >= 6) return 'Em evolução';
    return 'Precisa acompanhar';
  }

  void _processarTodosDados() {
    final now = DateTime.now();
    _alunosOrdenadosPorFrequencia =
    List<Map<String, dynamic>>.from(_alunosDaTurma)..sort(
          (a, b) =>
          _getFrequenciaPorFiltro(b).compareTo(_getFrequenciaPorFiltro(a)),
    );
    _alunosFrequentes = _alunosOrdenadosPorFrequencia.take(5).toList();

    final maiorFrequencia = _alunosDaTurma.isEmpty
        ? 0
        : _alunosDaTurma
        .map((a) => _getFrequenciaPorFiltro(a))
        .fold<int>(0, (maior, valor) => valor > maior ? valor : maior);

    _alunosDestaque = _alunosDaTurma.map((aluno) {
      final notaAvaliacao = _getNotaAvaliacaoAluno(aluno);
      final scoreFrequencia = _calcularScoreFrequencia(aluno, maiorFrequencia);
      final notaDestaque = _calcularNotaDestaque(
        notaAvaliacao: notaAvaliacao,
        scoreFrequencia: scoreFrequencia,
      );

      return {
        ...aluno,
        'nota_avaliacao': notaAvaliacao,
        'score_frequencia': scoreFrequencia,
        'nota_destaque': notaDestaque,
        'conceito_destaque': _conceitoDestaque(notaDestaque),
        'conceito_avaliacao': _getConceitoAvaliacaoAluno(aluno),
      };
    }).toList()
      ..sort((a, b) => _parseDouble(b['nota_destaque']).compareTo(_parseDouble(a['nota_destaque'])));

    final Map<String, int> distGrad = {};
    final Map<String, List<Map<String, dynamic>>> alunosPorGrad = {};
    for (var aluno in _alunosDaTurma) {
      String nome = _obterNomeGraduacaoAluno(aluno);
      if (nome.isEmpty) nome = 'SEM GRADUAÇÃO';
      distGrad[nome] = (distGrad[nome] ?? 0) + 1;
      alunosPorGrad.putIfAbsent(nome, () => []).add(aluno);
    }
    _distribuicaoGraduacao = distGrad;
    _alunosPorGraduacao = alunosPorGrad;

    final Map<String, int> faixas = Map.from(_faixasEtarias);
    final List<Map<String, dynamic>> alunosComIdade = [];
    for (var aluno in _alunosDaTurma) {
      final dataNasc = (aluno['data_nascimento'] as Timestamp?)?.toDate();
      if (dataNasc != null) {
        int idade = now.year - dataNasc.year;
        if (now.month < dataNasc.month ||
            (now.month == dataNasc.month && now.day < dataNasc.day))
          idade--;
        final a = Map<String, dynamic>.from(aluno);
        a['idade_calculada'] = idade;
        alunosComIdade.add(a);
        if (idade <= 7)
          faixas['4-7 anos'] = faixas['4-7 anos']! + 1;
        else if (idade <= 12)
          faixas['8-12 anos'] = faixas['8-12 anos']! + 1;
        else if (idade <= 17)
          faixas['13-17 anos'] = faixas['13-17 anos']! + 1;
        else if (idade <= 25)
          faixas['18-25 anos'] = faixas['18-25 anos']! + 1;
        else if (idade <= 35)
          faixas['26-35 anos'] = faixas['26-35 anos']! + 1;
        else if (idade <= 50)
          faixas['36-50 anos'] = faixas['36-50 anos']! + 1;
        else
          faixas['50+ anos'] = faixas['50+ anos']! + 1;
      }
    }
    alunosComIdade.sort(
          (a, b) =>
          (a['idade_calculada'] ?? 0).compareTo(b['idade_calculada'] ?? 0),
    );
    _alunosOrdenadosPorIdade = alunosComIdade;
    _distribuicaoIdade = faixas;
    _totalMeninos = _alunosDaTurma
        .where((a) => (a['sexo'] as String?)?.toUpperCase() == 'MASCULINO')
        .length;
    _totalMeninas = _alunosDaTurma
        .where((a) => (a['sexo'] as String?)?.toUpperCase() == 'FEMININO')
        .length;
  }

  int _getFrequenciaPorFiltro(Map<String, dynamic> aluno) {
    final freqData = aluno['frequencia_temporal'];
    if (freqData == null || freqData is! Map) return 0;
    final Map<String, int> freqMap = {};
    freqData.forEach((k, v) {
      if (k is String) freqMap[k] = _parseInt(v);
    });
    switch (filtroTemporalFrequencia) {
      case 'Semana':
        return freqMap['semana'] ?? 0;
      case 'Mês':
        return freqMap['mes'] ?? 0;
      case 'Ano':
        return anoSelecionado != null
            ? (freqMap[anoSelecionado!] ?? 0)
            : (freqMap['total'] ?? 0);
      case 'Total':
        return freqMap['total'] ?? 0;
      default:
        return 0;
    }
  }

  void _atualizarComFiltro() {
    setState(() {
      _processarTodosDados();
    });
  }

  Color _hexToColor(String hex) {
    if (_colorCache.containsKey(hex)) return _colorCache[hex]!;
    String clean = hex.replaceFirst('#', '');
    Color color = Colors.grey;
    if (clean.length == 6)
      color = Color(int.parse('FF$clean', radix: 16));
    else if (clean.length == 8)
      color = Color(int.parse(clean, radix: 16));
    _colorCache[hex] = color;
    return color;
  }

  Color _corTextoContraste(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.55 ? Colors.grey.shade900 : Colors.white;
  }

  Color _corTextoContrasteSuave(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.55 ? Colors.grey.shade800 : Colors.white.withOpacity(0.92);
  }

  Color _corTextoChipQuantidade(Color corBase) {
    // O chip da quantidade fica em cima de fundo branco/claro.
    // Mesmo que a corda seja escura, o fundo do chip usa opacity baixa,
    // então texto branco fica ruim. Por isso aqui forçamos uma cor escura.
    if (corBase.computeLuminance() > 0.70) {
      return Colors.grey.shade900;
    }

    return Colors.grey.shade900;
  }

  Color _corFundoChipQuantidade(Color corBase) {
    if (corBase.computeLuminance() > 0.70) {
      return Colors.grey.shade100;
    }

    return corBase.withOpacity(0.14);
  }

  Color _corBordaChipQuantidade(Color corBase) {
    if (corBase.computeLuminance() > 0.70) {
      return Colors.grey.shade300;
    }

    return corBase.withOpacity(0.26);
  }

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.turmaNome,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              'Dashboard de Desempenho',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_ultimaAtualizacao != null && !_isAtualizando)
            _buildCacheIndicator(),
          Stack(
            alignment: Alignment.center,
            children: [
              if (!_isAtualizando)
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => _atualizarDadosReais(recalcularTudo: true),
                  tooltip: 'Forçar recálculo pelos logs reais',
                ),
              if (_isAtualizando)
                RotationTransition(
                  turns: _rotateAnimation,
                  child: const Icon(Icons.sync_rounded, color: Colors.white),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // O resumo da turma agora fica dentro da aba Frequência,
          // deixando a barra de abas sempre no topo.

          Expanded(
            child: _isLoading
                ? _buildShimmerLoading()
                : _erro != null
                ? _buildErroScreen()
                : _alunosDaTurma.isEmpty
                ? _buildEmptyScreen()
                : _buildConteudoPrincipal(),
          ),
        ],
      ),
    );
  }

  Widget _buildCacheIndicator() {
    final agora = DateTime.now();
    final diferenca = agora.difference(_ultimaAtualizacao!);
    final minutosRestantes = _CACHE_VALIDADE_MINUTOS - diferenca.inMinutes;
    Color cor = minutosRestantes <= 0
        ? Colors.red
        : (minutosRestantes < 30 ? Colors.orange : Colors.green);
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time, size: 12, color: cor),
          const SizedBox(width: 4),
          Text(
            minutosRestantes <= 0 ? 'Exp' : '${minutosRestantes}m',
            style: TextStyle(
              fontSize: 10,
              color: cor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMetricas() {
    final totalAlunos = _alunosDaTurma.length;
    final soma = _alunosDaTurma.fold<int>(
      0,
          (sum, a) => sum + _getFrequenciaPorFiltro(a),
    );
    final media = totalAlunos > 0 ? (soma / totalAlunos) : 0.0;
    final melhor = _alunosFrequentes.isNotEmpty ? _alunosFrequentes.first : null;
    final melhorValor = melhor != null ? _getFrequenciaPorFiltro(melhor) : 0;
    final filtroLabel = filtroTemporalFrequencia == 'Ano' && anoSelecionado != null
        ? anoSelecionado!
        : filtroTemporalFrequencia;

    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.red.shade900,
            Colors.red.shade700,
            Colors.deepPurple.shade700,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.dashboard_customize_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resumo da turma',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Filtro atual: $filtroLabel',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.78),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isAtualizando)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        SizedBox(width: 6),
                        Text('Sync', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _metricHeader(Icons.people_alt_rounded, '$totalAlunos', 'Alunos', Colors.white)),
                const SizedBox(width: 8),
                Expanded(child: _metricHeader(Icons.trending_up_rounded, media.toStringAsFixed(1), 'Média', Colors.amber)),
                const SizedBox(width: 8),
                Expanded(child: _metricHeader(Icons.emoji_events_rounded, melhor?['nome']?.toString().split(' ').first ?? '-', '$melhorValor pres.', Colors.orange)),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: totalAlunos > 0 ? (media / 100).clamp(0.0, 1.0) : 0,
                backgroundColor: Colors.white.withOpacity(0.18),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricHeader(IconData icon, String valor, String label, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Icon(icon, color: cor, size: 24),
          const SizedBox(height: 6),
          Text(
            valor,
            style: TextStyle(
              color: cor,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _selecionarFiltroDashboard(String titulo) {
    if (filtroAtivo == titulo) {
      _centralizarAbaSelecionada(titulo);
      return;
    }

    setState(() {
      filtroAtivo = titulo;
      _visibleItems = 20;
      if (titulo != 'Sexo') filtroSexo = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centralizarAbaSelecionada(titulo);
    });
  }

  void _agendarCentralizacaoAbaInicial() {
    if (_centralizouAbaInicial) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _centralizouAbaInicial) return;

      await Future.delayed(const Duration(milliseconds: 160));
      if (!mounted || _centralizouAbaInicial) return;

      _centralizarAbaSelecionada(filtroAtivo, imediato: true);

      await Future.delayed(const Duration(milliseconds: 260));
      if (!mounted || _centralizouAbaInicial) return;

      _centralizarAbaSelecionada(filtroAtivo, imediato: true);
      _centralizouAbaInicial = true;
    });
  }

  void _centralizarAbaSelecionada(String titulo, {bool imediato = false}) {
    final key = _tabKeys[titulo];
    final contextAba = key?.currentContext;

    if (contextAba == null || !_tabsScrollController.hasClients) return;

    final renderObject = contextAba.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final itemSize = renderObject.size;
    final itemOffsetGlobal = renderObject.localToGlobal(Offset.zero);

    final viewportWidth = MediaQuery.of(context).size.width;
    final itemCenterGlobal = itemOffsetGlobal.dx + (itemSize.width / 2);
    final screenCenter = viewportWidth / 2;

    final currentOffset = _tabsScrollController.offset;
    final desiredOffset = currentOffset + (itemCenterGlobal - screenCenter);

    final min = _tabsScrollController.position.minScrollExtent;
    final max = _tabsScrollController.position.maxScrollExtent;
    final target = desiredOffset.clamp(min, max).toDouble();

    if ((target - currentOffset).abs() < 0.5) return;

    if (imediato) {
      _tabsScrollController.jumpTo(target);
    } else {
      _tabsScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _buildConteudoPrincipal() {
    _agendarCentralizacaoAbaInicial();

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.025),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: SingleChildScrollView(
            controller: _tabsScrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                const SizedBox(width: 12),
                _filtroChip('Aluno Destaque', Icons.emoji_events_rounded, Colors.amber.shade800),
                _filtroChip('Frequência', Icons.trending_up, Colors.blue),
                _filtroChip(
                  'Graduação',
                  Icons.workspace_premium,
                  Colors.purple,
                ),
                _filtroChip('Idade', Icons.cake, Colors.green),
                _filtroChip('Sexo', Icons.people, Colors.pink),
                SizedBox(width: MediaQuery.of(context).size.width * 0.28),
              ],
            ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey(filtroAtivo),
              child: _buildConteudoPorFiltro(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _filtroChip(String titulo, IconData icon, Color cor) {
    final ativo = filtroAtivo == titulo;

    return Padding(
      key: _tabKeys[titulo],
      padding: const EdgeInsets.only(right: 6),
      child: AnimatedScale(
        scale: ativo ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: ChoiceChip(
          avatar: Icon(icon, size: 16, color: ativo ? Colors.white : cor),
          label: Text(
            titulo,
            style: TextStyle(
              fontSize: ativo ? 12.5 : 12,
              fontWeight: ativo ? FontWeight.w900 : FontWeight.w700,
              color: ativo ? Colors.white : Colors.grey.shade700,
            ),
          ),
          selected: ativo,
          onSelected: (s) {
            if (s) _selecionarFiltroDashboard(titulo);
          },
          backgroundColor: Colors.grey.shade100,
          selectedColor: cor,
          elevation: ativo ? 4 : 0,
          shadowColor: cor.withOpacity(0.30),
          selectedShadowColor: cor.withOpacity(0.34),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: ativo ? cor.withOpacity(0.05) : Colors.grey.shade200,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConteudoPorFiltro() {
    switch (filtroAtivo) {
      case 'Frequência':
        return _buildAbaFrequencia();
      case 'Graduação':
        return _buildAbaGraduacao();
      case 'Idade':
        return _buildAbaIdade();
      case 'Sexo':
        return _buildAbaSexo();
      case 'Aluno Destaque':
        return _buildAbaAlunoDestaque();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAbaFrequencia() => RefreshIndicator(
    onRefresh: () => _atualizarDadosReais(recalcularTudo: true),
    color: Colors.blue,
    child: SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildHeaderMetricas(),
          const SizedBox(height: 14),
          _buildFiltroTemporal(),
          _buildGraficoFrequencia(),
          const SizedBox(height: 20),
          _buildListaTop5(),
          const SizedBox(height: 20),
          _buildListaCompleta(),
        ],
      ),
    ),
  );

  Widget _buildAbaGraduacao() => RefreshIndicator(
    onRefresh: () => _atualizarDadosReais(recalcularTudo: true),
    color: Colors.purple,
    child: SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: _buildGraficoGraduacao(),
    ),
  );

  Widget _buildAbaIdade() => RefreshIndicator(
    onRefresh: () => _atualizarDadosReais(recalcularTudo: true),
    color: Colors.green,
    child: SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: _buildGraficoIdade(),
    ),
  );

  Widget _buildAbaSexo() => RefreshIndicator(
    onRefresh: () => _atualizarDadosReais(recalcularTudo: true),
    color: Colors.pink,
    child: SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: _buildFiltroSexo(),
    ),
  );


  String _periodoAtualDestaqueLabel() {
    switch (filtroTemporalFrequencia) {
      case 'Semana':
        return 'Período: últimos 7 dias';
      case 'Mês':
        return 'Período: ${DateFormat('MMMM yyyy', 'pt_BR').format(DateTime.now())}';
      case 'Ano':
        return 'Período: ${anoSelecionado ?? DateTime.now().year.toString()}';
      case 'Total':
      default:
        return 'Período: histórico completo';
    }
  }

  String _nomeCurtoAlunoDestaque(Map<String, dynamic> aluno) {
    final nome = (aluno['nome']?.toString() ?? 'Aluno').trim();
    if (nome.isEmpty) return 'Aluno';
    final partes = nome.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (partes.length == 1) return partes.first;
    if (partes.length == 2) return '${partes.first} ${partes.last}';
    return '${partes.first} ${partes[1]}';
  }

  String _iniciaisAlunoDestaque(Map<String, dynamic> aluno) {
    final nome = (aluno['nome']?.toString() ?? 'Aluno').trim();
    if (nome.isEmpty) return 'A';
    final partes = nome.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
    return '${partes.first.substring(0, 1)}${partes.last.substring(0, 1)}'.toUpperCase();
  }

  Future<ui.Image?> _carregarLogoRanking() async {
    try {
      final data = await rootBundle.load('assets/images/logo_uai.png');
      final bytes = data.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar logo do ranking: $e');
      return null;
    }
  }

  Size _drawCanvasText(
      Canvas canvas,
      String text, {
        required double x,
        required double y,
        required double maxWidth,
        Color color = Colors.black,
        double fontSize = 22,
        FontWeight fontWeight = FontWeight.w600,
        TextAlign textAlign = TextAlign.left,
        int? maxLines,
      }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.15,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: textAlign,
      maxLines: maxLines,
      ellipsis: '…',
    );
    painter.layout(maxWidth: maxWidth);
    painter.paint(canvas, Offset(x, y));
    return painter.size;
  }

  void _drawImageContain(
      Canvas canvas,
      ui.Image image,
      Rect dst, {
        double borderRadius = 0,
      }) {
    final srcSize = Size(image.width.toDouble(), image.height.toDouble());
    final dstSize = dst.size;

    final scale = math.min(dstSize.width / srcSize.width, dstSize.height / srcSize.height);
    final fittedWidth = srcSize.width * scale;
    final fittedHeight = srcSize.height * scale;

    final fittedDst = Rect.fromLTWH(
      dst.left + (dst.width - fittedWidth) / 2,
      dst.top + (dst.height - fittedHeight) / 2,
      fittedWidth,
      fittedHeight,
    );

    if (borderRadius > 0) {
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(dst, Radius.circular(borderRadius)));
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        fittedDst,
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
    } else {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        fittedDst,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
  }

  void _drawImageCover(
      Canvas canvas,
      ui.Image image,
      Rect dst, {
        double borderRadius = 0,
      }) {
    final srcSize = Size(image.width.toDouble(), image.height.toDouble());
    final dstSize = dst.size;

    final scale = math.max(dstSize.width / srcSize.width, dstSize.height / srcSize.height);
    final cropWidth = dstSize.width / scale;
    final cropHeight = dstSize.height / scale;

    final src = Rect.fromLTWH(
      (srcSize.width - cropWidth) / 2,
      (srcSize.height - cropHeight) / 2,
      cropWidth,
      cropHeight,
    );

    canvas.save();
    if (borderRadius > 0) {
      canvas.clipRRect(RRect.fromRectAndRadius(dst, Radius.circular(borderRadius)));
    } else {
      canvas.clipRect(dst);
    }

    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  Future<ui.Image?> _carregarFotoAlunoRanking(String? url) async {
    if (url == null || url.trim().isEmpty || !url.startsWith('http')) return null;

    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }

      final bytes = builder.takeBytes();
      if (bytes.isEmpty) return null;

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      debugPrint('⚠️ Foto do aluno não carregou no ranking: $e');
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  Future<Map<String, ui.Image?>> _precarregarFotosRanking(
      List<Map<String, dynamic>> alunos,
      ) async {
    final result = <String, ui.Image?>{};

    for (final aluno in alunos) {
      final id = aluno['id']?.toString() ?? aluno['nome']?.toString() ?? UniqueKey().toString();
      final url = aluno['foto_perfil_aluno']?.toString() ??
          aluno['aluno_foto']?.toString() ??
          aluno['foto_url']?.toString();

      result[id] = await _carregarFotoAlunoRanking(url);
    }

    return result;
  }

  void _drawAvatarRanking(
      Canvas canvas,
      Map<String, dynamic> aluno, {
        required Offset center,
        required double radius,
        required Color backgroundColor,
        required Color textColor,
        required Map<String, ui.Image?> fotos,
        double borderWidth = 5,
        Color borderColor = Colors.white,
      }) {
    final id = aluno['id']?.toString() ?? aluno['nome']?.toString() ?? '';
    final foto = fotos[id];

    canvas.drawCircle(center, radius + borderWidth, Paint()..color = borderColor);
    canvas.drawCircle(center, radius, Paint()..color = backgroundColor);

    if (foto != null) {
      final dst = Rect.fromCircle(center: center, radius: radius);
      final srcSize = Size(foto.width.toDouble(), foto.height.toDouble());
      final dstSize = dst.size;

      // Cover proporcional: corta o excesso sem distorcer o rosto.
      final scale = math.max(
        dstSize.width / srcSize.width,
        dstSize.height / srcSize.height,
      );
      final cropWidth = dstSize.width / scale;
      final cropHeight = dstSize.height / scale;

      final src = Rect.fromLTWH(
        (srcSize.width - cropWidth) / 2,
        (srcSize.height - cropHeight) / 2,
        cropWidth,
        cropHeight,
      );

      canvas.save();
      final clip = Path()..addOval(dst);
      canvas.clipPath(clip);
      canvas.drawImageRect(
        foto,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.high
          ..isAntiAlias = true,
      );
      canvas.restore();

      canvas.drawCircle(
        center,
        radius + (borderWidth / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..color = borderColor,
      );
      return;
    }

    _drawCanvasText(
      canvas,
      _iniciaisAlunoDestaque(aluno),
      x: center.dx - radius,
      y: center.dy - (radius * 0.40),
      maxWidth: radius * 2,
      color: textColor,
      fontSize: radius * 0.62,
      fontWeight: FontWeight.w900,
      textAlign: TextAlign.center,
      maxLines: 1,
    );
  }

  String _canvasTextoTiposAula(
      Map<String, int> tipos, {
        int maxTipos = 6,
      }) {
    if (tipos.isEmpty) return 'Nenhuma aula encontrada no período';

    final ordenados = tipos.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final principais = ordenados
        .take(maxTipos)
        .map((e) => '${e.key}: ${e.value}')
        .toList();

    final restantes = ordenados.skip(maxTipos).fold<int>(0, (soma, e) => soma + e.value);
    if (restantes > 0) {
      principais.add('Outros: $restantes');
    }

    return principais.join('  |  ');
  }

  int _canvasTotalTiposAula(Map<String, int> tipos) {
    return tipos.values.fold<int>(0, (soma, valor) => soma + valor);
  }

  void _drawCanvasTiposAulaBox(
      Canvas canvas,
      Map<String, int> tipos, {
        required Rect rect,
        double fontSize = 12,
      }) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(18));

    canvas.drawRRect(
      rrect,
      Paint()..color = const Color(0xFFF0FDF4),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF86EFAC),
    );

    final total = _canvasTotalTiposAula(tipos);

    _drawCanvasText(
      canvas,
      total > 0 ? 'AULAS POR TIPO • TOTAL: $total' : 'AULAS POR TIPO',
      x: rect.left + 14,
      y: rect.top + 9,
      maxWidth: rect.width - 28,
      color: const Color(0xFF166534),
      fontSize: fontSize - 2,
      fontWeight: FontWeight.w900,
      maxLines: 1,
    );

    _drawCanvasText(
      canvas,
      _canvasTextoTiposAula(tipos),
      x: rect.left + 14,
      y: rect.top + 30,
      maxWidth: rect.width - 28,
      color: const Color(0xFF14532D),
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      maxLines: 2,
    );
  }

  void _drawCanvasInfoLinha(
      Canvas canvas,
      List<String> itens, {
        required double x,
        required double y,
        required double fontSize,
        required Color color,
      }) {
    double currentX = x;

    for (var i = 0; i < itens.length; i++) {
      if (i > 0) {
        canvas.drawCircle(
          Offset(currentX + 8, y + (fontSize * 0.62)),
          fontSize * 0.16,
          Paint()..color = const Color(0xFF9CA3AF),
        );
        currentX += 22;
      }

      final size = _drawCanvasText(
        canvas,
        itens[i],
        x: currentX,
        y: y,
        maxWidth: 260,
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        maxLines: 1,
      );

      currentX += size.width + 8;
    }
  }

  Future<Uint8List> _gerarImagemRankingAlunoDestaque() async {
    final top10 = _alunosDestaque.take(10).toList();
    final top3 = top10.take(3).toList();
    final demais = top10.length > 3
        ? top10.sublist(3, top10.length)
        : <Map<String, dynamic>>[];

    final fotos = await _precarregarFotosRanking(top10);
    _tiposAulaPdfCache = await _buscarTiposAulaPorAlunoRanking(top10);
    debugPrint('🖼️ Imagem Top10: tipos por aluno = ${_tiposAulaPdfCache.length}');

    const double width = 1080;
    const double height = 1900;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFF8FAFC),
          Color(0xFFFFF7ED),
          Color(0xFFFDF2F8),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(const Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), bgPaint);

    canvas.drawCircle(
      const Offset(95, 110),
      140,
      Paint()..color = const Color(0xFFB91C1C).withOpacity(0.045),
    );
    canvas.drawCircle(
      const Offset(width - 110, 250),
      170,
      Paint()..color = const Color(0xFFF59E0B).withOpacity(0.075),
    );
    canvas.drawCircle(
      const Offset(width - 120, height - 150),
      140,
      Paint()..color = const Color(0xFF7C3AED).withOpacity(0.045),
    );

    final mainCard = RRect.fromRectAndRadius(
      const Rect.fromLTWH(42, 42, width - 84, height - 84),
      const Radius.circular(48),
    );
    canvas.drawRRect(mainCard, Paint()..color = Colors.white.withOpacity(0.96));
    canvas.drawRRect(
      mainCard,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFE5E7EB),
    );

    final logo = await _carregarLogoRanking();
    final logoBox = RRect.fromRectAndRadius(
      const Rect.fromLTWH(82, 78, 150, 118),
      const Radius.circular(26),
    );
    canvas.drawRRect(logoBox, Paint()..color = const Color(0xFFFAFAFA));
    canvas.drawRRect(
      logoBox,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFE5E7EB),
    );

    if (logo != null) {
      _drawImageContain(
        canvas,
        logo,
        const Rect.fromLTWH(98, 92, 118, 90),
        borderRadius: 18,
      );
    } else {
      _drawCanvasText(
        canvas,
        'UAI',
        x: 102,
        y: 118,
        maxWidth: 110,
        color: const Color(0xFF991B1B),
        fontSize: 30,
        fontWeight: FontWeight.w900,
        textAlign: TextAlign.center,
        maxLines: 1,
      );
    }

    _drawCanvasText(
      canvas,
      'RANKING ALUNO DESTAQUE',
      x: 260,
      y: 78,
      maxWidth: 720,
      color: const Color(0xFF111827),
      fontSize: 40,
      fontWeight: FontWeight.w900,
      maxLines: 1,
    );

    _drawCanvasText(
      canvas,
      widget.turmaNome.toUpperCase(),
      x: 262,
      y: 128,
      maxWidth: 700,
      color: const Color(0xFF6B7280),
      fontSize: 20,
      fontWeight: FontWeight.w800,
      maxLines: 1,
    );

    final periodoBox = RRect.fromRectAndRadius(
      const Rect.fromLTWH(260, 166, 520, 42),
      const Radius.circular(21),
    );
    canvas.drawRRect(periodoBox, Paint()..color = const Color(0xFFF3F4F6));
    _drawCanvasText(
      canvas,
      _periodoAtualDestaqueLabel(),
      x: 280,
      y: 177,
      maxWidth: 480,
      color: const Color(0xFF374151),
      fontSize: 16,
      fontWeight: FontWeight.w800,
      textAlign: TextAlign.center,
      maxLines: 1,
    );

    final formulaBox = RRect.fromRectAndRadius(
      const Rect.fromLTWH(790, 166, 190, 42),
      const Radius.circular(21),
    );
    canvas.drawRRect(formulaBox, Paint()..color = const Color(0xFFFFF7ED));
    _drawCanvasText(
      canvas,
      '60% + 40%',
      x: 808,
      y: 177,
      maxWidth: 154,
      color: const Color(0xFF9A3412),
      fontSize: 17,
      fontWeight: FontWeight.w900,
      textAlign: TextAlign.center,
      maxLines: 1,
    );

    final criteriosCard = RRect.fromRectAndRadius(
      const Rect.fromLTWH(82, 236, width - 164, 194),
      const Radius.circular(30),
    );
    canvas.drawRRect(criteriosCard, Paint()..color = const Color(0xFFF9FAFB));
    canvas.drawRRect(
      criteriosCard,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFE5E7EB),
    );

    _drawCanvasText(
      canvas,
      'Critérios avaliados',
      x: 112,
      y: 262,
      maxWidth: 430,
      color: const Color(0xFF111827),
      fontSize: 24,
      fontWeight: FontWeight.w900,
      maxLines: 1,
    );

    _drawCanvasText(
      canvas,
      'Nota destaque: comportamento, disciplina, evolução e frequência',
      x: 112,
      y: 296,
      maxWidth: width - 224,
      color: const Color(0xFF6B7280),
      fontSize: 15,
      fontWeight: FontWeight.w700,
      maxLines: 1,
    );

    final criterios = [
      'Comportamento',
      'Casa',
      'Respeito',
      'Disciplina',
      'Participação',
      'Atenção',
      'Pontualidade',
      'Evolução técnica',
      'Ginga',
      'Musicalidade',
      'Instrumentos',
    ];

    double chipX = 112;
    double chipY = 332;
    for (final criterio in criterios) {
      final chipWidth = (criterio.length * 8.8 + 34).clamp(78.0, 190.0);
      if (chipX + chipWidth > width - 112) {
        chipX = 112;
        chipY += 38;
      }

      final chip = RRect.fromRectAndRadius(
        Rect.fromLTWH(chipX, chipY, chipWidth, 28),
        const Radius.circular(14),
      );
      canvas.drawRRect(chip, Paint()..color = Colors.white);
      canvas.drawRRect(
        chip,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFE5E7EB),
      );

      canvas.drawCircle(
        Offset(chipX + 15, chipY + 14),
        4.2,
        Paint()..color = const Color(0xFFB91C1C),
      );

      _drawCanvasText(
        canvas,
        criterio,
        x: chipX + 25,
        y: chipY + 7,
        maxWidth: chipWidth - 32,
        color: const Color(0xFF374151),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        maxLines: 1,
      );

      chipX += chipWidth + 8;
    }

    _drawCanvasText(
      canvas,
      'Top 3 da turma',
      x: 82,
      y: 470,
      maxWidth: 420,
      color: const Color(0xFF111827),
      fontSize: 32,
      fontWeight: FontWeight.w900,
      maxLines: 1,
    );

    if (top3.isNotEmpty) {
      final aluno = top3[0];
      final nota = _parseDouble(aluno['nota_destaque']);
      final aval = _parseDouble(aluno['nota_avaliacao']);
      final scoreFreq = _parseDouble(aluno['score_frequencia']);
      final pres = _getFrequenciaPorFiltro(aluno);

      final champ = RRect.fromRectAndRadius(
        const Rect.fromLTWH(82, 526, width - 164, 228),
        const Radius.circular(36),
      );
      canvas.drawRRect(champ, Paint()..color = const Color(0xFFFFFBEB));
      canvas.drawRRect(
        champ,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = const Color(0xFFF59E0B).withOpacity(0.38),
      );

      canvas.drawCircle(const Offset(124, 570), 22, Paint()..color = const Color(0xFFF59E0B));
      _drawCanvasText(
        canvas,
        '1',
        x: 107,
        y: 558,
        maxWidth: 34,
        color: Colors.white,
        fontSize: 17.0,
        fontWeight: FontWeight.w900,
        textAlign: TextAlign.center,
        maxLines: 1,
      );

      _drawAvatarRanking(
        canvas,
        aluno,
        center: const Offset(194, 640),
        radius: 70,
        backgroundColor: Colors.white,
        textColor: const Color(0xFF92400E),
        borderColor: Colors.white,
        borderWidth: 8,
        fotos: fotos,
      );

      _drawCanvasText(
        canvas,
        'CAMPEÃO DO RANKING',
        x: 286,
        y: 558,
        maxWidth: 470,
        color: const Color(0xFF92400E),
        fontSize: 23,
        fontWeight: FontWeight.w900,
        maxLines: 1,
      );

      _drawCanvasText(
        canvas,
        _nomeCurtoAlunoDestaque(aluno).toUpperCase(),
        x: 286,
        y: 598,
        maxWidth: 462,
        color: const Color(0xFF111827),
        fontSize: 31,
        fontWeight: FontWeight.w900,
        maxLines: 2,
      );

      _drawCanvasInfoLinha(
        canvas,
        [
          'Aval. ${aval.toStringAsFixed(1)}',
          'Freq. ${scoreFreq.toStringAsFixed(1)}',
          'Pres. $pres',
        ],
        x: 288,
        y: 695,
        fontSize: 18,
        color: const Color(0xFF4B5563),
      );

      _drawCanvasTiposAulaBox(
        canvas,
        _tiposAulaDoAlunoPdf(aluno),
        rect: const Rect.fromLTWH(650, 604, 250, 86),
        fontSize: 13,
      );

      final scoreBox = RRect.fromRectAndRadius(
        const Rect.fromLTWH(width - 252, 590, 124, 104),
        const Radius.circular(28),
      );
      canvas.drawRRect(scoreBox, Paint()..color = Colors.white);
      canvas.drawRRect(
        scoreBox,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFFFDE68A),
      );

      _drawCanvasText(
        canvas,
        nota.toStringAsFixed(1),
        x: width - 238,
        y: 606,
        maxWidth: 96,
        color: const Color(0xFF92400E),
        fontSize: 41,
        fontWeight: FontWeight.w900,
        textAlign: TextAlign.center,
        maxLines: 1,
      );
      _drawCanvasText(
        canvas,
        'NOTA',
        x: width - 238,
        y: 660,
        maxWidth: 96,
        color: const Color(0xFF92400E),
        fontSize: 14,
        fontWeight: FontWeight.w900,
        textAlign: TextAlign.center,
        maxLines: 1,
      );
    }

    final sideCards = [
      {
        'index': 1,
        'left': 82.0,
        'color': const Color(0xFFEFF6FF),
        'accent': const Color(0xFF1D4ED8),
        'rank': '2',
        'label': 'VICE-DESTAQUE',
      },
      {
        'index': 2,
        'left': 552.0,
        'color': const Color(0xFFFFF7ED),
        'accent': const Color(0xFF9A3412),
        'rank': '3',
        'label': 'TERCEIRO LUGAR',
      },
    ];

    for (final data in sideCards) {
      final idx = data['index'] as int;
      if (idx >= top3.length) continue;

      final aluno = top3[idx];
      final left = data['left'] as double;
      const top = 786.0;
      final bg = data['color'] as Color;
      final accent = data['accent'] as Color;
      final rank = data['rank'] as String;
      final label = data['label'] as String;
      final nota = _parseDouble(aluno['nota_destaque']);
      final aval = _parseDouble(aluno['nota_avaliacao']);
      final pres = _getFrequenciaPorFiltro(aluno);

      final card = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, 446, 294),
        const Radius.circular(34),
      );
      canvas.drawRRect(card, Paint()..color = bg);
      canvas.drawRRect(
        card,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = accent.withOpacity(0.20),
      );

      final rankBox = RRect.fromRectAndRadius(
        Rect.fromLTWH(left + 26, top + 24, 58, 36),
        const Radius.circular(18),
      );
      canvas.drawRRect(rankBox, Paint()..color = accent);
      _drawCanvasText(
        canvas,
        rank,
        x: left + 34,
        y: top + 32,
        maxWidth: 42,
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w900,
        textAlign: TextAlign.center,
        maxLines: 1,
      );

      _drawCanvasText(
        canvas,
        label,
        x: left + 96,
        y: top + 31,
        maxWidth: 280,
        color: accent,
        fontSize: 16,
        fontWeight: FontWeight.w900,
        maxLines: 1,
      );

      _drawAvatarRanking(
        canvas,
        aluno,
        center: Offset(left + 96, top + 142),
        radius: 56,
        backgroundColor: Colors.white,
        textColor: accent,
        borderColor: Colors.white,
        borderWidth: 7,
        fotos: fotos,
      );

      _drawCanvasText(
        canvas,
        _nomeCurtoAlunoDestaque(aluno).toUpperCase(),
        x: left + 174,
        y: top + 92,
        maxWidth: 230,
        color: const Color(0xFF111827),
        fontSize: 21,
        fontWeight: FontWeight.w900,
        maxLines: 3,
      );

      _drawCanvasInfoLinha(
        canvas,
        [
          'Aval. ${aval.toStringAsFixed(1)}',
          'Pres. $pres',
        ],
        x: left + 28,
        y: top + 222,
        fontSize: 15,
        color: const Color(0xFF4B5563),
      );

      _drawCanvasText(
        canvas,
        _conceitoDestaque(nota),
        x: left + 28,
        y: top + 252,
        maxWidth: 250,
        color: accent,
        fontSize: 14,
        fontWeight: FontWeight.w900,
        maxLines: 1,
      );

      _drawCanvasTiposAulaBox(
        canvas,
        _tiposAulaDoAlunoPdf(aluno),
        rect: Rect.fromLTWH(left + 28, top + 214, 248, 62),
        fontSize: 10,
      );

      final notaBox = RRect.fromRectAndRadius(
        Rect.fromLTWH(left + 292, top + 214, 112, 62),
        const Radius.circular(24),
      );
      canvas.drawRRect(notaBox, Paint()..color = Colors.white);
      _drawCanvasText(
        canvas,
        nota.toStringAsFixed(1),
        x: left + 306,
        y: top + 226,
        maxWidth: 84,
        color: accent,
        fontSize: 28,
        fontWeight: FontWeight.w900,
        textAlign: TextAlign.center,
        maxLines: 1,
      );
    }

    double listTop = 1128;
    if (demais.isNotEmpty) {
      _drawCanvasText(
        canvas,
        '4º ao 10º colocado',
        x: 82,
        y: listTop,
        maxWidth: 430,
        color: const Color(0xFF111827),
        fontSize: 30,
        fontWeight: FontWeight.w900,
        maxLines: 1,
      );
      listTop += 52;
    }

    for (int i = 0; i < demais.length; i++) {
      final aluno = demais[i];
      final rank = i + 4;
      final top = listTop + (i * 74.0);
      final nota = _parseDouble(aluno['nota_destaque']);
      final cor = _corNotaDestaque(nota);

      final card = RRect.fromRectAndRadius(
        Rect.fromLTWH(82, top, width - 164, 60),
        const Radius.circular(22),
      );
      canvas.drawRRect(card, Paint()..color = Colors.white);
      canvas.drawRRect(
        card,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = cor.withOpacity(0.18),
      );

      final rankBg = RRect.fromRectAndRadius(
        Rect.fromLTWH(104, top + 12, 54, 36),
        const Radius.circular(15),
      );
      canvas.drawRRect(rankBg, Paint()..color = const Color(0xFF111827));
      _drawCanvasText(
        canvas,
        '$rank',
        x: 108,
        y: top + 20,
        maxWidth: 42,
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w900,
        textAlign: TextAlign.center,
        maxLines: 1,
      );

      _drawAvatarRanking(
        canvas,
        aluno,
        center: Offset(194, top + 30),
        radius: 22,
        backgroundColor: const Color(0xFFFEF3C7),
        textColor: const Color(0xFF92400E),
        borderColor: const Color(0xFFFDE68A),
        borderWidth: 3,
        fotos: fotos,
      );

      _drawCanvasText(
        canvas,
        _nomeCurtoAlunoDestaque(aluno).toUpperCase(),
        x: 232,
        y: top + 10,
        maxWidth: 390,
        color: const Color(0xFF111827),
        fontSize: 16,
        fontWeight: FontWeight.w900,
        maxLines: 1,
      );

      _drawCanvasInfoLinha(
        canvas,
        [
          'Aval. ${_parseDouble(aluno['nota_avaliacao']).toStringAsFixed(1)}',
          'Pres. ${_getFrequenciaPorFiltro(aluno)}',
        ],
        x: 232,
        y: top + 34,
        fontSize: 12.5,
        color: const Color(0xFF6B7280),
      );

      _drawCanvasTiposAulaBox(
        canvas,
        _tiposAulaDoAlunoPdf(aluno),
        rect: Rect.fromLTWH(width - 505, top + 9, 270, 42),
        fontSize: 8.5,
      );

      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(width - 214, top + 12, 104, 36),
        const Radius.circular(17),
      );
      canvas.drawRRect(badgeRect, Paint()..color = cor.withOpacity(0.12));
      _drawCanvasText(
        canvas,
        nota.toStringAsFixed(1),
        x: width - 198,
        y: top + 19,
        maxWidth: 72,
        color: cor,
        fontSize: 18,
        fontWeight: FontWeight.w900,
        textAlign: TextAlign.center,
        maxLines: 1,
      );
    }

    final footerY = height - 128;
    final footerLine = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(112, footerY), Offset(width - 112, footerY), footerLine);

    _drawCanvasText(
      canvas,
      'ARQUIVO GERADO EM ${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(DateTime.now())} PELO SISTEMA UAI CAPOEIRA',
      x: 140,
      y: height - 94,
      maxWidth: width - 280,
      color: const Color(0xFF6B7280),
      fontSize: 16,
      fontWeight: FontWeight.w800,
      textAlign: TextAlign.center,
      maxLines: 1,
    );

    _drawCanvasText(
      canvas,
      DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(DateTime.now()),
      x: 140,
      y: height - 62,
      maxWidth: width - 280,
      color: const Color(0xFF9CA3AF),
      fontSize: 14,
      fontWeight: FontWeight.w700,
      textAlign: TextAlign.center,
      maxLines: 1,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }


  void _abrirLoadingGerandoRanking() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 26),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.92, end: 1.0),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeInOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: child,
                      );
                    },
                    child: Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.amber.shade700,
                            Colors.deepOrange.shade700,
                            Colors.red.shade800,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.deepOrange.shade700.withOpacity(0.28),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Gerando arte do ranking',
                    style: TextStyle(
                      color: Colors.grey.shade900,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Preparando fotos, logo e posições dos alunos...',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      color: Colors.deepOrange.shade700,
                      backgroundColor: Colors.orange.shade50,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Aguarde um instante',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _fecharLoadingGerandoRanking() {
    if (!mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<Uint8List?> _baixarBytesRankingUrl(String? url) async {
    if (url == null || url.trim().isEmpty || !url.startsWith('http')) return null;

    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (e) {
      debugPrint('⚠️ Erro ao baixar bytes para PDF: $e');
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  Future<Map<String, pw.MemoryImage?>> _precarregarFotosPdfRanking(
      List<Map<String, dynamic>> alunos,
      ) async {
    final result = <String, pw.MemoryImage?>{};

    for (final aluno in alunos) {
      final id = aluno['id']?.toString() ?? aluno['nome']?.toString() ?? UniqueKey().toString();
      final url = aluno['foto_perfil_aluno']?.toString() ??
          aluno['aluno_foto']?.toString() ??
          aluno['foto_url']?.toString();

      final bytes = await _baixarBytesRankingUrl(url);
      result[id] = bytes == null ? null : pw.MemoryImage(bytes);
    }

    return result;
  }

  pw.Widget _pdfAvatarAluno(
      Map<String, dynamic> aluno,
      Map<String, pw.MemoryImage?> fotos, {
        required double size,
        PdfColor? borderColor,
        PdfColor? backgroundColor,
        PdfColor? textColor,
        double borderWidth = 3,
      }) {
    final id = aluno['id']?.toString() ?? aluno['nome']?.toString() ?? '';
    final foto = fotos[id];

    return pw.Container(
      width: size,
      height: size,
      padding: pw.EdgeInsets.all(borderWidth),
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        color: borderColor ?? PdfColors.white,
      ),
      child: pw.Container(
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          color: backgroundColor ?? PdfColor.fromInt(0xFFFFF7ED),
        ),
        child: foto != null
            ? pw.ClipOval(
          child: pw.Image(
            foto,
            fit: pw.BoxFit.cover,
            width: size - (borderWidth * 2),
            height: size - (borderWidth * 2),
          ),
        )
            : pw.Center(
          child: pw.Text(
            _iniciaisAlunoDestaque(aluno),
            style: pw.TextStyle(
              color: textColor ?? PdfColor.fromInt(0xFF92400E),
              fontSize: size * 0.28,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  pw.Widget _pdfBolinhaSeparadora({
    PdfColor color = const PdfColor.fromInt(0xFF9CA3AF),
    double size = 3.4,
  }) {
    return pw.Container(
      width: size,
      height: size,
      margin: const pw.EdgeInsets.symmetric(horizontal: 5),
      decoration: pw.BoxDecoration(
        color: color,
        shape: pw.BoxShape.circle,
      ),
    );
  }

  pw.Widget _pdfInfoLinha(List<String> itens, {
    double fontSize = 8.5,
    PdfColor color = const PdfColor.fromInt(0xFF4B5563),
  }) {
    final children = <pw.Widget>[];

    for (var i = 0; i < itens.length; i++) {
      if (i > 0) {
        children.add(_pdfBolinhaSeparadora());
      }

      children.add(
        pw.Text(
          itens[i],
          style: pw.TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
    }

    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: children,
    );
  }

  pw.Widget _pdfChipCriterio(String texto) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(right: 3, bottom: 3),
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFE5E7EB), width: 0.7),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: 4,
            height: 4,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFB91C1C),
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Text(
            texto,
            style: pw.TextStyle(
              color: PdfColor.fromInt(0xFF374151),
              fontSize: 5.6,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _inicioPeriodoRankingPdf() {
    final now = DateTime.now();

    switch (filtroTemporalFrequencia) {
      case 'Semana':
        return _inicioSemanaAtual(now);
      case 'Mês':
        return _inicioMesAtual(now);
      case 'Ano':
        final ano = int.tryParse(anoSelecionado ?? now.year.toString()) ?? now.year;
        return DateTime(ano, 1, 1);
      case 'Total':
      default:
        return null;
    }
  }

  DateTime? _fimPeriodoRankingPdf() {
    final now = DateTime.now();

    switch (filtroTemporalFrequencia) {
      case 'Semana':
        return _inicioSemanaAtual(now).add(const Duration(days: 7));
      case 'Mês':
        return DateTime(now.year, now.month + 1, 1);
      case 'Ano':
        final ano = int.tryParse(anoSelecionado ?? now.year.toString()) ?? now.year;
        return DateTime(ano + 1, 1, 1);
      case 'Total':
      default:
        return null;
    }
  }

  String _normalizarTipoAulaRanking(dynamic valor) {
    final raw = valor?.toString().trim();
    if (raw == null || raw.isEmpty) return 'Outro';

    final lower = raw.toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');

    if (lower.contains('objetiva')) return 'Objetiva';
    if (lower.contains('roda')) return 'Roda';
    if (lower.contains('instrument')) return 'Instrumentação';
    if (lower.contains('especial')) return 'Especial';
    if (lower.contains('evento')) return 'Evento';
    if (lower.contains('batizado')) return 'Batizado';

    return raw;
  }

  bool _logPresencaValidaParaPdf(Map<String, dynamic> data) {
    final presente = data['presente'] ??
        data['is_presente'] ??
        data['presenca'] ??
        data['status_presenca'] ??
        data['status'];

    if (presente == true) return true;
    if (presente is num) return presente == 1;

    if (presente is String) {
      final v = presente.toLowerCase().trim();
      return v == 'true' ||
          v == '1' ||
          v == 'sim' ||
          v == 'presente' ||
          v == 'p';
    }

    // Alguns logs antigos podem existir apenas quando o aluno está presente.
    return presente == null;
  }

  DateTime? _dataLogTipoAulaPdf(Map<String, dynamic> data) {
    return _toDateTime(
      data['data_aula'] ??
          data['data'] ??
          data['data_chamada'] ??
          data['dataChamada'] ??
          data['createdAt'] ??
          data['criado_em'],
    );
  }

  bool _logDentroPeriodoPdf(DateTime? dataLog) {
    final inicio = _inicioPeriodoRankingPdf();
    final fim = _fimPeriodoRankingPdf();

    if (inicio == null && fim == null) return true;

    // Se o log não tiver data, não descartamos para não zerar histórico antigo.
    if (dataLog == null) return true;

    if (inicio != null && dataLog.isBefore(inicio)) return false;
    if (fim != null && !dataLog.isBefore(fim)) return false;

    return true;
  }

  dynamic _extrairCampoTipoAulaPdf(Map<String, dynamic> data) {
    return data['tipo_aula'] ??
        data['tipoAula'] ??
        data['tipo_aula_nome'] ??
        data['nome_tipo_aula'] ??
        data['tipo_de_aula'] ??
        data['tipoAulaNome'] ??
        data['aula_tipo'] ??
        data['categoria_aula'] ??
        data['tipo_chamada'] ??
        data['tipo'];
  }









  Future<Map<String, Map<String, int>>> _buscarTiposAulaPorAlunoRanking(
      List<Map<String, dynamic>> alunos,
      ) async {
    final result = <String, Map<String, int>>{};

    final ids = alunos
        .map((a) => a['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    if (ids.isEmpty) return result;

    int docsLidos = 0;
    int docsUsados = 0;

    for (var i = 0; i < ids.length; i += 10) {
      final end = math.min(i + 10, ids.length);
      final batchIds = ids.sublist(i, end);

      // Busca simples e robusta. Filtro de data/presença/tipo fica no app.
      final snap = await _firestore
          .collection('log_presenca_alunos')
          .where('aluno_id', whereIn: batchIds)
          .get(const GetOptions(source: Source.server));

      docsLidos += snap.docs.length;

      for (final doc in snap.docs) {
        final data = doc.data();

        final alunoId = (data['aluno_id'] ??
            data['alunoId'] ??
            data['id_aluno'] ??
            data['aluno'])
            ?.toString() ??
            '';

        if (alunoId.isEmpty) continue;
        if (!batchIds.contains(alunoId)) continue;
        if (!_logPresencaValidaParaPdf(data)) continue;

        final dataLog = _dataLogTipoAulaPdf(data);
        if (!_logDentroPeriodoPdf(dataLog)) continue;

        final tipo = _normalizarTipoAulaRanking(_extrairCampoTipoAulaPdf(data));

        result.putIfAbsent(alunoId, () => <String, int>{});
        result[alunoId]![tipo] = (result[alunoId]![tipo] ?? 0) + 1;
        docsUsados++;
      }
    }

    debugPrint(
      '📄 PDF Ranking: tipos por aluno = ${result.length}/${ids.length} alunos | '
          '$docsUsados logs usados de $docsLidos lidos | filtro $filtroTemporalFrequencia',
    );

    return result;
  }

  Map<String, int> _tiposAulaDoAlunoPdf(Map<String, dynamic> aluno) {
    final id = aluno['id']?.toString() ?? '';
    return _tiposAulaPdfCache[id] ?? <String, int>{};
  }

  String _pdfTextoTiposAula(
      Map<String, int> tipos, {
        int maxTipos = 6,
      }) {
    if (tipos.isEmpty) return 'Nenhuma aula encontrada no período';

    final ordenados = tipos.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final principais = ordenados
        .take(maxTipos)
        .map((e) => '${e.key}: ${e.value}')
        .toList();

    final restantes = ordenados.skip(maxTipos).fold<int>(0, (soma, e) => soma + e.value);
    if (restantes > 0) {
      principais.add('Outros: $restantes');
    }

    return principais.join('  |  ');
  }

  int _pdfTotalTiposAula(Map<String, int> tipos) {
    return tipos.values.fold<int>(0, (soma, valor) => soma + valor);
  }

  pw.Widget _pdfTiposAulaBox(
      Map<String, int> tipos, {
        double width = 178,
        double height = 38,
        int maxTipos = 6,
        double fontSize = 6.7,
      }) {
    final totalTipos = _pdfTotalTiposAula(tipos);

    return pw.Container(
      width: width,
      height: height,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFF0FDF4),
        borderRadius: pw.BorderRadius.circular(11),
        border: pw.Border.all(
          color: const PdfColor.fromInt(0xFF86EFAC),
          width: 0.85,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            totalTipos > 0
                ? 'AULAS POR TIPO • TOTAL: $totalTipos'
                : 'AULAS POR TIPO',
            maxLines: 1,
            style: pw.TextStyle(
              color: const PdfColor.fromInt(0xFF166534),
              fontSize: fontSize - 0.8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 1.7),
          pw.Text(
            _pdfTextoTiposAula(tipos, maxTipos: maxTipos),
            maxLines: 2,
            style: pw.TextStyle(
              color: const PdfColor.fromInt(0xFF14532D),
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
              lineSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfInfoRankingAluno({
    required double aval,
    required double freq,
    required int pres,
    double fontSize = 7.4,
    PdfColor color = const PdfColor.fromInt(0xFF4B5563),
  }) {
    return _pdfInfoLinha(
      [
        'Aval. ${aval.toStringAsFixed(1)}',
        'Freq. ${freq.toStringAsFixed(1)}',
        'Pres. $pres',
      ],
      fontSize: fontSize,
      color: color,
    );
  }

  pw.Widget _pdfCardTop1(
      Map<String, dynamic> aluno,
      Map<String, pw.MemoryImage?> fotos,
      ) {
    final nota = _parseDouble(aluno['nota_destaque']);
    final aval = _parseDouble(aluno['nota_avaliacao']);
    final scoreFreq = _parseDouble(aluno['score_frequencia']);
    final pres = _getFrequenciaPorFiltro(aluno);
    final tipos = _tiposAulaDoAlunoPdf(aluno);

    return pw.Container(
      height: 86,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFFFFBEB),
        borderRadius: pw.BorderRadius.circular(18),
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFFDE68A), width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 28,
            height: 28,
            decoration: const pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              color: PdfColor.fromInt(0xFFF59E0B),
            ),
            child: pw.Center(
              child: pw.Text(
                '1',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 11.8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 9),
          _pdfAvatarAluno(
            aluno,
            fotos,
            size: 53,
            borderColor: PdfColors.white,
            backgroundColor: const PdfColor.fromInt(0xFFFEF3C7),
            textColor: const PdfColor.fromInt(0xFF92400E),
            borderWidth: 4,
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            flex: 5,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'CAMPEÃO DO RANKING',
                  maxLines: 1,
                  style: pw.TextStyle(
                    color: const PdfColor.fromInt(0xFF92400E),
                    fontSize: 9.6,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2.6),
                pw.Text(
                  _nomeCurtoAlunoDestaque(aluno).toUpperCase(),
                  maxLines: 1,
                  style: pw.TextStyle(
                    color: const PdfColor.fromInt(0xFF111827),
                    fontSize: 16.8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3.5),
                _pdfInfoRankingAluno(
                  aval: aval,
                  freq: scoreFreq,
                  pres: pres,
                  fontSize: 7.7,
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 8),
          _pdfTiposAulaBox(
            tipos,
            width: 180,
            height: 50,
            maxTipos: 6,
            fontSize: 6.55,
          ),
          pw.SizedBox(width: 8),
          pw.Container(
            width: 54,
            height: 52,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(16),
              border: pw.Border.all(color: const PdfColor.fromInt(0xFFFDE68A), width: 1),
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  nota.toStringAsFixed(1),
                  style: pw.TextStyle(
                    color: const PdfColor.fromInt(0xFF92400E),
                    fontSize: 20.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'NOTA',
                  style: pw.TextStyle(
                    color: const PdfColor.fromInt(0xFF92400E),
                    fontSize: 5.9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfCardTopLateral({
    required Map<String, dynamic> aluno,
    required Map<String, pw.MemoryImage?> fotos,
    required String posicao,
    required String label,
    required PdfColor bg,
    required PdfColor accent,
  }) {
    final nota = _parseDouble(aluno['nota_destaque']);
    final aval = _parseDouble(aluno['nota_avaliacao']);
    final scoreFreq = _parseDouble(aluno['score_frequencia']);
    final pres = _getFrequenciaPorFiltro(aluno);
    final tipos = _tiposAulaDoAlunoPdf(aluno);

    return pw.Container(
      height: 97,
      padding: const pw.EdgeInsets.all(8.2),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(18),
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFE5E7EB), width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Container(
                width: 26,
                height: 20,
                decoration: pw.BoxDecoration(
                  color: accent,
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Center(
                  child: pw.Text(
                    posicao,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(height: 5),
              _pdfAvatarAluno(
                aluno,
                fotos,
                size: 41,
                borderColor: PdfColors.white,
                backgroundColor: PdfColors.white,
                textColor: accent,
                borderWidth: 3,
              ),
            ],
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  label,
                  maxLines: 1,
                  style: pw.TextStyle(
                    color: accent,
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  _nomeCurtoAlunoDestaque(aluno).toUpperCase(),
                  maxLines: 1,
                  style: pw.TextStyle(
                    color: const PdfColor.fromInt(0xFF111827),
                    fontSize: 11.4,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2.7),
                _pdfInfoRankingAluno(
                  aval: aval,
                  freq: scoreFreq,
                  pres: pres,
                  fontSize: 6.05,
                ),
                pw.SizedBox(height: 4.2),
                _pdfTiposAulaBox(
                  tipos,
                  width: 156,
                  height: 34,
                  maxTipos: 6,
                  fontSize: 5.65,
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 5),
          pw.Container(
            width: 41,
            height: 43,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(13),
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  nota.toStringAsFixed(1),
                  style: pw.TextStyle(
                    color: accent,
                    fontSize: 14.2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'NOTA',
                  style: pw.TextStyle(
                    color: accent,
                    fontSize: 4.9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfLinhaRanking(
      int posicao,
      Map<String, dynamic> aluno,
      Map<String, pw.MemoryImage?> fotos,
      ) {
    final nota = _parseDouble(aluno['nota_destaque']);
    final aval = _parseDouble(aluno['nota_avaliacao']);
    final scoreFreq = _parseDouble(aluno['score_frequencia']);
    final pres = _getFrequenciaPorFiltro(aluno);
    final tipos = _tiposAulaDoAlunoPdf(aluno);

    final cor = nota >= 9
        ? const PdfColor.fromInt(0xFF166534)
        : nota >= 8
        ? const PdfColor.fromInt(0xFF3F6212)
        : nota >= 7
        ? const PdfColor.fromInt(0xFF1D4ED8)
        : nota >= 6
        ? const PdfColor.fromInt(0xFFC2410C)
        : const PdfColor.fromInt(0xFFB91C1C);

    return pw.Container(
      height: 49,
      margin: const pw.EdgeInsets.only(bottom: 3.7),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8.5, vertical: 4.5),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFE5E7EB), width: 0.8),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 31,
            height: 22,
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFF111827),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Center(
              child: pw.Text(
                '$posicao',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 9.0,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          _pdfAvatarAluno(
            aluno,
            fotos,
            size: 25.5,
            borderColor: const PdfColor.fromInt(0xFFFDE68A),
            backgroundColor: const PdfColor.fromInt(0xFFFEF3C7),
            textColor: const PdfColor.fromInt(0xFF92400E),
            borderWidth: 2,
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  _nomeCurtoAlunoDestaque(aluno).toUpperCase(),
                  maxLines: 1,
                  style: pw.TextStyle(
                    color: const PdfColor.fromInt(0xFF111827),
                    fontSize: 9.15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                _pdfInfoRankingAluno(
                  aval: aval,
                  freq: scoreFreq,
                  pres: pres,
                  fontSize: 6.15,
                  color: const PdfColor.fromInt(0xFF6B7280),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 7),
          _pdfTiposAulaBox(
            tipos,
            width: 183,
            height: 38,
            maxTipos: 6,
            fontSize: 6.05,
          ),
          pw.SizedBox(width: 7),
          pw.Container(
            width: 44,
            height: 34,
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF9FAFB),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Center(
              child: pw.Text(
                nota.toStringAsFixed(1),
                style: pw.TextStyle(
                  color: cor,
                  fontSize: 11.2,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _gerarPdfRankingAlunoDestaque() async {
    final top10 = _alunosDestaque.take(10).toList();
    final top3 = top10.take(3).toList();
    final demais = top10.length > 3
        ? top10.sublist(3, top10.length)
        : <Map<String, dynamic>>[];

    final fotos = await _precarregarFotosPdfRanking(top10);
    _tiposAulaPdfCache = await _buscarTiposAulaPorAlunoRanking(top10);
    debugPrint('📄 PDF Top10 CARDS MAIORES: top10=${top10.length}, top3=${top3.length}, demais=${demais.length}, cacheTipos=${_tiposAulaPdfCache.length}');
    debugPrint('📄 PDF Top10: top10=${top10.length}, demais=${demais.length}, cacheTipos=${_tiposAulaPdfCache.length}');

    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/logo_uai.png');
      logoBytes = data.buffer.asUint8List();
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar logo para PDF: $e');
    }

    final logoImage = logoBytes == null ? null : pw.MemoryImage(logoBytes);

    // Fonte com suporte completo a acentos em português.
    final pdfFontRegular = await PdfGoogleFonts.robotoRegular();
    final pdfFontBold = await PdfGoogleFonts.robotoBold();

    final pdf = pw.Document(
      title: 'Ranking Aluno Destaque - ${widget.turmaNome}',
      author: 'Uai Capoeira',
      subject: 'Ranking Aluno Destaque',
      creator: 'Uai Capoeira App',
    );

    const criterios = [
      'Comportamento',
      'Casa',
      'Respeito',
      'Disciplina',
      'Participação',
      'Atenção',
      'Pontualidade',
      'Evolução técnica',
      'Ginga',
      'Musicalidade',
      'Instrumentos',
    ];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(14),
        build: (context) {
          return pw.Theme(
            data: pw.ThemeData.withFont(
              base: pdfFontRegular,
              bold: pdfFontBold,
            ),
            child: pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFFBFBFB),
                borderRadius: pw.BorderRadius.circular(22),
                border: pw.Border.all(color: PdfColor.fromInt(0xFFE5E7EB), width: 1),
              ),
              padding: const pw.EdgeInsets.all(12),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        width: 62,
                        height: 48,
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(14),
                          border: pw.Border.all(color: PdfColor.fromInt(0xFFE5E7EB), width: 1),
                        ),
                        child: logoImage != null
                            ? pw.Center(child: pw.Image(logoImage, fit: pw.BoxFit.contain, alignment: pw.Alignment.center))
                            : pw.Center(
                          child: pw.Text(
                            'UAI',
                            style: pw.TextStyle(
                              color: PdfColor.fromInt(0xFF991B1B),
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 14),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'RANKING ALUNO DESTAQUE',
                              style: pw.TextStyle(
                                color: PdfColor.fromInt(0xFF111827),
                                fontSize: 19,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              widget.turmaNome.toUpperCase(),
                              maxLines: 1,
                              style: pw.TextStyle(
                                color: PdfColor.fromInt(0xFF6B7280),
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2.5),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                          decoration: pw.BoxDecoration(
                            color: PdfColor.fromInt(0xFFF3F4F6),
                            borderRadius: pw.BorderRadius.circular(14),
                          ),
                          child: pw.Text(
                            _periodoAtualDestaqueLabel(),
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              color: PdfColor.fromInt(0xFF374151),
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Container(
                        width: 104,
                        padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFFFF7ED),
                          borderRadius: pw.BorderRadius.circular(14),
                        ),
                        child: pw.Text(
                          '60% + 40%',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            color: PdfColor.fromInt(0xFF9A3412),
                            fontSize: 9.0,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(7.5),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFF9FAFB),
                      borderRadius: pw.BorderRadius.circular(16),
                      border: pw.Border.all(color: PdfColor.fromInt(0xFFE5E7EB), width: 0.8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Critérios avaliados',
                          style: pw.TextStyle(
                            color: PdfColor.fromInt(0xFF111827),
                            fontSize: 10.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Nota destaque: comportamento, disciplina, evolução e frequência',
                          style: pw.TextStyle(
                            color: PdfColor.fromInt(0xFF6B7280),
                            fontSize: 7.2,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Wrap(
                          children: criterios.map(_pdfChipCriterio).toList(),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Top 3 da turma',
                    style: pw.TextStyle(
                      color: PdfColor.fromInt(0xFF111827),
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  if (top3.isNotEmpty) _pdfCardTop1(top3[0], fotos),
                  pw.SizedBox(height: 5),
                  pw.Row(
                    children: [
                      if (top3.length > 1)
                        pw.Expanded(
                          child: _pdfCardTopLateral(
                            aluno: top3[1],
                            fotos: fotos,
                            posicao: '2',
                            label: 'VICE-DESTAQUE',
                            bg: PdfColor.fromInt(0xFFEFF6FF),
                            accent: PdfColor.fromInt(0xFF1D4ED8),
                          ),
                        ),
                      if (top3.length > 1 && top3.length > 2) pw.SizedBox(width: 8),
                      if (top3.length > 2)
                        pw.Expanded(
                          child: _pdfCardTopLateral(
                            aluno: top3[2],
                            fotos: fotos,
                            posicao: '3',
                            label: 'TERCEIRO LUGAR',
                            bg: PdfColor.fromInt(0xFFFFF7ED),
                            accent: PdfColor.fromInt(0xFF9A3412),
                          ),
                        ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  if (demais.isNotEmpty)
                    pw.Text(
                      '4º ao 10º colocado',
                      style: pw.TextStyle(
                        color: PdfColor.fromInt(0xFF111827),
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  pw.SizedBox(height: 1),
                  ...demais.asMap().entries.map((entry) {
                    return _pdfLinhaRanking(entry.key + 4, entry.value, fotos);
                  }),
                  pw.SizedBox(height: 3),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.only(top: 5),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(color: PdfColor.fromInt(0xFFE5E7EB), width: 0.8),
                      ),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'ARQUIVO GERADO EM ${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(DateTime.now())} PELO SISTEMA UAI CAPOEIRA',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            color: PdfColor.fromInt(0xFF6B7280),
                            fontSize: 6.8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<void> _compartilharPdfRankingAlunoDestaque() async {
    if (_alunosDestaque.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Nenhum aluno disponível para gerar o PDF.'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }

    bool loadingAberto = false;

    try {
      if (mounted) {
        setState(() => _isGerandoPdfDestaque = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isGerandoPdfDestaque) {
            _abrirLoadingGerandoRanking();
          }
        });
        await Future.delayed(const Duration(milliseconds: 180));
        loadingAberto = true;
      }

      final pdfBytes = await _gerarPdfRankingAlunoDestaque();

      if (loadingAberto) {
        _fecharLoadingGerandoRanking();
        loadingAberto = false;
        await Future.delayed(const Duration(milliseconds: 120));
      }

      final safeTurma = widget.turmaNome
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'ranking_aluno_destaque_${safeTurma}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      debugPrint('❌ Erro ao gerar PDF do ranking: $e');

      if (loadingAberto) {
        _fecharLoadingGerandoRanking();
        loadingAberto = false;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF do ranking: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (loadingAberto) {
        _fecharLoadingGerandoRanking();
      }

      if (mounted) {
        setState(() => _isGerandoPdfDestaque = false);
      }
    }
  }

  Future<Uint8List> _gerarPdfRankingCompletoAlunoDestaque() async {
    final alunosPdf = List<Map<String, dynamic>>.from(_alunosDestaque);
    _tiposAulaPdfCache = await _buscarTiposAulaPorAlunoRanking(alunosPdf);
    debugPrint('📄 PDF Completo LEGÍVEL: alunos=${alunosPdf.length}, cacheTipos=${_tiposAulaPdfCache.length}');
    debugPrint('📄 PDF Completo: alunos=${alunosPdf.length}, cacheTipos=${_tiposAulaPdfCache.length}');

    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/logo_uai.png');
      logoBytes = data.buffer.asUint8List();
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar logo para PDF completo: $e');
    }

    final logoImage = logoBytes == null ? null : pw.MemoryImage(logoBytes);
    final pdfFontRegular = await PdfGoogleFonts.robotoRegular();
    final pdfFontBold = await PdfGoogleFonts.robotoBold();

    final pdf = pw.Document(
      title: 'Ranking Completo Aluno Destaque - ${widget.turmaNome}',
      author: 'Uai Capoeira',
      subject: 'Ranking Completo Aluno Destaque',
      creator: 'Uai Capoeira App',
    );

    const criterios = [
      'Comportamento',
      'Casa',
      'Respeito',
      'Disciplina',
      'Participação',
      'Atenção',
      'Pontualidade',
      'Evolução técnica',
      'Ginga',
      'Musicalidade',
      'Instrumentos',
    ];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        theme: pw.ThemeData.withFont(
          base: pdfFontRegular,
          bold: pdfFontBold,
        ),
        header: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFE5E7EB), width: 0.8),
              ),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 58,
                  height: 46,
                  padding: const pw.EdgeInsets.all(5),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(12),
                    border: pw.Border.all(color: const PdfColor.fromInt(0xFFE5E7EB), width: 1),
                  ),
                  child: logoImage != null
                      ? pw.Image(logoImage, fit: pw.BoxFit.contain)
                      : pw.Center(child: pw.Text('UAI')),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'RANKING COMPLETO ALUNO DESTAQUE',
                        style: pw.TextStyle(
                          color: const PdfColor.fromInt(0xFF111827),
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        '${widget.turmaNome.toUpperCase()}  |  ${_periodoAtualDestaqueLabel()}',
                        style: pw.TextStyle(
                          color: const PdfColor.fromInt(0xFF6B7280),
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        footer: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColor.fromInt(0xFFE5E7EB), width: 0.8),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Gerado automaticamente pelo Uai Capoeira',
                  style: const pw.TextStyle(
                    color: PdfColor.fromInt(0xFF6B7280),
                    fontSize: 8,
                  ),
                ),
                pw.Text(
                  'Página ${context.pageNumber}/${context.pagesCount}',
                  style: const pw.TextStyle(
                    color: PdfColor.fromInt(0xFF9CA3AF),
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          );
        },
        build: (context) {
          return [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFF9FAFB),
                borderRadius: pw.BorderRadius.circular(14),
                border: pw.Border.all(color: const PdfColor.fromInt(0xFFE5E7EB), width: 0.8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Critérios avaliados',
                    style: pw.TextStyle(
                      color: const PdfColor.fromInt(0xFF111827),
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Wrap(
                    children: criterios.map(_pdfChipCriterio).toList(),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Todos os alunos da turma',
              style: pw.TextStyle(
                color: const PdfColor.fromInt(0xFF111827),
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            ...alunosPdf.asMap().entries.map((entry) {
              return _pdfLinhaRanking(entry.key + 1, entry.value, const <String, pw.MemoryImage?>{});
            }),
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<void> _compartilharPdfCompletoRankingAlunoDestaque() async {
    if (_alunosDestaque.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Nenhum aluno disponível para gerar o PDF completo.'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }

    bool loadingAberto = false;

    try {
      if (mounted) {
        setState(() => _isGerandoPdfCompletoDestaque = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isGerandoPdfCompletoDestaque) {
            _abrirLoadingGerandoRanking();
          }
        });
        await Future.delayed(const Duration(milliseconds: 180));
        loadingAberto = true;
      }

      final pdfBytes = await _gerarPdfRankingCompletoAlunoDestaque();

      if (loadingAberto) {
        _fecharLoadingGerandoRanking();
        loadingAberto = false;
        await Future.delayed(const Duration(milliseconds: 120));
      }

      final safeTurma = widget.turmaNome
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'ranking_completo_aluno_destaque_${safeTurma}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      debugPrint('❌ Erro ao gerar PDF completo do ranking: $e');

      if (loadingAberto) {
        _fecharLoadingGerandoRanking();
        loadingAberto = false;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF completo: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (loadingAberto) {
        _fecharLoadingGerandoRanking();
      }

      if (mounted) {
        setState(() => _isGerandoPdfCompletoDestaque = false);
      }
    }
  }

  Future<void> _compartilharRankingAlunoDestaque() async {
    if (_alunosDestaque.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Nenhum aluno disponível para gerar o ranking.'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }

    bool loadingAberto = false;

    try {
      if (mounted) {
        setState(() => _isGerandoImagemDestaque = true);

        // Dá tempo da UI abrir a tela de carregamento antes de começar o canvas.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isGerandoImagemDestaque) {
            _abrirLoadingGerandoRanking();
          }
        });

        await Future.delayed(const Duration(milliseconds: 180));
        loadingAberto = true;
      }

      final bytes = await _gerarImagemRankingAlunoDestaque();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/ranking_aluno_destaque_${widget.turmaId}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);

      if (loadingAberto) {
        _fecharLoadingGerandoRanking();
        loadingAberto = false;
        await Future.delayed(const Duration(milliseconds: 120));
      }

      final periodo = _periodoAtualDestaqueLabel();
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Ranking Aluno Destaque - ${widget.turmaNome}\n$periodo',
        subject: 'Ranking Aluno Destaque - ${widget.turmaNome}',
      );
    } catch (e) {
      debugPrint('❌ Erro ao compartilhar ranking: $e');

      if (loadingAberto) {
        _fecharLoadingGerandoRanking();
        loadingAberto = false;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar imagem do ranking: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (loadingAberto) {
        _fecharLoadingGerandoRanking();
      }

      if (mounted) {
        setState(() => _isGerandoImagemDestaque = false);
      }
    }
  }

  Widget _buildAbaAlunoDestaque() => RefreshIndicator(
    onRefresh: () => _atualizarDadosReais(recalcularTudo: true),
    color: Colors.amber.shade800,
    child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: _buildAlunoDestaqueConteudo(),
    ),
  );

  Widget _buildAlunoDestaqueConteudo() {
    final avaliados = _alunosDestaque.where((a) => _parseDouble(a['nota_avaliacao']) > 0).length;
    final mediaDestaque = _alunosDestaque.isEmpty
        ? 0.0
        : _alunosDestaque
        .map((a) => _parseDouble(a['nota_destaque']))
        .fold<double>(0, (s, n) => s + n) /
        _alunosDestaque.length;

    if (_alunosDestaque.isEmpty) {
      return _emptyChart('Sem alunos para calcular destaque');
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.amber.shade800.withOpacity(0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.045),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.amber.shade700,
                          Colors.deepOrange.shade700,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Aluno Destaque',
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '60% avaliação + 40% frequência',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.amber.shade100),
                    ),
                    child: Column(
                      children: [
                        Text(
                          mediaDestaque.toStringAsFixed(1),
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'média',
                          style: TextStyle(
                            color: Colors.amber.shade900.withOpacity(0.75),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: _destaqueInfoSlim(
                      '${_alunosDestaque.length}',
                      'alunos',
                      Icons.groups_rounded,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _destaqueInfoSlim(
                      '$avaliados',
                      'avaliados',
                      Icons.star_rate_rounded,
                      Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _destaqueInfoSlim(
                      '${(_alunosDestaque.length - avaliados).clamp(0, _alunosDestaque.length)}',
                      'pendentes',
                      Icons.pending_actions_rounded,
                      Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isGerandoImagemDestaque ? null : _compartilharRankingAlunoDestaque,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepOrange.shade800,
                        side: BorderSide(color: Colors.deepOrange.shade100),
                        backgroundColor: Colors.deepOrange.shade50.withOpacity(0.45),
                        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon: _isGerandoImagemDestaque
                          ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.deepOrange.shade800,
                        ),
                      )
                          : const Icon(Icons.image_rounded, size: 18),
                      label: Text(
                        _isGerandoImagemDestaque ? 'Imagem...' : 'Imagem',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isGerandoPdfDestaque ? null : _compartilharPdfRankingAlunoDestaque,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade900,
                        side: BorderSide(color: Colors.red.shade100),
                        backgroundColor: Colors.red.shade50.withOpacity(0.45),
                        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon: _isGerandoPdfDestaque
                          ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.red.shade900,
                        ),
                      )
                          : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: Text(
                        _isGerandoPdfDestaque ? 'PDF...' : 'PDF',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isGerandoPdfCompletoDestaque ? null : _compartilharPdfCompletoRankingAlunoDestaque,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepPurple.shade800,
                        side: BorderSide(color: Colors.deepPurple.shade100),
                        backgroundColor: Colors.deepPurple.shade50.withOpacity(0.45),
                        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon: _isGerandoPdfCompletoDestaque
                          ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.deepPurple.shade800,
                        ),
                      )
                          : const Icon(Icons.groups_rounded, size: 18),
                      label: Text(
                        _isGerandoPdfCompletoDestaque ? 'Tudo...' : 'Todos',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildFiltroTemporal(),
        const SizedBox(height: 4),
        ..._alunosDestaque.asMap().entries.map((entry) {
          return _buildAlunoDestaqueCard(entry.key + 1, entry.value);
        }),
      ],
    );
  }

  Widget _destaqueInfoSlim(String valor, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.075),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Flexible(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: valor,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: ' $label',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _destaqueResumoCard(String valor, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 4),
          Text(
            valor,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildAlunoDestaqueCard(int posicao, Map<String, dynamic> aluno) {
    final nome = aluno['nome']?.toString() ?? 'Sem nome';
    final foto = aluno['foto_perfil_aluno']?.toString() ?? '';
    final freq = _getFrequenciaPorFiltro(aluno);
    final notaAvaliacao = _parseDouble(aluno['nota_avaliacao']);
    final scoreFrequencia = _parseDouble(aluno['score_frequencia']);
    final notaDestaque = _parseDouble(aluno['nota_destaque']);
    final conceito = aluno['conceito_destaque']?.toString() ?? _conceitoDestaque(notaDestaque);
    final cor = _corNotaDestaque(notaDestaque);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cor.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: posicao <= 3 ? Colors.amber.shade100 : Colors.grey.shade100,
                shape: BoxShape.circle,
                border: Border.all(
                  color: posicao <= 3 ? Colors.amber.shade700 : Colors.grey.shade300,
                ),
              ),
              child: Center(
                child: Text(
                  '$posicao',
                  style: TextStyle(
                    color: posicao <= 3 ? Colors.amber.shade900 : Colors.grey.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _buildAlunoAvatarDestaque(foto, nome),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nome,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      _destaqueChip('Aval.', notaAvaliacao.toStringAsFixed(1), Colors.deepPurple),
                      _destaqueChip('Freq.', scoreFrequencia.toStringAsFixed(1), Colors.blue),
                      _destaqueChip('Pres.', '$freq', Colors.green),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    conceito,
                    style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 54,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: cor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: cor.withOpacity(0.18)),
              ),
              child: Column(
                children: [
                  Text(
                    notaDestaque.toStringAsFixed(1),
                    style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'nota',
                    style: TextStyle(color: cor.withOpacity(0.82), fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlunoAvatarDestaque(String foto, String nome) {
    final letra = nome.trim().isNotEmpty ? nome.trim()[0].toUpperCase() : '?';

    if (foto.startsWith('http')) {
      return ClipOval(
        child: Image.network(
          foto,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          cacheWidth: 120,
          errorBuilder: (_, __, ___) => _avatarDestaqueFallback(letra),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _avatarDestaqueFallback(letra);
          },
        ),
      );
    }

    return _avatarDestaqueFallback(letra);
  }

  Widget _avatarDestaqueFallback(String letra) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.amber.shade100,
      child: Text(
        letra,
        style: TextStyle(
          color: Colors.amber.shade900,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _destaqueChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ============ FILTRO TEMPORAL ============
  Widget _buildFiltroTemporal() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            children: [
              _btnTemporal('Semana', Icons.calendar_view_week),
              _btnTemporal('Mês', Icons.calendar_month),
              _btnTemporal('Ano', Icons.calendar_today),
              _btnTemporal('Total', Icons.history),
            ],
          ),
        ),
        if (filtroTemporalFrequencia == 'Ano' && anosDisponiveis.isNotEmpty)
          _buildSeletorAno(),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _btnTemporal(String t, IconData i) {
    final ativo = filtroTemporalFrequencia == t;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            filtroTemporalFrequencia = t;
            _atualizarComFiltro();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: ativo ? Colors.blue.shade600 : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                i,
                size: 14,
                color: ativo ? Colors.white : Colors.grey.shade600,
              ),
              const SizedBox(width: 4),
              Text(
                t,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ativo ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeletorAno() {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(top: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: anosDisponiveis.length,
        itemBuilder: (ctx, i) {
          final ano = anosDisponiveis[i];
          final ativo = anoSelecionado == ano;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(ano),
              selected: ativo,
              onSelected: (s) {
                if (s)
                  setState(() {
                    anoSelecionado = ano;
                    _atualizarComFiltro();
                  });
              },
              backgroundColor: Colors.grey.shade100,
              selectedColor: Colors.blue.shade100,
            ),
          );
        },
      ),
    );
  }

  // ============ GRÁFICOS ============
  Widget _buildGraficoFrequencia() {
    if (_alunosFrequentes.isEmpty)
      return _emptyChart('Sem dados de frequência');
    final Map<String, int> dados = {};
    int maxV = 0;
    for (var a in _alunosFrequentes) {
      final n = a['nome']?.split(' ').first ?? '?';
      final v = _getFrequenciaPorFiltro(a);
      dados[n] = v;
      if (v > maxV) maxV = v;
    }
    double intervalo = maxV <= 5
        ? 1
        : maxV <= 10
        ? 2
        : maxV <= 20
        ? 4
        : maxV <= 50
        ? 10
        : maxV <= 100
        ? 20
        : (maxV / 10).ceilToDouble();
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Top 5 Alunos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    filtroTemporalFrequencia == 'Ano' && anoSelecionado != null
                        ? anoSelecionado!
                        : filtroTemporalFrequencia,
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (maxV + intervalo).toDouble(),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (g) => Colors.blue.shade800,
                      getTooltipItem: (g, gi, r, ri) => BarTooltipItem(
                        '${dados.keys.elementAt(g.x)}\n${r.toY.toInt()} presenças',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 35,
                        getTitlesWidget: (v, m) {
                          final idx = v.toInt();
                          if (idx >= 0 && idx < dados.keys.length)
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                dados.keys.elementAt(idx),
                                style: const TextStyle(fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: intervalo,
                        reservedSize: 30,
                        getTitlesWidget: (v, m) => Text(
                          v.toInt().toString(),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                      left: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: intervalo,
                    drawVerticalLine: false,
                  ),
                  barGroups: dados.entries.map((e) {
                    final idx = dados.keys.toList().indexOf(e.key);
                    return BarChartGroupData(
                      x: idx,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.toDouble(),
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.shade400,
                              Colors.cyan.shade300,
                            ],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          width: 22,
                          borderRadius: BorderRadius.circular(4),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxV.toDouble(),
                            color: Colors.grey.shade100,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  //  GRÁFICO DE GRADUAÇÃO PREMIUM
  Widget _buildGraficoGraduacao() {
    if (_distribuicaoGraduacao.isEmpty) {
      return _emptyChart('Sem dados de graduação');
    }

    final ordenadas = _distribuicaoGraduacao.entries.toList()
      ..sort((a, b) {
        final nivelA = _getNivelGraduacao(a.key);
        final nivelB = _getNivelGraduacao(b.key);
        return nivelA.compareTo(nivelB);
      });

    final totalAlunos = _distribuicaoGraduacao.values.fold<int>(0, (s, v) => s + v);
    final totalGraduacoes = ordenadas.where((e) => e.key != 'SEM GRADUAÇÃO').length;
    final maiorGrupo = ordenadas.isEmpty ? 0 : ordenadas.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final graduacaoDestaque = ordenadas.isEmpty ? '-' : ordenadas.first.key;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.deepPurple.shade800,
                Colors.purple.shade600,
                Colors.red.shade700,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurple.shade800.withOpacity(0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mapa de Graduações',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Distribuição dos alunos por corda',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _graduacaoResumoCard(
                      valor: '$totalAlunos',
                      label: 'Alunos',
                      icon: Icons.groups_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _graduacaoResumoCard(
                      valor: '$totalGraduacoes',
                      label: 'Cordas',
                      icon: Icons.military_tech_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _graduacaoResumoCard(
                      valor: '$maiorGrupo',
                      label: 'Maior grupo',
                      icon: Icons.bar_chart_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Primeira graduação na ordem: $graduacaoDestaque',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.pie_chart_rounded, color: Colors.purple.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Distribuição visual',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 210,
                  child: PieChart(
                    PieChartData(
                      sections: ordenadas.map((e) {
                        final cache = _graduacoesCache[e.key];
                        final String hex = cache?['hex_cor1']?.toString() ?? '#CCCCCC';
                        final percentual = totalAlunos > 0 ? (e.value / totalAlunos) * 100 : 0;

                        return PieChartSectionData(
                          value: e.value.toDouble(),
                          title: percentual >= 7 ? '${percentual.toStringAsFixed(0)}%' : '',
                          radius: 72,
                          titleStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _corTextoContraste(_hexToColor(hex)),
                          ),
                          color: _hexToColor(hex),
                        );
                      }).toList(),
                      sectionsSpace: 3,
                      centerSpaceRadius: 44,
                      centerSpaceColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...ordenadas.map((e) => _buildGraduacaoMiniLinha(e.key, e.value, totalAlunos)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...ordenadas.map(
              (e) => _buildGraduacaoCard(
            nomeGraduacao: e.key,
            quantidade: e.value,
            totalAlunos: totalAlunos,
            alunos: _alunosPorGraduacao[e.key] ?? [],
          ),
        ),
      ],
    );
  }

  Widget _graduacaoResumoCard({
    required String valor,
    required String label,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 6),
          Text(
            valor,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildGraduacaoMiniLinha(String nomeGraduacao, int quantidade, int totalAlunos) {
    final cache = _graduacoesCache[nomeGraduacao];
    final String hex = cache?['hex_cor1']?.toString() ?? '#CCCCCC';
    final cor = nomeGraduacao == 'SEM GRADUAÇÃO' ? Colors.grey : _hexToColor(hex);
    final percentual = totalAlunos > 0 ? quantidade / totalAlunos : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nomeGraduacao,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _corFundoChipQuantidade(cor),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _corBordaChipQuantidade(cor)),
                ),
                child: Text(
                  '$quantidade   ${(percentual * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _corTextoChipQuantidade(cor),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: percentual,
              minHeight: 7,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(cor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraduacaoCard({
    required String nomeGraduacao,
    required int quantidade,
    required int totalAlunos,
    required List<Map<String, dynamic>> alunos,
  }) {
    final bool isSem = nomeGraduacao == 'SEM GRADUAÇÃO';
    final cache = _graduacoesCache[nomeGraduacao];
    final String cor1 = cache?['hex_cor1']?.toString() ?? '#CCCCCC';
    final Color cor = isSem ? Colors.grey : _hexToColor(cor1);
    final double percentual = totalAlunos > 0 ? quantidade / totalAlunos : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: cor.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: cor.withOpacity(0.16)),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            leading: Container(
              width: 50,
              height: 66,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isSem ? Colors.grey.shade100 : cor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cor.withOpacity(0.22)),
              ),
              child: isSem
                  ? Icon(Icons.workspace_premium_outlined, color: Colors.grey.shade500)
                  : _buildCordaWidget(nomeGraduacao),
            ),
            title: Text(
              nomeGraduacao,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.grey.shade800,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: percentual,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(cor),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${(percentual * 100).toStringAsFixed(0)}% da turma',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _corFundoChipQuantidade(cor),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _corBordaChipQuantidade(cor),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$quantidade',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _corTextoChipQuantidade(cor),
                    ),
                  ),
                  Text(
                    quantidade == 1 ? 'aluno' : 'alunos',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: _corTextoChipQuantidade(cor).withOpacity(0.78),
                    ),
                  ),
                ],
              ),
            ),
            children: alunos.map((a) {
              final nomeAluno = a['nome']?.toString() ?? 'Sem nome';

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  leading: _buildAlunoAvatar(a),
                  title: Text(
                    nomeAluno,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _obterNomeGraduacaoAluno(a),
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey.shade400,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  //  CORDA SVG COM FALLBACK INTELIGENTE
  Widget _buildCordaWidget(String nomeGraduacao) {
    if (nomeGraduacao == 'SEM GRADUAÇÃO' || _svgContent == null) {
      return const SizedBox(width: 40, height: 60);
    }

    return FutureBuilder<String?>(
      future: _getSvgGraduacaoPorNome(nomeGraduacao),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.purple.shade400,
              ),
            ),
          );
        }

        final svgString = snapshot.data;

        if (svgString == null || svgString.isEmpty) {
          return Center(
            child: Icon(
              Icons.workspace_premium,
              size: 24,
              color: Colors.grey.shade500,
            ),
          );
        }

        return SvgPicture.string(
          svgString,
          width: 40,
          height: 60,
          fit: BoxFit.contain,
        );
      },
    );
  }

  Widget _buildAlunoAvatar(Map<String, dynamic> aluno) {
    final foto = aluno['foto_perfil_aluno'] as String?;
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: foto != null && foto.isNotEmpty
          ? NetworkImage(foto)
          : null,
      child: foto == null || foto.isEmpty
          ? Text(
        aluno['nome']?.substring(0, 1).toUpperCase() ?? '?',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      )
          : null,
    );
  }

  // ============ IDADE, SEXO, LISTAS ============
  Widget _buildGraficoIdade() {
    if (_alunosOrdenadosPorIdade.isEmpty)
      return _emptyChart('Nenhum aluno com idade calculada');
    final maxV =
        _distribuicaoIdade.values.reduce((a, b) => a > b ? a : b).toDouble() +
            1;
    return Column(
      children: [
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Distribuição por Faixa Etária',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxV,
                      barTouchData: BarTouchData(enabled: false),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, m) {
                              final idx = v.toInt();
                              if (idx >= 0 &&
                                  idx < _distribuicaoIdade.keys.length)
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _distribuicaoIdade.keys
                                        .elementAt(idx)
                                        .split(' ')
                                        .first,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 2,
                            reservedSize: 25,
                          ),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: _distribuicaoIdade.entries.map((e) {
                        final idx = _distribuicaoIdade.keys.toList().indexOf(
                          e.key,
                        );
                        return BarChartGroupData(
                          x: idx,
                          barRods: [
                            BarChartRodData(
                              toY: e.value.toDouble(),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.green.shade400,
                                  Colors.teal.shade300,
                                ],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                              width: 20,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ..._distribuicaoIdade.entries.map(
                      (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          _iconesFaixa[e.key] ?? Icons.person,
                          size: 18,
                          color: Colors.green.shade600,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.key,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          '${e.value} alunos',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildListaIdade(),
      ],
    );
  }

  Widget _buildListaIdade() => Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sort, color: Colors.green.shade700, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Alunos por idade',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _alunosOrdenadosPorIdade.length > _visibleItems
                ? _visibleItems
                : _alunosOrdenadosPorIdade.length,
            itemBuilder: (ctx, i) {
              final a = _alunosOrdenadosPorIdade[i];
              final idade = a['idade_calculada'] ?? 0;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: _buildAlunoAvatar(a),
                title: Text(
                  a['nome'] ?? '?',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$idade a',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
              );
            },
          ),
          if (_alunosOrdenadosPorIdade.length > _visibleItems)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _visibleItems += 20),
                child: const Text('Ver mais...'),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _buildFiltroSexo() => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: _btnSexo(
              'TODOS',
              Icons.people,
              filtroSexo == null,
              Colors.blue,
                  () => setState(() => filtroSexo = null),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _btnSexo(
              'MENINOS',
              Icons.male,
              filtroSexo == 'MASCULINO',
              Colors.blue,
                  () => setState(() => filtroSexo = 'MASCULINO'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _btnSexo(
              'MENINAS',
              Icons.female,
              filtroSexo == 'FEMININO',
              Colors.pink,
                  () => setState(() => filtroSexo = 'FEMININO'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: _cardSexo('MENINOS', _totalMeninos, Colors.blue, Icons.male),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _cardSexo(
              'MENINAS',
              _totalMeninas,
              Colors.pink,
              Icons.female,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _buildListaSexo(),
    ],
  );

  Widget _btnSexo(
      String t,
      IconData i,
      bool ativo,
      Color c,
      VoidCallback onTap,
      ) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: ativo ? c.withOpacity(0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ativo ? c : Colors.grey.shade300,
          width: ativo ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Icon(i, color: ativo ? c : Colors.grey.shade600, size: 22),
          const SizedBox(height: 4),
          Text(
            t,
            style: TextStyle(
              color: ativo ? c : Colors.grey.shade600,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _cardSexo(String t, int qtd, Color c, IconData i) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [c.withOpacity(0.7), c],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: c.withOpacity(0.3), blurRadius: 8)],
    ),
    child: Column(
      children: [
        Icon(i, color: Colors.white, size: 32),
        const SizedBox(height: 8),
        Text(
          t,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$qtd',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _buildListaSexo() {
    final filtrados = _alunosDaTurma.where((a) {
      if (filtroSexo == null) return true;
      return (a['sexo'] as String?)?.toUpperCase() == filtroSexo;
    }).toList();
    if (filtrados.isEmpty) return _emptyChart('Nenhum aluno');
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  filtroSexo == 'MASCULINO'
                      ? Icons.male
                      : filtroSexo == 'FEMININO'
                      ? Icons.female
                      : Icons.people,
                  color: filtroSexo == 'MASCULINO'
                      ? Colors.blue
                      : filtroSexo == 'FEMININO'
                      ? Colors.pink
                      : Colors.grey.shade700,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  filtroSexo == null
                      ? 'TODOS'
                      : filtroSexo == 'MASCULINO'
                      ? 'MENINOS'
                      : 'MENINAS',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: filtroSexo == 'MASCULINO'
                        ? Colors.blue
                        : filtroSexo == 'FEMININO'
                        ? Colors.pink
                        : Colors.grey.shade700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${filtrados.length} alunos',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtrados.length > _visibleItems
                  ? _visibleItems
                  : filtrados.length,
              itemBuilder: (ctx, i) {
                final a = filtrados[i];
                final isM =
                    (a['sexo'] as String?)?.toUpperCase() == 'MASCULINO';
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: _buildAlunoAvatar(a),
                  title: Text(
                    a['nome'] ?? '?',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isM ? Colors.blue.shade50 : Colors.pink.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isM ? Icons.male : Icons.female,
                      size: 14,
                      color: isM ? Colors.blue : Colors.pink,
                    ),
                  ),
                );
              },
            ),
            if (filtrados.length > _visibleItems)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _visibleItems += 20),
                  child: const Text('Ver mais...'),
                ),
              ),
          ],
        ),
      ),
    );
  }


  Widget _buildRankingAlunoTile(
      Map<String, dynamic> aluno, {
        required int posicao,
        required int valor,
        required bool destaque,
      }) {
    final nome = aluno['nome']?.toString() ?? 'Sem nome';
    final graduacao = _obterNomeGraduacaoAluno(aluno);
    final Color corBase = destaque ? Colors.amber.shade700 : Colors.blue.shade700;
    final Color medalColor = posicao == 1
        ? Colors.amber.shade700
        : posicao == 2
        ? Colors.blueGrey.shade400
        : posicao == 3
        ? Colors.brown.shade400
        : corBase;

    return InkWell(
      onTap: () => _mostrarDialog(aluno),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: destaque ? Colors.amber.shade50.withOpacity(0.55) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: destaque ? Colors.amber.shade100 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: medalColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$posicao',
                style: TextStyle(
                  fontSize: 12,
                  color: medalColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _buildAlunoAvatar(aluno),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nome,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    graduacao,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: corBase.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: corBase.withOpacity(0.16)),
              ),
              child: Text(
                '$valor',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: corBase,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaTop5() {
    if (_alunosFrequentes.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.shade700.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.workspace_premium_rounded, color: Colors.amber.shade800, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _getTituloTop5(),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _alunosFrequentes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final a = _alunosFrequentes[i];
                  final v = _getFrequenciaPorFiltro(a);
                  return _buildRankingAlunoTile(a, posicao: i + 1, valor: v, destaque: true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListaCompleta() {
    if (_alunosOrdenadosPorFrequencia.isEmpty) return const SizedBox.shrink();
    final totalVisivel = _alunosOrdenadosPorFrequencia.length > _visibleItems
        ? _visibleItems
        : _alunosOrdenadosPorFrequencia.length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.format_list_numbered_rounded, color: Colors.blue.shade700, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _getTituloLista(),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
                Text(
                  '$totalVisivel/${_alunosOrdenadosPorFrequencia.length}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: totalVisivel,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final a = _alunosOrdenadosPorFrequencia[i];
                final v = _getFrequenciaPorFiltro(a);
                return _buildRankingAlunoTile(a, posicao: i + 1, valor: v, destaque: false);
              },
            ),
            if (_alunosOrdenadosPorFrequencia.length > _visibleItems)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _visibleItems += 20),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: const Text('Ver mais alunos'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                      side: BorderSide(color: Colors.blue.shade100),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialog(Map<String, dynamic> aluno) {
    if (filtroAtivo != 'Frequência') return;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return _DetalheFrequenciaAlunoDashboardDialog(
          aluno: aluno,
          alunoId: aluno['id']?.toString() ?? '',
          alunoNome: aluno['nome']?.toString() ?? 'Aluno',
          turmaId: widget.turmaId,
          turmaNome: widget.turmaNome,
          filtroTemporal: filtroTemporalFrequencia,
          anoSelecionado: anoSelecionado,
        );
      },
    );
  }

  String _getTituloLista() =>
      filtroTemporalFrequencia == 'Ano' && anoSelecionado != null
          ? 'Todos os alunos - $anoSelecionado'
          : 'Todos os alunos ($filtroTemporalFrequencia)';

  String _getTituloTop5() =>
      filtroTemporalFrequencia == 'Ano' && anoSelecionado != null
          ? 'Top 5 - $anoSelecionado'
          : 'Top 5 ($filtroTemporalFrequencia)';

  Widget _emptyChart(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.show_chart, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    ),
  );

  Widget _buildShimmerLoading() => Shimmer.fromColors(
    baseColor: Colors.grey.shade300,
    highlightColor: Colors.grey.shade100,
    child: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );

  Widget _buildErroScreen() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(_erro!, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _inicializarDados,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildEmptyScreen() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('Nenhum aluno na turma'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _atualizarDadosReais,
            icon: const Icon(Icons.refresh),
            label: const Text('Verificar alunos'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );

  String _formatarTempoCache() {
    if (_ultimaAtualizacao == null) return 'Cache vazio';
    final agora = DateTime.now();
    final diferenca = agora.difference(_ultimaAtualizacao!);
    final minutosRestantes = _CACHE_VALIDADE_MINUTOS - diferenca.inMinutes;
    if (minutosRestantes <= 0) return 'Expirado';
    if (minutosRestantes < 60) return '${minutosRestantes}min';
    final horas = minutosRestantes ~/ 60;
    final minutos = minutosRestantes % 60;
    return '${horas}h${minutos > 0 ? '${minutos}m' : ''}';
  }
}


// ============================================
// 🔥 DETALHE DE FREQUÊNCIA DO ALUNO NO DASHBOARD
// Conta presenças pelos logs e ausências pelas chamadas também.
// ============================================

class _DetalheFrequenciaAlunoDashboardDialog extends StatefulWidget {
  final Map<String, dynamic> aluno;
  final String alunoId;
  final String alunoNome;
  final String turmaId;
  final String turmaNome;
  final String filtroTemporal;
  final String? anoSelecionado;

  const _DetalheFrequenciaAlunoDashboardDialog({
    required this.aluno,
    required this.alunoId,
    required this.alunoNome,
    required this.turmaId,
    required this.turmaNome,
    required this.filtroTemporal,
    required this.anoSelecionado,
  });

  @override
  State<_DetalheFrequenciaAlunoDashboardDialog> createState() =>
      _DetalheFrequenciaAlunoDashboardDialogState();
}

class _DetalheFrequenciaAlunoDashboardDialogState
    extends State<_DetalheFrequenciaAlunoDashboardDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final DateFormat _monthFormat = DateFormat('MMMM', 'pt_BR');

  bool _carregando = true;
  String? _erro;

  List<Map<String, dynamic>> _todos = [];
  List<Map<String, dynamic>> _presencas = [];
  List<Map<String, dynamic>> _ausencias = [];
  Map<String, int> _porTipo = {};
  Map<String, int> _porFonte = {};

  int _aba = 0;

  DateTimeRange? get _range => _periodoRange();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  DateTimeRange? _periodoRange() {
    final agora = DateTime.now();

    switch (widget.filtroTemporal) {
      case 'Semana':
        final inicio = agora.subtract(Duration(days: agora.weekday - 1));
        return DateTimeRange(
          start: DateTime(inicio.year, inicio.month, inicio.day),
          end: DateTime(agora.year, agora.month, agora.day, 23, 59, 59),
        );

      case 'Mês':
        return DateTimeRange(
          start: DateTime(agora.year, agora.month, 1),
          end: DateTime(agora.year, agora.month + 1, 0, 23, 59, 59),
        );

      case 'Ano':
        final ano = int.tryParse(widget.anoSelecionado ?? '') ?? agora.year;
        return DateTimeRange(
          start: DateTime(ano, 1, 1),
          end: DateTime(ano, 12, 31, 23, 59, 59),
        );

      case 'Total':
      default:
        return null;
    }
  }

  String get _tituloPeriodo {
    final agora = DateTime.now();

    switch (widget.filtroTemporal) {
      case 'Semana':
        return 'SEMANA ATUAL';
      case 'Mês':
        return _monthFormat.format(agora).toUpperCase();
      case 'Ano':
        return widget.anoSelecionado ?? agora.year.toString();
      case 'Total':
      default:
        return 'TODO HISTÓRICO';
    }
  }

  bool _dentroDoPeriodo(DateTime? data) {
    if (data == null) return false;

    final range = _range;

    if (range == null) return true;

    return !data.isBefore(range.start) && !data.isAfter(range.end);
  }

  Future<void> _carregar() async {
    if (widget.alunoId.isEmpty) {
      setState(() {
        _carregando = false;
        _erro = 'Aluno sem ID.';
      });
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final mapa = <String, Map<String, dynamic>>{};

      await _carregarLogsAluno(mapa);
      await _carregarChamadasTurma(mapa, 'chamadas');
      await _carregarChamadasTurma(mapa, 'chamadas_turma');

      final todos = mapa.values.toList()
        ..sort((a, b) {
          final da = a['data'] as DateTime? ?? DateTime(1900);
          final db = b['data'] as DateTime? ?? DateTime(1900);
          return db.compareTo(da);
        });

      final presencas = todos.where((e) => e['presente'] == true).toList();
      final ausencias = todos.where((e) => e['presente'] != true).toList();

      final porTipo = <String, int>{};
      final porFonte = <String, int>{};

      for (final item in todos) {
        if (item['presente'] == true) {
          final tipo = item['tipo_aula']?.toString() ?? 'Aula';
          porTipo[tipo] = (porTipo[tipo] ?? 0) + 1;
        }

        final fonte = item['fonte']?.toString() ?? 'logs';
        porFonte[fonte] = (porFonte[fonte] ?? 0) + 1;
      }

      if (!mounted) return;

      setState(() {
        _todos = todos;
        _presencas = presencas;
        _ausencias = ausencias;
        _porTipo = porTipo;
        _porFonte = porFonte;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
        _erro = 'Erro ao carregar detalhe: $e';
      });
    }
  }

  Future<void> _carregarLogsAluno(Map<String, Map<String, dynamic>> mapa) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('log_presenca_alunos')
        .where('aluno_id', isEqualTo: widget.alunoId);

    final range = _range;

    if (range != null) {
      query = query
          .where(
        'data_aula',
        isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
      )
          .where(
        'data_aula',
        isLessThanOrEqualTo: Timestamp.fromDate(range.end),
      );
    }

    final snapshot = await query
        .orderBy('data_aula', descending: true)
        .get(const GetOptions(source: Source.server));

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final dataAula = _toDate(data['data_aula']);

      if (!_dentroDoPeriodo(dataAula)) continue;

      final tipo = data['tipo_aula']?.toString() ?? 'Aula';
      final dataKey = _dataKey(dataAula, data['data_formatada']);
      final key = 'log_${doc.id}_$dataKey';

      mapa[key] = {
        'id': doc.id,
        'data': dataAula,
        'data_formatada': data['data_formatada']?.toString() ??
            (dataAula != null ? _dateFormat.format(dataAula) : ''),
        'presente': data['presente'] == true,
        'tipo_aula': tipo,
        'professor_nome': data['professor_nome']?.toString() ??
            data['professor']?.toString() ??
            data['registrado_por']?.toString() ??
            'Não informado',
        'observacao': data['observacao']?.toString() ?? '',
        'turma_id': data['turma_id']?.toString() ?? widget.turmaId,
        'turma_nome': data['turma_nome']?.toString() ?? widget.turmaNome,
        'fonte': 'log_presenca_alunos',
      };
    }
  }

  Future<void> _carregarChamadasTurma(
      Map<String, Map<String, dynamic>> mapa,
      String collection,
      ) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection(collection)
        .where('turma_id', isEqualTo: widget.turmaId);

    final snapshot = await query.get(const GetOptions(source: Source.server));

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final dataAula = _extrairDataChamada(data);

      if (!_dentroDoPeriodo(dataAula)) continue;

      final alunosRaw = data['alunos'];

      if (alunosRaw is! List) continue;

      Map<String, dynamic>? alunoNaChamada;

      for (final raw in alunosRaw) {
        if (raw is! Map) continue;

        final aluno = Map<String, dynamic>.from(raw);
        final alunoId = aluno['aluno_id']?.toString() ??
            aluno['id']?.toString() ??
            aluno['alunoId']?.toString() ??
            '';

        if (alunoId == widget.alunoId) {
          alunoNaChamada = aluno;
          break;
        }
      }

      if (alunoNaChamada == null) continue;

      final presente = _parsePresente(alunoNaChamada);
      final dataFormatada = data['data_formatada']?.toString() ??
          alunoNaChamada['data_formatada']?.toString() ??
          (dataAula != null ? _dateFormat.format(dataAula) : '');
      final tipo = data['tipo_aula']?.toString() ??
          alunoNaChamada['tipo_aula']?.toString() ??
          'Aula';
      final professor = data['professor_nome']?.toString() ??
          data['professor']?.toString() ??
          data['registrado_por_nome']?.toString() ??
          data['registrado_por']?.toString() ??
          alunoNaChamada['professor_nome']?.toString() ??
          'Não informado';

      final key = _chamadaKey(dataAula, dataFormatada, tipo);

      if (mapa.containsKey(key)) {
        final atual = mapa[key]!;

        // Se já veio do log, mantém a presença/falta do log,
        // mas marca que também foi confirmado na chamada.
        atual['fonte'] = '${atual['fonte']} + $collection';
        continue;
      }

      mapa[key] = {
        'id': doc.id,
        'data': dataAula,
        'data_formatada': dataFormatada,
        'presente': presente,
        'tipo_aula': tipo,
        'professor_nome': professor,
        'observacao': alunoNaChamada['observacao']?.toString() ??
            data['observacao']?.toString() ??
            '',
        'turma_id': widget.turmaId,
        'turma_nome': data['turma_nome']?.toString() ?? widget.turmaNome,
        'fonte': collection,
      };
    }
  }

  String _chamadaKey(DateTime? data, String dataFormatada, String tipo) {
    final dia = data != null ? _dateFormat.format(data) : dataFormatada;
    return 'chamada_${dia}_${tipo.toLowerCase().trim()}';
  }

  String _dataKey(DateTime? data, dynamic dataFormatada) {
    if (data != null) return _dateFormat.format(data);
    return dataFormatada?.toString() ?? '';
  }

  bool _parsePresente(Map<String, dynamic> data) {
    final value = data['presente'] ??
        data['is_presente'] ??
        data['presenca'] ??
        data['status_presenca'] ??
        data['status'];

    if (value == true) return true;
    if (value == false) return false;

    if (value is num) return value == 1;

    if (value is String) {
      final v = value.toLowerCase().trim();

      if (v == 'true' ||
          v == '1' ||
          v == 'sim' ||
          v == 'presente' ||
          v == 'p') {
        return true;
      }

      if (v == 'false' ||
          v == '0' ||
          v == 'não' ||
          v == 'nao' ||
          v == 'ausente' ||
          v == 'falta' ||
          v == 'faltou' ||
          v == 'a') {
        return false;
      }
    }

    return false;
  }

  DateTime? _extrairDataChamada(Map<String, dynamic> data) {
    final candidatos = [
      data['data_aula'],
      data['data_chamada'],
      data['data'],
      data['createdAt'],
      data['data_criacao'],
    ];

    for (final candidato in candidatos) {
      final parsed = _toDate(candidato);

      if (parsed != null) return parsed;
    }

    final dataFormatada = data['data_formatada']?.toString();

    if (dataFormatada != null && dataFormatada.trim().isNotEmpty) {
      try {
        return _dateFormat.parseStrict(dataFormatada.trim());
      } catch (_) {}
    }

    return null;
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  double get _percentual {
    final total = _presencas.length + _ausencias.length;
    if (total == 0) return 0;

    return (_presencas.length / total) * 100;
  }

  List<Map<String, dynamic>> get _listaAtual {
    switch (_aba) {
      case 1:
        return _presencas;
      case 2:
        return _ausencias;
      case 0:
      default:
        return _todos;
    }
  }

  Color _tipoColor(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'objetiva':
        return Colors.blue;
      case 'roda':
        return Colors.red;
      case 'instrumentação':
      case 'instrumentacao':
        return Colors.amber.shade700;
      case 'especial':
        return Colors.purple;
      case 'evento':
        return Colors.orange;
      case 'batizado':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: Colors.white.withOpacity(0.15),
              child: const Icon(
                Icons.person_search_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.alunoNome,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${widget.turmaNome} • $_tituloPeriodo',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _carregar,
              color: Colors.white,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Atualizar',
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              color: Colors.white,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Fechar',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_carregando) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.red),
            SizedBox(height: 12),
            Text('Calculando presença e ausência...'),
          ],
        ),
      );
    }

    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 74, color: Colors.red.shade300),
              const SizedBox(height: 12),
              const Text(
                'Erro ao carregar',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                _erro!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _carregar,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('TENTAR NOVAMENTE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        _buildResumo(),
        _buildAbas(),
        Expanded(
          child: _listaAtual.isEmpty
              ? _buildVazio()
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
            itemCount: _listaAtual.length,
            itemBuilder: (context, index) {
              return _buildItem(_listaAtual[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResumo() {
    final total = _todos.length;

    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;

              final cards = [
                _metricCard(
                  value: '${_presencas.length}',
                  label: 'Presenças',
                  icon: Icons.check_circle_rounded,
                  color: Colors.green,
                ),
                _metricCard(
                  value: '${_ausencias.length}',
                  label: 'Ausências',
                  icon: Icons.cancel_rounded,
                  color: Colors.red,
                ),
                _metricCard(
                  value: '${_percentual.toStringAsFixed(0)}%',
                  label: 'Frequência',
                  icon: Icons.pie_chart_rounded,
                  color: Colors.amber.shade800,
                ),
              ];

              if (narrow) {
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: cards,
                );
              }

              return Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 10),
                  Expanded(child: cards[1]),
                  const SizedBox(width: 10),
                  Expanded(child: cards[2]),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: total > 0 ? _percentual / 100 : 0,
              minHeight: 9,
              backgroundColor: Colors.red.shade50,
              valueColor: AlwaysStoppedAnimation<Color>(
                _percentual >= 80
                    ? Colors.green
                    : _percentual >= 60
                    ? Colors.amber
                    : Colors.red,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildFonteResumo(),
          if (_porTipo.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: _porTipo.entries.map((entry) {
                final color = _tipoColor(entry.key);

                return _chipInfo(
                  '${entry.key}: ${entry.value}',
                  color,
                  Icons.school_rounded,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricCard({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 124),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 7),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFonteResumo() {
    final logs = _porFonte.entries
        .where((e) => e.key.contains('log_presenca_alunos'))
        .fold<int>(0, (sum, e) => sum + e.value);
    final chamadas = _porFonte.entries
        .where((e) => e.key.contains('chamadas'))
        .fold<int>(0, (sum, e) => sum + e.value);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.blueGrey.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Presenças e ausências calculadas por logs + chamadas. '
                  'Logs: $logs • Chamadas: $chamadas',
              style: TextStyle(
                color: Colors.blueGrey.shade800,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipInfo(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbas() {
    final items = [
      ['Todos', _todos.length, Icons.list_alt_rounded, Colors.blueGrey],
      ['Presenças', _presencas.length, Icons.check_circle_rounded, Colors.green],
      ['Ausências', _ausencias.length, Icons.cancel_rounded, Colors.red],
    ];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final selected = _aba == index;
          final color = item[3] as Color;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                onTap: () => setState(() => _aba = index),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? color.withOpacity(0.12) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? color.withOpacity(0.30) : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item[2] as IconData, color: color, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${item[0]} (${item[1]})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? color : Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final presente = item['presente'] == true;
    final data = item['data'] as DateTime?;
    final dataFormatada = item['data_formatada']?.toString() ??
        (data != null ? _dateFormat.format(data) : '--/--/----');
    final tipo = item['tipo_aula']?.toString() ?? 'Aula';
    final professor = item['professor_nome']?.toString() ?? 'Não informado';
    final observacao = item['observacao']?.toString() ?? '';
    final fonte = item['fonte']?.toString() ?? '';
    final color = presente ? Colors.green : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: presente ? 2 : 1,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.16)),
          ),
          child: Row(
            children: [
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.24),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dataFormatada,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.09),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            presente ? 'PRESENTE' : 'AUSENTE',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        _chipInfo(tipo, _tipoColor(tipo), Icons.school_rounded),
                        _chipInfo(
                          fonte.contains('chamadas') ? 'chamada' : 'log',
                          Colors.blueGrey,
                          Icons.storage_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.assignment_ind_rounded,
                          color: Colors.purple.shade600,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Aula registrada por: $professor',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (observacao.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        observacao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, color: Colors.grey.shade300, size: 82),
            const SizedBox(height: 12),
            Text(
              _aba == 2
                  ? 'Nenhuma ausência encontrada'
                  : _aba == 1
                  ? 'Nenhuma presença encontrada'
                  : 'Nenhum registro encontrado',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Se existirem chamadas antigas, toque em atualizar ou confira se o aluno está no array da chamada.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

