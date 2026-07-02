// screens/alunos/historico_frequencia_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

Color _readableOn(Color background) {
  return background.computeLuminance() > 0.48
      ? const Color(0xFF111827)
      : const Color(0xFFFFFFFF);
}

// ============================================
// CACHE EM MEMÓRIA PARA ECONOMIZAR LEITURAS
// ============================================

class CacheService {
  static final CacheService _instance = CacheService._internal();

  factory CacheService() => _instance;

  CacheService._internal();

  final Map<String, CacheEntry> _memoryCache = {};
  final Duration cacheValidity = const Duration(minutes: 30);

  bool isCacheValid(String key) {
    final entry = _memoryCache[key];
    if (entry == null) return false;
    return DateTime.now().difference(entry.timestamp) < cacheValidity;
  }

  Future<void> saveToCache(String key, dynamic data) async {
    _memoryCache[key] = CacheEntry(data: data, timestamp: DateTime.now());
  }

  dynamic loadFromCache(String key) {
    if (_memoryCache.containsKey(key) && isCacheValid(key)) {
      return _memoryCache[key]!.data;
    }
    return null;
  }

  void remove(String key) => _memoryCache.remove(key);
}

class CacheEntry {
  final dynamic data;
  final DateTime timestamp;

  CacheEntry({required this.data, required this.timestamp});
}

// ============================================
// TELA PRINCIPAL - RAIO-X DE FREQUÊNCIA
// ============================================

class HistoricoFrequenciaScreen extends StatefulWidget {
  final String alunoId;
  final String alunoNome;

  const HistoricoFrequenciaScreen({
    super.key,
    required this.alunoId,
    required this.alunoNome,
  });

  @override
  State<HistoricoFrequenciaScreen> createState() =>
      _HistoricoFrequenciaScreenState();
}

