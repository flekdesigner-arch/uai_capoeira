import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';

class AreaAlunoFrequenciaScreen extends StatefulWidget {
  final Map<String, dynamic> aluno;
  final Map<String, dynamic> authPayload;

  const AreaAlunoFrequenciaScreen({
    super.key,
    required this.aluno,
    required this.authPayload,
  });

  @override
  State<AreaAlunoFrequenciaScreen> createState() =>
      _AreaAlunoFrequenciaScreenState();
}

class _AreaAlunoFrequenciaScreenState extends State<AreaAlunoFrequenciaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _periodo = 'Este Mês';
  String? _tipoAula;

  bool _carregandoBuscaUnica = false;
  bool _erroBuscaUnica = false;
  String _mensagemErroBuscaUnica = '';

  _FrequenciaResumo? _resumoBuscaUnica;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _realtimeSub;

  bool _carregandoRealtime = true;
  bool _erroRealtime = false;
  String _mensagemErroRealtime = '';
  _FrequenciaResumo? _resumoRealtime;

  bool _carregandoIndicadores = true;
  bool _indicadoresAtivo = true;
  bool _mostrarTextoUltimaPresencaIndicador = true;
  List<_IndicadorFaixa> _faixasIndicadores = [];

  final Map<String, _CacheFrequenciaEntry> _cache = {};

  static const Duration _cacheValidade = Duration(minutes: 20);
  static DateTime? _indicadoresCacheEm;
  static bool? _indicadoresAtivoCache;
  static bool? _mostrarTextoUltimaPresencaIndicadorCache;
  static List<_IndicadorFaixa>? _faixasIndicadoresCache;
  static const Duration _indicadoresCacheValidade = Duration(minutes: 20);

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

  String get _alunoId {
    return widget.aluno['aluno_id']?.toString() ??
        widget.aluno['id']?.toString() ??
        widget.aluno['docId']?.toString() ??
        '';
  }

  String get _alunoNome => widget.aluno['nome']?.toString() ?? 'Aluno';

  bool get _usaTempoReal => _periodo == 'Este Mês';

  String get _cacheKey => '${_alunoId}_${_periodo}_${_tipoAula ?? 'TODAS'}';

  @override
  void initState() {
    super.initState();
    _prepararTela();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _prepararTela() async {
    await _carregarConfiguracaoIndicadores();
    await _carregarAtual();
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

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  Color _onPrimary() {
    final t = context.uai;
    final temaEscuro =
        t.background.computeLuminance() < 0.45 || t.surface.computeLuminance() < 0.45;

    if (temaEscuro) return Colors.white;
    return _readableOn(t.primary);
  }

  Future<void> _carregarConfiguracaoIndicadores({bool forcar = false}) async {
    final cacheValido = _indicadoresCacheEm != null &&
        DateTime.now().difference(_indicadoresCacheEm!) < _indicadoresCacheValidade &&
        _faixasIndicadoresCache != null;

    if (!forcar && cacheValido) {
      if (!mounted) return;
      setState(() {
        _indicadoresAtivo = _indicadoresAtivoCache ?? true;
        _mostrarTextoUltimaPresencaIndicador =
            _mostrarTextoUltimaPresencaIndicadorCache ?? true;
        _faixasIndicadores = List<_IndicadorFaixa>.from(_faixasIndicadoresCache!);
        _carregandoIndicadores = false;
      });
      return;
    }

    if (mounted) setState(() => _carregandoIndicadores = true);

    try {
      final doc = await _firestore
          .collection('configuracoes_sistema')
          .doc('indicadores_ausencia')
          .get(const GetOptions(source: Source.serverAndCache));

      final data = doc.data();
      final faixasRaw = data?['faixas'];
      final faixas = faixasRaw is List
          ? faixasRaw
          .whereType<Map>()
          .map((e) => _IndicadorFaixa.fromMap(Map<String, dynamic>.from(e)))
          .toList()
          : _faixasIndicadoresPadrao();

      faixas.sort((a, b) => a.ateDias.compareTo(b.ateDias));

      _indicadoresAtivoCache = data?['ativo'] != false;
      _mostrarTextoUltimaPresencaIndicadorCache =
          data?['mostrar_texto_ultima_presenca'] != false;
      _faixasIndicadoresCache = faixas;
      _indicadoresCacheEm = DateTime.now();

      if (!mounted) return;
      setState(() {
        _indicadoresAtivo = _indicadoresAtivoCache ?? true;
        _mostrarTextoUltimaPresencaIndicador =
            _mostrarTextoUltimaPresencaIndicadorCache ?? true;
        _faixasIndicadores = faixas;
        _carregandoIndicadores = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _indicadoresAtivo = true;
        _mostrarTextoUltimaPresencaIndicador = true;
        _faixasIndicadores = _faixasIndicadoresPadrao();
        _carregandoIndicadores = false;
      });
    }
  }

  List<_IndicadorFaixa> _faixasIndicadoresPadrao() {
    return const [
      _IndicadorFaixa(
        ateDias: 3,
        corHex: '#2196F3',
        label: 'Frequente',
        geraAlerta: false,
        mensagemAlerta: '',
      ),
      _IndicadorFaixa(
        ateDias: 6,
        corHex: '#4CAF50',
        label: 'Regular',
        geraAlerta: false,
        mensagemAlerta: '',
      ),
      _IndicadorFaixa(
        ateDias: 12,
        corHex: '#FFC107',
        label: 'Atenção',
        geraAlerta: true,
        mensagemAlerta: '',
      ),
      _IndicadorFaixa(
        ateDias: 24,
        corHex: '#FF9800',
        label: 'Ausente',
        geraAlerta: true,
        mensagemAlerta: '',
      ),
      _IndicadorFaixa(
        ateDias: 35,
        corHex: '#FF5722',
        label: 'Muito ausente',
        geraAlerta: true,
        mensagemAlerta: '',
      ),
      _IndicadorFaixa(
        ateDias: 9999,
        corHex: '#F44336',
        label: 'Risco de inatividade',
        geraAlerta: true,
        mensagemAlerta: '',
      ),
    ];
  }

  Future<void> _carregarAtual({bool forcar = false}) async {
    await _realtimeSub?.cancel();
    _realtimeSub = null;

    if (_alunoId.isEmpty) {
      setState(() {
        _carregandoRealtime = false;
        _carregandoBuscaUnica = false;
        _erroRealtime = true;
        _mensagemErroRealtime = 'Aluno não identificado.';
      });
      return;
    }

    if (_usaTempoReal) {
      _iniciarTempoReal();
    } else {
      await _carregarBuscaUnica(forcar: forcar);
    }
  }

  void _iniciarTempoReal() {
    setState(() {
      _carregandoRealtime = true;
      _erroRealtime = false;
      _mensagemErroRealtime = '';
      _resumoRealtime = null;
    });

    _realtimeSub = _buildLogsQuery().snapshots().listen(
          (snapshot) {
        final resumo = _calcularResumo(snapshot.docs);

        if (!mounted) return;

        setState(() {
          _resumoRealtime = resumo;
          _carregandoRealtime = false;
          _erroRealtime = false;
          _mensagemErroRealtime = '';
        });
      },
      onError: (error) {
        if (!mounted) return;

        setState(() {
          _carregandoRealtime = false;
          _erroRealtime = true;
          _mensagemErroRealtime = error.toString();
        });
      },
    );
  }

  Future<void> _carregarBuscaUnica({bool forcar = false}) async {
    final key = _cacheKey;
    final cacheado = _cache[key];

    if (!forcar && cacheado != null && cacheado.estaValido) {
      setState(() {
        _resumoBuscaUnica = cacheado.resumo;
        _carregandoBuscaUnica = false;
        _erroBuscaUnica = false;
        _mensagemErroBuscaUnica = '';
      });
      return;
    }

    setState(() {
      _carregandoBuscaUnica = true;
      _erroBuscaUnica = false;
      _mensagemErroBuscaUnica = '';
      if (forcar) _resumoBuscaUnica = null;
    });

    try {
      final snapshot = await _buildLogsQuery()
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final resumo = _calcularResumo(snapshot.docs);

      _cache[key] = _CacheFrequenciaEntry(
        resumo: resumo,
        criadoEm: DateTime.now(),
      );

      if (!mounted) return;

      setState(() {
        _resumoBuscaUnica = resumo;
        _carregandoBuscaUnica = false;
        _erroBuscaUnica = false;
        _mensagemErroBuscaUnica = '';
      });
    } catch (e) {
      if (!mounted) return;

      final cacheFallback = _cache[key];

      if (cacheFallback != null) {
        setState(() {
          _resumoBuscaUnica = cacheFallback.resumo;
          _carregandoBuscaUnica = false;
          _erroBuscaUnica = false;
          _mensagemErroBuscaUnica = '';
        });
        return;
      }

      setState(() {
        _carregandoBuscaUnica = false;
        _erroBuscaUnica = true;
        _mensagemErroBuscaUnica = e.toString();
      });
    }
  }

  Future<void> _atualizar() async {
    _cache.remove(_cacheKey);
    await _carregarConfiguracaoIndicadores(forcar: true);
    await _carregarAtual(forcar: true);
  }

  void _aplicarPeriodo(String periodo) {
    if (_periodo == periodo) return;

    setState(() => _periodo = periodo);
    _carregarAtual();
  }

  void _aplicarTipoAula(String? tipo) {
    if (_tipoAula == tipo) return;

    setState(() => _tipoAula = tipo);
    _carregarAtual();
  }

  DateTimeRange? _periodoRange() {
    final agora = DateTime.now();

    switch (_periodo) {
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

  Query<Map<String, dynamic>> _buildLogsQuery() {
    Query<Map<String, dynamic>> query = _firestore
        .collection('log_presenca_alunos')
        .where('aluno_id', isEqualTo: _alunoId);

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

    if (_tipoAula != null && _tipoAula!.trim().isNotEmpty) {
      query = query.where('tipo_aula', isEqualTo: _tipoAula);
    }

    return query.orderBy('data_aula', descending: true);
  }

  _FrequenciaResumo _calcularResumo(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    int presencas = 0;
    int faltas = 0;
    int sequenciaPresencasAtual = 0;
    int sequenciaFaltasAtual = 0;
    int melhorSequenciaPresencas = 0;
    int maiorSequenciaFaltas = 0;
    DateTime? ultimaPresenca;

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
      final tipo = data['tipo_aula']?.toString() ?? 'Outro';
      final dia = _normalizarDiaSemanaAbrev(
        data['dia_semana_abrev'] ?? data['dia_semana'],
      );

      final dataAula = _toDate(data['data_aula']) ?? DateTime.now();
      final dataFormatada =
      data['data_formatada']?.toString().trim().isNotEmpty == true
          ? data['data_formatada'].toString()
          : DateFormat('dd/MM/yyyy').format(dataAula);

      int diasEntre = 0;

      if (i < docs.length - 1) {
        final proximaData = _toDate(docs[i + 1].data()['data_aula']);

        if (proximaData != null) {
          diasEntre = dataAula.difference(proximaData).inDays.abs();
        }
      }

      if (presente) {
        presencas++;
        ultimaPresenca ??= dataAula;

        if (porDia.containsKey(dia)) {
          porDia[dia] = (porDia[dia] ?? 0) + 1;
        }

        porTipo[tipo] = (porTipo[tipo] ?? 0) + 1;
      } else {
        faltas++;
      }

      historico.add({
        'id': doc.id,
        'data': dataAula,
        'data_formatada': dataFormatada,
        'presente': presente,
        'tipo_aula': tipo,
        'registrado_por': data['professor_nome']?.toString() ??
            data['professor']?.toString() ??
            data['usuario_nome']?.toString() ??
            'Não informado',
        'observacao': data['observacao']?.toString() ?? '',
        'turma_id': data['turma_id']?.toString() ?? '',
        'turma_nome': data['turma_nome']?.toString() ??
            widget.aluno['turma']?.toString() ??
            '',
        'dias_entre': diasEntre,
      });
    }

    final totalAulas = presencas + faltas;
    final percentual = totalAulas > 0 ? (presencas / totalAulas) * 100 : 0.0;

    if (docs.isNotEmpty) {
      final primeiroStatusPresente = docs.first.data()['presente'] == true;

      for (final doc in docs) {
        final presente = doc.data()['presente'] == true;
        if (presente == primeiroStatusPresente) {
          if (presente) {
            sequenciaPresencasAtual++;
          } else {
            sequenciaFaltasAtual++;
          }
        } else {
          break;
        }
      }
    }

    final cronologico = docs.reversed.toList();
    int atualPresencas = 0;
    int atualFaltas = 0;

    for (final doc in cronologico) {
      final presente = doc.data()['presente'] == true;
      if (presente) {
        atualPresencas++;
        atualFaltas = 0;
      } else {
        atualFaltas++;
        atualPresencas = 0;
      }
      if (atualPresencas > melhorSequenciaPresencas) {
        melhorSequenciaPresencas = atualPresencas;
      }
      if (atualFaltas > maiorSequenciaFaltas) {
        maiorSequenciaFaltas = atualFaltas;
      }
    }

    final ultimaWidget = _ultimaPresencaDoAlunoWidget();
    if (ultimaWidget != null &&
        (ultimaPresenca == null || ultimaWidget.isAfter(ultimaPresenca))) {
      ultimaPresenca = ultimaWidget;
    }

    final diasDesdeUltimaPresenca = _diasDesde(ultimaPresenca);
    final indicador = _faixaParaDias(diasDesdeUltimaPresenca);
    final perfil = _classificarPerfil(percentual: percentual, totalAulas: totalAulas);
    final tendencia = _classificarTendencia(docs);
    final risco = _classificarRisco(
      indicador: indicador,
      percentual: percentual,
      totalAulas: totalAulas,
      sequenciaFaltasAtual: sequenciaFaltasAtual,
      diasDesdeUltimaPresenca: diasDesdeUltimaPresenca,
    );
    final diagnostico = _montarDiagnostico(
      indicador: indicador,
      perfil: perfil,
      tendencia: tendencia,
      risco: risco,
      presencas: presencas,
      totalAulas: totalAulas,
      percentual: percentual,
      sequenciaPresencasAtual: sequenciaPresencasAtual,
      sequenciaFaltasAtual: sequenciaFaltasAtual,
      diasDesdeUltimaPresenca: diasDesdeUltimaPresenca,
    );

    return _FrequenciaResumo(
      totalPresencas: presencas,
      totalFaltas: faltas,
      totalAulas: totalAulas,
      percentualPresenca: percentual,
      sequenciaPresencasAtual: sequenciaPresencasAtual,
      sequenciaFaltasAtual: sequenciaFaltasAtual,
      melhorSequenciaPresencas: melhorSequenciaPresencas,
      maiorSequenciaFaltas: maiorSequenciaFaltas,
      ultimaPresenca: ultimaPresenca,
      diasDesdeUltimaPresenca: diasDesdeUltimaPresenca,
      indicadorAtual: indicador,
      perfil: perfil,
      tendencia: tendencia,
      risco: risco,
      diagnostico: diagnostico,
      presencasPorDia: porDia,
      presencasPorTipoAula: porTipo,
      historico: historico,
      carregadoEm: DateTime.now(),
      origem: _usaTempoReal ? 'Tempo real' : 'Busca única com cache',
    );
  }

  DateTime? _ultimaPresencaDoAlunoWidget() {
    final campos = [
      widget.aluno['ultimo_dia_presente'],
      widget.aluno['ultimoDiaPresente'],
      widget.aluno['ultima_presenca'],
      widget.aluno['ultimaPresenca'],
      widget.aluno['data_ultima_presenca'],
      widget.aluno['dataUltimaPresenca'],
      widget.aluno['ultimo_presente_em'],
      widget.aluno['ultimoPresenteEm'],
      widget.aluno['last_presence'],
      widget.aluno['lastPresence'],
    ];

    for (final campo in campos) {
      final data = _toDate(campo) ?? _parseDataBrasileira(campo);
      if (data != null) return data;
    }

    return null;
  }

  DateTime? _parseDataBrasileira(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;

    try {
      return DateFormat('dd/MM/yyyy').parseStrict(text);
    } catch (_) {
      return null;
    }
  }

  int? _diasDesde(DateTime? data) {
    if (data == null) return null;
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final base = DateTime(data.year, data.month, data.day);
    final dias = hoje.difference(base).inDays;
    return dias < 0 ? 0 : dias;
  }

  _IndicadorFaixa? _faixaParaDias(int? dias) {
    if (!_indicadoresAtivo || dias == null) return null;

    final faixas = _faixasIndicadores.isEmpty
        ? _faixasIndicadoresPadrao()
        : _faixasIndicadores;

    for (final faixa in faixas) {
      if (dias <= faixa.ateDias) return faixa;
    }

    return faixas.isNotEmpty ? faixas.last : null;
  }

  _AnaliseInfo _classificarPerfil({
    required double percentual,
    required int totalAulas,
  }) {
    if (totalAulas == 0) {
      return const _AnaliseInfo(
        titulo: 'Sem dados no período',
        descricao: 'Ainda não existem chamadas suficientes nesse filtro para avaliar a constância.',
        icone: Icons.hourglass_empty_rounded,
        corHex: '#9E9E9E',
      );
    }

    if (percentual >= 85) {
      return const _AnaliseInfo(
        titulo: 'Muito frequente',
        descricao: 'Participa da maioria das aulas. Ótimo sinal de compromisso.',
        icone: Icons.verified_rounded,
        corHex: '#4CAF50',
      );
    }

    if (percentual >= 65) {
      return const _AnaliseInfo(
        titulo: 'Frequente',
        descricao: 'Vai bem, mas ainda pode melhorar a regularidade.',
        icone: Icons.thumb_up_alt_rounded,
        corHex: '#2196F3',
      );
    }

    if (percentual >= 45) {
      return const _AnaliseInfo(
        titulo: 'Regular',
        descricao: 'Participa algumas vezes, mas perde uma parte importante das aulas.',
        icone: Icons.balance_rounded,
        corHex: '#FFC107',
      );
    }

    if (percentual >= 20) {
      return const _AnaliseInfo(
        titulo: 'Baixa constância',
        descricao: 'A presença está baixa. É bom acompanhar para não perder o ritmo.',
        icone: Icons.trending_down_rounded,
        corHex: '#FF9800',
      );
    }

    if (percentual > 0) {
      return const _AnaliseInfo(
        titulo: 'Muito irregular',
        descricao: 'Aparece pouco no período escolhido. Precisa de atenção.',
        icone: Icons.warning_amber_rounded,
        corHex: '#FF5722',
      );
    }

    return const _AnaliseInfo(
      titulo: 'Sem presença no período',
      descricao: 'Não há presença registrada no período escolhido.',
      icone: Icons.person_off_rounded,
      corHex: '#F44336',
    );
  }

  _AnaliseInfo _classificarTendencia(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    if (docs.length < 4) {
      return const _AnaliseInfo(
        titulo: 'Poucos registros',
        descricao: 'Ainda há poucos registros para identificar uma tendência confiável.',
        icone: Icons.insights_rounded,
        corHex: '#9E9E9E',
      );
    }

    final recentes = docs.take(4).toList();
    final anteriores = docs.skip(4).take(4).toList();

    final recentesPct = _percentualDocs(recentes);
    final anterioresPct = anteriores.isEmpty ? recentesPct : _percentualDocs(anteriores);
    final diff = recentesPct - anterioresPct;

    if (diff >= 18) {
      return const _AnaliseInfo(
        titulo: 'Melhorando',
        descricao: 'Nas últimas aulas, a participação melhorou em relação ao período anterior.',
        icone: Icons.trending_up_rounded,
        corHex: '#4CAF50',
      );
    }

    if (diff <= -18) {
      return const _AnaliseInfo(
        titulo: 'Queda recente',
        descricao: 'Nas últimas aulas, a presença caiu. Vale ficar atento.',
        icone: Icons.south_east_rounded,
        corHex: '#F44336',
      );
    }

    return const _AnaliseInfo(
      titulo: 'Estável',
      descricao: 'O padrão recente está parecido com o comportamento anterior.',
      icone: Icons.trending_flat_rounded,
      corHex: '#2196F3',
    );
  }

  double _percentualDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) return 0;
    final presentes = docs.where((d) => d.data()['presente'] == true).length;
    return (presentes / docs.length) * 100;
  }

  _AnaliseInfo _classificarRisco({
    required _IndicadorFaixa? indicador,
    required double percentual,
    required int totalAulas,
    required int sequenciaFaltasAtual,
    required int? diasDesdeUltimaPresenca,
  }) {
    if (indicador?.geraAlerta == true ||
        sequenciaFaltasAtual >= 3 ||
        (diasDesdeUltimaPresenca != null && diasDesdeUltimaPresenca >= 21)) {
      return const _AnaliseInfo(
        titulo: 'Precisa de atenção',
        descricao: 'Existe sinal de afastamento. É bom conversar com a coordenação ou professor responsável.',
        icone: Icons.priority_high_rounded,
        corHex: '#F44336',
      );
    }

    if (totalAulas >= 4 && percentual < 45) {
      return const _AnaliseInfo(
        titulo: 'Acompanhar de perto',
        descricao: 'A frequência está baixa no período. Melhor manter atenção para recuperar o ritmo.',
        icone: Icons.visibility_rounded,
        corHex: '#FF9800',
      );
    }

    return const _AnaliseInfo(
      titulo: 'Sem alerta forte',
      descricao: 'Não existe sinal forte de afastamento neste momento.',
      icone: Icons.check_circle_rounded,
      corHex: '#4CAF50',
    );
  }

  String _montarDiagnostico({
    required _IndicadorFaixa? indicador,
    required _AnaliseInfo perfil,
    required _AnaliseInfo tendencia,
    required _AnaliseInfo risco,
    required int presencas,
    required int totalAulas,
    required double percentual,
    required int sequenciaPresencasAtual,
    required int sequenciaFaltasAtual,
    required int? diasDesdeUltimaPresenca,
  }) {
    final estado = indicador?.label ?? 'Sem indicador atual';
    final ultima = diasDesdeUltimaPresenca == null
        ? 'sem presença registrada'
        : diasDesdeUltimaPresenca == 0
        ? 'com presença hoje'
        : diasDesdeUltimaPresenca == 1
        ? 'com última presença ontem'
        : 'com última presença há $diasDesdeUltimaPresenca dias';

    final buffer = StringBuffer()
      ..write('Situação atual: $estado, $ultima. ');

    if (totalAulas == 0) {
      buffer.write('Neste filtro ainda não existem aulas registradas para montar uma análise completa.');
      return buffer.toString();
    }

    buffer.write(
      'No período selecionado, participou de $presencas de $totalAulas aula(s), '
          'ficando com ${percentual.toStringAsFixed(0)}% de frequência. ',
    );

    buffer.write('Perfil: ${perfil.titulo.toLowerCase()}. ');

    if (sequenciaPresencasAtual > 0) {
      buffer.write('Vem de $sequenciaPresencasAtual presença(s) seguida(s). ');
    } else if (sequenciaFaltasAtual > 0) {
      buffer.write('Vem de $sequenciaFaltasAtual falta(s) seguida(s). ');
    }

    buffer.write('Tendência: ${tendencia.titulo.toLowerCase()}. ');
    buffer.write('Leitura geral: ${risco.titulo.toLowerCase()}.');

    return buffer.toString();
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

    if (semPonto.startsWith('seg') || semPonto.contains('segunda')) return 'seg';
    if (semPonto.startsWith('ter') || semPonto.contains('terca')) return 'ter';
    if (semPonto.startsWith('qua') || semPonto.contains('quarta')) return 'qua';
    if (semPonto.startsWith('qui') || semPonto.contains('quinta')) return 'qui';
    if (semPonto.startsWith('sex') || semPonto.contains('sexta')) return 'sex';
    if (semPonto.startsWith('sab') || semPonto.contains('sabado')) return 'sab';
    if (semPonto.startsWith('dom') || semPonto.contains('domingo')) return 'dom';

    return semPonto.length >= 3 ? semPonto.substring(0, 3) : semPonto;
  }

  String _getTituloPeriodo() {
    final agora = DateTime.now();

    switch (_periodo) {
      case 'Este Mês':
        return DateFormat('MMMM', 'pt_BR').format(agora).toUpperCase();

      case 'Mês Passado':
        final mp = DateTime(agora.year, agora.month - 1, 1);
        return DateFormat('MMMM', 'pt_BR').format(mp).toUpperCase();

      case 'Últimos 3 Meses':
        final m1 = DateTime(agora.year, agora.month - 2, 1);
        return '${DateFormat('MMMM', 'pt_BR').format(m1).toUpperCase()} - ${DateFormat('MMMM', 'pt_BR').format(agora).toUpperCase()}';

      case 'Este Ano':
        return agora.year.toString();

      case 'Ano Passado':
        return (agora.year - 1).toString();

      case 'Todos':
        return 'TODO HISTÓRICO';

      default:
        return _periodo.toUpperCase();
    }
  }

  String _getSubtituloPeriodo() {
    final agora = DateTime.now();

    switch (_periodo) {
      case 'Este Mês':
        return '${agora.day} de ${DateFormat('MMMM', 'pt_BR').format(agora)} de ${agora.year}';

      case 'Mês Passado':
        final mp = DateTime(agora.year, agora.month - 1, 1);
        return '${DateFormat('MMMM', 'pt_BR').format(mp)} de ${mp.year}';

      case 'Últimos 3 Meses':
        final ini = DateTime(agora.year, agora.month - 2, 1);
        return 'De ${DateFormat('MMMM', 'pt_BR').format(ini)} a ${DateFormat('MMMM', 'pt_BR').format(agora)} de ${agora.year}';

      case 'Este Ano':
        return 'Janeiro a Dezembro de ${agora.year}';

      case 'Ano Passado':
        return 'Janeiro a Dezembro de ${agora.year - 1}';

      case 'Todos':
        return 'Todos os registros encontrados';

      default:
        return '';
    }
  }

  String _formatHora(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  String _formatDataCurta(DateTime? date) {
    if (date == null) return 'Nunca';
    return DateFormat('dd/MM/yyyy').format(date);
  }

  Color _colorFromHex(String value, {Color? fallback}) {
    try {
      var cleaned = value.trim().replaceAll('#', '').toUpperCase();
      if (cleaned.length == 6) cleaned = 'FF$cleaned';
      if (cleaned.length != 8) return fallback ?? context.uai.textMuted;
      return Color(int.parse(cleaned, radix: 16));
    } catch (_) {
      return fallback ?? context.uai.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    final resumoAtual = _usaTempoReal ? _resumoRealtime : _resumoBuscaUnica;
    final carregandoAtual =
    _usaTempoReal ? _carregandoRealtime : _carregandoBuscaUnica;
    final erroAtual = _usaTempoReal ? _erroRealtime : _erroBuscaUnica;
    final mensagemErro =
    _usaTempoReal ? _mensagemErroRealtime : _mensagemErroBuscaUnica;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Minha Frequência',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            Text(
              _alunoNome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _appBarFg().withOpacity(0.82),
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: _appBarBg(),
        foregroundColor: _appBarFg(),
        iconTheme: IconThemeData(color: _appBarFg()),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _atualizar,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth > 980 ? 980.0 : constraints.maxWidth;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                children: [
                  _buildFiltros(),
                  Expanded(
                    child: _buildBody(
                      resumo: resumoAtual,
                      carregando: carregandoAtual || _carregandoIndicadores,
                      erro: erroAtual,
                      mensagemErro: mensagemErro,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody({
    required _FrequenciaResumo? resumo,
    required bool carregando,
    required bool erro,
    required String mensagemErro,
  }) {
    final t = context.uai;

    if (carregando) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          margin: const EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: t.primary),
              const SizedBox(height: 14),
              Text(
                _usaTempoReal
                    ? 'Atualizando sua frequência deste mês...'
                    : 'Buscando sua frequência do período...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Só um instante, estamos organizando os dados de forma fácil de entender.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (erro) return _buildErro(mensagemErro);

    if (resumo == null) return _buildErro('Nenhum resumo disponível.');

    return _buildConteudo(resumo);
  }

  Widget _buildErro(String error) {
    final t = context.uai;
    final danger = _ensureVisible(t.error, t.card);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: _cardDecoration(borderColor: danger.withOpacity(0.18)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 76, color: danger),
              const SizedBox(height: 14),
              Text(
                'Não foi possível carregar agora',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _atualizar,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('TENTAR NOVAMENTE'),
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

  Widget _buildFiltros() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.surface);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.border)),
        boxShadow: t.softShadow,
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          primary.withOpacity(0.08),
                          t.cardAlt,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: primary.withOpacity(0.12)),
                      ),
                      child: Icon(Icons.tune_rounded, color: primary, size: 19),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Escolha o período',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _usaTempoReal
                                ? 'Este mês atualiza sozinho quando há nova chamada'
                                : 'Este filtro usa cache para economizar internet e leituras',
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
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
      ),
    );
  }

  Widget _buildModoChip() {
    final t = context.uai;
    final color = _usaTempoReal ? t.success : t.info;
    final visible = _ensureVisible(color, t.surface);
    final text = _usaTempoReal ? 'AO VIVO' : 'CACHE';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(visible.withOpacity(0.10), t.cardAlt),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: visible.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _usaTempoReal ? Icons.bolt_rounded : Icons.memory_rounded,
            color: visible,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: visible,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroDropdownPeriodo() {
    final t = context.uai;

    return DropdownButtonFormField<String>(
      value: _periodo,
      isExpanded: true,
      borderRadius: BorderRadius.circular(t.inputRadius),
      dropdownColor: t.surface,
      style: TextStyle(color: t.textPrimary),
      decoration: _inputDecorationFiltro(
        label: 'Período',
        icon: Icons.calendar_month_rounded,
        color: t.primary,
      ),
      items: _periodos.map((periodo) {
        final selected = _periodo == periodo;

        return DropdownMenuItem<String>(
          value: periodo,
          child: Row(
            children: [
              Icon(
                _iconePeriodo(periodo),
                size: 18,
                color: selected
                    ? _ensureVisible(t.primary, t.surface)
                    : t.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  periodo,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;

        if (value == 'Todos' &&
            !_cache.containsKey('${_alunoId}_Todos_${_tipoAula ?? 'TODAS'}')) {
          _confirmarFiltroTodos(value);
          return;
        }

        _aplicarPeriodo(value);
      },
    );
  }

  Future<void> _confirmarFiltroTodos(String periodo) async {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.surface);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Row(
            children: [
              Icon(Icons.all_inclusive_rounded, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Carregar todo histórico?',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Esse filtro busca todos os registros encontrados para este aluno. '
                'Depois da primeira busca, o resultado fica em cache por ${_cacheValidade.inMinutes} minutos.',
            style: TextStyle(color: t.textSecondary, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'CANCELAR',
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: _readableOn(t.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
              ),
              child: const Text('CARREGAR'),
            ),
          ],
        );
      },
    );

    if (confirmar == true) {
      _aplicarPeriodo(periodo);
    }
  }

  Widget _buildFiltroDropdownTipoAula() {
    final t = context.uai;

    return DropdownButtonFormField<String?>(
      value: _tipoAula,
      isExpanded: true,
      borderRadius: BorderRadius.circular(t.inputRadius),
      dropdownColor: t.surface,
      style: TextStyle(color: t.textPrimary),
      decoration: _inputDecorationFiltro(
        label: 'Tipo de aula',
        icon: Icons.sports_martial_arts_rounded,
        color: t.info,
      ),
      items: _tiposAula.map((tipo) {
        final label = tipo == null ? 'Todas as aulas' : _labelTipoAula(tipo);
        final color = tipo == null ? t.info : _tipoAulaColor(tipo);

        return DropdownMenuItem<String?>(
          value: tipo,
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: _ensureVisible(color, t.surface),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: _aplicarTipoAula,
    );
  }

  InputDecoration _inputDecorationFiltro({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: t.textSecondary),
      prefixIcon: Icon(icon, color: accent, size: 20),
      filled: true,
      fillColor: t.cardAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

  Widget _buildConteudo(_FrequenciaResumo resumo) {
    final t = context.uai;

    if (resumo.totalAulas == 0 && resumo.historico.isEmpty) {
      return RefreshIndicator(
        onRefresh: _atualizar,
        color: t.primary,
        backgroundColor: t.surface,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 60),
            Icon(Icons.history_rounded, size: 90, color: t.textMuted),
            const SizedBox(height: 16),
            Text(
              'Nenhum registro encontrado',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tente escolher outro período ou outro tipo de aula.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: t.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _atualizar,
      color: t.primary,
      backgroundColor: t.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          _buildResumoLeigo(resumo),
          const SizedBox(height: 12),
          _buildExplicacaoCard(resumo),
          const SizedBox(height: 12),
          _buildAnalisesCards(resumo),
          const SizedBox(height: 12),
          _buildMetricasDetalhadas(resumo),
          const SizedBox(height: 12),
          _buildFonteDadosCard(resumo),
          const SizedBox(height: 12),
          _buildPresencasPorDia(resumo),
          const SizedBox(height: 12),
          _buildPresencasPorTipoAula(resumo),
          const SizedBox(height: 14),
          _buildSectionTitle(resumo),
          const SizedBox(height: 8),
          ...resumo.historico.map(_buildHistoricoItem),
        ],
      ),
    );
  }

  Widget _buildResumoLeigo(_FrequenciaResumo resumo) {
    final t = context.uai;
    final onPrimary = _onPrimary();
    final indicador = resumo.indicadorAtual;
    final indicadorColor = indicador == null
        ? onPrimary
        : _ensureVisible(_colorFromHex(indicador.corHex), t.primary);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.cardRadius),
        gradient: t.primaryGradient,
        boxShadow: t.cardShadow,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: onPrimary.withOpacity(0.14)),
            ),
            child: Text(
              _getTituloPeriodo(),
              style: TextStyle(
                color: onPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _getSubtituloPeriodo(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: onPrimary.withOpacity(0.76),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumo fácil',
                      style: TextStyle(
                        color: onPrimary.withOpacity(0.82),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${resumo.percentualPresenca.toStringAsFixed(0)}% de frequência',
                      style: TextStyle(
                        color: onPrimary,
                        fontSize: 27,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${resumo.totalPresencas} presença(s) em ${resumo.totalAulas} aula(s)',
                      style: TextStyle(
                        color: onPrimary.withOpacity(0.82),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 86,
                height: 86,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 86,
                      height: 86,
                      child: CircularProgressIndicator(
                        value: resumo.totalAulas > 0
                            ? (resumo.percentualPresenca / 100).clamp(0.0, 1.0)
                            : 0,
                        strokeWidth: 9,
                        backgroundColor: onPrimary.withOpacity(0.24),
                        valueColor: AlwaysStoppedAnimation<Color>(indicadorColor),
                      ),
                    ),
                    Text(
                      '${resumo.percentualPresenca.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: onPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildIndicadorAtualPill(resumo),
        ],
      ),
    );
  }

  Widget _buildIndicadorAtualPill(_FrequenciaResumo resumo) {
    final t = context.uai;
    final onPrimary = _onPrimary();
    final indicador = resumo.indicadorAtual;
    final color = indicador == null
        ? onPrimary
        : _ensureVisible(_colorFromHex(indicador.corHex), t.primary);
    final label = indicador?.label ?? 'Sem indicador atual';
    final dias = resumo.diasDesdeUltimaPresenca;
    final ultimaTexto = dias == null
        ? 'Sem presença registrada'
        : dias == 0
        ? 'Presença registrada hoje'
        : dias == 1
        ? 'Última presença ontem'
        : 'Última presença há $dias dias';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.13),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: onPrimary.withOpacity(0.30)),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Situação atual: $label',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                if (_mostrarTextoUltimaPresencaIndicador)
                  Text(
                    ultimaTexto,
                    style: TextStyle(
                      color: onPrimary.withOpacity(0.78),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplicacaoCard(_FrequenciaResumo resumo) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(borderColor: accent.withOpacity(0.14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.psychology_alt_rounded, color: accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'O que isso quer dizer?',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  resumo.diagnostico,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12.5,
                    height: 1.34,
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

  Widget _buildAnalisesCards(_FrequenciaResumo resumo) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildAnaliseCard(
                title: 'Constância',
                info: resumo.perfil,
                help: 'Mostra se a presença é regular no período escolhido.',
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _buildAnaliseCard(
                title: 'Tendência',
                info: resumo.tendencia,
                help: 'Compara as aulas recentes com as anteriores.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        _buildAnaliseCard(
          title: 'Acompanhamento',
          info: resumo.risco,
          help: 'Junta presença atual, faltas seguidas e frequência para indicar atenção.',
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _buildAnaliseCard({
    required String title,
    required _AnaliseInfo info,
    required String help,
    bool fullWidth = false,
  }) {
    final t = context.uai;
    final color = _ensureVisible(_colorFromHex(info.corHex), t.card);

    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(13),
      decoration: _cardDecoration(borderColor: color.withOpacity(0.14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(color.withOpacity(0.10), t.cardAlt),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(info.icone, color: color, size: 19),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      info.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            info.descricao,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 11.8,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            help,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10.5,
              height: 1.22,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricasDetalhadas(_FrequenciaResumo resumo) {
    final t = context.uai;

    return _buildWhiteCard(
      icon: Icons.analytics_rounded,
      iconColor: t.associacao,
      title: 'Detalhes do período',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMiniMetric(
                  value: '${resumo.totalPresencas}',
                  label: 'Presenças',
                  icon: Icons.check_circle_rounded,
                  color: t.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniMetric(
                  value: '${resumo.totalFaltas}',
                  label: 'Faltas',
                  icon: Icons.cancel_rounded,
                  color: t.error,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniMetric(
                  value: '${resumo.totalAulas}',
                  label: 'Aulas',
                  icon: Icons.event_note_rounded,
                  color: t.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMiniMetric(
                  value: '${resumo.sequenciaPresencasAtual}',
                  label: 'Presenças seguidas',
                  icon: Icons.local_fire_department_rounded,
                  color: t.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniMetric(
                  value: '${resumo.melhorSequenciaPresencas}',
                  label: 'Melhor sequência',
                  icon: Icons.emoji_events_rounded,
                  color: t.inscricoes,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniMetric(
                  value: '${resumo.maiorSequenciaFaltas}',
                  label: 'Maior sequência de faltas',
                  icon: Icons.warning_amber_rounded,
                  color: t.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: resumo.totalAulas > 0
                  ? (resumo.percentualPresenca / 100).clamp(0.0, 1.0)
                  : 0,
              minHeight: 10,
              backgroundColor: t.border,
              valueColor: AlwaysStoppedAnimation<Color>(
                resumo.percentualPresenca >= 80
                    ? t.success
                    : resumo.percentualPresenca >= 60
                    ? t.warning
                    : t.error,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Essa barra mostra a porcentagem de presença dentro do período escolhido.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 9.5,
              height: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFonteDadosCard(_FrequenciaResumo resumo) {
    final t = context.uai;
    final cacheEntry = _cache[_cacheKey];
    final usandoCache = !_usaTempoReal && cacheEntry != null;
    final color = _usaTempoReal ? t.success : t.info;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.14)),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Icon(
            _usaTempoReal ? Icons.bolt_rounded : Icons.cached_rounded,
            color: accent,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _usaTempoReal
                  ? 'Este mês está em tempo real. Quando uma chamada nova for registrada, esta tela atualiza sozinha.'
                  : usandoCache
                  ? 'Dados carregados em cache às ${_formatHora(cacheEntry.criadoEm)}. Toque em atualizar para buscar de novo.'
                  : 'Dados carregados uma vez para economizar leituras.',
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresencasPorDia(_FrequenciaResumo resumo) {
    final porDia = resumo.presencasPorDia;

    if (porDia.values.every((v) => v == 0)) {
      return const SizedBox.shrink();
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

    return _buildWhiteCard(
      icon: Icons.calendar_month_rounded,
      iconColor: context.uai.primary,
      title: 'Em quais dias mais teve presença',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aqui dá para ver em quais dias da semana existem mais presenças registradas.',
            style: TextStyle(
              color: context.uai.textSecondary,
              fontSize: 11.5,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth < 420
                  ? (constraints.maxWidth - 18) / 4
                  : 46.0;

              return Wrap(
                spacing: 6,
                runSpacing: 7,
                alignment: WrapAlignment.center,
                children: dias.map((dia) {
                  final qtd = porDia[dia[0]] ?? 0;

                  return SizedBox(
                    width: cardWidth,
                    child: _buildDiaCard(dia[1], qtd),
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
    final t = context.uai;
    final ativo = qtd > 0;
    final accent = _ensureVisible(ativo ? t.primary : t.textMuted, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(ativo ? 0.10 : 0.05), t.cardAlt),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ativo ? accent.withOpacity(0.22) : t.border,
        ),
      ),
      child: Column(
        children: [
          Text(
            dia,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$qtd',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresencasPorTipoAula(_FrequenciaResumo resumo) {
    final porTipo = resumo.presencasPorTipoAula;

    if (porTipo.isEmpty) return const SizedBox.shrink();

    final entries = porTipo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _buildWhiteCard(
      icon: Icons.sports_martial_arts_rounded,
      iconColor: context.uai.info,
      title: 'Presenças por tipo de aula',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mostra em quais tipos de aula houve presença. Exemplo: objetiva, roda, instrumentação ou evento.',
            style: TextStyle(
              color: context.uai.textSecondary,
              fontSize: 11.5,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...entries.map((entry) {
            final color = _tipoAulaColor(entry.key);
            final total = resumo.totalPresencas == 0 ? 1 : resumo.totalPresencas;
            final percent = entry.value / total;

            return _buildTipoAulaBar(
              tipo: entry.key,
              quantidade: entry.value,
              percent: percent,
              color: color,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTipoAulaBar({
    required String tipo,
    required int quantidade,
    required double percent,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 102,
            child: Text(
              _labelTipoAula(tipo),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: percent.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: t.border,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$quantidade',
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(_FrequenciaResumo resumo) {
    final t = context.uai;

    return Row(
      children: [
        Icon(Icons.history_rounded, color: _ensureVisible(t.primary, t.background)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Histórico de aulas',
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ),
        Text(
          '${resumo.historico.length}',
          style: TextStyle(
            color: t.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoricoItem(Map<String, dynamic> item) {
    final t = context.uai;
    final presente = item['presente'] == true;
    final tipo = item['tipo_aula']?.toString() ?? 'Outro';
    final color = presente ? t.success : t.error;
    final accent = _ensureVisible(color, t.card);
    final data = item['data'] is DateTime ? item['data'] as DateTime : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: _cardDecoration(borderColor: accent.withOpacity(0.12)),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
          iconColor: accent,
          collapsedIconColor: t.textMuted,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: accent.withOpacity(0.14)),
            ),
            child: Icon(
              presente ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: accent,
              size: 22,
            ),
          ),
          title: Text(
            item['data_formatada']?.toString() ?? '',
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
            ),
          ),
          subtitle: Text(
            '${_labelTipoAula(tipo)} • ${presente ? 'Presente' : 'Falta'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            _buildHistoricoDetail(
              icon: Icons.sports_martial_arts_rounded,
              label: 'Tipo de aula',
              value: _labelTipoAula(tipo),
              color: _tipoAulaColor(tipo),
            ),
            _buildHistoricoDetail(
              icon: Icons.person_rounded,
              label: 'Aula registrada por',
              value: item['registrado_por']?.toString() ?? 'Não informado',
              color: t.info,
            ),
            if ((item['turma_nome']?.toString() ?? '').isNotEmpty)
              _buildHistoricoDetail(
                icon: Icons.groups_rounded,
                label: 'Turma',
                value: item['turma_nome'].toString(),
                color: t.associacao,
              ),
            if (data != null)
              _buildHistoricoDetail(
                icon: Icons.access_time_rounded,
                label: 'Data do registro',
                value: DateFormat('dd/MM/yyyy HH:mm').format(data),
                color: t.warning,
              ),
            if ((item['observacao']?.toString() ?? '').trim().isNotEmpty)
              _buildHistoricoDetail(
                icon: Icons.notes_rounded,
                label: 'Observação',
                value: item['observacao'].toString(),
                color: t.textSecondary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoricoDetail({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 8),
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhiteCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(iconColor, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: _cardDecoration(borderColor: accent.withOpacity(0.13)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Color _tipoAulaColor(String tipo) {
    final t = context.uai;

    switch (tipo.toUpperCase()) {
      case 'OBJETIVA':
        return t.info;
      case 'RODA':
        return t.primary;
      case 'INSTRUMENTAÇÃO':
      case 'INSTRUMENTACAO':
        return t.warning;
      case 'ESPECIAL':
        return t.associacao;
      case 'EVENTO':
        return t.eventos;
      case 'BATIZADO':
        return t.inscricoes;
      default:
        return t.textMuted;
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

class _CacheFrequenciaEntry {
  final _FrequenciaResumo resumo;
  final DateTime criadoEm;

  const _CacheFrequenciaEntry({
    required this.resumo,
    required this.criadoEm,
  });

  bool get estaValido {
    return DateTime.now().difference(criadoEm) <
        _AreaAlunoFrequenciaScreenState._cacheValidade;
  }
}

class _IndicadorFaixa {
  final int ateDias;
  final String corHex;
  final String label;
  final bool geraAlerta;
  final String mensagemAlerta;

  const _IndicadorFaixa({
    required this.ateDias,
    required this.corHex,
    required this.label,
    required this.geraAlerta,
    required this.mensagemAlerta,
  });

  factory _IndicadorFaixa.fromMap(Map<String, dynamic> map) {
    return _IndicadorFaixa(
      ateDias: _parseInt(map['ate_dias'], fallback: 9999),
      corHex: map['cor']?.toString() ?? '#9E9E9E',
      label: map['label']?.toString().trim().isNotEmpty == true
          ? map['label'].toString().trim()
          : 'Indicador',
      geraAlerta: map['gera_alerta'] == true,
      mensagemAlerta: map['mensagem_alerta']?.toString() ?? '',
    );
  }

  static int _parseInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '') ?? fallback;
  }
}

class _AnaliseInfo {
  final String titulo;
  final String descricao;
  final IconData icone;
  final String corHex;

  const _AnaliseInfo({
    required this.titulo,
    required this.descricao,
    required this.icone,
    required this.corHex,
  });
}

class _FrequenciaResumo {
  final int totalPresencas;
  final int totalFaltas;
  final int totalAulas;
  final double percentualPresenca;
  final int sequenciaPresencasAtual;
  final int sequenciaFaltasAtual;
  final int melhorSequenciaPresencas;
  final int maiorSequenciaFaltas;
  final DateTime? ultimaPresenca;
  final int? diasDesdeUltimaPresenca;
  final _IndicadorFaixa? indicadorAtual;
  final _AnaliseInfo perfil;
  final _AnaliseInfo tendencia;
  final _AnaliseInfo risco;
  final String diagnostico;
  final Map<String, int> presencasPorDia;
  final Map<String, int> presencasPorTipoAula;
  final List<Map<String, dynamic>> historico;
  final DateTime carregadoEm;
  final String origem;

  const _FrequenciaResumo({
    required this.totalPresencas,
    required this.totalFaltas,
    required this.totalAulas,
    required this.percentualPresenca,
    required this.sequenciaPresencasAtual,
    required this.sequenciaFaltasAtual,
    required this.melhorSequenciaPresencas,
    required this.maiorSequenciaFaltas,
    required this.ultimaPresenca,
    required this.diasDesdeUltimaPresenca,
    required this.indicadorAtual,
    required this.perfil,
    required this.tendencia,
    required this.risco,
    required this.diagnostico,
    required this.presencasPorDia,
    required this.presencasPorTipoAula,
    required this.historico,
    required this.carregadoEm,
    required this.origem,
  });
}
