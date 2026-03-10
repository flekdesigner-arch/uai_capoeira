// screens/aluno/historico_frequencia_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/frequencia_service.dart';
import '../../models/frequencia_model.dart';

class HistoricoFrequenciaScreen extends StatefulWidget {
  final String alunoId;
  final String alunoNome;

  const HistoricoFrequenciaScreen({
    super.key,
    required this.alunoId,
    required this.alunoNome,
  });

  @override
  State<HistoricoFrequenciaScreen> createState() => _HistoricoFrequenciaScreenState();
}

class _HistoricoFrequenciaScreenState extends State<HistoricoFrequenciaScreen> {
  final FrequenciaService _frequenciaService = FrequenciaService();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final DateFormat _timeFormat = DateFormat('HH:mm');

  // Controle de paginação
  static const int _limiteInicial = 30;
  static const int _incrementoCarregamento = 20;

  List<QueryDocumentSnapshot> _todosDocumentos = []; // ← Mudado para QueryDocumentSnapshot
  int _itensExibidos = 0;
  bool _carregandoInicial = true;
  bool _carregandoMais = false;
  bool _temErro = false;
  String _mensagemErro = '';

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
  }

  // Carrega os dados iniciais (apenas 30 itens)
  Future<void> _carregarDadosIniciais() async {
    setState(() {
      _carregandoInicial = true;
      _temErro = false;
    });

    try {
      final snapshot = await _frequenciaService
          .getHistoricoAluno(widget.alunoId)
          .first;

      setState(() {
        _todosDocumentos = snapshot.docs; // ← Agora é List<QueryDocumentSnapshot>
        _itensExibidos = _todosDocumentos.length > _limiteInicial
            ? _limiteInicial
            : _todosDocumentos.length;
        _carregandoInicial = false;
      });
    } catch (e) {
      setState(() {
        _carregandoInicial = false;
        _temErro = true;
        _mensagemErro = e.toString();
      });
    }
  }

  // Carrega mais itens
  Future<void> _carregarMais() async {
    if (_carregandoMais) return;

    setState(() {
      _carregandoMais = true;
    });

    // Simular um pequeno delay para feedback visual
    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      int proximosItens = _itensExibidos + _incrementoCarregamento;
      _itensExibidos = proximosItens > _todosDocumentos.length
          ? _todosDocumentos.length
          : proximosItens;
      _carregandoMais = false;
    });
  }

  // Recarregar em caso de erro
  Future<void> _recarregar() async {
    await _carregarDadosIniciais();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Histórico de ${widget.alunoNome}',
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          // Botão de recarregar (aparece apenas em caso de erro)
          if (_temErro)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _recarregar,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  // Constrói o corpo da tela baseado no estado
  Widget _buildBody() {
    if (_carregandoInicial) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Carregando histórico...'),
          ],
        ),
      );
    }

    if (_temErro) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              'Erro ao carregar histórico',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _mensagemErro,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _recarregar,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    if (_todosDocumentos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'Nenhum registro de frequência encontrado',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final documentosExibidos = _todosDocumentos.sublist(0, _itensExibidos);
    final historicoCalculado = _frequenciaService.calcularDiferencasEntreAulas(documentosExibidos);

    return Column(
      children: [
        // Indicador de progresso
        _buildProgressIndicator(),

        // Lista de frequências
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: historicoCalculado.length + 1, // +1 para o botão de carregar mais
            itemBuilder: (context, index) {
              if (index == historicoCalculado.length) {
                return _buildLoadMoreButton();
              }

              final item = historicoCalculado[index];
              return _buildHistoryItem(item);
            },
          ),
        ),
      ],
    );
  }

  // Indicador de progresso (quantos itens estão sendo mostrados)
  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.history_edu,
                  size: 16,
                  color: Colors.red.shade900,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Mostrando $_itensExibidos de ${_todosDocumentos.length} registros',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          // Indicador de porcentagem
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${((_itensExibidos / _todosDocumentos.length) * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Botão "Carregar mais"
  Widget _buildLoadMoreButton() {
    if (_itensExibidos >= _todosDocumentos.length) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 32,
              color: Colors.green.shade300,
            ),
            const SizedBox(height: 8),
            Text(
              'Todos os registros carregados',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          if (_carregandoMais)
            const Center(
              child: CircularProgressIndicator(),
            )
          else
            ElevatedButton(
              onPressed: _carregarMais,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_outline, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Carregar mais $_incrementoCarregamento',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            '${_todosDocumentos.length - _itensExibidos} registros restantes',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  // Item do histórico
  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final data = item['data'] as DateTime;
    final diasEntre = item['dias_entre'] as int;
    final presente = item['presente'] as bool;
    final tipoAula = item['tipo_aula'] as String;
    final professor = item['professor'] as String;
    final cor = item['cor'] as Color;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: presente ? Colors.green.shade200 : Colors.red.shade200,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Linha 1: Indicador + Data + Tipo de Aula + Dias
            Row(
              children: [
                // Indicador de presença (círculo verde/vermelho)
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: presente ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 12),

                // Data e hora
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dateFormat.format(data),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _timeFormat.format(data),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                // TIPO DE AULA
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    tipoAula,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: cor,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Contador de dias entre aulas
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: cor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$diasEntre ${diasEntre == 1 ? 'dia' : 'dias'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: cor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Linha 2: Professor
            Row(
              children: [
                Icon(Icons.person, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Professor: $professor',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}