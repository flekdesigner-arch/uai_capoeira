// screens/alunos/historico_frequencia_screen.dart
import 'dart:async';

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
// 🔥 CACHE EM MEMÓRIA PARA ECONOMIZAR LEITURAS
// ============================================

class CacheService {
  static final CacheService _instance = CacheService._internal();

  factory CacheService() => _instance;

  CacheService._internal();

  final Map<String, CacheEntry> _memoryCache = {};
  final Duration cacheValidity = Duration(minutes: 30);

  bool isCacheValid(String key) {
    final entry = _memoryCache[key];
    if (entry == null) return false;

    return DateTime.now().difference(entry.timestamp) < cacheValidity;
  }

  Future<void> saveToCache(String key, dynamic data) async {
    _memoryCache[key] = CacheEntry(
      data: data,
      timestamp: DateTime.now(),
    );
  }

  dynamic loadFromCache(String key) {
    if (_memoryCache.containsKey(key) && isCacheValid(key)) {
      return _memoryCache[key]!.data;
    }

    return null;
  }

  void remove(String key) {
    _memoryCache.remove(key);
  }
}

class CacheEntry {
  final dynamic data;
  final DateTime timestamp;

  CacheEntry({
    required this.data,
    required this.timestamp,
  });
}

// ============================================
// 🔥 TELA PRINCIPAL DO HISTÓRICO
// ============================================

class HistoricoFrequenciaScreen extends StatefulWidget {
  final String alunoId;
  final String alunoNome;

  HistoricoFrequenciaScreen({
    super.key,
    required this.alunoId,
    required this.alunoNome,
  });

  @override
  State<HistoricoFrequenciaScreen> createState() =>
      _HistoricoFrequenciaScreenState();
}

class _HistoricoFrequenciaScreenState extends State<HistoricoFrequenciaScreen> {
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


  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CacheService _cache = CacheService();
  final Connectivity _connectivity = Connectivity();

  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final DateFormat _timeFormat = DateFormat('HH:mm');
  final DateFormat _monthNameFormat = DateFormat('MMMM', 'pt_BR');

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tempoRealSub;

  String _filtroPeriodo = 'Este Mês';
  String? _filtroTipoAula;

  bool _carregando = true;
  bool _temErro = false;
  bool _isOffline = false;
  String _mensagemErro = '';

  int _totalPresencas = 0;
  int _totalFaltas = 0;
  int _totalAulas = 0;
  double _percentualPresenca = 0.0;
  int _sequenciaAtual = 0;
  String? _ultimaPresenca;
  Map<String, int> _presencasPorDia = {
    'seg': 0,
    'ter': 0,
    'qua': 0,
    'qui': 0,
    'sex': 0,
    'sab': 0,
    'dom': 0,
  };
  Map<String, int> _presencasPorTipoAula = {};
  List<Map<String, dynamic>> _historicoItems = [];

  DateTime? _ultimaBusca;
  String _fonteDados = 'Carregando...';

  final List<String> _periodos = const [
    'Este Mês',
    'Mês Passado',
    'Últimos 3 Meses',
    'Este Ano',
    'Ano Passado',
    'Todos',
  ];

  final List<String?> _tiposAula = const [
    null,
    'OBJETIVA',
    'RODA',
    'INSTRUMENTAÇÃO',
    'ESPECIAL',
    'EVENTO',
    'BATIZADO',
  ];

  bool get _usaTempoReal => _filtroPeriodo == 'Este Mês';

