// widgets/card_frequencia_moderno.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CardFrequenciaModerno extends StatefulWidget {
  final String alunoId;
  final String? filtroTemporal;
  final String? anoSelecionado;

  const CardFrequenciaModerno({
    super.key,
    required this.alunoId,
    this.filtroTemporal,
    this.anoSelecionado,
  });

  @override
  State<CardFrequenciaModerno> createState() => _CardFrequenciaModernoState();
}

class _CardFrequenciaModernoState extends State<CardFrequenciaModerno> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _dadosAluno;
  Map<String, dynamic>? _contador;
  List<Map<String, dynamic>> _logsRecentes = [];

  bool _isLoading = true;
  bool _expanded = false;
  String? _erro;

  int _totalPresencas = 0;
  int _totalAusencias = 0;
  int _valorFiltroAtual = 0;
  int _diasSemTreinar = 0;

  late Map<String, int> _presencasPorDia;
  Timestamp? _ultimaPresenca;

  @override
  void initState() {
    super.initState();
    _resetContadores();
    _carregarDados();
  }

  @override
  void didUpdateWidget(covariant CardFrequenciaModerno oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.alunoId != widget.alunoId ||
        oldWidget.filtroTemporal != widget.filtroTemporal ||
        oldWidget.anoSelecionado != widget.anoSelecionado) {
      _carregarDados();
    }
  }

  void _resetContadores() {
    _presencasPorDia = {
      'seg': 0,
      'ter': 0,
      'qua': 0,
      'qui': 0,
      'sex': 0,
      'sab': 0,
      'dom': 0,
    };

    _totalPresencas = 0;
    _totalAusencias = 0;
    _valorFiltroAtual = 0;
    _diasSemTreinar = 0;
    _ultimaPresenca = null;
    _logsRecentes = [];
    _erro = null;
  }

  Future<void> _carregarDados() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _resetContadores();
    });

    try {
      final alunoFuture = _firestore
          .collection('alunos')
          .doc(widget.alunoId)
          .get(const GetOptions(source: Source.server));

      final contadorFuture = _firestore
          .collection('alunos')
          .doc(widget.alunoId)
          .collection('contadores')
          .doc('frequencia_dashboard')
          .get(const GetOptions(source: Source.server));

      final results = await Future.wait([alunoFuture, contadorFuture]);

      final alunoDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final contadorDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;

      if (!alunoDoc.exists) {
        if (!mounted) return;
        setState(() {
          _erro = 'Aluno não encontrado';
          _isLoading = false;
        });
        return;
      }

      _dadosAluno = alunoDoc.data();
      _contador = contadorDoc.exists ? contadorDoc.data() : null;

      _aplicarContador();

      // Mantém somente os últimos logs para exibição expandida.
      // Não usa esses logs para o total principal, evitando leituras pesadas.
      await _carregarLogsRecentes();

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('❌ Erro em CardFrequenciaModerno._carregarDados: $e');

      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar frequência';
        _isLoading = false;
      });
    }
  }

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, int> _parseMapStringInt(dynamic value) {
    final result = <String, int>{};

    if (value is Map) {
      value.forEach((key, val) {
        if (key != null) {
          result[key.toString()] = _parseInt(val);
        }
      });
    }

    return result;
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Timestamp? _toTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value;
    if (value is DateTime) return Timestamp.fromDate(value);
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return Timestamp.fromDate(parsed);
    }
    return null;
  }

  String _mesKey(DateTime data) {
    final mes = data.month.toString().padLeft(2, '0');
    return '${data.year}-$mes';
  }

  String _semanaKeyIso(DateTime data) {
    // Mesmo formato usado no index.js com Luxon: 2026-W20.
    final quinta = data.add(Duration(days: 4 - data.weekday));
    final inicioAno = DateTime(quinta.year, 1, 1);
    final semana = ((quinta.difference(inicioAno).inDays + inicioAno.weekday + 6) / 7).floor();

    return '${quinta.year}-W${semana.toString().padLeft(2, '0')}';
  }

  String _normalizarDiaSemana(dynamic dia) {
    final valor = dia
        ?.toString()
        .toLowerCase()
        .replaceAll('.', '')
        .trim() ??
        '';

    switch (valor) {
      case 'segunda':
      case 'seg':
      case 'mon':
        return 'seg';
      case 'terça':
      case 'terca':
      case 'ter':
      case 'tue':
        return 'ter';
      case 'quarta':
      case 'qua':
      case 'wed':
        return 'qua';
      case 'quinta':
      case 'qui':
      case 'thu':
        return 'qui';
      case 'sexta':
      case 'sex':
      case 'fri':
        return 'sex';
      case 'sábado':
      case 'sabado':
      case 'sab':
      case 'sat':
        return 'sab';
      case 'domingo':
      case 'dom':
      case 'sun':
        return 'dom';
      default:
        return valor.length >= 3 ? valor.substring(0, 3) : valor;
    }
  }

  void _aplicarContador() {
    final contador = _contador ?? {};
    final now = DateTime.now();

    final porAno = _parseMapStringInt(contador['porAno']);
    final porMes = _parseMapStringInt(contador['porMes']);
    final porSemana = _parseMapStringInt(contador['porSemana']);
    final porDiaSemana = _parseMapStringInt(contador['porDiaSemana']);

    final mesAtual = _mesKey(now);
    final semanaAtual = _semanaKeyIso(now);

    _totalPresencas = _parseInt(contador['total']);

    // Compatível com versões novas e antigas.
    _totalAusencias = _parseInt(
      contador['total_ausencias'] ??
          contador['ausencias'] ??
          contador['faltas'] ??
          contador['total_faltas'],
    );

    _ultimaPresenca = _toTimestamp(
      contador['ultima_presenca'] ??
          _dadosAluno?['ultima_presenca'] ??
          _dadosAluno?['ultimo_dia_presente'],
    );

    final ultimaPresencaDate = _ultimaPresenca?.toDate();
    if (ultimaPresencaDate != null) {
      _diasSemTreinar = DateTime.now()
          .difference(DateTime(
        ultimaPresencaDate.year,
        ultimaPresencaDate.month,
        ultimaPresencaDate.day,
      ))
          .inDays;
    } else {
      _diasSemTreinar = 0;
    }

    // Dias da semana vindos do contador novo.
    _presencasPorDia = {
      'seg': porDiaSemana['seg'] ?? _parseInt(contador['seg']),
      'ter': porDiaSemana['ter'] ?? _parseInt(contador['ter']),
      'qua': porDiaSemana['qua'] ?? _parseInt(contador['qua']),
      'qui': porDiaSemana['qui'] ?? _parseInt(contador['qui']),
      'sex': porDiaSemana['sex'] ?? _parseInt(contador['sex']),
      'sab': porDiaSemana['sab'] ?? _parseInt(contador['sab']),
      'dom': porDiaSemana['dom'] ?? _parseInt(contador['dom']),
    };

    switch (widget.filtroTemporal) {
      case 'Semana':
        _valorFiltroAtual = porSemana[semanaAtual] ?? _parseInt(contador['semana']);
        break;
      case 'Mês':
        _valorFiltroAtual = porMes[mesAtual] ?? _parseInt(contador['mes']);
        break;
      case 'Ano':
        final ano = widget.anoSelecionado ?? now.year.toString();
        _valorFiltroAtual = porAno[ano] ?? 0;
        break;
      case 'Total':
      case null:
      default:
        _valorFiltroAtual = _totalPresencas;
        break;
    }
  }

  Future<void> _carregarLogsRecentes() async {
    try {
      final snapshot = await _firestore
          .collection('log_presenca_alunos')
          .where('aluno_id', isEqualTo: widget.alunoId)
          .orderBy('data_aula', descending: true)
          .limit(10)
          .get(const GetOptions(source: Source.server));

      _logsRecentes = snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data(),
        };
      }).toList();

      // Se ainda não tiver porDiaSemana no contador, usa os logs recentes como fallback visual parcial.
      final temDiaSemana = _presencasPorDia.values.any((v) => v > 0);
      if (!temDiaSemana) {
        for (final log in _logsRecentes) {
          final presente = log['presente'] == true;
          if (!presente) continue;

          final dia = _normalizarDiaSemana(log['dia_semana_abrev']);
          if (_presencasPorDia.containsKey(dia)) {
            _presencasPorDia[dia] = _presencasPorDia[dia]! + 1;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar logs recentes: $e');
      _logsRecentes = [];
    }
  }

  String _formatarData(Timestamp? timestamp) {
    if (timestamp == null) return 'Nunca';

    final data = timestamp.toDate();
    final hoje = DateTime.now();
    final hojeLimpo = DateTime(hoje.year, hoje.month, hoje.day);
    final dataLimpa = DateTime(data.year, data.month, data.day);

    if (dataLimpa == hojeLimpo) {
      return 'Hoje';
    }

    if (dataLimpa == hojeLimpo.subtract(const Duration(days: 1))) {
      return 'Ontem';
    }

    return DateFormat('dd/MM/yyyy').format(data);
  }

  String _getTituloFiltro() {
    if (widget.filtroTemporal == null) return 'Total geral';

    if (widget.filtroTemporal == 'Ano' && widget.anoSelecionado != null) {
      return 'Ano ${widget.anoSelecionado}';
    }

    return widget.filtroTemporal!;
  }

  String _getSubtituloFiltro() {
    final now = DateTime.now();

    switch (widget.filtroTemporal) {
      case 'Semana':
        final inicio = now.subtract(Duration(days: now.weekday - 1));
        return 'Semana atual desde ${DateFormat('dd/MM').format(inicio)}';
      case 'Mês':
        return 'Mês atual: ${DateFormat('MM/yyyy').format(now)}';
      case 'Ano':
        return widget.anoSelecionado ?? now.year.toString();
      case 'Total':
      case null:
        return 'Todo histórico do aluno';
      default:
        return '';
    }
  }

  Color _getCorStatus() {
    if (_ultimaPresenca == null) return Colors.grey;
    if (_diasSemTreinar <= 7) return Colors.green.shade700;
    if (_diasSemTreinar <= 15) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  String _getNivelTexto() {
    if (_ultimaPresenca == null) return 'Sem presença registrada';
    if (_diasSemTreinar <= 7) return 'Em dia';
    if (_diasSemTreinar <= 15) return 'Atenção';
    return 'Muito tempo sem presença';
  }

  String _getStatusTexto() {
    if (_ultimaPresenca == null) return 'Nenhuma presença encontrada';
    if (_diasSemTreinar == 0) return 'Treinou hoje';
    if (_diasSemTreinar == 1) return 'Treinou ontem';
    return 'Há $_diasSemTreinar dias sem presença';
  }

  Widget _buildAlunoAvatar() {
    final fotoUrl = _dadosAluno?['foto_perfil_aluno'] as String?;
    final nome = _dadosAluno?['nome']?.toString() ?? '?';
    final inicial = nome.isNotEmpty ? nome.substring(0, 1).toUpperCase() : '?';

    return CircleAvatar(
      radius: 40,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty
          ? NetworkImage(fotoUrl)
          : null,
      child: fotoUrl == null || fotoUrl.isEmpty
          ? Text(
        inicial,
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      )
          : null,
    );
  }

  Widget _buildMetricCard({
    required String value,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiaCardCompacto(String dia, int quantidade) {
    return Container(
      width: 40,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: quantidade > 0 ? Colors.red.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: quantidade > 0 ? Colors.red.shade200 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            dia,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: quantidade > 0 ? Colors.red.shade900 : Colors.grey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            quantidade.toString(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: quantidade > 0 ? Colors.red.shade900 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErro() {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 42),
            const SizedBox(height: 10),
            Text(
              _erro ?? 'Erro ao carregar dados',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _carregarDados,
              icon: const Icon(Icons.refresh_rounded, size: 18),
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
  }

  Widget _buildSkeleton() {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(18),
      child: Center(
        child: CircularProgressIndicator(color: Colors.red.shade900),
      ),
    );
  }

  Widget _buildLogsRecentes() {
    if (_logsRecentes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.history_rounded, color: Colors.grey.shade500, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Nenhum log recente encontrado.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.28,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _logsRecentes.length,
        itemBuilder: (context, index) {
          final log = _logsRecentes[index];
          final presente = log['presente'] == true;
          final data = _toTimestamp(log['data_aula']);
          final tipo = log['tipo_aula']?.toString() ?? 'Aula';
          final professor = log['professor_nome']?.toString() ?? '';

          return Container(
            margin: const EdgeInsets.only(bottom: 7),
            decoration: BoxDecoration(
              color: presente ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: presente ? Colors.green.shade100 : Colors.red.shade100,
              ),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(
                presente ? Icons.check_circle : Icons.cancel,
                color: presente ? Colors.green.shade700 : Colors.red.shade700,
                size: 20,
              ),
              title: Text(
                _formatarData(data),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: professor.isNotEmpty
                  ? Text(
                'Prof. $professor',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
                  : null,
              trailing: Text(
                tipo,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton();
    if (_erro != null || _dadosAluno == null) return _buildErro();

    final corStatus = _getCorStatus();
    final nome = _dadosAluno!['nome']?.toString() ?? 'Aluno';

    final cardContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                corStatus.withOpacity(0.18),
                Colors.white,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
            ),
          ),
          child: Row(
            children: [
              _buildAlunoAvatar(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: corStatus.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: corStatus.withOpacity(0.25)),
                          ),
                          child: Text(
                            _getNivelTexto(),
                            style: TextStyle(
                              color: corStatus,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.blue.shade100),
                          ),
                          child: Text(
                            _getTituloFiltro(),
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _getSubtituloFiltro(),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  _buildMetricCard(
                    value: '$_valorFiltroAtual',
                    label: 'No filtro',
                    color: Colors.blue.shade700,
                    icon: Icons.filter_alt_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildMetricCard(
                    value: '$_totalPresencas',
                    label: 'Total',
                    color: Colors.green.shade700,
                    icon: Icons.event_available_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildMetricCard(
                    value: '$_totalAusencias',
                    label: 'Faltas',
                    color: Colors.red.shade700,
                    icon: Icons.event_busy_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: corStatus.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.calendar_today_rounded,
                        color: corStatus,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Última presença',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatarData(_ultimaPresenca),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _getStatusTexto(),
                            style: TextStyle(
                              fontSize: 11,
                              color: corStatus,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: corStatus.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _ultimaPresenca == null ? '-' : '${_diasSemTreinar}d',
                        style: TextStyle(
                          color: corStatus,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.calendar_month_rounded, color: Colors.red.shade900, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Presenças por dia da semana',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildDiaCardCompacto('Seg', _presencasPorDia['seg'] ?? 0),
                  _buildDiaCardCompacto('Ter', _presencasPorDia['ter'] ?? 0),
                  _buildDiaCardCompacto('Qua', _presencasPorDia['qua'] ?? 0),
                  _buildDiaCardCompacto('Qui', _presencasPorDia['qui'] ?? 0),
                  _buildDiaCardCompacto('Sex', _presencasPorDia['sex'] ?? 0),
                  _buildDiaCardCompacto('Sáb', _presencasPorDia['sab'] ?? 0),
                  _buildDiaCardCompacto('Dom', _presencasPorDia['dom'] ?? 0),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Icon(Icons.history_rounded, color: Colors.grey.shade700, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Últimos registros',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildLogsRecentes(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('FECHAR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              IconButton(
                onPressed: () {
                  setState(() {
                    _expanded = !_expanded;
                  });
                },
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.red.shade900,
                ),
                splashRadius: 20,
                tooltip: _expanded ? 'Recolher' : 'Ver registros recentes',
              ),
            ],
          ),
        ),
      ],
    );

    return GestureDetector(
      onTap: () {
        setState(() {
          _expanded = !_expanded;
        });
      },
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 13,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: cardContent,
          ),
        ),
      ),
    );
  }
}
