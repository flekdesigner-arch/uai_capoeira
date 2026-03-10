import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/graduacao_model.dart';
import '../../services/svg_service.dart';
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

class _DashboardTurmasPageState extends State<DashboardTurmasPage> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  // ⏰ CONSTANTES DE CACHE - 1 HORA
  static const int _CACHE_VALIDADE_HORAS = 1;
  static const int _CACHE_VALIDADE_MINUTOS = _CACHE_VALIDADE_HORAS * 60;
  static const int _CACHE_VALIDADE_SEGUNDOS = _CACHE_VALIDADE_MINUTOS * 60;
  static const int _CACHE_VALIDADE_MS = _CACHE_VALIDADE_HORAS * 60 * 60 * 1000;

  // 🎯 FILTROS
  String filtroAtivo = 'Frequência';
  String? filtroSexo;
  String filtroTemporalFrequencia = 'Ano';
  String? anoSelecionado;
  List<String> anosDisponiveis = [];

  // 🔥 FIREBASE INSTANCE
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔥 ÚNICA FONTE DA VERDADE - TUDO EM MEMÓRIA
  List<Map<String, dynamic>> _alunosDaTurma = [];
  Map<String, GraduacaoModel> _graduacoesPorNome = {};
  String? _svgContent;

  // 📊 DADOS PROCESSADOS
  List<Map<String, dynamic>> _alunosOrdenadosPorFrequencia = [];
  List<Map<String, dynamic>> _alunosFrequentes = [];
  Map<String, int> _distribuicaoGraduacao = {};
  Map<String, List<Map<String, dynamic>>> _alunosPorGraduacao = {};
  List<Map<String, dynamic>> _alunosOrdenadosPorIdade = [];
  Map<String, int> _distribuicaoIdade = {};
  int _totalMeninos = 0;
  int _totalMeninas = 0;

  // ⚡ ESTADOS DE CARREGAMENTO E CACHE
  bool _isLoading = true;
  String? _erro;
  bool _isAtualizando = false;

  // ⏰ NOVO: CONTROLE DE CACHE
  DateTime? _ultimaAtualizacao;
  bool _verificouCacheHoje = false;
  Timer? _timerCache;

  // 📜 CONTROLE DE SCROLL
  final ScrollController _scrollController = ScrollController();
  int _visibleItems = 20;

  // 🎨 CACHES LOCAIS
  final Map<String, Color> _colorCache = {};
  final Map<String, String?> _svgCache = {};

  // 🗓️ CONSTANTES
  final Map<String, int> _faixasEtarias = {
    '4-7 anos': 0, '8-12 anos': 0, '13-17 anos': 0,
    '18-25 anos': 0, '26-35 anos': 0, '36-50 anos': 0, '50+ anos': 0,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inicializarDados();
    _scrollController.addListener(_onScroll);
    _iniciarTimerCache();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _timerCache?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Quando o app volta para foreground, verifica o cache
    if (state == AppLifecycleState.resumed) {
      _verificarEAtualizarCache();
    }
  }

  // ⏰ NOVO: INICIAR TIMER PARA VERIFICAR CACHE A CADA 30 MINUTOS
  void _iniciarTimerCache() {
    _timerCache = Timer.periodic(const Duration(minutes: 30), (timer) {
      if (mounted) {
        _verificarEAtualizarCache();
      }
    });
  }

  // ⏰ NOVO: VERIFICAR SE CACHE EXPIROU E ATUALIZAR
  Future<void> _verificarEAtualizarCache() async {
    if (!mounted) return;

    // Se já está atualizando, não faz nada
    if (_isAtualizando) return;

    // Se nunca foi atualizado, precisa atualizar
    if (_ultimaAtualizacao == null) {
      debugPrint('⏰ Cache nunca foi atualizado, atualizando...');
      await _atualizarDadosReais();
      return;
    }

    // Calcula diferença de tempo
    final agora = DateTime.now();
    final diferenca = agora.difference(_ultimaAtualizacao!);
    final expirado = diferenca.inMilliseconds > _CACHE_VALIDADE_MS;

    debugPrint('⏰ Última atualização: ${_ultimaAtualizacao!}');
    debugPrint('⏰ Diferença: ${diferenca.inMinutes} minutos');
    debugPrint('⏰ Cache expirado? $expirado');

    if (expirado) {
      debugPrint('⏰ Cache EXPIRADO! Atualizando automaticamente...');
      await _atualizarDadosReais();
    } else {
      debugPrint('⏰ Cache ainda VÁLIDO por mais ${_CACHE_VALIDADE_MINUTOS - diferenca.inMinutes} minutos');
    }
  }

  // ⏰ NOVO: SALVAR TIMESTAMP DA ATUALIZAÇÃO
  Future<void> _salvarTimestampAtualizacao() async {
    try {
      await _firestore
          .collection('turmas')
          .doc(widget.turmaId)
          .collection('estatisticas')
          .doc('dashboard')
          .update({
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('❌ Erro ao salvar timestamp: $e');
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      setState(() => _visibleItems += 20);
    }
  }

  // ==================== 🔥 MÉTODOS DE PARSING SEGURO ====================

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, int> _parseMapStringInt(dynamic value) {
    if (value == null) return {};

    if (value is Map) {
      final result = <String, int>{};
      value.forEach((key, val) {
        if (key is String) {
          result[key] = _parseInt(val);
        }
      });
      return result;
    }

    return {};
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
          final Map<String, dynamic> alunoMap = Map<String, dynamic>.from(aluno);

          if (alunoMap.containsKey('frequencia_temporal')) {
            alunoMap['frequencia_temporal'] = _parseFrequenciaTemporal(alunoMap['frequencia_temporal']);
          }

          if (alunoMap.containsKey('total_presencas')) {
            alunoMap['total_presencas'] = _parseInt(alunoMap['total_presencas']);
          }

          return alunoMap;
        }
        return <String, dynamic>{};
      }).toList();
    }

    return [];
  }

  // ==================== 🚀 CARREGAMENTO INTELIGENTE ====================

  Future<void> _inicializarDados() async {
    setState(() {
      _isLoading = true;
      _erro = null;
    });

    try {
      await Future.wait([
        _carregarSvg(),
        _carregarTodasGraduacoes(),
      ]);

      await _carregarAlunosDaTurma();

    } catch (e) {
      setState(() {
        _erro = 'Erro ao carregar: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _carregarSvg() async {
    _svgContent = await SvgService.getSvgContent(context);
    if (mounted) setState(() {});
  }

  Future<void> _carregarTodasGraduacoes() async {
    try {
      final snapshot = await _firestore
          .collection('graduacoes')
          .get(const GetOptions(source: Source.cache));

      final graduacoesPorNome = <String, GraduacaoModel>{};
      for (var doc in snapshot.docs) {
        final graduacao = GraduacaoModel.fromFirestore(doc);
        graduacoesPorNome[graduacao.nome] = graduacao;
      }
      _graduacoesPorNome = graduacoesPorNome;
    } catch (e) {
      final snapshot = await _firestore
          .collection('graduacoes')
          .get();
      final graduacoesPorNome = <String, GraduacaoModel>{};
      for (var doc in snapshot.docs) {
        final graduacao = GraduacaoModel.fromFirestore(doc);
        graduacoesPorNome[graduacao.nome] = graduacao;
      }
      _graduacoesPorNome = graduacoesPorNome;
    }
  }

  Future<void> _carregarAlunosDaTurma() async {
    try {
      DocumentSnapshot<Map<String, dynamic>> turmaDoc;

      // PRIMEIRO: TENTA CARREGAR DO CACHE (MAIS RÁPIDO)
      try {
        turmaDoc = await _firestore
            .collection('turmas')
            .doc(widget.turmaId)
            .collection('estatisticas')
            .doc('dashboard')
            .get(const GetOptions(source: Source.cache));

        debugPrint('📦 Dados carregados do CACHE com sucesso!');
      } catch (e) {
        // SE FALHAR CACHE, BUSCA DO SERVIDOR
        debugPrint('📦 Cache não encontrado, buscando do servidor...');
        turmaDoc = await _firestore
            .collection('turmas')
            .doc(widget.turmaId)
            .collection('estatisticas')
            .doc('dashboard')
            .get();
      }

      if (!turmaDoc.exists) {
        debugPrint('📦 Documento não existe, criando...');
        await _criarDocumentoDashboard();
        await _carregarAlunosDaTurma();
        return;
      }

      final data = turmaDoc.data()!;

      // ⏰ VERIFICAR TIMESTAMP DA ÚLTIMA ATUALIZAÇÃO
      final timestamp = data['ultima_atualizacao'] as Timestamp?;
      if (timestamp != null) {
        _ultimaAtualizacao = timestamp.toDate();
        debugPrint('⏰ Última atualização do cache: ${_ultimaAtualizacao!}');
      }

      _alunosDaTurma = _parseAlunos(data['alunos']);
      anosDisponiveis = List<String>.from(data['anos_disponiveis'] ?? []);

      if (anosDisponiveis.isEmpty) {
        anosDisponiveis = [DateTime.now().year.toString()];
      }

      if (anoSelecionado == null && anosDisponiveis.isNotEmpty) {
        anoSelecionado = anosDisponiveis.first;
      }

      _processarTodosDados();

      setState(() {
        _isLoading = false;
      });

      // ⏰ APÓS CARREGAR, VERIFICA SE PRECISA ATUALIZAR O CACHE
      await _verificarEAtualizarCache();

    } catch (e) {
      debugPrint('❌ Erro: $e');
      setState(() {
        _erro = 'Erro ao carregar dados';
        _isLoading = false;
      });
    }
  }

  // ==================== 🔄 FUNÇÃO DE ATUALIZAÇÃO REAL ====================

  Future<void> _atualizarDadosReais() async {
    // Se já está atualizando, não faz nada
    if (_isAtualizando) return;

    setState(() {
      _isAtualizando = true;
      _erro = null;
    });

    try {
      debugPrint('🔄 INICIANDO ATUALIZAÇÃO REAL DOS DADOS...');

      // 1️⃣ BUSCAR ALUNOS ATUAIS DA TURMA (FONTE VERDADEIRA)
      final alunosSnapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .get(const GetOptions(source: Source.server));

      final alunosAtuais = alunosSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();

      debugPrint('📊 Alunos atuais encontrados: ${alunosAtuais.length}');

      // 2️⃣ BUSCAR TODOS OS LOGS DE PRESENÇA DOS ALUNOS ATUAIS
      final logsMap = await _buscarTodosLogsAlunos(alunosAtuais);

      // 3️⃣ PROCESSAR ALUNOS COM LOGS ATUALIZADOS
      final alunosProcessados = await _processarAlunosComLogs(alunosAtuais, logsMap);

      // 4️⃣ COLETAR ANOS DISPONÍVEIS
      final Set<String> anosSet = {};
      for (var aluno in alunosProcessados) {
        final freqTemporal = aluno['frequencia_temporal'] as Map<String, int>? ?? {};
        freqTemporal.forEach((key, value) {
          if (key.length == 4 && int.tryParse(key) != null && value > 0) {
            anosSet.add(key);
          }
        });
      }

      if (anosSet.isEmpty) {
        anosSet.add(DateTime.now().year.toString());
      }

      final anosList = anosSet.toList()..sort((a, b) => b.compareTo(a));

      // 5️⃣ CRIAR NOVO DOCUMENTO LIMPO (SOBRESCREVER COMPLETAMENTE)
      final agora = DateTime.now();
      final novoDashboard = {
        'alunos': alunosProcessados,
        'anos_disponiveis': anosList,
        'total_alunos': alunosProcessados.length,
        'ultima_atualizacao': Timestamp.fromDate(agora), // Usar Timestamp do Firebase
        'ultima_atualizacao_iso': agora.toIso8601String(),
      };

      // 6️⃣ SALVAR NO FIRESTORE (SOBRESCREVER)
      await _firestore
          .collection('turmas')
          .doc(widget.turmaId)
          .collection('estatisticas')
          .doc('dashboard')
          .set(novoDashboard);

      // 7️⃣ ATUALIZAR TIMESTAMP LOCAL
      setState(() {
        _ultimaAtualizacao = agora;
      });

      debugPrint('✅ Dashboard atualizado com sucesso em: $agora');

      // 8️⃣ ATUALIZAR ESTADO LOCAL
      setState(() {
        _alunosDaTurma = alunosProcessados;
        anosDisponiveis = anosList;
        if (anoSelecionado == null || !anosDisponiveis.contains(anoSelecionado)) {
          anoSelecionado = anosDisponiveis.isNotEmpty ? anosDisponiveis.first : null;
        }
      });

      // 9️⃣ REPROCESSAR DADOS
      _processarTodosDados();

      // 🔟 MOSTRA MENSAGEM DE SUCESSO (OPCIONAL - PODE REMOVER SE QUISER SILENCIOSO)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Dados atualizados! ${alunosProcessados.length} alunos sincronizados'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      }

    } catch (e) {
      debugPrint('❌ Erro na atualização: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao atualizar: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  // 🔍 BUSCAR TODOS OS LOGS DOS ALUNOS
  Future<Map<String, List<Map<String, dynamic>>>> _buscarTodosLogsAlunos(
      List<Map<String, dynamic>> alunos
      ) async {
    final Map<String, List<Map<String, dynamic>>> logsMap = {};
    final idsAlunos = alunos.map((a) => a['id'] as String).toList();

    // Processa em lotes de 10 (limitação do Firestore)
    for (var i = 0; i < idsAlunos.length; i += 10) {
      final end = i + 10 < idsAlunos.length ? i + 10 : idsAlunos.length;
      final batchIds = idsAlunos.sublist(i, end);

      final snapshot = await _firestore
          .collection('log_presenca_alunos')
          .where('aluno_id', whereIn: batchIds)
          .where('turma_id', isEqualTo: widget.turmaId)
          .get(const GetOptions(source: Source.server));

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final alunoId = data['aluno_id'] as String;
        logsMap.putIfAbsent(alunoId, () => []);
        logsMap[alunoId]!.add(data);
      }
    }

    debugPrint('📊 Logs encontrados: ${logsMap.values.fold(0, (sum, list) => sum + list.length)}');
    return logsMap;
  }

  // 🧮 PROCESSAR ALUNOS COM LOGS
  Future<List<Map<String, dynamic>>> _processarAlunosComLogs(
      List<Map<String, dynamic>> alunos,
      Map<String, List<Map<String, dynamic>>> logsMap
      ) async {
    final List<Map<String, dynamic>> alunosProcessados = [];

    for (var aluno in alunos) {
      final alunoId = aluno['id'] as String;
      final logs = logsMap[alunoId] ?? [];

      // Calcula frequência temporal
      final frequenciaTemporal = _calcularPresencasPorPeriodo(logs);

      // Cria aluno com dados processados
      final alunoProcessado = {
        ...aluno,
        'frequencia_temporal': frequenciaTemporal,
        'total_presencas': frequenciaTemporal['total'] ?? 0,
      };

      alunosProcessados.add(alunoProcessado);
    }

    return alunosProcessados;
  }

  // 🧮 CALCULAR PRESENÇAS
  Map<String, int> _calcularPresencasPorPeriodo(List<Map<String, dynamic>> logs) {
    final now = DateTime.now();
    final umaSemanaAtras = now.subtract(const Duration(days: 7));
    final umMesAtras = DateTime(now.year, now.month - 1, now.day);

    int total = 0;
    int semana = 0;
    int mes = 0;
    final Map<String, int> porAno = {};

    for (var log in logs) {
      final presente = log['presente'] as bool? ?? false;
      if (!presente) continue;

      final dataLog = (log['data_aula'] as Timestamp?)?.toDate();
      if (dataLog == null) continue;

      total++;

      if (dataLog.isAfter(umaSemanaAtras)) semana++;
      if (dataLog.isAfter(umMesAtras)) mes++;

      final ano = dataLog.year.toString();
      porAno[ano] = (porAno[ano] ?? 0) + 1;
    }

    return {
      'total': total,
      'semana': semana,
      'mes': mes,
      ...porAno,
    };
  }

  // 📝 CRIAR DOCUMENTO DE DASHBOARD
  Future<void> _criarDocumentoDashboard() async {
    try {
      final alunosSnapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .get();

      final alunos = alunosSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();

      final logsMap = await _buscarTodosLogsAlunos(alunos);
      final dadosAgregados = await _processarAlunosComLogs(alunos, logsMap);

      final Set<String> anosSet = {};
      for (var aluno in dadosAgregados) {
        final freqTemporal = aluno['frequencia_temporal'] as Map<String, int>? ?? {};
        freqTemporal.forEach((key, value) {
          if (key.length == 4 && int.tryParse(key) != null && value > 0) {
            anosSet.add(key);
          }
        });
      }

      if (anosSet.isEmpty) anosSet.add(DateTime.now().year.toString());
      final anosList = anosSet.toList()..sort((a, b) => b.compareTo(a));

      final agora = DateTime.now();
      await _firestore
          .collection('turmas')
          .doc(widget.turmaId)
          .collection('estatisticas')
          .doc('dashboard')
          .set({
        'alunos': dadosAgregados,
        'anos_disponiveis': anosList,
        'ultima_atualizacao': Timestamp.fromDate(agora),
        'ultima_atualizacao_iso': agora.toIso8601String(),
        'total_alunos': alunos.length,
      });

    } catch (e) {
      debugPrint('❌ Erro ao criar dashboard: $e');
    }
  }

  // 🔥 PROCESSAR TODOS OS DADOS
  void _processarTodosDados() {
    final now = DateTime.now();

    // 1️⃣ ORDENAR POR FREQUÊNCIA
    _alunosOrdenadosPorFrequencia = List<Map<String, dynamic>>.from(_alunosDaTurma)
      ..sort((a, b) {
        final freqA = _getFrequenciaPorFiltro(a);
        final freqB = _getFrequenciaPorFiltro(b);
        return freqB.compareTo(freqA);
      });

    _alunosFrequentes = _alunosOrdenadosPorFrequencia.take(5).toList();

    // 2️⃣ DISTRIBUIÇÃO POR GRADUAÇÃO
    final Map<String, int> distGraduacao = {};
    final Map<String, List<Map<String, dynamic>>> alunosPorGrad = {};

    for (var aluno in _alunosDaTurma) {
      String graduacaoNome = aluno['graduacao_atual'] ?? 'SEM GRADUAÇÃO';

      if (graduacaoNome.isEmpty) {
        graduacaoNome = 'SEM GRADUAÇÃO';
      }

      distGraduacao[graduacaoNome] = (distGraduacao[graduacaoNome] ?? 0) + 1;
      alunosPorGrad.putIfAbsent(graduacaoNome, () => []).add(aluno);
    }

    _distribuicaoGraduacao = distGraduacao;
    _alunosPorGraduacao = alunosPorGrad;

    // 3️⃣ IDADES
    final Map<String, int> faixas = Map.from(_faixasEtarias);
    final List<Map<String, dynamic>> alunosComIdade = [];

    for (var aluno in _alunosDaTurma) {
      final dataNascimento = (aluno['data_nascimento'] as Timestamp?)?.toDate();

      if (dataNascimento != null) {
        int idade = now.year - dataNascimento.year;
        if (now.month < dataNascimento.month ||
            (now.month == dataNascimento.month && now.day < dataNascimento.day)) {
          idade--;
        }

        final alunoComIdade = Map<String, dynamic>.from(aluno);
        alunoComIdade['idade_calculada'] = idade;
        alunosComIdade.add(alunoComIdade);

        if (idade <= 7) faixas['4-7 anos'] = faixas['4-7 anos']! + 1;
        else if (idade <= 12) faixas['8-12 anos'] = faixas['8-12 anos']! + 1;
        else if (idade <= 17) faixas['13-17 anos'] = faixas['13-17 anos']! + 1;
        else if (idade <= 25) faixas['18-25 anos'] = faixas['18-25 anos']! + 1;
        else if (idade <= 35) faixas['26-35 anos'] = faixas['26-35 anos']! + 1;
        else if (idade <= 50) faixas['36-50 anos'] = faixas['36-50 anos']! + 1;
        else faixas['50+ anos'] = faixas['50+ anos']! + 1;
      }
    }

    alunosComIdade.sort((a, b) {
      int idadeA = a['idade_calculada'] ?? 0;
      int idadeB = b['idade_calculada'] ?? 0;
      return idadeA.compareTo(idadeB);
    });

    _alunosOrdenadosPorIdade = alunosComIdade;
    _distribuicaoIdade = faixas;

    // 4️⃣ SEXO
    _totalMeninos = _alunosDaTurma
        .where((a) => (a['sexo'] as String?)?.toUpperCase() == 'MASCULINO')
        .length;
    _totalMeninas = _alunosDaTurma
        .where((a) => (a['sexo'] as String?)?.toUpperCase() == 'FEMININO')
        .length;
  }

  // 🎯 GET FREQUÊNCIA POR FILTRO
  int _getFrequenciaPorFiltro(Map<String, dynamic> aluno) {
    try {
      final frequenciaData = aluno['frequencia_temporal'];

      if (frequenciaData == null) return 0;

      Map<String, int> freqMap;

      if (frequenciaData is Map) {
        freqMap = {};
        frequenciaData.forEach((key, value) {
          if (key is String) {
            freqMap[key] = _parseInt(value);
          }
        });
      } else {
        return 0;
      }

      switch (filtroTemporalFrequencia) {
        case 'Semana':
          return freqMap['semana'] ?? 0;
        case 'Mês':
          return freqMap['mes'] ?? 0;
        case 'Ano':
          if (anoSelecionado != null) {
            return freqMap[anoSelecionado!] ?? 0;
          }
          return freqMap['total'] ?? 0;
        case 'Total':
          return freqMap['total'] ?? 0;
        default:
          return 0;
      }
    } catch (e) {
      debugPrint('❌ Erro ao pegar frequência: $e');
      return 0;
    }
  }

  // 🔄 ATUALIZAR COM FILTRO
  void _atualizarComFiltro() {
    setState(() {
      _alunosOrdenadosPorFrequencia = List<Map<String, dynamic>>.from(_alunosDaTurma)
        ..sort((a, b) {
          final freqA = _getFrequenciaPorFiltro(a);
          final freqB = _getFrequenciaPorFiltro(b);
          return freqB.compareTo(freqA);
        });
      _alunosFrequentes = _alunosOrdenadosPorFrequencia.take(5).toList();
    });
  }

  // 🎨 CONVERTER HEX PARA COLOR
  Color _hexToColor(String hex) {
    if (_colorCache.containsKey(hex)) return _colorCache[hex]!;
    String hexClean = hex.replaceFirst('#', '');
    Color color;
    if (hexClean.length == 6) {
      color = Color(int.parse('FF$hexClean', radix: 16));
    } else if (hexClean.length == 8) {
      color = Color(int.parse(hexClean, radix: 16));
    } else {
      color = Colors.grey;
    }
    _colorCache[hex] = color;
    return color;
  }

  // ==================== 📊 GRÁFICO DE FREQUÊNCIA ====================

  Widget _buildGraficoFrequencia() {
    if (_alunosFrequentes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text('Sem dados de frequência', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    final Map<String, int> dadosGrafico = {};
    int maxValor = 0;

    for (var aluno in _alunosFrequentes) {
      final nome = aluno['nome']?.split(' ').first ?? 'Aluno';
      final valor = _getFrequenciaPorFiltro(aluno);
      dadosGrafico[nome] = valor;
      if (valor > maxValor) maxValor = valor;
    }

    double intervaloY = _calcularIntervaloGrafico(maxValor);

    return SizedBox(
      height: 250,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (maxValor + intervaloY).toDouble(),
          minY: 0,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => Colors.blue.shade700,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${dadosGrafico.keys.elementAt(group.x)}\n${rod.toY.toInt()} presenças',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < dadosGrafico.keys.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Transform.rotate(
                        angle: -0.3,
                        child: Text(
                          dadosGrafico.keys.elementAt(index),
                          style: const TextStyle(fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: intervaloY,
                reservedSize: 35,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300, width: 1),
              left: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
          ),
          gridData: FlGridData(
            show: true,
            horizontalInterval: intervaloY,
            drawVerticalLine: false,
          ),
          barGroups: dadosGrafico.entries.map((entry) {
            final index = dadosGrafico.keys.toList().indexOf(entry.key);
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: entry.value.toDouble(),
                  color: Colors.blue.shade400,
                  width: 22,
                  borderRadius: BorderRadius.circular(4),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxValor.toDouble(),
                    color: Colors.grey.shade200,
                  ),
                ),
              ],
              showingTooltipIndicators: [0],
            );
          }).toList(),
        ),
      ),
    );
  }

  double _calcularIntervaloGrafico(int maxValor) {
    if (maxValor <= 5) return 1;
    if (maxValor <= 10) return 2;
    if (maxValor <= 20) return 4;
    if (maxValor <= 50) return 10;
    if (maxValor <= 100) return 20;
    return (maxValor / 10).ceilToDouble();
  }

  // ==================== 🎛️ FILTROS ====================

  Widget _buildFiltroTemporal() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            children: [
              _buildTemporalButton('Semana', Icons.calendar_view_week),
              _buildTemporalButton('Mês', Icons.calendar_month),
              _buildTemporalButton('Ano', Icons.calendar_today),
              _buildTemporalButton('Total', Icons.history),
            ],
          ),
        ),
        if (filtroTemporalFrequencia == 'Ano' && anosDisponiveis.isNotEmpty)
          _buildSeletorAno(),
      ],
    );
  }

  Widget _buildTemporalButton(String titulo, IconData icone) {
    bool isAtivo = filtroTemporalFrequencia == titulo;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            filtroTemporalFrequencia = titulo;
            _atualizarComFiltro();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isAtivo ? Colors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, size: 16, color: isAtivo ? Colors.white : Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                titulo,
                style: TextStyle(
                  color: isAtivo ? Colors.white : Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: isAtivo ? FontWeight.bold : FontWeight.normal,
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
      margin: const EdgeInsets.only(bottom: 16),
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: anosDisponiveis.length,
        itemBuilder: (context, index) {
          final ano = anosDisponiveis[index];
          final isAtivo = anoSelecionado == ano;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(ano),
              selected: isAtivo,
              onSelected: (selected) {
                setState(() {
                  anoSelecionado = ano;
                  _atualizarComFiltro();
                });
              },
              backgroundColor: Colors.grey.shade100,
              selectedColor: Colors.blue.shade100,
              labelStyle: TextStyle(
                color: isAtivo ? Colors.blue.shade700 : Colors.grey.shade700,
                fontWeight: isAtivo ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  // ==================== 📋 LISTAS ====================

  Widget _buildListaFrequenciaCompleta() {
    if (_alunosOrdenadosPorFrequencia.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sort_by_alpha, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _getTituloLista(),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _alunosOrdenadosPorFrequencia.length > _visibleItems
                    ? _visibleItems
                    : _alunosOrdenadosPorFrequencia.length,
                itemBuilder: (context, index) {
                  final aluno = _alunosOrdenadosPorFrequencia[index];
                  final total = _getFrequenciaPorFiltro(aluno);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: _buildAlunoAvatar(aluno),
                    title: Text(
                      aluno['nome'] ?? 'Sem nome',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _getSubtitulo(total),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        '$total',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                      ),
                    ),
                    onTap: () => _mostrarDialogFrequencia(aluno),
                  );
                },
              ),
              if (_alunosOrdenadosPorFrequencia.length > _visibleItems)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: TextButton(
                      onPressed: () => setState(() => _visibleItems += 20),
                      child: const Text('Carregar mais...'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _getTituloLista() {
    if (filtroTemporalFrequencia == 'Ano' && anoSelecionado != null) {
      return 'Todos os alunos - $anoSelecionado';
    }
    return 'Todos os alunos por frequência ($filtroTemporalFrequencia)';
  }

  String _getSubtitulo(int total) {
    if (filtroTemporalFrequencia == 'Ano' && anoSelecionado != null) {
      return 'Presenças em $anoSelecionado: $total';
    }
    return 'Presenças ($filtroTemporalFrequencia): $total';
  }

  Widget _buildListaTop5Frequentes() {
    if (_alunosFrequentes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Icon(Icons.star, color: Colors.amber[700], size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _getTituloTop5(),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _alunosFrequentes.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final aluno = _alunosFrequentes[index];
            final total = _getFrequenciaPorFiltro(aluno);

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              leading: _buildAlunoAvatar(aluno),
              title: Text(
                aluno['nome'] ?? 'Sem nome',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _getSubtitulo(total),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Text(
                  '$total',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade700),
                ),
              ),
              onTap: () => _mostrarDialogFrequencia(aluno),
            );
          },
        ),
      ],
    );
  }

  String _getTituloTop5() {
    if (filtroTemporalFrequencia == 'Ano' && anoSelecionado != null) {
      return 'Top 5 alunos - $anoSelecionado';
    }
    return 'Top 5 alunos ($filtroTemporalFrequencia)';
  }

  // ==================== 🎴 DIALOG ====================

  void _mostrarDialogFrequencia(Map<String, dynamic> aluno) {
    if (filtroAtivo != 'Frequência') return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: CardFrequenciaModerno(
            alunoId: aluno['id'],
            filtroTemporal: filtroTemporalFrequencia,
            anoSelecionado: anoSelecionado,
          ),
        ),
      ),
    );
  }

  // ==================== 🎓 GRÁFICO DE GRADUAÇÃO ====================

  Widget _buildGraficoGraduacao() {
    if (_distribuicaoGraduacao.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text('Sem dados de graduação', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    var graduacoesOrdenadas = _distribuicaoGraduacao.entries.toList()
      ..sort((a, b) {
        GraduacaoModel? gradA, gradB;
        gradA = _graduacoesPorNome[a.key];
        gradB = _graduacoesPorNome[b.key];
        return (gradA?.nivel ?? 999).compareTo(gradB?.nivel ?? 999);
      });

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sections: graduacoesOrdenadas.map((entry) {
                String corHex = '#CCCCCC';
                final graduacao = _graduacoesPorNome[entry.key];
                if (graduacao != null) {
                  corHex = graduacao.cor1;
                }
                return PieChartSectionData(
                  value: entry.value.toDouble(),
                  title: '${entry.value}',
                  radius: 80,
                  titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  color: _hexToColor(corHex),
                );
              }).toList(),
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              centerSpaceColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: graduacoesOrdenadas.map((entry) {
            String corHex = '#CCCCCC';
            final graduacao = _graduacoesPorNome[entry.key];
            if (graduacao != null) {
              corHex = graduacao.cor1;
            }
            final cor = _hexToColor(corHex);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(entry.key.split('-').last.trim(), style: TextStyle(fontSize: 12, color: cor, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 4),
                  Text('${entry.value}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cor)),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        ...graduacoesOrdenadas.map((entry) {
          final alunos = _alunosPorGraduacao[entry.key] ?? [];
          String cor1 = '#CCCCCC', cor2 = '#FFFFFF', ponta1 = '#CCCCCC', ponta2 = '#CCCCCC';
          final graduacao = _graduacoesPorNome[entry.key];
          if (graduacao != null) {
            cor1 = graduacao.cor1;
            cor2 = graduacao.cor2;
            ponta1 = graduacao.ponta1;
            ponta2 = graduacao.ponta2;
          }
          return _buildGraduacaoCard(
            nomeGraduacao: entry.key,
            quantidade: entry.value,
            alunos: alunos,
            cor1: cor1,
            cor2: cor2,
            ponta1: ponta1,
            ponta2: ponta2,
          );
        }).toList(),
      ],
    );
  }

  Widget _buildGraduacaoCard({
    required String nomeGraduacao,
    required int quantidade,
    required List<Map<String, dynamic>> alunos,
    required String cor1,
    required String cor2,
    required String ponta1,
    required String ponta2,
  }) {
    final bool isSemGraduacao = nomeGraduacao == 'SEM GRADUAÇÃO';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: isSemGraduacao
              ? const SizedBox(width: 40, height: 60)
              : _buildCordaWidget(cor1, cor2, ponta1, ponta2),
          title: Text(nomeGraduacao, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSemGraduacao ? Colors.grey.shade200 : _hexToColor(cor1).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$quantidade',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSemGraduacao ? Colors.grey : _hexToColor(cor1),
              ),
            ),
          ),
          children: alunos.map((aluno) {
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: _buildAlunoAvatar(aluno),
              title: Text(
                aluno['nome'] ?? 'Sem nome',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _getGraduacaoNome(aluno),
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: null,
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCordaWidget(String cor1, String cor2, String ponta1, String ponta2) {
    final cacheKey = '$cor1-$cor2-$ponta1-$ponta2';
    if (_svgCache.containsKey(cacheKey)) {
      final cached = _svgCache[cacheKey];
      if (cached != null) return SvgPicture.string(cached, width: 40, height: 60, fit: BoxFit.contain);
    }
    if (_svgContent == null) {
      return Container(width: 40, height: 60, color: Colors.grey.shade200, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final modified = SvgService.getModifiedSvg(
      svgContent: _svgContent!,
      cor1: _hexToColor(cor1),
      cor2: _hexToColor(cor2),
      ponta1: _hexToColor(ponta1),
      ponta2: _hexToColor(ponta2),
    );
    if (modified == null) {
      return Container(width: 40, height: 60, color: Colors.grey.shade200, child: const Icon(Icons.error, color: Colors.red));
    }
    _svgCache[cacheKey] = modified;
    return SvgPicture.string(modified, width: 40, height: 60, fit: BoxFit.contain);
  }

  Widget _buildAlunoAvatar(Map<String, dynamic> aluno) {
    final fotoUrl = aluno['foto_perfil_aluno'] as String?;

    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty
          ? NetworkImage(fotoUrl)
          : null,
      child: fotoUrl == null || fotoUrl.isEmpty
          ? Text(
        aluno['nome']?.substring(0, 1).toUpperCase() ?? '?',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
      )
          : null,
    );
  }

  String _getGraduacaoNome(Map<String, dynamic> aluno) {
    return aluno['graduacao_atual']?.split('-').last.trim() ?? '';
  }

  // ==================== 📊 GRÁFICO DE IDADE ====================

  Widget _buildGraficoIdade() {
    if (_alunosOrdenadosPorIdade.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text('Nenhum aluno com idade calculada', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 250,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: _distribuicaoIdade.values.reduce((a, b) => a > b ? a : b).toDouble() + 1,
              barTouchData: BarTouchData(enabled: false),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < _distribuicaoIdade.keys.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _distribuicaoIdade.keys.elementAt(index),
                            style: const TextStyle(fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 2,
                    reservedSize: 30,
                  ),
                ),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              barGroups: _distribuicaoIdade.entries.map((entry) {
                final index = _distribuicaoIdade.keys.toList().indexOf(entry.key);
                return BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: entry.value.toDouble(),
                      color: Colors.green.shade400,
                      width: 20,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ..._distribuicaoIdade.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.green.shade400, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(entry.key, style: const TextStyle(fontSize: 14))),
                Text('${entry.value} alunos', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          );
        }).toList(),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sort_by_alpha, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Alunos por idade (do mais novo ao mais velho)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _alunosOrdenadosPorIdade.length > _visibleItems ? _visibleItems : _alunosOrdenadosPorIdade.length,
                itemBuilder: (context, index) {
                  final aluno = _alunosOrdenadosPorIdade[index];
                  final idade = aluno['idade_calculada'] ?? 0;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: _buildAlunoAvatar(aluno),
                    title: Text(
                      aluno['nome'] ?? 'Sem nome',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('Idade: $idade anos', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Text('$idade anos', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                    ),
                    onTap: null,
                  );
                },
              ),
              if (_alunosOrdenadosPorIdade.length > _visibleItems)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: TextButton(
                      onPressed: () => setState(() => _visibleItems += 20),
                      child: const Text('Carregar mais...'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== 👫 FILTRO DE SEXO ====================

  Widget _buildFiltroSexo() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildSexoButton('TODOS', Icons.people, filtroSexo == null, Colors.blue, () {
              setState(() {
                filtroSexo = null;
              });
            })),
            const SizedBox(width: 8),
            Expanded(child: _buildSexoButton('MENINOS', Icons.male, filtroSexo == 'MASCULINO', Colors.blue, () {
              setState(() {
                filtroSexo = 'MASCULINO';
              });
            })),
            const SizedBox(width: 8),
            Expanded(child: _buildSexoButton('MENINAS', Icons.female, filtroSexo == 'FEMININO', Colors.pink, () {
              setState(() {
                filtroSexo = 'FEMININO';
              });
            })),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _buildSexoCard('MENINOS', _totalMeninos, Colors.blue, Icons.male)),
            const SizedBox(width: 12),
            Expanded(child: _buildSexoCard('MENINAS', _totalMeninas, Colors.pink, Icons.female)),
          ],
        ),
        const SizedBox(height: 20),
        _buildListaPorSexo(),
      ],
    );
  }

  Widget _buildSexoButton(String titulo, IconData icone, bool ativo, Color cor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: ativo ? cor.withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ativo ? cor : Colors.grey.shade300, width: ativo ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(icone, color: ativo ? cor : Colors.grey.shade600, size: 24),
            const SizedBox(height: 4),
            Text(titulo, style: TextStyle(color: ativo ? cor : Colors.grey.shade600, fontWeight: ativo ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSexoCard(String titulo, int quantidade, Color cor, IconData icone) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cor.withOpacity(0.7), cor]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: cor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Icon(icone, color: Colors.white, size: 32),
          const SizedBox(height: 8),
          Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('$quantidade', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildListaPorSexo() {
    final alunosFiltrados = _alunosDaTurma.where((aluno) {
      if (filtroSexo == null) return true;
      final sexo = (aluno['sexo'] as String?)?.toUpperCase();
      return sexo == filtroSexo;
    }).toList();

    if (alunosFiltrados.isEmpty) {
      return Center(
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text('Nenhum aluno', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                filtroSexo == 'MASCULINO' ? Icons.male : filtroSexo == 'FEMININO' ? Icons.female : Icons.people,
                color: filtroSexo == 'MASCULINO' ? Colors.blue : filtroSexo == 'FEMININO' ? Colors.pink : Colors.grey.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                filtroSexo == null ? 'TODOS OS ALUNOS' : filtroSexo == 'MASCULINO' ? 'MENINOS' : 'MENINAS',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: filtroSexo == 'MASCULINO' ? Colors.blue : filtroSexo == 'FEMININO' ? Colors.pink : Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              Text('${alunosFiltrados.length} alunos', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: alunosFiltrados.length > _visibleItems ? _visibleItems : alunosFiltrados.length,
            itemBuilder: (context, index) {
              final aluno = alunosFiltrados[index];
              final isMenino = (aluno['sexo'] as String?)?.toUpperCase() == 'MASCULINO';
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                leading: _buildAlunoAvatar(aluno),
                title: Text(
                  aluno['nome'] ?? 'Sem nome',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isMenino ? Colors.blue.shade50 : Colors.pink.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    aluno['sexo'] ?? '',
                    style: TextStyle(color: isMenino ? Colors.blue : Colors.pink, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                onTap: null,
              );
            },
          ),
          if (alunosFiltrados.length > _visibleItems)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: TextButton(
                  onPressed: () => setState(() => _visibleItems += 20),
                  child: const Text('Carregar mais...'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 🎨 CONTEÚDO PRINCIPAL ====================

  Widget _buildConteudoPorFiltro() {
    switch (filtroAtivo) {
      case 'Frequência':
        return SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            children: [
              _buildFiltroTemporal(),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Top 5 - Presenças por Aluno', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                            child: Text(
                              filtroTemporalFrequencia == 'Ano' && anoSelecionado != null ? anoSelecionado! : filtroTemporalFrequencia,
                              style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildGraficoFrequencia(),
                    ],
                  ),
                ),
              ),
              _buildListaTop5Frequentes(),
              _buildListaFrequenciaCompleta(),
            ],
          ),
        );
      case 'Graduação':
        return SingleChildScrollView(
          controller: _scrollController,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Distribuição por Graduação', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                  const SizedBox(height: 16),
                  _buildGraficoGraduacao(),
                ],
              ),
            ),
          ),
        );
      case 'Idade':
        return SingleChildScrollView(
          controller: _scrollController,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Distribuição por Faixa Etária', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                  const SizedBox(height: 16),
                  _buildGraficoIdade(),
                ],
              ),
            ),
          ),
        );
      case 'Sexo':
        return SingleChildScrollView(
          controller: _scrollController,
          child: _buildFiltroSexo(),
        );
      default:
        return const Center(child: Text('Selecione um filtro'));
    }
  }

  Widget _filtroChip(String titulo) {
    bool isAtivo = filtroAtivo == titulo;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(titulo),
        selected: isAtivo,
        onSelected: (selected) {
          if (selected) {
            setState(() {
              filtroAtivo = titulo;
              _visibleItems = 20;
              if (titulo != 'Sexo') filtroSexo = null;
            });
          }
        },
        backgroundColor: Colors.white,
        selectedColor: titulo == 'Frequência' ? Colors.blue.shade50 :
        titulo == 'Graduação' ? Colors.purple.shade50 :
        titulo == 'Idade' ? Colors.green.shade50 :
        Colors.pink.shade50,
        labelStyle: TextStyle(
          color: isAtivo ?
          (titulo == 'Frequência' ? Colors.blue.shade700 :
          titulo == 'Graduação' ? Colors.purple.shade700 :
          titulo == 'Idade' ? Colors.green.shade700 :
          Colors.pink.shade700)
              : Colors.grey[700],
          fontWeight: isAtivo ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        itemCount: 6,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 80,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // ==================== 🏗️ BUILD PRINCIPAL ====================

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(widget.turmaNome),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          // ⏰ INDICADOR DE CACHE
          if (_ultimaAtualizacao != null && !_isAtualizando)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.green.shade700),
                      const SizedBox(width: 4),
                      Text(
                        '${_formatarTempoCache()}',
                        style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Botão de atualização com feedback visual
          Stack(
            alignment: Alignment.center,
            children: [
              if (!_isAtualizando)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _atualizarDadosReais,
                  tooltip: 'Atualizar dados reais',
                ),
              if (_isAtualizando)
                Container(
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(12),
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filtroChip('Frequência'),
                  _filtroChip('Graduação'),
                  _filtroChip('Idade'),
                  _filtroChip('Sexo'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? _buildShimmerLoading()
                  : _erro != null
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                    const SizedBox(height: 8),
                    Text(_erro!, style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _inicializarDados,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              )
                  : _alunosDaTurma.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text('Nenhum aluno na turma', style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _atualizarDadosReais,
                      child: const Text('Verificar alunos'),
                    ),
                  ],
                ),
              )
                  : _buildConteudoPorFiltro(),
            ),
          ],
        ),
      ),
    );
  }

  // ⏰ NOVO: FORMATAR TEMPO RESTANTE DO CACHE
  String _formatarTempoCache() {
    if (_ultimaAtualizacao == null) return 'Cache vazio';

    final agora = DateTime.now();
    final diferenca = agora.difference(_ultimaAtualizacao!);
    final minutosRestantes = _CACHE_VALIDADE_MINUTOS - diferenca.inMinutes;

    if (minutosRestantes <= 0) return 'Expirado';
    if (minutosRestantes < 60) {
      return '${minutosRestantes}min';
    }
    final horas = minutosRestantes ~/ 60;
    final minutos = minutosRestantes % 60;
    return '${horas}h${minutos > 0 ? '${minutos}m' : ''}';
  }
}