  String get _cacheKey {
    return 'historico_freq_${widget.alunoId}_${_filtroPeriodo}_${_filtroTipoAula ?? 'TODAS'}';
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

      if (cacheado is _ResumoFrequencia) {
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

        if (cacheado is _ResumoFrequencia) {
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

  Future<void> _carregarBuscaUnica({
    bool forcarAtualizacao = false,
  }) async {
    final cacheado = _cache.loadFromCache(_cacheKey);

    if (!forcarAtualizacao && cacheado is _ResumoFrequencia) {
      _aplicarResumo(cacheado, fonte: 'Cache inteligente');
      return;
    }

    try {
      final snapshot = await _buildQuery()
          .get(GetOptions(source: Source.server))
          .timeout(Duration(seconds: 20));

      final resumo = _calcularResumo(snapshot.docs);

      await _cache.saveToCache(_cacheKey, resumo);

      if (!mounted) return;

      _aplicarResumo(resumo, fonte: 'Busca única');
    } catch (e) {
      final fallback = _cache.loadFromCache(_cacheKey);

      if (fallback is _ResumoFrequencia) {
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

    if (_filtroTipoAula != null && _filtroTipoAula!.trim().isNotEmpty) {
      query = query.where('tipo_aula', isEqualTo: _filtroTipoAula);
    }

    return query.orderBy('data_aula', descending: true);
  }

  DateTimeRange? _periodoRange() {
    final agora = DateTime.now();

    switch (_filtroPeriodo) {
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
          end: DateTime(agora.year, agora.month, agora.day, 23, 59, 59),
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

  _ResumoFrequencia _calcularResumo(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    int presencas = 0;
    int faltas = 0;
    int sequencia = 0;
    bool sequenciaAtiva = true;
    String? ultimaData;

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
    final historico = <Map<String, dynamic>>[];

    for (int i = 0; i < docs.length; i++) {
      final doc = docs[i];
      final data = doc.data();

      final presente = data['presente'] == true;
      final dataAula = _toDate(data['data_aula']) ?? DateTime.now();
      final tipoAula = data['tipo_aula']?.toString() ?? 'Aula';
      final professor = data['professor_nome']?.toString() ??
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

        ultimaData ??= data['data_formatada']?.toString().trim().isNotEmpty == true
            ? data['data_formatada'].toString()
            : _dateFormat.format(dataAula);

        if (sequenciaAtiva) {
          sequencia++;
        }

        if (porDia.containsKey(dia)) {
          porDia[dia] = (porDia[dia] ?? 0) + 1;
        }

        porTipo[tipoAula] = (porTipo[tipoAula] ?? 0) + 1;
      } else {
        faltas++;
        sequenciaAtiva = false;
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
        'data_formatada': data['data_formatada']?.toString() ??
            _dateFormat.format(dataAula),
      });
    }

    final totalAulas = presencas + faltas;

    return _ResumoFrequencia(
      totalPresencas: presencas,
      totalFaltas: faltas,
      totalAulas: totalAulas,
      percentualPresenca: totalAulas > 0 ? (presencas / totalAulas) * 100 : 0,
      sequenciaAtual: sequencia,
      ultimaPresenca: ultimaData,
      presencasPorDia: porDia,
      presencasPorTipoAula: porTipo,
      historicoItems: historico,
      carregadoEm: DateTime.now(),
    );
  }

  void _aplicarResumo(_ResumoFrequencia resumo, {required String fonte}) {
    if (!mounted) return;

    setState(() {
      _totalPresencas = resumo.totalPresencas;
      _totalFaltas = resumo.totalFaltas;
      _totalAulas = resumo.totalAulas;
      _percentualPresenca = resumo.percentualPresenca;
      _sequenciaAtual = resumo.sequenciaAtual;
      _ultimaPresenca = resumo.ultimaPresenca;
      _presencasPorDia = resumo.presencasPorDia;
      _presencasPorTipoAula = resumo.presencasPorTipoAula;
      _historicoItems = resumo.historicoItems;
      _ultimaBusca = resumo.carregadoEm;
      _fonteDados = fonte;
      _carregando = false;
      _temErro = false;
      _mensagemErro = '';
    });

    debugPrint(
      '📊 Histórico frequência: $_totalPresencas presenças, '
          '$_totalFaltas faltas, $_totalAulas aulas, fonte: $fonte',
    );
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _normalizarDiaSemanaAbrev(dynamic valor) {
    final raw = valor?.toString().toLowerCase().trim() ?? '';

    if (raw.isEmpty) return '';

    final semPonto = raw
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

    if (semPonto.startsWith('seg') || semPonto.contains('segunda')) {
      return 'seg';
    }

    if (semPonto.startsWith('ter') || semPonto.contains('terca')) {
      return 'ter';
    }

    if (semPonto.startsWith('qua') || semPonto.contains('quarta')) {
      return 'qua';
    }

    if (semPonto.startsWith('qui') || semPonto.contains('quinta')) {
      return 'qui';
    }

    if (semPonto.startsWith('sex') || semPonto.contains('sexta')) {
      return 'sex';
    }

    if (semPonto.startsWith('sab') || semPonto.contains('sabado')) {
      return 'sab';
    }

    if (semPonto.startsWith('dom') || semPonto.contains('domingo')) {
      return 'dom';
    }

    return semPonto.length >= 3 ? semPonto.substring(0, 3) : semPonto;
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
        return context.uai.warning;
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

  String _getTituloPeriodo() {
    final agora = DateTime.now();

    switch (_filtroPeriodo) {
      case 'Este Mês':
        return _monthNameFormat.format(agora).toUpperCase();

      case 'Mês Passado':
        return _monthNameFormat
            .format(DateTime(agora.year, agora.month - 1, 1))
            .toUpperCase();

      case 'Últimos 3 Meses':
        final m1 = DateTime(agora.year, agora.month - 2, 1);
        return '${_monthNameFormat.format(m1).toUpperCase()} - ${_monthNameFormat.format(agora).toUpperCase()}';

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

  String _getSubtituloPeriodo() {
    final agora = DateTime.now();

    switch (_filtroPeriodo) {
      case 'Este Mês':
        return '${agora.day} de ${_monthNameFormat.format(agora)} de ${agora.year}';

      case 'Mês Passado':
        final mp = DateTime(agora.year, agora.month - 1, 1);
        return '${_monthNameFormat.format(mp)} de ${mp.year}';

      case 'Últimos 3 Meses':
        final ini = DateTime(agora.year, agora.month - 2, 1);
        return 'De ${_monthNameFormat.format(ini)} a ${_monthNameFormat.format(agora)} de ${agora.year}';

      case 'Este Ano':
        return 'Janeiro a Dezembro de ${agora.year}';

      case 'Ano Passado':
        return 'Janeiro a Dezembro de ${agora.year - 1}';

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

  Future<void> _atualizar() async {
    _cache.remove(_cacheKey);
    await _carregarDados(forcarAtualizacao: true);
  }

  void _aplicarFiltro(String periodo) {
    if (_filtroPeriodo == periodo) return;

    if (periodo == 'Todos' &&
        _cache.loadFromCache('historico_freq_${widget.alunoId}_Todos_${_filtroTipoAula ?? 'TODAS'}') == null) {
      _confirmarFiltroTodos();
      return;
    }

    setState(() {
      _filtroPeriodo = periodo;
      _historicoItems = [];
      _carregando = true;
    });

    _carregarDados();
  }

  Future<void> _confirmarFiltroTodos() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.all_inclusive_rounded, color: context.uai.primary),
              SizedBox(width: 8),
              Expanded(child: Text('Carregar todo histórico?')),
            ],
          ),
          content: Text(
            'Esse filtro busca todos os logs do aluno. Depois da primeira busca, o resultado fica em cache por 30 minutos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
                foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
              ),
              child: Text('CARREGAR'),
            ),
          ],
        );
      },
    );

    if (confirmar == true) {
      setState(() {
        _filtroPeriodo = 'Todos';
        _historicoItems = [];
        _carregando = true;
      });

      _carregarDados();
    }
  }

  void _aplicarFiltroTipoAula(String? tipo) {
    if (_filtroTipoAula == tipo) return;

    setState(() {
      _filtroTipoAula = tipo;
      _historicoItems = [];
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
              'Histórico de Frequência',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.alunoNome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
        elevation: 2,
        actions: [
          if (_isOffline)
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(
                Icons.wifi_off,
                color: t.warning,
                size: 20,
              ),
            ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _atualizar,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
          constraints.maxWidth > 980 ? 980.0 : constraints.maxWidth;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                children: [
                  if (!_carregando || _historicoItems.isNotEmpty) _buildFiltros(),
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
      padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: context.uai.surface,
        border: Border(
          bottom: BorderSide(color: context.uai.border),
        ),
        boxShadow: [
          BoxShadow(
            color: context.uai.textPrimary.withOpacity(0.045),
            blurRadius: 10,
            offset: Offset(0, 3),
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
                      Icons.tune_rounded,
                      color: context.uai.primary,
                      size: 19,
                    ),
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Filtros da frequência',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            height: 1.05,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          _usaTempoReal
                              ? 'Este mês em tempo real'
                              : 'Busca única com cache inteligente',
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
              SizedBox(height: 12),
              if (isWide)
                Row(
                  children: [
                    Expanded(child: _buildFiltroDropdownPeriodo()),
                    SizedBox(width: 10),
                    Expanded(child: _buildFiltroDropdownTipoAula()),
                  ],
                )
              else
                Column(
                  children: [
                    _buildFiltroDropdownPeriodo(),
                    SizedBox(height: 9),
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
    final color = _usaTempoReal ? context.uai.success : context.uai.textMuted;
    final text = _usaTempoReal ? 'AO VIVO' : 'FILTRO';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _usaTempoReal ? Icons.bolt_rounded : Icons.tune_rounded,
            color: color,
            size: 14,
          ),
          SizedBox(width: 4),
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
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  periodo,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;
        _aplicarFiltro(value);
      },
    );
  }

  Widget _buildFiltroDropdownTipoAula() {
    return DropdownButtonFormField<String?>(
      value: _filtroTipoAula,
      isExpanded: true,
      borderRadius: BorderRadius.circular(16),
      dropdownColor: context.uai.surface,
      decoration: _inputDecorationFiltro(
        label: 'Tipo de aula',
        icon: Icons.sports_martial_arts_rounded,
        color: context.uai.info,
      ),
      items: _tiposAula.map((tipo) {
        final label = tipo == null ? 'Todas as aulas' : _labelTipoAula(tipo);
        final color = tipo == null ? context.uai.info : _corTipoAula(tipo);

        return DropdownMenuItem<String?>(
          value: tipo,
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
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
      filled: true,
      fillColor: context.uai.cardAlt,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
      ),
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
      case 'Este Mês':
        return Icons.today_rounded;
      case 'Mês Passado':
        return Icons.history_rounded;
      case 'Últimos 3 Meses':
        return Icons.date_range_rounded;
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
            SizedBox(height: 16),
            Text(
              _usaTempoReal
                  ? 'Escutando chamadas deste mês...'
                  : 'Buscando histórico...',
              style: TextStyle(color: context.uai.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_temErro) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 80,
                color: context.uai.error,
              ),
              SizedBox(height: 16),
              Text(
                'Ops! Algo deu errado',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                _mensagemErro,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.uai.textSecondary, fontSize: 14),
              ),
              SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _atualizar,
                icon: Icon(Icons.refresh),
                label: Text('Tentar novamente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
                  foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_historicoItems.isEmpty) {
      return RefreshIndicator(
        onRefresh: _atualizar,
        child: ListView(
          padding: EdgeInsets.all(24),
          children: [
            SizedBox(height: 80),
            Icon(Icons.history, size: 100, color: context.uai.border),
            SizedBox(height: 16),
            Text(
              'Nenhum registro encontrado',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: context.uai.textMuted),
            ),
            SizedBox(height: 8),
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
        padding: EdgeInsets.only(bottom: 24),
        children: [
          _buildHeaderEstatistico(),
          _buildPresencasPorDia(),
          _buildPresencasPorTipoAula(),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Icon(Icons.history_rounded, color: context.uai.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Histórico de aulas (${_historicoItems.length})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._historicoItems.map(_buildHistoryItem),
          Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 28,
                    color: context.uai.success.withOpacity(0.75),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Todos os registros do filtro foram carregados',
                    style: TextStyle(fontSize: 13, color: context.uai.textMuted),
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
      margin: EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _usaTempoReal ? context.uai.success.withOpacity(0.10) : context.uai.info.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _usaTempoReal ? context.uai.success.withOpacity(0.18) : context.uai.info.withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _usaTempoReal ? Icons.bolt_rounded : Icons.cached_rounded,
            color: _usaTempoReal ? context.uai.success : context.uai.info,
            size: 20,
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              _usaTempoReal
                  ? 'Este mês está em tempo real. Novas chamadas aparecem automaticamente.'
                  : 'Dados carregados por $_fonteDados às ${_formatHora(_ultimaBusca)}. Atualizar força nova busca.',
              style: TextStyle(
                color:
                _usaTempoReal ? context.uai.success : context.uai.info,
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

  Widget _buildHeaderEstatistico() {
    return Container(
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withOpacity(0.22),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
        gradient: context.uai.primaryGradient,
      ),
      child: Padding(
        padding: EdgeInsets.all(22),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: context.uai.card.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _getTituloPeriodo(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.uai.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            SizedBox(height: 6),
            Text(
              _getSubtituloPeriodo(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.uai.card.withOpacity(0.72),
                fontSize: 11,
              ),
            ),
            SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 430;

                final metricas = [
                  _buildMetrica(
                    '$_totalPresencas',
                    'Presenças',
                    Icons.check_circle_rounded,
                    context.uai.success.withOpacity(0.75),
                  ),
                  _buildMetrica(
                    '$_totalFaltas',
                    'Faltas',
                    Icons.cancel_rounded,
                    context.uai.error,
                  ),
                  _buildMetrica(
                    '${_percentualPresenca.toStringAsFixed(0)}%',
                    'Frequência',
                    Icons.pie_chart_rounded,
                    context.uai.warning,
                  ),
                ];

                if (narrow) {
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: metricas,
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: metricas,
                );
              },
            ),
            SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _totalAulas > 0 ? _percentualPresenca / 100 : 0,
                backgroundColor: context.uai.card.withOpacity(0.25),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _percentualPresenca >= 80
                      ? context.uai.success
                      : _percentualPresenca >= 60
                      ? context.uai.warning
                      : context.uai.error,
                ),
                minHeight: 10,
              ),
            ),
            SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 430;

                final linhas = [
                  _buildInfoRow(
                    Icons.local_fire_department,
                    'Sequência',
                    '$_sequenciaAtual presença(s)',
                    context.uai.warning,
                  ),
                  _buildInfoRow(
                    Icons.event_available,
                    'Última presença',
                    _formatarDataStr(_ultimaPresenca),
                    context.uai.success.withOpacity(0.75),
                  ),
                ];

                if (narrow) {
                  return Column(
                    children: [
                      linhas[0],
                      SizedBox(height: 10),
                      linhas[1],
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: linhas,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetrica(
      String valor,
      String label,
      IconData icon,
      Color color,
      ) {
    return SizedBox(
      width: 94,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.uai.card.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          SizedBox(height: 10),
          Text(
            valor,
            style: TextStyle(
              color: context.uai.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.uai.card.withOpacity(0.8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
      IconData icon,
      String label,
      String valor,
      Color color,
      ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: context.uai.card.withOpacity(0.7),
                fontSize: 10,
              ),
            ),
            Text(
              valor,
              style: TextStyle(
                color: context.uai.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPresencasPorDia() {
    if (_presencasPorDia.values.every((v) => v == 0)) {
      return SizedBox.shrink();
    }

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
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month, color: context.uai.primary, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Presenças por Dia',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
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
                      _presencasPorDia[dia[0]] ?? 0,
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

    return Container(
      padding: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: ativo ? context.uai.error.withOpacity(0.10) : context.uai.cardAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ativo ? context.uai.error.withOpacity(0.24) : context.uai.border,
        ),
      ),
      child: Column(
        children: [
          Text(
            dia,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: ativo ? context.uai.primary : context.uai.textMuted,
            ),
          ),
          SizedBox(height: 2),
          Text(
            '$qtd',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: ativo ? context.uai.primary : context.uai.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresencasPorTipoAula() {
    if (_presencasPorTipoAula.isEmpty) return SizedBox.shrink();

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school, color: context.uai.info, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Por Tipo de Aula',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presencasPorTipoAula.entries.map((entry) {
              final cor = _corTipoAula(entry.key);

              return Container(
                padding:
                EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                      decoration:
                      BoxDecoration(color: cor, shape: BoxShape.circle),
                    ),
                    SizedBox(width: 6),
                    Text(
                      _labelTipoAula(entry.key),
                      style: TextStyle(
                        fontSize: 11,
                        color: cor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 4),
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
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        elevation: presente ? 3 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _mostrarDetalhesAula(item),
          child: Padding(
            padding: EdgeInsets.all(14),
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
                            color: (presente ? context.uai.success : context.uai.error)
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
                SizedBox(width: 14),
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
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
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
                      SizedBox(height: 6),
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
                      SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            Icons.assignment_ind_rounded,
                            size: 13,
                            color: context.uai.associacao,
                          ),
                          SizedBox(width: 4),
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
                SizedBox(width: 4),
                Icon(Icons.chevron_right, color: context.uai.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  void _mostrarDetalhesAula(Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return _DetalheAulaDialog(
          item: item,
          alunoId: widget.alunoId,
          alunoNome: widget.alunoNome,
        );
      },
    );
  }
}

// ============================================
// 🔥 MODELO DE RESUMO
// ============================================

class _ResumoFrequencia {
  final int totalPresencas;
  final int totalFaltas;
  final int totalAulas;
  final double percentualPresenca;
  final int sequenciaAtual;
  final String? ultimaPresenca;
  final Map<String, int> presencasPorDia;
  final Map<String, int> presencasPorTipoAula;
  final List<Map<String, dynamic>> historicoItems;
  final DateTime carregadoEm;

  _ResumoFrequencia({
    required this.totalPresencas,
    required this.totalFaltas,
    required this.totalAulas,
    required this.percentualPresenca,
    required this.sequenciaAtual,
    required this.ultimaPresenca,
    required this.presencasPorDia,
    required this.presencasPorTipoAula,
    required this.historicoItems,
    required this.carregadoEm,
  });
}

// ============================================
// 🔥 DIÁLOGO DE DETALHE DA AULA
// ============================================

class _DetalheAulaDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final String alunoId;
  final String alunoNome;

  _DetalheAulaDialog({
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
  final DateFormat _fullDateFormat =
  DateFormat("EEEE, dd 'de' MMMM 'de' yyyy", 'pt_BR');

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
      duration: Duration(milliseconds: 800),
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
        final alunos = (data['alunos'] as List<dynamic>?)
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
        return context.uai.warning;
      default:
        return context.uai.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final data = item['data'] as DateTime;
    final presente = item['presente'] as bool;
    final tipoAula = item['tipo_aula'] as String;
    final professor = item['professor'] as String;
    final observacao = item['observacao'] as String;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(16),
      child: Container(
        constraints: BoxConstraints(maxHeight: 650, maxWidth: 680),
        decoration: BoxDecoration(
          color: context.uai.textPrimary,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: context.uai.textPrimary.withOpacity(0.2),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(data, presente),
              Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildChip(Icons.school, tipoAula, _corTipo(tipoAula)),
                        _buildChip(
                          Icons.assignment_ind_rounded,
                          'Aula registrada por: $professor',
                          context.uai.associacao,
                        ),
                      ],
                    ),
                    if (observacao.isNotEmpty) ...[
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.uai.warning.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.uai.warning.withOpacity(0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.note_rounded,
                              size: 16,
                              color: context.uai.warning,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                observacao,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.uai.warning,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 16),
                    Divider(),
                    SizedBox(height: 8),
                    _buildChamadaContent(),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
                          foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'FECHAR',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(DateTime data, bool presente) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: presente
              ? [context.uai.success, context.uai.success.withOpacity(0.74)]
              : [context.uai.primaryDark, context.uai.error],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.uai.card.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.person, color: context.uai.textPrimary, size: 40),
                SizedBox(height: 8),
                Text(
                  widget.alunoNome.toUpperCase(),
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Container(
                  padding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.uai.card.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    presente ? '✅ PRESENTE' : '❌ AUSENTE',
                    style: TextStyle(
                      color: context.uai.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          Text(
            _fullDateFormat.format(data),
            style: TextStyle(color: context.uai.card.withOpacity(0.9), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          Text(
            _timeFormat.format(data),
            style: TextStyle(color: context.uai.card.withOpacity(0.8), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildChamadaContent() {
    if (_carregandoChamada) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(color: context.uai.error),
        ),
      );
    }

    if (_erro != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            _erro!,
            style: TextStyle(color: context.uai.textMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_chamadaData == null) {
      return SizedBox.shrink();
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.uai.error.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.groups, color: context.uai.primary, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _chamadaData!['turma_nome']?.toString() ?? 'Turma',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: context.uai.primary,
                      ),
                    ),
                    Text(
                      '${_chamadaData!['presentes'] ?? 0} presentes de ${_chamadaData!['total_alunos'] ?? 0} alunos',
                      style: TextStyle(fontSize: 11, color: context.uai.primaryDark),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.uai.textPrimary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_chamadaData!['porcentagem_frequencia'] ?? 0}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: context.uai.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        ..._alunosChamada.map(_buildAlunoChamadaTile),
      ],
    );
  }

  Widget _buildAlunoChamadaTile(Map<String, dynamic> aluno) {
    final isDestaque = aluno['aluno_id']?.toString() == widget.alunoId;
    final nome = aluno['aluno_nome']?.toString() ?? 'Sem nome';
    final presente = aluno['presente'] == true;
    final observacao = aluno['observacao']?.toString() ?? '';

    return AnimatedBuilder(
      animation: _piscaAnimation,
      builder: (context, child) {
        final opacidade = isDestaque ? _piscaAnimation.value : 1.0;

        return Opacity(
          opacity: opacidade,
          child: Container(
            margin: EdgeInsets.only(bottom: 6),
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDestaque
                  ? (presente ? context.uai.success.withOpacity(0.18) : context.uai.error.withOpacity(0.16))
                  : context.uai.cardAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDestaque
                    ? (presente ? context.uai.success : context.uai.error)
                    : context.uai.border,
                width: isDestaque ? 2.5 : 1,
              ),
              boxShadow: isDestaque
                  ? [
                BoxShadow(
                  color: (presente ? context.uai.success : context.uai.error)
                      .withOpacity(0.3),
                  blurRadius: 8,
                ),
              ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: presente ? context.uai.success : context.uai.error,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                          isDestaque ? FontWeight.bold : FontWeight.normal,
                          color:
                          isDestaque ? context.uai.textPrimary : context.uai.textSecondary,
                        ),
                      ),
                      if (observacao.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            observacao,
                            style: TextStyle(
                              fontSize: 10,
                              color: context.uai.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
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
    );
  }

  Widget _buildChip(IconData icon, String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
