import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/frequencia_service.dart';
import '../../models/frequencia_model.dart';

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
  final FrequenciaService _frequenciaService = FrequenciaService();

  Map<String, dynamic>? _dadosAluno;
  FrequenciaModel? _frequencia;
  List<Map<String, dynamic>> _logsFrequencia = [];
  bool _isLoading = true;
  bool _expanded = false;

  // Contadores calculados dos logs
  int _totalPresencas = 0;
  int _totalAusencias = 0;
  late Map<String, int> _presencasPorDia;
  Timestamp? _ultimaPresenca;

  @override
  void initState() {
    super.initState();
    _resetContadores();
    _carregarDados();
  }

  void _resetContadores() {
    _presencasPorDia = {
      'seg': 0, 'ter': 0, 'qua': 0, 'qui': 0, 'sex': 0, 'sab': 0, 'dom': 0
    };
    _totalPresencas = 0;
    _totalAusencias = 0;
    _ultimaPresenca = null;
  }

  Future<void> _carregarDados() async {
    try {
      setState(() {
        _isLoading = true;
        _resetContadores();
      });

      // Carrega dados do aluno
      final alunoDoc = await _firestore.collection('alunos').doc(widget.alunoId).get();

      if (!alunoDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      _dadosAluno = alunoDoc.data();

      // Carrega LOGS REAIS com filtro
      await _carregarLogsComFiltro();

      // Calcula frequência com base nos logs
      _calcularFrequenciaDosLogs();

    } catch (e) {
      debugPrint('❌ Erro em _carregarDados: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Carrega logs aplicando o filtro
  Future<void> _carregarLogsComFiltro() async {
    try {
      Query query = _firestore
          .collection('log_presenca_alunos')
          .where('aluno_id', isEqualTo: widget.alunoId)
          .orderBy('data_aula', descending: true);

      // Aplica filtro temporal
      if (widget.filtroTemporal != null) {
        final now = DateTime.now();

        switch (widget.filtroTemporal) {
          case 'Semana':
            final umaSemanaAtras = now.subtract(const Duration(days: 7));
            query = query.where('data_aula', isGreaterThanOrEqualTo: Timestamp.fromDate(umaSemanaAtras));
            break;
          case 'Mês':
            final umMesAtras = DateTime(now.year, now.month - 1, now.day);
            query = query.where('data_aula', isGreaterThanOrEqualTo: Timestamp.fromDate(umMesAtras));
            break;
          case 'Ano':
            if (widget.anoSelecionado != null) {
              final inicioAno = DateTime(int.parse(widget.anoSelecionado!), 1, 1);
              final fimAno = DateTime(int.parse(widget.anoSelecionado!), 12, 31, 23, 59, 59);
              query = query
                  .where('data_aula', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioAno))
                  .where('data_aula', isLessThanOrEqualTo: Timestamp.fromDate(fimAno));
            }
            break;
        }
      }

      final snapshot = await query.get();

      // 🔥 CORREÇÃO DEFINITIVA: Cast explícito
      _logsFrequencia = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data != null) {
          _logsFrequencia.add(data as Map<String, dynamic>);
        }
      }

      debugPrint('📊 Logs carregados: ${_logsFrequencia.length} para aluno ${widget.alunoId}');

    } catch (e) {
      debugPrint('❌ Erro ao carregar logs: $e');
      _logsFrequencia = [];
    }
  }

  // Calcula estatísticas dos logs
  void _calcularFrequenciaDosLogs() {
    for (var log in _logsFrequencia) {
      final presente = log['presente'] as bool? ?? false;
      final dataLog = log['data_aula'] as Timestamp?;
      final diaSemana = log['dia_semana_abrev'] as String?;

      if (presente) {
        _totalPresencas++;

        // Atualiza última presença
        if (dataLog != null) {
          if (_ultimaPresenca == null || dataLog.toDate().isAfter(_ultimaPresenca!.toDate())) {
            _ultimaPresenca = dataLog;
          }
        }

        // Conta por dia da semana
        if (diaSemana != null && _presencasPorDia.containsKey(diaSemana)) {
          _presencasPorDia[diaSemana] = _presencasPorDia[diaSemana]! + 1;
        }
      } else {
        _totalAusencias++;
      }
    }

    // Cria dados combinados para o FrequenciaService
    final dadosCompletos = <String, dynamic>{
      if (_dadosAluno != null) ..._dadosAluno!,
      'seg': _presencasPorDia['seg'],
      'ter': _presencasPorDia['ter'],
      'qua': _presencasPorDia['qua'],
      'qui': _presencasPorDia['qui'],
      'sex': _presencasPorDia['sex'],
      'sab': _presencasPorDia['sab'],
      'dom': _presencasPorDia['dom'],
      'total_presencas': _totalPresencas,
      'total_ausencias': _totalAusencias,
      'ultimo_dia_presente': _ultimaPresenca,
    };

    _frequencia = _frequenciaService.calcularFrequencia(dadosCompletos);

    if (mounted) {
      setState(() {});
    }

    debugPrint('📊 Frequência calculada - Total: $_totalPresencas, Última: $_ultimaPresenca');
  }

  String _formatarData(Timestamp? timestamp) {
    if (timestamp == null) return "Nunca";
    return DateFormat("dd/MM/yyyy").format(timestamp.toDate());
  }

  Widget _buildAlunoAvatar() {
    final fotoUrl = _dadosAluno?['foto_perfil_aluno'] as String?;

    return CircleAvatar(
      radius: 40,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty
          ? NetworkImage(fotoUrl)
          : null,
      child: fotoUrl == null || fotoUrl.isEmpty
          ? Text(
        _dadosAluno?['nome']?.toString().substring(0, 1).toUpperCase() ?? '?',
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
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: color,
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildDiaCardCompacto(String dia, int quantidade) {
    return Container(
      width: 38,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: quantidade > 0 ? Colors.red.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
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
              fontSize: 12,
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

  String _getTituloFiltro() {
    if (widget.filtroTemporal == null) return '';

    if (widget.filtroTemporal == 'Ano' && widget.anoSelecionado != null) {
      return ' • $widget.anoSelecionado';
    }
    return ' • ${widget.filtroTemporal}';
  }

  String _getSubtituloFiltro() {
    if (widget.filtroTemporal == null) return '';

    switch (widget.filtroTemporal) {
      case 'Semana':
        return 'Últimos 7 dias';
      case 'Mês':
        return 'Últimos 30 dias';
      case 'Ano':
        return widget.anoSelecionado ?? 'Ano selecionado';
      case 'Total':
        return 'Todo histórico';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 300,
        padding: const EdgeInsets.all(16),
        child: const Center(child: CircularProgressIndicator(color: Colors.red)),
      );
    }

    if (_frequencia == null || _dadosAluno == null) {
      return Container(
        height: 200,
        padding: const EdgeInsets.all(16),
        child: const Center(child: Text('Erro ao carregar dados')),
      );
    }

    final frequencia = _frequencia!;
    final nome = _dadosAluno!['nome'] ?? 'Aluno';

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
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabeçalho com nome e foto
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: frequencia.corIndicador.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                nome,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: frequencia.corIndicador.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                frequencia.nivel,
                                style: TextStyle(
                                  color: frequencia.corIndicador,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (widget.filtroTemporal != null) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _getTituloFiltro(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (widget.filtroTemporal != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _getSubtituloFiltro(),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Conteúdo
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Métricas principais
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMetricCard(
                        value: '$_totalPresencas',
                        label: 'Presenças',
                        color: Colors.blue,
                        icon: Icons.event_available,
                      ),
                      _buildMetricCard(
                        value: '$_totalAusencias',
                        label: 'Faltas',
                        color: Colors.red,
                        icon: Icons.event_busy,
                      ),
                      _buildMetricCard(
                        value: '${frequencia.diasSemTreinar}',
                        label: 'Dias sem',
                        color: frequencia.corIndicador,
                        icon: Icons.calendar_today,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Última presença
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: frequencia.corIndicador,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Última presença',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                _formatarData(_ultimaPresenca),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                frequencia.statusTexto,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: frequencia.corIndicador,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Dias da semana
                  const Text(
                    'Presenças por dia',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildDiaCardCompacto('S', _presencasPorDia['seg']!),
                      _buildDiaCardCompacto('T', _presencasPorDia['ter']!),
                      _buildDiaCardCompacto('Q', _presencasPorDia['qua']!),
                      _buildDiaCardCompacto('Q', _presencasPorDia['qui']!),
                      _buildDiaCardCompacto('S', _presencasPorDia['sex']!),
                      _buildDiaCardCompacto('S', _presencasPorDia['sab']!),
                      _buildDiaCardCompacto('D', _presencasPorDia['dom']!),
                    ],
                  ),

                  if (_expanded) ...[
                    const SizedBox(height: 20),

                    // Lista dos últimos logs
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _logsFrequencia.length > 10 ? 10 : _logsFrequencia.length,
                        itemBuilder: (context, index) {
                          final log = _logsFrequencia[index];
                          final presente = log['presente'] as bool? ?? false;
                          final data = log['data_aula'] as Timestamp?;

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              presente ? Icons.check_circle : Icons.cancel,
                              color: presente ? Colors.green : Colors.red,
                              size: 18,
                            ),
                            title: Text(
                              _formatarData(data),
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Text(
                              log['tipo_aula']?.toString() ?? 'N/A',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Botão de ver histórico
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.history, size: 18),
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
                  ],

                  const SizedBox(height: 8),

                  // Botão de expandir/recolher
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}