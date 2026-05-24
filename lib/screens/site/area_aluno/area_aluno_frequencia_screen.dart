import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  final Map<String, _CacheFrequenciaEntry> _cache = {};

  static const Duration _cacheValidade = Duration(minutes: 20);
  static const int _maxDocsSemConfirmar = 600;

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

  String get _alunoId => widget.aluno['aluno_id']?.toString() ?? '';
  String get _alunoNome => widget.aluno['nome']?.toString() ?? 'Aluno';

  bool get _usaTempoReal {
    return _periodo == 'Este Mês';
  }

  String get _cacheKey {
    return '${_alunoId}_${_periodo}_${_tipoAula ?? 'TODAS'}';
  }

  @override
  void initState() {
    super.initState();
    _carregarAtual();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _carregarAtual({bool forcar = false}) async {
    await _realtimeSub?.cancel();
    _realtimeSub = null;

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
      final query = _buildLogsQuery();

      final snapshot = await query.get(const GetOptions(source: Source.server));

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
    final key = _cacheKey;
    _cache.remove(key);

    await _carregarAtual(forcar: true);
  }

  void _aplicarPeriodo(String periodo) {
    if (_periodo == periodo) return;

    setState(() {
      _periodo = periodo;
    });

    _carregarAtual();
  }

  void _aplicarTipoAula(String? tipo) {
    if (_tipoAula == tipo) return;

    setState(() {
      _tipoAula = tipo;
    });

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
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
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
    int sequencia = 0;
    bool sequenciaAtiva = true;
    String ultimaPresenca = '';

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

        if (ultimaPresenca.isEmpty) {
          ultimaPresenca = dataFormatada;
        }

        if (sequenciaAtiva) {
          sequencia++;
        }

        if (porDia.containsKey(dia)) {
          porDia[dia] = (porDia[dia] ?? 0) + 1;
        }

        porTipo[tipo] = (porTipo[tipo] ?? 0) + 1;
      } else {
        faltas++;
        sequenciaAtiva = false;
      }

      historico.add({
        'id': doc.id,
        'data': dataAula,
        'data_formatada': dataFormatada,
        'presente': presente,
        'tipo_aula': tipo,
        'professor_nome': data['professor_nome']?.toString() ??
            data['professor']?.toString() ??
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

    return _FrequenciaResumo(
      totalPresencas: presencas,
      totalFaltas: faltas,
      totalAulas: totalAulas,
      percentualPresenca: percentual,
      sequenciaAtual: sequencia,
      ultimaPresenca: ultimaPresenca,
      presencasPorDia: porDia,
      presencasPorTipoAula: porTipo,
      historico: historico,
      carregadoEm: DateTime.now(),
      origem: _usaTempoReal ? 'Tempo real' : 'Busca única com cache',
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
        return 'Todos os registros encontrados nos logs';

      default:
        return '';
    }
  }

  String _formatHora(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final resumoAtual = _usaTempoReal ? _resumoRealtime : _resumoBuscaUnica;
    final carregandoAtual =
    _usaTempoReal ? _carregandoRealtime : _carregandoBuscaUnica;
    final erroAtual = _usaTempoReal ? _erroRealtime : _erroBuscaUnica;
    final mensagemErro =
    _usaTempoReal ? _mensagemErroRealtime : _mensagemErroBuscaUnica;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Minha Frequência',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              _alunoNome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
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
          final maxWidth =
          constraints.maxWidth > 980 ? 980.0 : constraints.maxWidth;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                children: [
                  _buildFiltros(),
                  Expanded(
                    child: _buildBody(
                      resumo: resumoAtual,
                      carregando: carregandoAtual,
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
    if (carregando) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.red.shade900),
            const SizedBox(height: 14),
            Text(
              _usaTempoReal
                  ? 'Escutando logs deste mês...'
                  : 'Buscando logs do período...',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      );
    }

    if (erro) {
      return _buildErro(mensagemErro);
    }

    if (resumo == null) {
      return _buildErro('Nenhum resumo disponível.');
    }

    return _buildConteudo(resumo);
  }

  Widget _buildErro(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 76, color: Colors.red.shade300),
            const SizedBox(height: 14),
            const Text(
              'Ops! Algo deu errado',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _atualizar,
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

  Widget _buildFiltros() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        color: Colors.red.shade900,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Filtros da frequência',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _usaTempoReal
                                ? 'Este mês em tempo real'
                                : 'Busca única com cache inteligente',
                            style: TextStyle(
                              color: Colors.grey.shade600,
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
      ),
    );
  }

  Widget _buildModoChip() {
    final color = _usaTempoReal ? Colors.green : Colors.blueGrey;
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
            _usaTempoReal ? Icons.bolt_rounded : Icons.memory_rounded,
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
      value: _periodo,
      isExpanded: true,
      borderRadius: BorderRadius.circular(16),
      dropdownColor: Colors.white,
      decoration: _inputDecorationFiltro(
        label: 'Período',
        icon: Icons.calendar_month_rounded,
        color: Colors.red.shade900,
      ),
      items: _periodos.map((periodo) {
        return DropdownMenuItem<String>(
          value: periodo,
          child: Row(
            children: [
              Icon(
                _iconePeriodo(periodo),
                size: 18,
                color: _periodo == periodo
                    ? Colors.red.shade900
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  periodo,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;

        if (value == 'Todos' && !_cache.containsKey('${_alunoId}_Todos_${_tipoAula ?? 'TODAS'}')) {
          _confirmarFiltroTodos(value);
          return;
        }

        _aplicarPeriodo(value);
      },
    );
  }

  Future<void> _confirmarFiltroTodos(String periodo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.all_inclusive_rounded, color: Colors.red.shade900),
              const SizedBox(width: 8),
              const Expanded(child: Text('Carregar todo histórico?')),
            ],
          ),
          content: Text(
            'Esse filtro busca todos os logs encontrados para este aluno. '
                'Normalmente é tranquilo, mas pode consumir mais leituras se o aluno tiver muitos registros. '
                'Depois da primeira busca, o resultado fica em cache por ${_cacheValidade.inMinutes} minutos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
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
    return DropdownButtonFormField<String?>(
      value: _tipoAula,
      isExpanded: true,
      borderRadius: BorderRadius.circular(16),
      dropdownColor: Colors.white,
      decoration: _inputDecorationFiltro(
        label: 'Tipo de aula',
        icon: Icons.sports_martial_arts_rounded,
        color: Colors.blue.shade700,
      ),
      items: _tiposAula.map((tipo) {
        final label = tipo == null ? 'Todas as aulas' : _labelTipoAula(tipo);
        final color = tipo == null ? Colors.blue.shade700 : _tipoAulaColor(tipo);

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
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        _aplicarTipoAula(value);
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
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Colors.grey.shade300),
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

  Widget _buildConteudo(_FrequenciaResumo resumo) {
    if (resumo.totalAulas == 0 && resumo.historico.isEmpty) {
      return RefreshIndicator(
        onRefresh: _atualizar,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 60),
            Icon(Icons.history_rounded, size: 90, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'Nenhum registro encontrado',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Tente alterar o filtro ou confira se existem logs para este aluno.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _atualizar,
      color: Colors.red.shade900,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          _buildHeaderEstatistico(resumo),
          const SizedBox(height: 10),
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

  Widget _buildFonteDadosCard(_FrequenciaResumo resumo) {
    final cacheEntry = _cache[_cacheKey];
    final usandoCache = !_usaTempoReal && cacheEntry != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _usaTempoReal ? Colors.green.shade50 : Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _usaTempoReal ? Colors.green.shade100 : Colors.blueGrey.shade100,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _usaTempoReal ? Icons.bolt_rounded : Icons.cached_rounded,
            color: _usaTempoReal ? Colors.green.shade800 : Colors.blueGrey.shade700,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _usaTempoReal
                  ? 'Este mês está em tempo real. Novos logs aparecem automaticamente.'
                  : usandoCache
                  ? 'Filtro carregado em cache às ${_formatHora(cacheEntry.criadoEm)}. Toque em atualizar para buscar de novo.'
                  : 'Filtro carregado por busca única.',
              style: TextStyle(
                color: _usaTempoReal ? Colors.green.shade900 : Colors.blueGrey.shade800,
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

  Widget _buildHeaderEstatistico(_FrequenciaResumo resumo) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              _getTituloPeriodo(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _getSubtituloPeriodo(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.76),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 430;

              final children = [
                _buildMetrica(
                  '${resumo.totalPresencas}',
                  'Presenças',
                  Icons.check_circle_rounded,
                  Colors.green.shade300,
                ),
                _buildMetrica(
                  '${resumo.totalFaltas}',
                  'Faltas',
                  Icons.cancel_rounded,
                  Colors.red.shade200,
                ),
                _buildMetrica(
                  '${resumo.percentualPresenca.toStringAsFixed(0)}%',
                  'Frequência',
                  Icons.pie_chart_rounded,
                  Colors.amber.shade300,
                ),
              ];

              if (narrow) {
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: children,
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: children,
              );
            },
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: resumo.totalAulas > 0 ? resumo.percentualPresenca / 100 : 0,
              minHeight: 10,
              backgroundColor: Colors.white.withOpacity(0.25),
              valueColor: AlwaysStoppedAnimation<Color>(
                resumo.percentualPresenca >= 80
                    ? Colors.green.shade400
                    : resumo.percentualPresenca >= 60
                    ? Colors.amber.shade400
                    : Colors.red.shade300,
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 430;

              final widgets = [
                _buildInfoRow(
                  Icons.local_fire_department_rounded,
                  'Sequência',
                  '${resumo.sequenciaAtual} presença(s)',
                  Colors.orange.shade300,
                ),
                _buildInfoRow(
                  Icons.event_available_rounded,
                  'Última presença',
                  resumo.ultimaPresenca.isEmpty ? 'Nunca' : resumo.ultimaPresenca,
                  Colors.green.shade300,
                ),
              ];

              if (narrow) {
                return Column(
                  children: [
                    widgets[0],
                    const SizedBox(height: 10),
                    widgets[1],
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: widgets,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetrica(String valor, String label, IconData icon, Color color) {
    return SizedBox(
      width: 94,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 25),
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.80),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.70),
                fontSize: 10,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
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
      iconColor: Colors.red.shade900,
      title: 'Presenças por dia',
      child: LayoutBuilder(
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
    );
  }

  Widget _buildDiaCard(String dia, int qtd) {
    final ativo = qtd > 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: ativo ? Colors.red.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ativo ? Colors.red.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        children: [
          Text(
            dia,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: ativo ? Colors.red.shade900 : Colors.grey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$qtd',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: ativo ? Colors.red.shade900 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresencasPorTipoAula(_FrequenciaResumo resumo) {
    final porTipo = resumo.presencasPorTipoAula;

    if (porTipo.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildWhiteCard(
      icon: Icons.school_rounded,
      iconColor: Colors.blue.shade700,
      title: 'Presenças por tipo de aula',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: porTipo.entries.map((entry) {
          final label = entry.key.toString();
          final qtd = entry.value;
          final color = _tipoAulaColor(label);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: color.withOpacity(0.24)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  _labelTipoAula(label),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '$qtd',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWhiteCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }

  Widget _buildSectionTitle(_FrequenciaResumo resumo) {
    return Row(
      children: [
        Icon(Icons.history_rounded, color: Colors.red.shade900),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Histórico de aulas (${resumo.historico.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoricoItem(Map<String, dynamic> item) {
    final presente = item['presente'] == true;
    final tipo = item['tipo_aula']?.toString() ?? 'Aula';
    final professor = item['professor_nome']?.toString() ?? 'Não informado';
    final dataAula = item['data'] as DateTime? ?? DateTime.now();
    final dataFormatada = DateFormat('dd/MM/yyyy').format(dataAula);
    final observacao = item['observacao']?.toString() ?? '';
    final diasEntre = item['dias_entre'] as int? ?? 0;
    final color = _tipoAulaColor(tipo);

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: presente ? 2 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _mostrarDetalhesAula(item),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: presente
                    ? Colors.green.withOpacity(0.16)
                    : Colors.red.withOpacity(0.12),
              ),
            ),
            child: Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: presente ? Colors.green.shade600 : Colors.red.shade400,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (presente ? Colors.green : Colors.red)
                                .withOpacity(0.26),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    if (diasEntre > 0)
                      Container(
                        width: 2,
                        height: 20,
                        color: Colors.grey.shade300,
                      ),
                  ],
                ),
                const SizedBox(width: 12),
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
                          _buildStatusBadge(presente),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 7,
                        runSpacing: 5,
                        children: [
                          _buildTag(_labelTipoAula(tipo), color),
                          if (diasEntre > 0)
                            _buildTag(
                              '$diasEntre ${diasEntre == 1 ? 'dia' : 'dias'}',
                              Colors.orange,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.assignment_ind_rounded,
                            size: 14,
                            color: Colors.purple.shade600,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Aula registrada por: $professor',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (observacao.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.notes_rounded, size: 14, color: Colors.amber.shade700),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                observacao,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool presente) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: presente ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        presente ? 'PRESENTE' : 'AUSENTE',
        style: TextStyle(
          color: presente ? Colors.green.shade700 : Colors.red.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  void _mostrarDetalhesAula(Map<String, dynamic> item) {
    final presente = item['presente'] == true;
    final tipo = item['tipo_aula']?.toString() ?? 'Aula';
    final professor = item['professor_nome']?.toString() ?? 'Não informado';
    final dataAula = item['data'] as DateTime? ?? DateTime.now();
    final dataFormatada = DateFormat('dd/MM/yyyy').format(dataAula);
    final observacao = item['observacao']?.toString() ?? '';
    final turma = item['turma_nome']?.toString() ??
        widget.aluno['turma']?.toString() ??
        '';

    showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          titlePadding: EdgeInsets.zero,
          title: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: presente
                    ? [Colors.green.shade700, Colors.green.shade500]
                    : [Colors.red.shade700, Colors.red.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              children: [
                Icon(
                  presente ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: Colors.white,
                  size: 44,
                ),
                const SizedBox(height: 8),
                Text(
                  presente ? 'Presença registrada' : 'Ausência registrada',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  dataFormatada,
                  style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 12),
                ),
              ],
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetalheLinha(
                Icons.school_rounded,
                'Tipo de aula',
                _labelTipoAula(tipo),
                _tipoAulaColor(tipo),
              ),
              _buildDetalheLinha(
                Icons.assignment_ind_rounded,
                'Aula registrada por',
                professor,
                Colors.purple,
              ),
              if (turma.isNotEmpty)
                _buildDetalheLinha(Icons.groups_rounded, 'Turma', turma, Colors.blue),
              if (observacao.isNotEmpty)
                _buildDetalheLinha(
                  Icons.notes_rounded,
                  'Observação',
                  observacao,
                  Colors.amber.shade800,
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('FECHAR'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetalheLinha(
      IconData icon,
      String label,
      String value,
      Color color,
      ) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _tipoAulaColor(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'OBJETIVA':
        return Colors.blue;
      case 'RODA':
        return Colors.red;
      case 'INSTRUMENTAÇÃO':
      case 'INSTRUMENTACAO':
        return Colors.amber.shade700;
      case 'ESPECIAL':
        return Colors.purple;
      case 'EVENTO':
        return Colors.orange;
      case 'BATIZADO':
        return Colors.deepOrange;
      default:
        return Colors.grey;
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
}

class _CacheFrequenciaEntry {
  final _FrequenciaResumo resumo;
  final DateTime criadoEm;

  const _CacheFrequenciaEntry({
    required this.resumo,
    required this.criadoEm,
  });

  bool get estaValido {
    return DateTime.now().difference(criadoEm) < const Duration(minutes: 20);
  }
}

class _FrequenciaResumo {
  final int totalPresencas;
  final int totalFaltas;
  final int totalAulas;
  final double percentualPresenca;
  final int sequenciaAtual;
  final String ultimaPresenca;
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
    required this.sequenciaAtual,
    required this.ultimaPresenca,
    required this.presencasPorDia,
    required this.presencasPorTipoAula,
    required this.historico,
    required this.carregadoEm,
    required this.origem,
  });
}