class _HistoricoFrequenciaScreenState extends State<HistoricoFrequenciaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CacheService _cache = CacheService();
  final Connectivity _connectivity = Connectivity();

  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final DateFormat _timeFormat = DateFormat('HH:mm');
  final DateFormat _monthNameFormat = DateFormat('MMMM', 'pt_BR');

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tempoRealSub;

  String _filtroPeriodo = 'Últimos 30 dias';
  String _filtroTipoAula = 'TODAS';

  bool _carregando = true;
  bool _temErro = false;
  bool _isOffline = false;
  String _mensagemErro = '';

  _ResumoFrequenciaInteligente? _resumo;
  DateTime? _ultimaBusca;
  String _fonteDados = 'Carregando...';

  final List<String> _periodos = const [
    'Últimos 30 dias',
    'Últimos 60 dias',
    'Últimos 90 dias',
    'Este Mês',
    'Mês Passado',
    'Últimos 3 Meses',
    'Este Ano',
    'Ano Passado',
    'Todos',
  ];

  final List<String> _tiposAula = const [
    'TODAS',
    'OBJETIVA',
    'RODA',
    'INSTRUMENTAÇÃO',
    'ESPECIAL',
    'EVENTO',
    'BATIZADO',
  ];

  bool get _usaTempoReal => _filtroPeriodo == 'Este Mês';

  String get _cacheKey {
    return 'freq_inteligente_${widget.alunoId}_${_filtroPeriodo}_$_filtroTipoAula';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregarDados());
  }

  @override
  void dispose() {
    _tempoRealSub?.cancel();
    super.dispose();
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onPrimary() {
    final t = context.uai;
    final temaEscuro =
        t.background.computeLuminance() < 0.45 ||
        t.surface.computeLuminance() < 0.45;
    if (temaEscuro) return Colors.white;
    return _readableOn(t.primary);
  }

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  Future<bool> _temInternet() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return !result.contains(ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<void> _carregarDados({bool forcarAtualizacao = false}) async {
    await _tempoRealSub?.cancel();
    _tempoRealSub = null;

    final temNet = await _temInternet();
    if (!mounted) return;

    setState(() {
      _isOffline = !temNet;
      _carregando = true;
      _temErro = false;
      _mensagemErro = '';
    });

    if (!temNet) {
      final cacheado = _cache.loadFromCache(_cacheKey);
      if (cacheado is _ResumoFrequenciaInteligente) {
        _aplicarResumo(cacheado, fonte: 'Cache offline');
        return;
      }

      if (!mounted) return;
      setState(() {
        _carregando = false;
        _temErro = true;
        _mensagemErro = 'Sem conexão e sem cache disponível para este filtro.';
      });
      return;
    }

    if (_usaTempoReal) {
      _iniciarTempoReal();
    } else {
      await _carregarBuscaUnica(forcarAtualizacao: forcarAtualizacao);
    }
  }

  void _iniciarTempoReal() {
    _tempoRealSub = _buildQuery().snapshots().listen(
      (snapshot) {
        final resumo = _calcularResumo(snapshot.docs);
        _cache.saveToCache(_cacheKey, resumo);
        if (!mounted) return;
        _aplicarResumo(resumo, fonte: 'Tempo real');
      },
      onError: (error) {
        if (!mounted) return;
        final cacheado = _cache.loadFromCache(_cacheKey);
        if (cacheado is _ResumoFrequenciaInteligente) {
          _aplicarResumo(cacheado, fonte: 'Cache após erro');
          return;
        }
        setState(() {
          _carregando = false;
          _temErro = true;
          _mensagemErro = error.toString();
        });
      },
    );
  }

  Future<void> _carregarBuscaUnica({bool forcarAtualizacao = false}) async {
    final cacheado = _cache.loadFromCache(_cacheKey);
    if (!forcarAtualizacao && cacheado is _ResumoFrequenciaInteligente) {
      _aplicarResumo(cacheado, fonte: 'Cache inteligente');
      return;
    }

    try {
      final snapshot = await _buildQuery()
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 22));

      final resumo = _calcularResumo(snapshot.docs);
      await _cache.saveToCache(_cacheKey, resumo);

      if (!mounted) return;
      _aplicarResumo(resumo, fonte: 'Busca única');
    } catch (e) {
      final fallback = _cache.loadFromCache(_cacheKey);
      if (fallback is _ResumoFrequenciaInteligente) {
        _aplicarResumo(fallback, fonte: 'Cache após erro');
        return;
      }

      if (!mounted) return;
      setState(() {
        _carregando = false;
        _temErro = true;
        _mensagemErro = 'Erro ao carregar frequência: $e';
      });
    }
  }

  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query = _firestore
        .collection('log_presenca_alunos')
        .where('aluno_id', isEqualTo: widget.alunoId);

    final range = _periodoRange();
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

    if (_filtroTipoAula != 'TODAS') {
      query = query.where('tipo_aula', isEqualTo: _filtroTipoAula);
    }

    return query.orderBy('data_aula', descending: true);
  }

  DateTimeRange? _periodoRange() {
    final agora = DateTime.now();
    final hojeFim = DateTime(agora.year, agora.month, agora.day, 23, 59, 59);

    switch (_filtroPeriodo) {
      case 'Últimos 30 dias':
        return DateTimeRange(
          start: hojeFim.subtract(const Duration(days: 30)),
          end: hojeFim,
        );
      case 'Últimos 60 dias':
        return DateTimeRange(
          start: hojeFim.subtract(const Duration(days: 60)),
          end: hojeFim,
        );
      case 'Últimos 90 dias':
        return DateTimeRange(
          start: hojeFim.subtract(const Duration(days: 90)),
          end: hojeFim,
        );
      case 'Este Mês':
        return DateTimeRange(
          start: DateTime(agora.year, agora.month, 1),
          end: DateTime(agora.year, agora.month + 1, 0, 23, 59, 59),
        );
      case 'Mês Passado':
        return DateTimeRange(
          start: DateTime(agora.year, agora.month - 1, 1),
          end: DateTime(agora.year, agora.month, 0, 23, 59, 59),
        );
      case 'Últimos 3 Meses':
        return DateTimeRange(
          start: DateTime(agora.year, agora.month - 2, 1),
          end: hojeFim,
        );
      case 'Este Ano':
        return DateTimeRange(
          start: DateTime(agora.year, 1, 1),
          end: DateTime(agora.year, 12, 31, 23, 59, 59),
        );
      case 'Ano Passado':
        return DateTimeRange(
          start: DateTime(agora.year - 1, 1, 1),
          end: DateTime(agora.year - 1, 12, 31, 23, 59, 59),
        );
      case 'Todos':
      default:
        return null;
    }
  }

  _ResumoFrequenciaInteligente _calcularResumo(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final historico = <Map<String, dynamic>>[];
    final porDia = <String, int>{
      'seg': 0,
      'ter': 0,
      'qua': 0,
      'qui': 0,
      'sex': 0,
      'sab': 0,
      'dom': 0,
    };
    final porTipo = <String, int>{};

    int presencas = 0;
    int faltas = 0;
    DateTime? ultimaPresencaData;
    String? ultimaPresencaTexto;

    for (int i = 0; i < docs.length; i++) {
      final doc = docs[i];
      final data = doc.data();
      final dataAula = _toDate(data['data_aula']) ?? DateTime.now();
      final presente = data['presente'] == true;
      final tipoAula = data['tipo_aula']?.toString().trim().isNotEmpty == true
          ? data['tipo_aula'].toString()
          : 'Aula';
      final professor =
          data['professor_nome']?.toString() ??
          data['professor']?.toString() ??
          'Não informado';
      final dia = _normalizarDiaSemanaAbrev(
        data['dia_semana_abrev'] ?? data['dia_semana'],
      );

      int diasEntre = 0;
      if (i < docs.length - 1) {
        final proximaData = _toDate(docs[i + 1].data()['data_aula']);
        if (proximaData != null) {
          diasEntre = dataAula.difference(proximaData).inDays.abs();
        }
      }

      if (presente) {
        presencas++;
        ultimaPresencaData ??= dataAula;
        ultimaPresencaTexto ??=
            data['data_formatada']?.toString().trim().isNotEmpty == true
            ? data['data_formatada'].toString()
            : _dateFormat.format(dataAula);

        if (porDia.containsKey(dia)) {
          porDia[dia] = (porDia[dia] ?? 0) + 1;
        }
        porTipo[tipoAula] = (porTipo[tipoAula] ?? 0) + 1;
      } else {
        faltas++;
      }

      historico.add({
        'id': doc.id,
        'data': dataAula,
        'presente': presente,
        'tipo_aula': tipoAula,
        'professor': professor,
        'professor_nome': professor,
        'dias_entre': diasEntre,
        'cor': _corTipoAula(tipoAula),
        'observacao': data['observacao']?.toString() ?? '',
        'turma_id': data['turma_id']?.toString() ?? '',
        'turma_nome': data['turma_nome']?.toString() ?? '',
        'academia_id': data['academia_id']?.toString() ?? '',
        'academia_nome': data['academia_nome']?.toString() ?? '',
        'data_formatada':
            data['data_formatada']?.toString() ?? _dateFormat.format(dataAula),
      });
    }

    final totalAulas = presencas + faltas;
    final percentual = totalAulas > 0 ? (presencas / totalAulas) * 100 : 0.0;

    final sequencia = _calcularSequenciaAtual(historico);
    final melhorSequencia = _calcularMelhorSequencia(historico, presente: true);
    final maiorSequenciaFaltas = _calcularMelhorSequencia(
      historico,
      presente: false,
    );
    final tendencia = _calcularTendencia(historico);
    final perfil = _classificarPerfil(percentual, totalAulas);
    final diasSemPresenca = ultimaPresencaData == null
        ? null
        : DateTime.now()
              .difference(
                DateTime(
                  ultimaPresencaData.year,
                  ultimaPresencaData.month,
                  ultimaPresencaData.day,
                ),
              )
              .inDays
              .clamp(0, 99999)
              .toInt();
    final estadoAtual = _classificarEstadoAtual(diasSemPresenca);
    final risco = _classificarRisco(
      percentual: percentual,
      totalAulas: totalAulas,
      sequenciaFaltasAtual: sequencia.status == _StatusSequencia.falta
          ? sequencia.quantidade
          : 0,
      diasSemPresenca: diasSemPresenca,
    );
    final diagnostico = _montarDiagnostico(
      perfil: perfil,
      estadoAtual: estadoAtual,
      tendencia: tendencia,
      risco: risco,
      percentual: percentual,
      presencas: presencas,
      totalAulas: totalAulas,
      sequencia: sequencia,
      diasSemPresenca: diasSemPresenca,
    );

    return _ResumoFrequenciaInteligente(
      totalPresencas: presencas,
      totalFaltas: faltas,
      totalAulas: totalAulas,
      percentualPresenca: percentual,
      perfil: perfil,
      estadoAtual: estadoAtual,
      tendencia: tendencia,
      risco: risco,
      sequenciaAtual: sequencia,
      melhorSequenciaPresencas: melhorSequencia,
      maiorSequenciaFaltas: maiorSequenciaFaltas,
      ultimaPresenca: ultimaPresencaTexto,
      ultimaPresencaData: ultimaPresencaData,
      diasSemPresenca: diasSemPresenca,
      presencasPorDia: porDia,
      presencasPorTipoAula: porTipo,
      historicoItems: historico,
      diagnostico: diagnostico,
      carregadoEm: DateTime.now(),
    );
  }

  _SequenciaInfo _calcularSequenciaAtual(
    List<Map<String, dynamic>> historicoDesc,
  ) {
    if (historicoDesc.isEmpty) {
      return const _SequenciaInfo(
        status: _StatusSequencia.nenhuma,
        quantidade: 0,
      );
    }

    final primeiroStatus = historicoDesc.first['presente'] == true;
    int total = 0;

    for (final item in historicoDesc) {
      if ((item['presente'] == true) == primeiroStatus) {
        total++;
      } else {
        break;
      }
    }

    return _SequenciaInfo(
      status: primeiroStatus
          ? _StatusSequencia.presenca
          : _StatusSequencia.falta,
      quantidade: total,
    );
  }

  int _calcularMelhorSequencia(
    List<Map<String, dynamic>> historicoDesc, {
    required bool presente,
  }) {
    final cronologico = historicoDesc.reversed.toList();
    int atual = 0;
    int melhor = 0;

    for (final item in cronologico) {
      if (item['presente'] == presente) {
        atual++;
        melhor = math.max(melhor, atual);
      } else {
        atual = 0;
      }
    }

    return melhor;
  }

  _TendenciaInfo _calcularTendencia(List<Map<String, dynamic>> historicoDesc) {
    if (historicoDesc.length < 4) {
      return const _TendenciaInfo(
        status: _StatusTendencia.poucosDados,
        label: 'Poucos dados',
        descricao: 'Ainda faltam registros para medir tendência.',
        diferencaPercentual: 0,
      );
    }

    final janela = math.min(6, historicoDesc.length ~/ 2);
    final recentes = historicoDesc.take(janela).toList();
    final anteriores = historicoDesc.skip(janela).take(janela).toList();

    double percentual(List<Map<String, dynamic>> itens) {
      if (itens.isEmpty) return 0;
      final presentes = itens.where((e) => e['presente'] == true).length;
      return (presentes / itens.length) * 100;
    }

    final atual = percentual(recentes);
    final antes = percentual(anteriores);
    final diff = atual - antes;

    if (diff >= 18) {
      return _TendenciaInfo(
        status: _StatusTendencia.melhorando,
        label: 'Melhorando',
        descricao: 'As últimas aulas foram melhores que o período anterior.',
        diferencaPercentual: diff,
      );
    }

    if (diff <= -18) {
      return _TendenciaInfo(
        status: _StatusTendencia.caindo,
        label: 'Caindo',
        descricao: 'A frequência recente caiu em relação ao período anterior.',
        diferencaPercentual: diff,
      );
    }

    return _TendenciaInfo(
      status: _StatusTendencia.estavel,
      label: 'Estável',
      descricao:
          'O comportamento recente está parecido com o período anterior.',
      diferencaPercentual: diff,
    );
  }

  _ClassificacaoInfo _classificarPerfil(double percentual, int totalAulas) {
    if (totalAulas == 0) {
      return const _ClassificacaoInfo(
        label: 'Sem dados',
        descricao: 'Nenhuma aula encontrada no período.',
        corBase: _CorBase.neutra,
        icone: Icons.help_outline_rounded,
      );
    }

    if (percentual >= 85) {
      return const _ClassificacaoInfo(
        label: 'Muito frequente',
        descricao: 'Comparece na grande maioria das aulas.',
        corBase: _CorBase.sucesso,
        icone: Icons.workspace_premium_rounded,
      );
    }
    if (percentual >= 65) {
      return const _ClassificacaoInfo(
        label: 'Frequente',
        descricao: 'Mantém boa presença no período.',
        corBase: _CorBase.sucesso,
        icone: Icons.verified_rounded,
      );
    }
    if (percentual >= 45) {
      return const _ClassificacaoInfo(
        label: 'Regular',
        descricao: 'Vai, mas ainda oscila bastante.',
        corBase: _CorBase.alerta,
        icone: Icons.balance_rounded,
      );
    }
    if (percentual >= 20) {
      return const _ClassificacaoInfo(
        label: 'Baixa constância',
        descricao: 'Aparece pouco em relação às aulas registradas.',
        corBase: _CorBase.perigo,
        icone: Icons.trending_down_rounded,
      );
    }
    if (percentual > 0) {
      return const _ClassificacaoInfo(
        label: 'Muito irregular',
        descricao: 'Presença muito baixa no período.',
        corBase: _CorBase.perigo,
        icone: Icons.warning_amber_rounded,
      );
    }

    return const _ClassificacaoInfo(
      label: 'Inativo no período',
      descricao: 'Não teve presença registrada neste período.',
      corBase: _CorBase.perigo,
      icone: Icons.person_off_rounded,
    );
  }

  _ClassificacaoInfo _classificarEstadoAtual(int? diasSemPresenca) {
    if (diasSemPresenca == null) {
      return const _ClassificacaoInfo(
        label: 'Sem presença registrada',
        descricao: 'Ainda não existe presença confirmada para o aluno.',
        corBase: _CorBase.perigo,
        icone: Icons.history_toggle_off_rounded,
      );
    }

    if (diasSemPresenca == 0) {
      return const _ClassificacaoInfo(
        label: 'Presente hoje',
        descricao: 'Estado atual está positivo.',
        corBase: _CorBase.sucesso,
        icone: Icons.check_circle_rounded,
      );
    }
    if (diasSemPresenca <= 3) {
      return const _ClassificacaoInfo(
        label: 'Frequente agora',
        descricao: 'Teve presença recente.',
        corBase: _CorBase.sucesso,
        icone: Icons.event_available_rounded,
      );
    }
    if (diasSemPresenca <= 7) {
      return const _ClassificacaoInfo(
        label: 'Atenção leve',
        descricao: 'Começou a abrir espaço entre as presenças.',
        corBase: _CorBase.alerta,
        icone: Icons.schedule_rounded,
      );
    }
    if (diasSemPresenca <= 15) {
      return const _ClassificacaoInfo(
        label: 'Atenção',
        descricao: 'Já está há vários dias sem presença.',
        corBase: _CorBase.alerta,
        icone: Icons.warning_amber_rounded,
      );
    }
    if (diasSemPresenca <= 30) {
      return const _ClassificacaoInfo(
        label: 'Ausente',
        descricao: 'Precisa de contato ou acompanhamento.',
        corBase: _CorBase.perigo,
        icone: Icons.report_problem_rounded,
      );
    }

    return const _ClassificacaoInfo(
      label: 'Risco de inatividade',
      descricao: 'Muito tempo sem presença registrada.',
      corBase: _CorBase.perigo,
      icone: Icons.priority_high_rounded,
    );
  }

  _ClassificacaoInfo _classificarRisco({
    required double percentual,
    required int totalAulas,
    required int sequenciaFaltasAtual,
    required int? diasSemPresenca,
  }) {
    final dias = diasSemPresenca ?? 9999;

    if (totalAulas == 0) {
      return const _ClassificacaoInfo(
        label: 'Sem leitura',
        descricao: 'Ainda não há aulas suficientes no período.',
        corBase: _CorBase.neutra,
        icone: Icons.help_outline_rounded,
      );
    }

    if (sequenciaFaltasAtual >= 4 || dias >= 30 || percentual <= 15) {
      return const _ClassificacaoInfo(
        label: 'Risco alto',
        descricao: 'Aluno pode estar se afastando do projeto.',
        corBase: _CorBase.perigo,
        icone: Icons.dangerous_rounded,
      );
    }

    if (sequenciaFaltasAtual >= 2 || dias >= 12 || percentual < 45) {
      return const _ClassificacaoInfo(
        label: 'Risco médio',
        descricao: 'Vale acompanhar e fazer contato preventivo.',
        corBase: _CorBase.alerta,
        icone: Icons.warning_amber_rounded,
      );
    }

    return const _ClassificacaoInfo(
      label: 'Risco baixo',
      descricao: 'Sem sinal forte de afastamento no momento.',
      corBase: _CorBase.sucesso,
      icone: Icons.shield_rounded,
    );
  }

  String _montarDiagnostico({
    required _ClassificacaoInfo perfil,
    required _ClassificacaoInfo estadoAtual,
    required _TendenciaInfo tendencia,
    required _ClassificacaoInfo risco,
    required double percentual,
    required int presencas,
    required int totalAulas,
    required _SequenciaInfo sequencia,
    required int? diasSemPresenca,
  }) {
    if (totalAulas == 0) {
      return 'Ainda não existem registros suficientes para analisar a frequência deste aluno no período selecionado.';
    }

    final base =
        'Compareceu em $presencas de $totalAulas aulas (${percentual.toStringAsFixed(0)}%).';
    final estado = diasSemPresenca == null
        ? 'Não há última presença registrada.'
        : diasSemPresenca == 0
        ? 'Veio hoje.'
        : 'Última presença há $diasSemPresenca dia${diasSemPresenca == 1 ? '' : 's'}.';

    final sequenciaTxt = sequencia.quantidade == 0
        ? ''
        : sequencia.status == _StatusSequencia.presenca
        ? ' Está em sequência positiva de ${sequencia.quantidade} presença${sequencia.quantidade == 1 ? '' : 's'}.'
        : ' Está em sequência de ${sequencia.quantidade} falta${sequencia.quantidade == 1 ? '' : 's'}.';

    return '$estado $base Perfil: ${perfil.label}. Tendência: ${tendencia.label}. Risco: ${risco.label}.$sequenciaTxt';
  }

  void _aplicarResumo(
    _ResumoFrequenciaInteligente resumo, {
    required String fonte,
  }) {
    if (!mounted) return;

    setState(() {
      _resumo = resumo;
      _ultimaBusca = resumo.carregadoEm;
      _fonteDados = fonte;
      _carregando = false;
      _temErro = false;
      _mensagemErro = '';
    });
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is Map) {
      final seconds = value['_seconds'] ?? value['seconds'];
      if (seconds is int) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
      }
    }
    return null;
  }

  String _normalizarDiaSemanaAbrev(dynamic valor) {
    final raw = valor?.toString().toLowerCase().trim() ?? '';
    if (raw.isEmpty) return '';

    final semAcento = raw
        .replaceAll('.', '')
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

    if (semAcento.startsWith('seg') || semAcento.contains('segunda'))
      return 'seg';
    if (semAcento.startsWith('ter') || semAcento.contains('terca'))
      return 'ter';
    if (semAcento.startsWith('qua') || semAcento.contains('quarta'))
      return 'qua';
    if (semAcento.startsWith('qui') || semAcento.contains('quinta'))
      return 'qui';
    if (semAcento.startsWith('sex') || semAcento.contains('sexta'))
      return 'sex';
    if (semAcento.startsWith('sab') || semAcento.contains('sabado'))
      return 'sab';
    if (semAcento.startsWith('dom') || semAcento.contains('domingo'))
      return 'dom';

    return semAcento.length >= 3 ? semAcento.substring(0, 3) : semAcento;
  }

  Color _corTipoAula(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'objetiva':
        return context.uai.info;
      case 'roda':
        return context.uai.error;
      case 'instrumentação':
      case 'instrumentacao':
        return context.uai.warning;
      case 'especial':
        return context.uai.associacao;
      case 'evento':
      case 'batizado':
        return context.uai.warning;
      default:
        return context.uai.textMuted;
    }
  }

  String _labelTipoAula(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'OBJETIVA':
        return 'Objetiva';
      case 'RODA':
        return 'Roda';
      case 'INSTRUMENTAÇÃO':
      case 'INSTRUMENTACAO':
        return 'Instrumentação';
      case 'ESPECIAL':
        return 'Especial';
      case 'EVENTO':
        return 'Evento';
      case 'BATIZADO':
        return 'Batizado';
      default:
        return tipo;
    }
  }

  String _tituloPeriodo() {
    final agora = DateTime.now();

    switch (_filtroPeriodo) {
      case 'Últimos 30 dias':
      case 'Últimos 60 dias':
      case 'Últimos 90 dias':
        return _filtroPeriodo.toUpperCase();
      case 'Este Mês':
        return _monthNameFormat.format(agora).toUpperCase();
      case 'Mês Passado':
        return _monthNameFormat
            .format(DateTime(agora.year, agora.month - 1, 1))
            .toUpperCase();
      case 'Últimos 3 Meses':
        final ini = DateTime(agora.year, agora.month - 2, 1);
        return '${_monthNameFormat.format(ini).toUpperCase()} - ${_monthNameFormat.format(agora).toUpperCase()}';
      case 'Este Ano':
        return agora.year.toString();
      case 'Ano Passado':
        return (agora.year - 1).toString();
      case 'Todos':
        return 'TODO HISTÓRICO';
      default:
        return _filtroPeriodo.toUpperCase();
    }
  }

  String _subtituloPeriodo() {
    final agora = DateTime.now();

    switch (_filtroPeriodo) {
      case 'Últimos 30 dias':
        return 'Janela principal para medir constância real';
      case 'Últimos 60 dias':
        return 'Janela ampliada para acompanhar evolução';
      case 'Últimos 90 dias':
        return 'Leitura mais estável do comportamento';
      case 'Este Mês':
        return 'Este mês em tempo real';
      case 'Mês Passado':
        final mp = DateTime(agora.year, agora.month - 1, 1);
        return '${_monthNameFormat.format(mp)} de ${mp.year}';
      case 'Últimos 3 Meses':
        final ini = DateTime(agora.year, agora.month - 2, 1);
        return 'De ${_monthNameFormat.format(ini)} a ${_monthNameFormat.format(agora)}';
      case 'Este Ano':
        return 'Janeiro a dezembro de ${agora.year}';
      case 'Ano Passado':
        return 'Janeiro a dezembro de ${agora.year - 1}';
      case 'Todos':
        return 'Todos os registros encontrados nos logs';
      default:
        return '';
    }
  }

  String _formatarDataStr(String? s) {
    if (s == null || s.isEmpty) return 'Nunca';
    try {
      return DateFormat('dd/MM').format(DateTime.parse(s));
    } catch (_) {
      return s;
    }
  }

  String _formatHora(DateTime? data) {
    if (data == null) return '--:--';
    return _timeFormat.format(data);
  }

  Color _colorFromBase(_CorBase base, {Color? background}) {
    final bg = background ?? context.uai.card;
    switch (base) {
      case _CorBase.sucesso:
        return _ensureVisible(context.uai.success, bg);
      case _CorBase.alerta:
        return _ensureVisible(context.uai.warning, bg);
      case _CorBase.perigo:
        return _ensureVisible(context.uai.error, bg);
      case _CorBase.info:
        return _ensureVisible(context.uai.info, bg);
      case _CorBase.neutra:
        return _ensureVisible(context.uai.textMuted, bg);
    }
  }

  Future<void> _atualizar() async {
    _cache.remove(_cacheKey);
    await _carregarDados(forcarAtualizacao: true);
  }

  void _aplicarFiltroPeriodo(String periodo) {
    if (_filtroPeriodo == periodo) return;

    if (periodo == 'Todos' &&
        _cache.loadFromCache(
              'freq_inteligente_${widget.alunoId}_Todos_$_filtroTipoAula',
            ) ==
            null) {
      _confirmarFiltroTodos();
      return;
    }

    setState(() {
      _filtroPeriodo = periodo;
      _resumo = null;
      _carregando = true;
    });
    _carregarDados();
  }

  Future<void> _confirmarFiltroTodos() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.uai.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.uai.cardRadius),
        ),
        title: Row(
          children: [
            Icon(Icons.all_inclusive_rounded, color: context.uai.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Carregar todo histórico?',
                style: TextStyle(
                  color: context.uai.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Esse filtro busca todos os logs do aluno. Depois da primeira busca, fica em cache por 30 minutos.',
          style: TextStyle(
            color: context.uai.textSecondary,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _appBarBg(),
              foregroundColor: _appBarFg(),
            ),
            child: const Text('CARREGAR'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      setState(() {
        _filtroPeriodo = 'Todos';
        _resumo = null;
        _carregando = true;
      });
      _carregarDados();
    }
  }

  void _aplicarFiltroTipoAula(String tipo) {
    if (_filtroTipoAula == tipo) return;

    setState(() {
      _filtroTipoAula = tipo;
      _resumo = null;
      _carregando = true;
    });
    _carregarDados();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Raio-X de Frequência',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _appBarFg(),
              ),
            ),
            Text(
              widget.alunoNome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _appBarFg().withOpacity(0.82),
              ),
            ),
          ],
        ),
        backgroundColor: _appBarBg(),
        foregroundColor: _appBarFg(),
        iconTheme: IconThemeData(color: _appBarFg()),
        actions: [
          if (_isOffline)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.wifi_off, color: t.warning, size: 20),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _atualizar,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth > 980
              ? 980.0
              : constraints.maxWidth;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                children: [
                  if (!_carregando || _resumo != null) _buildFiltros(),
                  Expanded(child: _buildConteudo()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFiltros() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: context.uai.surface,
        border: Border(bottom: BorderSide(color: context.uai.border)),
        boxShadow: [
          BoxShadow(
            color: context.uai.textPrimary.withOpacity(0.045),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 720;

          return Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: context.uai.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.insights_rounded,
                      color: context.uai.primary,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Análise inteligente',
                          style: TextStyle(
                            color: context.uai.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _usaTempoReal
                              ? 'Este mês em tempo real'
                              : 'Busca única com cache de 30 minutos',
                          style: TextStyle(
                            color: context.uai.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildModoChip(),
                ],
              ),
              const SizedBox(height: 12),
              if (isWide)
                Row(
                  children: [
                    Expanded(child: _buildFiltroDropdownPeriodo()),
                    const SizedBox(width: 10),
                    Expanded(child: _buildFiltroDropdownTipoAula()),
                  ],
                )
              else
                Column(
                  children: [
                    _buildFiltroDropdownPeriodo(),
                    const SizedBox(height: 9),
                    _buildFiltroDropdownTipoAula(),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildModoChip() {
    final color = _ensureVisible(
      _usaTempoReal ? context.uai.success : context.uai.info,
      context.uai.surface,
    );
    final text = _usaTempoReal ? 'AO VIVO' : 'CACHE';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _usaTempoReal ? Icons.bolt_rounded : Icons.cached_rounded,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroDropdownPeriodo() {
    return DropdownButtonFormField<String>(
      value: _filtroPeriodo,
      style: TextStyle(
        color: context.uai.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      isExpanded: true,
      borderRadius: BorderRadius.circular(16),
      dropdownColor: context.uai.surface,
      decoration: _inputDecorationFiltro(
        label: 'Período',
        icon: Icons.calendar_month_rounded,
        color: context.uai.primary,
      ),
      items: _periodos.map((periodo) {
        return DropdownMenuItem<String>(
          value: periodo,
          child: Row(
            children: [
              Icon(
                _iconePeriodo(periodo),
                size: 18,
                color: _filtroPeriodo == periodo
                    ? context.uai.primary
                    : context.uai.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  periodo,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;
        _aplicarFiltroPeriodo(value);
      },
    );
  }

  Widget _buildFiltroDropdownTipoAula() {
    return DropdownButtonFormField<String>(
      value: _filtroTipoAula,
      style: TextStyle(
        color: context.uai.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      isExpanded: true,
      borderRadius: BorderRadius.circular(16),
      dropdownColor: context.uai.surface,
      decoration: _inputDecorationFiltro(
        label: 'Tipo de aula',
        icon: Icons.sports_martial_arts_rounded,
        color: context.uai.info,
      ),
      items: _tiposAula.map((tipo) {
        final label = tipo == 'TODAS' ? 'Todas as aulas' : _labelTipoAula(tipo);
        final color = tipo == 'TODAS' ? context.uai.info : _corTipoAula(tipo);

        return DropdownMenuItem<String>(
          value: tipo,
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;
        _aplicarFiltroTipoAula(value);
      },
    );
  }

  InputDecoration _inputDecorationFiltro({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: color, size: 20),
      labelStyle: TextStyle(
        color: context.uai.textSecondary,
        fontWeight: FontWeight.w700,
      ),
      floatingLabelStyle: TextStyle(color: color, fontWeight: FontWeight.w900),
      filled: true,
      fillColor: context.uai.cardAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: context.uai.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: color, width: 1.4),
      ),
    );
  }

  IconData _iconePeriodo(String periodo) {
    switch (periodo) {
      case 'Últimos 30 dias':
        return Icons.looks_3_rounded;
      case 'Últimos 60 dias':
        return Icons.date_range_rounded;
      case 'Últimos 90 dias':
        return Icons.timeline_rounded;
      case 'Este Mês':
        return Icons.today_rounded;
      case 'Mês Passado':
        return Icons.history_rounded;
      case 'Últimos 3 Meses':
        return Icons.query_stats_rounded;
      case 'Este Ano':
        return Icons.event_rounded;
      case 'Ano Passado':
        return Icons.event_repeat_rounded;
      case 'Todos':
        return Icons.all_inclusive_rounded;
      default:
        return Icons.calendar_month_rounded;
    }
  }

  Widget _buildConteudo() {
    if (_carregando) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: context.uai.primary),
            const SizedBox(height: 16),
            Text(
              _usaTempoReal
                  ? 'Escutando chamadas deste mês...'
                  : 'Calculando análise inteligente...',
              style: TextStyle(color: context.uai.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_temErro) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 80, color: context.uai.error),
              const SizedBox(height: 16),
              Text(
                'Ops! Algo deu errado',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: context.uai.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _mensagemErro,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.uai.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _atualizar,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _appBarBg(),
                  foregroundColor: _appBarFg(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final resumo = _resumo;
    if (resumo == null || resumo.historicoItems.isEmpty) {
      return RefreshIndicator(
        onRefresh: _atualizar,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            Icon(Icons.history, size: 100, color: context.uai.border),
            const SizedBox(height: 16),
            Text(
              'Nenhum registro encontrado',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: context.uai.textMuted),
            ),
            const SizedBox(height: 8),
            Text(
              'Tente alterar o filtro ou confira se existem logs para este aluno.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.uai.textMuted),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _atualizar,
      color: context.uai.primary,
      backgroundColor: context.uai.surface,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _buildHeaderInteligente(resumo),
          _buildFonteDadosCard(),
          _buildDiagnosticoCard(resumo),
          _buildLeiturasPrincipais(resumo),
          _buildSequenciasCard(resumo),
          _buildPresencasPorDia(resumo),
          _buildPresencasPorTipoAula(resumo),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Icon(Icons.history_rounded, color: context.uai.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Histórico de aulas (${resumo.historicoItems.length})',
                    style: TextStyle(
                      color: context.uai.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...resumo.historicoItems.map(_buildHistoryItem),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 28,
                    color: context.uai.success.withOpacity(0.75),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Todos os registros do filtro foram carregados',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.uai.textMuted,
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

  Widget _buildFonteDadosCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _usaTempoReal
            ? context.uai.success.withOpacity(0.10)
            : context.uai.info.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _usaTempoReal
              ? context.uai.success.withOpacity(0.18)
              : context.uai.info.withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _usaTempoReal ? Icons.bolt_rounded : Icons.cached_rounded,
            color: _usaTempoReal ? context.uai.success : context.uai.info,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _usaTempoReal
                  ? 'Este mês está em tempo real. Novas chamadas aparecem automaticamente.'
                  : 'Dados carregados por $_fonteDados às ${_formatHora(_ultimaBusca)}. Atualizar força nova busca.',
              style: TextStyle(
                color: _usaTempoReal ? context.uai.success : context.uai.info,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderInteligente(_ResumoFrequenciaInteligente resumo) {
    final perfilColor = _colorFromBase(
      resumo.perfil.corBase,
      background: context.uai.primary,
    );

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withOpacity(0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
        gradient: context.uai.primaryGradient,
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _onPrimary().withOpacity(0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _tituloPeriodo(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _onPrimary(),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _subtituloPeriodo(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _onPrimary().withOpacity(0.78),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 132,
                  height: 132,
                  child: CircularProgressIndicator(
                    value: resumo.totalAulas > 0
                        ? resumo.percentualPresenca / 100
                        : 0,
                    strokeWidth: 12,
                    backgroundColor: _onPrimary().withOpacity(0.18),
                    valueColor: AlwaysStoppedAnimation<Color>(perfilColor),
                  ),
                ),
                Column(
                  children: [
                    Icon(resumo.perfil.icone, color: perfilColor, size: 28),
                    const SizedBox(height: 3),
                    Text(
                      '${resumo.percentualPresenca.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: _onPrimary(),
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    Text(
                      'presença',
                      style: TextStyle(
                        color: _onPrimary().withOpacity(0.74),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              resumo.perfil.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: perfilColor,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              resumo.perfil.descricao,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _onPrimary().withOpacity(0.78),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _buildHeaderMini(
                  'Presenças',
                  '${resumo.totalPresencas}',
                  Icons.check_circle_rounded,
                  context.uai.success.withOpacity(0.75),
                ),
                const SizedBox(width: 8),
                _buildHeaderMini(
                  'Faltas',
                  '${resumo.totalFaltas}',
                  Icons.cancel_rounded,
                  context.uai.error,
                ),
                const SizedBox(width: 8),
                _buildHeaderMini(
                  'Aulas',
                  '${resumo.totalAulas}',
                  Icons.groups_rounded,
                  _onPrimary(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderMini(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 7),
        decoration: BoxDecoration(
          color: _onPrimary().withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _onPrimary().withOpacity(0.14)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                color: _onPrimary(),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: _onPrimary().withOpacity(0.76),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticoCard(_ResumoFrequenciaInteligente resumo) {
    final riscoColor = _colorFromBase(resumo.risco.corBase);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(riscoColor.withOpacity(0.06), context.uai.card),
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        border: Border.all(color: riscoColor.withOpacity(0.18)),
        boxShadow: context.uai.softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: riscoColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: riscoColor.withOpacity(0.16)),
            ),
            child: Icon(Icons.psychology_rounded, color: riscoColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leitura inteligente',
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  resumo.diagnostico,
                  style: TextStyle(
                    color: context.uai.textSecondary,
                    height: 1.32,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeiturasPrincipais(_ResumoFrequenciaInteligente resumo) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.dashboard_customize_rounded,
                color: context.uai.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'As 3 leituras do aluno',
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 620;
              final cards = [
                _buildLeituraCard(
                  'Estado atual',
                  resumo.estadoAtual,
                  _textoEstadoAtual(resumo),
                ),
                _buildLeituraCard(
                  'Constância',
                  resumo.perfil,
                  '${resumo.totalPresencas}/${resumo.totalAulas} aulas',
                ),
                _buildTendenciaCard(resumo.tendencia),
                _buildLeituraCard(
                  'Risco',
                  resumo.risco,
                  resumo.risco.descricao,
                ),
              ];

              if (!isWide) {
                return Column(
                  children: cards
                      .map(
                        (card) => Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: card,
                        ),
                      )
                      .toList(),
                );
              }

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: cards.map((card) {
                  return SizedBox(
                    width: (constraints.maxWidth - 10) / 2,
                    child: card,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _textoEstadoAtual(_ResumoFrequenciaInteligente resumo) {
    final dias = resumo.diasSemPresenca;
    if (dias == null) return 'Sem presença';
    if (dias == 0) return 'Veio hoje';
    if (dias == 1) return 'Veio ontem';
    return 'Há $dias dias';
  }

  Widget _buildLeituraCard(
    String title,
    _ClassificacaoInfo info,
    String value,
  ) {
    final color = _colorFromBase(info.corBase);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(0.06), context.uai.cardAlt),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(info.icone, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.uai.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.uai.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTendenciaCard(_TendenciaInfo tendencia) {
    final base = tendencia.status == _StatusTendencia.melhorando
        ? _CorBase.sucesso
        : tendencia.status == _StatusTendencia.caindo
        ? _CorBase.perigo
        : tendencia.status == _StatusTendencia.estavel
        ? _CorBase.info
        : _CorBase.neutra;
    final color = _colorFromBase(base);
    final icon = tendencia.status == _StatusTendencia.melhorando
        ? Icons.trending_up_rounded
        : tendencia.status == _StatusTendencia.caindo
        ? Icons.trending_down_rounded
        : tendencia.status == _StatusTendencia.estavel
        ? Icons.trending_flat_rounded
        : Icons.help_outline_rounded;

    final diff = tendencia.diferencaPercentual.round();
    final diffText = diff == 0
        ? 'sem variação'
        : '${diff > 0 ? '+' : ''}$diff%';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(0.06), context.uai.cardAlt),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tendência',
                  style: TextStyle(
                    color: context.uai.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tendencia.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  diffText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.uai.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSequenciasCard(_ResumoFrequenciaInteligente resumo) {
    final atualColor = resumo.sequenciaAtual.status == _StatusSequencia.presenca
        ? _ensureVisible(context.uai.success, context.uai.card)
        : resumo.sequenciaAtual.status == _StatusSequencia.falta
        ? _ensureVisible(context.uai.error, context.uai.card)
        : _ensureVisible(context.uai.textMuted, context.uai.card);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                color: context.uai.warning,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sequências e comportamento',
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSequenciaMini(
                label: 'Atual',
                value: '${resumo.sequenciaAtual.quantidade}',
                subtitle:
                    resumo.sequenciaAtual.status == _StatusSequencia.presenca
                    ? 'presença(s)'
                    : resumo.sequenciaAtual.status == _StatusSequencia.falta
                    ? 'falta(s)'
                    : 'sem dados',
                color: atualColor,
                icon: resumo.sequenciaAtual.status == _StatusSequencia.presenca
                    ? Icons.check_circle_rounded
                    : resumo.sequenciaAtual.status == _StatusSequencia.falta
                    ? Icons.cancel_rounded
                    : Icons.help_outline_rounded,
              ),
              const SizedBox(width: 8),
              _buildSequenciaMini(
                label: 'Melhor sequência',
                value: '${resumo.melhorSequenciaPresencas}',
                subtitle: 'presenças',
                color: _ensureVisible(context.uai.success, context.uai.card),
                icon: Icons.emoji_events_rounded,
              ),
              const SizedBox(width: 8),
              _buildSequenciaMini(
                label: 'Maior queda',
                value: '${resumo.maiorSequenciaFaltas}',
                subtitle: 'faltas',
                color: _ensureVisible(context.uai.error, context.uai.card),
                icon: Icons.warning_amber_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSequenciaMini({
    required String label,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withOpacity(0.07), context.uai.cardAlt),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.16)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 19,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.uai.textPrimary,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.uai.textSecondary,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresencasPorDia(_ResumoFrequenciaInteligente resumo) {
    if (resumo.presencasPorDia.values.every((v) => v == 0))
      return const SizedBox.shrink();

    final dias = [
      ['seg', 'Seg'],
      ['ter', 'Ter'],
      ['qua', 'Qua'],
      ['qui', 'Qui'],
      ['sex', 'Sex'],
      ['sab', 'Sáb'],
      ['dom', 'Dom'],
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month, color: context.uai.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Presenças por dia da semana',
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth < 420
                  ? (constraints.maxWidth - 18) / 4
                  : 42.0;
              return Wrap(
                spacing: 6,
                runSpacing: 7,
                alignment: WrapAlignment.center,
                children: dias.map((dia) {
                  return SizedBox(
                    width: cardWidth,
                    child: _buildDiaCard(
                      dia[1],
                      resumo.presencasPorDia[dia[0]] ?? 0,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDiaCard(String dia, int qtd) {
    final ativo = qtd > 0;
    final accent = _ensureVisible(context.uai.primary, context.uai.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: ativo
            ? context.uai.primary.withOpacity(0.10)
            : context.uai.cardAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ativo
              ? context.uai.primary.withOpacity(0.24)
              : context.uai.border,
        ),
      ),
      child: Column(
        children: [
          Text(
            dia,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: ativo ? accent : context.uai.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$qtd',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: ativo ? accent : context.uai.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresencasPorTipoAula(_ResumoFrequenciaInteligente resumo) {
    if (resumo.presencasPorTipoAula.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school, color: context.uai.info, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Presenças por tipo de aula',
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: resumo.presencasPorTipoAula.entries.map((entry) {
              final cor = _ensureVisible(
                _corTipoAula(entry.key),
                context.uai.card,
              );
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: cor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _labelTipoAula(entry.key),
                      style: TextStyle(
                        fontSize: 11,
                        color: cor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${entry.value}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cor,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    final t = context.uai;
    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      border: Border.all(color: t.border),
      boxShadow: t.softShadow,
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final data = item['data'] as DateTime;
    final diasEntre = item['dias_entre'] as int;
    final presente = item['presente'] as bool;
    final tipoAula = item['tipo_aula'] as String;
    final professor = item['professor'] as String;
    final cor = item['cor'] as Color;
    final obs = item['observacao'] as String;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        elevation: presente ? 3 : 1,
        color: context.uai.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: context.uai.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _mostrarDetalhesAula(item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: presente
                            ? context.uai.success
                            : context.uai.error,
                        boxShadow: [
                          BoxShadow(
                            color:
                                (presente
                                        ? context.uai.success
                                        : context.uai.error)
                                    .withOpacity(0.4),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    if (diasEntre > 0)
                      Container(
                        width: 2,
                        height: 20,
                        color: context.uai.border,
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _dateFormat.format(data),
                              style: TextStyle(
                                color: context.uai.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: presente
                                  ? context.uai.success.withOpacity(0.10)
                                  : context.uai.error.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              presente ? 'PRESENTE' : 'AUSENTE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: presente
                                    ? context.uai.success
                                    : context.uai.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildTag(_labelTipoAula(tipoAula), cor),
                          if (diasEntre > 0)
                            _buildTag(
                              '$diasEntre ${diasEntre == 1 ? 'dia' : 'dias'}',
                              context.uai.warning,
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            Icons.assignment_ind_rounded,
                            size: 13,
                            color: context.uai.associacao,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Aula registrada por: $professor',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.uai.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (obs.isNotEmpty)
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 14,
                              color: context.uai.warning,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  color: context.uai.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String label, Color color) {
    final accent = _ensureVisible(color, context.uai.card);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withOpacity(0.30)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }

  void _mostrarDetalhesAula(Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _DetalheAulaDialog(
        item: item,
        alunoId: widget.alunoId,
        alunoNome: widget.alunoNome,
      ),
    );
  }
}

// ============================================
// MODELOS DA ANÁLISE
// ============================================

enum _CorBase { sucesso, alerta, perigo, info, neutra }

enum _StatusSequencia { presenca, falta, nenhuma }

enum _StatusTendencia { melhorando, caindo, estavel, poucosDados }

class _ClassificacaoInfo {
  final String label;
  final String descricao;
  final _CorBase corBase;
  final IconData icone;

  const _ClassificacaoInfo({
    required this.label,
    required this.descricao,
    required this.corBase,
    required this.icone,
  });
}

class _SequenciaInfo {
  final _StatusSequencia status;
  final int quantidade;

  const _SequenciaInfo({required this.status, required this.quantidade});
}

class _TendenciaInfo {
  final _StatusTendencia status;
  final String label;
  final String descricao;
  final double diferencaPercentual;

  const _TendenciaInfo({
    required this.status,
    required this.label,
    required this.descricao,
    required this.diferencaPercentual,
  });
}

class _ResumoFrequenciaInteligente {
  final int totalPresencas;
  final int totalFaltas;
  final int totalAulas;
  final double percentualPresenca;
  final _ClassificacaoInfo perfil;
  final _ClassificacaoInfo estadoAtual;
  final _TendenciaInfo tendencia;
  final _ClassificacaoInfo risco;
  final _SequenciaInfo sequenciaAtual;
  final int melhorSequenciaPresencas;
  final int maiorSequenciaFaltas;
  final String? ultimaPresenca;
  final DateTime? ultimaPresencaData;
  final int? diasSemPresenca;
  final Map<String, int> presencasPorDia;
  final Map<String, int> presencasPorTipoAula;
  final List<Map<String, dynamic>> historicoItems;
  final String diagnostico;
  final DateTime carregadoEm;

  const _ResumoFrequenciaInteligente({
    required this.totalPresencas,
    required this.totalFaltas,
    required this.totalAulas,
    required this.percentualPresenca,
    required this.perfil,
    required this.estadoAtual,
    required this.tendencia,
    required this.risco,
    required this.sequenciaAtual,
    required this.melhorSequenciaPresencas,
    required this.maiorSequenciaFaltas,
    required this.ultimaPresenca,
    required this.ultimaPresencaData,
    required this.diasSemPresenca,
    required this.presencasPorDia,
    required this.presencasPorTipoAula,
    required this.historicoItems,
    required this.diagnostico,
    required this.carregadoEm,
  });
}

// ============================================
// DIÁLOGO DE DETALHE DA AULA
// ============================================

class _DetalheAulaDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final String alunoId;
  final String alunoNome;

  const _DetalheAulaDialog({
    required this.item,
    required this.alunoId,
    required this.alunoNome,
  });

  @override
  State<_DetalheAulaDialog> createState() => _DetalheAulaDialogState();
}

class _DetalheAulaDialogState extends State<_DetalheAulaDialog>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat _timeFormat = DateFormat('HH:mm');
  final DateFormat _fullDateFormat = DateFormat(
    "EEEE, dd 'de' MMMM 'de' yyyy",
    'pt_BR',
  );

  bool _carregandoChamada = true;
  Map<String, dynamic>? _chamadaData;
  List<Map<String, dynamic>> _alunosChamada = [];
  String? _erro;

  late final AnimationController _piscaController;
  late final Animation<double> _piscaAnimation;

  @override
  void initState() {
    super.initState();
    _buscarChamada();
    _piscaController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _piscaAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _piscaController, curve: Curves.easeInOut),
    );
    _piscaController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _piscaController.dispose();
    super.dispose();
  }

  Color _readableOnLocal(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisibleLocal(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.26) return color;
    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;
  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ??
      _readableOnLocal(_appBarBg());

  Color _onGradientText() {
    final t = context.uai;
    final temaEscuro =
        t.background.computeLuminance() < 0.45 ||
        t.surface.computeLuminance() < 0.45;
    if (temaEscuro) return Colors.white;
    return _readableOnLocal(t.primary);
  }

  Future<void> _buscarChamada() async {
    try {
      final turmaId = widget.item['turma_id']?.toString() ?? '';
      final dataFmt = widget.item['data_formatada']?.toString() ?? '';

      if (turmaId.isEmpty || dataFmt.isEmpty) {
        if (mounted) {
          setState(() {
            _carregandoChamada = false;
            _erro = 'Dados insuficientes para buscar a chamada.';
          });
        }
        return;
      }

      var query = await _firestore
          .collection('chamadas')
          .where('turma_id', isEqualTo: turmaId)
          .where('data_formatada', isEqualTo: dataFmt)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        query = await _firestore
            .collection('chamadas_turma')
            .where('turma_id', isEqualTo: turmaId)
            .where('data_formatada', isEqualTo: dataFmt)
            .limit(1)
            .get();
      }

      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();
        final alunos =
            (data['alunos'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((a) => Map<String, dynamic>.from(a))
                .toList() ??
            [];

        if (mounted) {
          setState(() {
            _chamadaData = data;
            _alunosChamada = alunos;
            _carregandoChamada = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _carregandoChamada = false;
            _erro = 'Chamada não encontrada.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregandoChamada = false;
          _erro = 'Erro ao buscar chamada: $e';
        });
      }
    }
  }

  Color _corTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'objetiva':
        return context.uai.info;
      case 'roda':
        return context.uai.error;
      case 'instrumentação':
      case 'instrumentacao':
        return context.uai.warning;
      case 'especial':
        return context.uai.associacao;
      case 'evento':
      case 'batizado':
        return context.uai.warning;
      default:
        return context.uai.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final item = widget.item;
    final data = item['data'] as DateTime;
    final presente = item['presente'] as bool;
    final tipoAula = item['tipo_aula'] as String;
    final professor = item['professor'] as String;
    final observacao = item['observacao'] as String;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(14),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 680, maxWidth: 700),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.cardRadius + 6),
          border: Border.all(color: t.border),
          boxShadow: t.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(t.cardRadius + 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(data, presente),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildChip(
                            Icons.school_rounded,
                            tipoAula,
                            _corTipo(tipoAula),
                          ),
                          _buildChip(
                            Icons.assignment_ind_rounded,
                            'Aula registrada por: $professor',
                            t.associacao,
                          ),
                        ],
                      ),
                      if (observacao.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _buildObservacaoBox(observacao),
                      ],
                      const SizedBox(height: 16),
                      Divider(color: t.border),
                      const SizedBox(height: 10),
                      _buildChamadaContent(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border(top: BorderSide(color: t.border)),
                ),
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('FECHAR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _appBarBg(),
                    foregroundColor: _appBarFg(),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(DateTime data, bool presente) {
    final t = context.uai;
    final baseColor = presente ? t.success : t.error;
    final statusColor = _ensureVisibleLocal(baseColor, t.surface);
    final onStatus = _onGradientText();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColor,
            Color.alphaBlend(statusColor.withOpacity(0.80), t.primary),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: onStatus.withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: onStatus.withOpacity(0.16)),
            ),
            child: Icon(Icons.person_rounded, color: onStatus, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.alunoNome.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onStatus,
                    fontSize: 17,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _buildHeaderPill(
                      icon: presente
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      label: presente ? 'PRESENTE' : 'AUSENTE',
                      onColor: onStatus,
                    ),
                    _buildHeaderPill(
                      icon: Icons.calendar_today_rounded,
                      label: _fullDateFormat.format(data),
                      onColor: onStatus,
                    ),
                    _buildHeaderPill(
                      icon: Icons.access_time_rounded,
                      label: _timeFormat.format(data),
                      onColor: onStatus,
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: onStatus),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderPill({
    required IconData icon,
    required String label,
    required Color onColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: onColor.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onColor.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onColor, size: 13),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onColor,
                fontSize: 10.8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObservacaoBox(String observacao) {
    final t = context.uai;
    final warning = _ensureVisibleLocal(t.warning, t.card);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(warning.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: warning.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.note_rounded, size: 18, color: warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              observacao,
              style: TextStyle(
                fontSize: 13,
                color: t.textPrimary,
                height: 1.3,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChamadaContent() {
    final t = context.uai;

    if (_carregandoChamada) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: t.primary),
              const SizedBox(height: 12),
              Text(
                'Carregando detalhes da chamada...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_erro != null) {
      return Center(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color.alphaBlend(t.error.withOpacity(0.08), t.card),
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(color: t.error.withOpacity(0.18)),
          ),
          child: Text(
            _erro!,
            style: TextStyle(
              color: _ensureVisibleLocal(t.error, t.card),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_chamadaData == null) return const SizedBox.shrink();

    return Column(
      children: [
        _buildResumoChamadaCard(),
        const SizedBox(height: 12),
        ..._alunosChamada.map(_buildAlunoChamadaTile),
      ],
    );
  }

  Widget _buildResumoChamadaCard() {
    final t = context.uai;
    final primary = _ensureVisibleLocal(t.primary, t.card);
    final turmaNome = _chamadaData!['turma_nome']?.toString() ?? 'Turma';
    final presentes = _chamadaData!['presentes'] ?? 0;
    final total = _chamadaData!['total_alunos'] ?? 0;
    final porcentagem = _chamadaData!['porcentagem_frequencia'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Color.alphaBlend(primary.withOpacity(0.07), t.card),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: primary.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.groups_rounded, color: primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  turmaNome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$presentes presentes de $total alunos',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: t.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '$porcentagem%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: _readableOnLocal(primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlunoChamadaTile(Map<String, dynamic> aluno) {
    final t = context.uai;
    final isDestaque =
        aluno['aluno_id']?.toString() == widget.alunoId ||
        aluno['id']?.toString() == widget.alunoId;
    final nome =
        aluno['aluno_nome']?.toString() ??
        aluno['nome']?.toString() ??
        'Sem nome';
    final presente = aluno['presente'] == true;
    final observacao = aluno['observacao']?.toString() ?? '';
    final statusColor = _ensureVisibleLocal(
      presente ? t.success : t.error,
      t.card,
    );

    return AnimatedBuilder(
      animation: _piscaAnimation,
      builder: (context, child) {
        final opacidade = isDestaque ? _piscaAnimation.value : 1.0;
        return Opacity(
          opacity: opacidade,
          child: Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDestaque
                  ? Color.alphaBlend(statusColor.withOpacity(0.12), t.card)
                  : t.cardAlt,
              borderRadius: BorderRadius.circular(t.inputRadius),
              border: Border.all(
                color: isDestaque ? statusColor : t.border,
                width: isDestaque ? 2.2 : 1,
              ),
              boxShadow: isDestaque
                  ? [
                      BoxShadow(
                        color: statusColor.withOpacity(0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isDestaque
                              ? FontWeight.w900
                              : FontWeight.w700,
                          color: isDestaque ? statusColor : t.textPrimary,
                        ),
                      ),
                      if (observacao.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            observacao,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: t.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      statusColor.withOpacity(0.08),
                      t.card,
                    ),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: statusColor.withOpacity(0.14)),
                  ),
                  child: Text(
                    presente ? 'P' : 'A',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChip(IconData icon, String label, Color color) {
    final t = context.uai;
    final accent = _ensureVisibleLocal(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: accent),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
