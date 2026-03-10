// lib/screens/eventos/camisas_evento_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CamisasEventoScreen extends StatefulWidget {
  final String eventoId;
  final String eventoNome;

  const CamisasEventoScreen({
    super.key,
    required this.eventoId,
    required this.eventoNome,
  });

  @override
  State<CamisasEventoScreen> createState() => _CamisasEventoScreenState();
}

class _CamisasEventoScreenState extends State<CamisasEventoScreen> {
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _tamanhoController = TextEditingController();
  final TextEditingController _valorController = TextEditingController();

  final List<String> _tamanhosPadrao = [
    'PP', 'P', 'M', 'G', 'GG', 'XG', 'XXG',
    '4A', '6A', '8A', '10A', '12A', '14A'
  ];

  List<String> _tamanhosDisponiveis = [];
  bool _isLoadingTamanhos = true;

  // 🔥 FILTROS
  String _filtroStatus = 'TODOS'; // TODOS, PAGO, PENDENTE, ENTREGUE, NAO_ENTREGUE

  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _carregarTamanhosDoEvento();
  }

  Future<void> _carregarTamanhosDoEvento() async {
    try {
      final eventoDoc = await FirebaseFirestore.instance
          .collection('eventos')
          .doc(widget.eventoId)
          .get();

      if (eventoDoc.exists) {
        final data = eventoDoc.data();
        final tamanhosEvento = data?['tamanhosDisponiveis'] as List?;

        if (tamanhosEvento != null && tamanhosEvento.isNotEmpty) {
          setState(() {
            _tamanhosDisponiveis = List<String>.from(tamanhosEvento);
            _isLoadingTamanhos = false;
          });
          debugPrint('✅ Tamanhos carregados do evento: $_tamanhosDisponiveis');
          return;
        }
      }

      setState(() {
        _tamanhosDisponiveis = _tamanhosPadrao;
        _isLoadingTamanhos = false;
      });

    } catch (e) {
      debugPrint('❌ Erro ao carregar tamanhos: $e');
      setState(() {
        _tamanhosDisponiveis = _tamanhosPadrao;
        _isLoadingTamanhos = false;
      });
    }
  }

  Future<void> _adicionarCamisa() async {
    if (_nomeController.text.isEmpty || _tamanhoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha todos os campos!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 🔥 VALIDA VALOR
    double valor = 0;
    if (_valorController.text.isNotEmpty) {
      valor = double.tryParse(_valorController.text.replaceAll(',', '.')) ?? 0;
    }

    try {
      await FirebaseFirestore.instance
          .collection('camisas_eventos')
          .add({
        'evento_id': widget.eventoId,
        'evento_nome': widget.eventoNome,
        'nome_participante': _nomeController.text.trim(),
        'tamanho': _tamanhoController.text.trim(),
        'valor': valor,
        'pago': false,           // 🔥 NOVO: controle de pagamento
        'entregue': false,       // 🔥 Mantido: controle de entrega
        'data_registro': FieldValue.serverTimestamp(),
        'data_pagamento': null,  // 🔥 NOVO: data do pagamento
        'data_entrega': null,    // 🔥 NOVO: data da entrega
      });

      _nomeController.clear();
      _tamanhoController.clear();
      _valorController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Camisa registrada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao adicionar camisa: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 🔥 MARCAR COMO PAGO
  Future<void> _marcarPago(String camisaId, bool pago) async {
    try {
      await FirebaseFirestore.instance
          .collection('camisas_eventos')
          .doc(camisaId)
          .update({
        'pago': pago,
        'data_pagamento': pago ? FieldValue.serverTimestamp() : null,
      });
    } catch (e) {
      debugPrint('Erro ao marcar pagamento: $e');
    }
  }

  // 🔥 MARCAR COMO ENTREGUE
  Future<void> _marcarEntregue(String camisaId, bool entregue) async {
    try {
      await FirebaseFirestore.instance
          .collection('camisas_eventos')
          .doc(camisaId)
          .update({
        'entregue': entregue,
        'data_entrega': entregue ? FieldValue.serverTimestamp() : null,
      });
    } catch (e) {
      debugPrint('Erro ao marcar entrega: $e');
    }
  }

  // 🔥 EDITAR VALOR
  Future<void> _editarValor(String camisaId, double valorAtual) async {
    final TextEditingController valorEditController = TextEditingController(
      text: valorAtual.toStringAsFixed(2).replaceAll('.', ','),
    );

    final novoValor = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Valor'),
        content: TextField(
          controller: valorEditController,
          decoration: const InputDecoration(
            labelText: 'Valor (R\$)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.attach_money),
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              final valor = double.tryParse(
                  valorEditController.text.replaceAll(',', '.')
              ) ?? 0;
              Navigator.pop(context, valor);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );

    if (novoValor != null && novoValor != valorAtual) {
      try {
        await FirebaseFirestore.instance
            .collection('camisas_eventos')
            .doc(camisaId)
            .update({'valor': novoValor});
      } catch (e) {
        debugPrint('Erro ao editar valor: $e');
      }
    }
  }

  Future<void> _excluirCamisa(String camisaId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Registro'),
        content: const Text('Remover esta camisa da lista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('camisas_eventos')
            .doc(camisaId)
            .delete();
      } catch (e) {
        debugPrint('Erro ao excluir camisa: $e');
      }
    }
  }

  void _selecionarTamanho() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        height: 400,
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Selecione o tamanho',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoadingTamanhos
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.5,
                ),
                itemCount: _tamanhosDisponiveis.length,
                itemBuilder: (context, index) {
                  final tamanho = _tamanhosDisponiveis[index];
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _tamanhoController.text = tamanho;
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: Center(
                        child: Text(
                          tamanho,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade900,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔥 FILTRO DE STATUS
  Widget _buildFiltros() {
    final List<Map<String, dynamic>> opcoes = [
      {'label': 'TODOS', 'icon': Icons.list, 'color': Colors.grey},
      {'label': 'PAGO', 'icon': Icons.paid, 'color': Colors.green},
      {'label': 'PENDENTE', 'icon': Icons.pending, 'color': Colors.orange},
      {'label': 'ENTREGUE', 'icon': Icons.check_circle, 'color': Colors.blue},
      {'label': 'NÃO ENTREGUE', 'icon': Icons.access_time, 'color': Colors.red},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: opcoes.map((opcao) {
            final isSelected = _filtroStatus == opcao['label'];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      opcao['icon'],
                      size: 16,
                      color: isSelected ? Colors.white : opcao['color'],
                    ),
                    const SizedBox(width: 4),
                    Text(opcao['label']),
                  ],
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _filtroStatus = opcao['label'];
                  });
                },
                selectedColor: opcao['color'],
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontSize: 12,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // 🔥 APLICA FILTROS NA QUERY
  Query _buildQuery() {
    Query query = FirebaseFirestore.instance
        .collection('camisas_eventos')
        .where('evento_id', isEqualTo: widget.eventoId);

    switch (_filtroStatus) {
      case 'PAGO':
        query = query.where('pago', isEqualTo: true);
        break;
      case 'PENDENTE':
        query = query.where('pago', isEqualTo: false);
        break;
      case 'ENTREGUE':
        query = query.where('entregue', isEqualTo: true);
        break;
      case 'NÃO ENTREGUE':
        query = query.where('entregue', isEqualTo: false);
        break;
    }

    return query.orderBy('data_registro', descending: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '👕 Camisas - ${widget.eventoNome}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoadingTamanhos
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // FORMULÁRIO
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Campo Nome
                TextField(
                  controller: _nomeController,
                  decoration: InputDecoration(
                    labelText: 'Nome do Participante',
                    labelStyle: const TextStyle(color: Colors.purple),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.person, color: Colors.purple),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Linha com Tamanho, Valor e Botão
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Campo Tamanho
                    Expanded(
                      flex: 1,
                      child: InkWell(
                        onTap: _selecionarTamanho,
                        child: Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.shopping_bag, color: Colors.purple, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _tamanhoController.text.isEmpty
                                      ? 'Tam.'
                                      : _tamanhoController.text,
                                  style: TextStyle(
                                    color: _tamanhoController.text.isEmpty
                                        ? Colors.grey.shade600
                                        : Colors.purple.shade900,
                                    fontWeight: _tamanhoController.text.isEmpty
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, color: Colors.purple),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Campo Valor
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _valorController,
                        decoration: InputDecoration(
                          hintText: 'R\$ 0,00',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Botão ADD
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _adicionarCamisa,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Icon(Icons.add, size: 24),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // FILTROS
          _buildFiltros(),

          // ESTATÍSTICAS
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('camisas_eventos')
                .where('evento_id', isEqualTo: widget.eventoId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();

              final docs = snapshot.data!.docs;
              Map<String, int> contagem = {};
              int entregues = 0;
              int pagos = 0;
              double totalValor = 0;

              for (var doc in docs) {
                final data = doc.data() as Map<String, dynamic>;
                final tamanho = data['tamanho'] as String? ?? 'OUTRO';
                final entregue = data['entregue'] as bool? ?? false;
                final pago = data['pago'] as bool? ?? false;
                final valor = (data['valor'] as num?)?.toDouble() ?? 0;

                contagem[tamanho] = (contagem[tamanho] ?? 0) + 1;
                if (entregue) entregues++;
                if (pago) {
                  pagos++;
                  totalValor += valor;
                }
              }

              return Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '📊 RESUMO',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Total: ${docs.length}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Distribuição por tamanho
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: contagem.entries.map((entry) {
                          return Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${entry.value}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Status de Pagamento e Entrega
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Pagos: $pagos',
                                  style: const TextStyle(color: Colors.green),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.orange,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Pendentes: ${docs.length - pagos}',
                                  style: const TextStyle(color: Colors.orange),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Entregues: $entregues',
                                  style: const TextStyle(color: Colors.blue),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Não entregues: ${docs.length - entregues}',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),

                    const Divider(height: 16),

                    // Total em valor
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '💰 TOTAL ARRECADADO:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _realFormat.format(totalValor),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          // LISTA DE CAMISAS COM FILTRO
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _buildQuery().snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Erro: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.shopping_bag,
                            size: 60,
                            color: Colors.purple.shade200,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _filtroStatus == 'TODOS'
                              ? 'Nenhuma camisa registrada'
                              : 'Nenhuma camisa com filtro $_filtroStatus',
                          style: const TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _filtroStatus == 'TODOS'
                              ? 'Adicione a primeira camisa acima'
                              : 'Tente outro filtro',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final camisa = doc.data() as Map<String, dynamic>;
                    final pago = camisa['pago'] as bool? ?? false;
                    final entregue = camisa['entregue'] as bool? ?? false;
                    final valor = (camisa['valor'] as num?)?.toDouble() ?? 0;

                    // Determina a cor baseada no status
                    Color corCard = Colors.purple;
                    if (pago && entregue) {
                      corCard = Colors.green;
                    } else if (pago && !entregue) {
                      corCard = Colors.blue;
                    } else if (!pago && entregue) {
                      corCard = Colors.orange;
                    } else {
                      corCard = Colors.red;
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: corCard.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            // Linha principal
                            Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        corCard.withOpacity(0.7),
                                        corCard,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      camisa['tamanho'] ?? '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        camisa['nome_participante'] ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          // Badge de Pagamento
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: pago
                                                  ? Colors.green.shade50
                                                  : Colors.orange.shade50,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  pago ? Icons.paid : Icons.pending,
                                                  size: 12,
                                                  color: pago ? Colors.green : Colors.orange,
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  pago ? 'Pago' : 'Pendente',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: pago ? Colors.green : Colors.orange,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 4),

                                          // Badge de Entrega
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: entregue
                                                  ? Colors.blue.shade50
                                                  : Colors.red.shade50,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  entregue
                                                      ? Icons.check_circle
                                                      : Icons.access_time,
                                                  size: 12,
                                                  color: entregue ? Colors.blue : Colors.red,
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  entregue ? 'Entregue' : 'Não entregue',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: entregue ? Colors.blue : Colors.red,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Valor
                                Text(
                                  _realFormat.format(valor),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: corCard,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            // Botões de ação
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Botão Pagar
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _marcarPago(doc.id, !pago),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: pago
                                            ? Colors.green.shade50
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.paid,
                                            size: 16,
                                            color: pago ? Colors.green : Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            pago ? 'PAGO' : 'PAGAR',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: pago ? Colors.green : Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),

                                // Botão Entregar
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _marcarEntregue(doc.id, !entregue),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: entregue
                                            ? Colors.blue.shade50
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            entregue
                                                ? Icons.check_circle
                                                : Icons.local_shipping,
                                            size: 16,
                                            color: entregue ? Colors.blue : Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            entregue ? 'ENTREGUE' : 'ENTREGAR',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: entregue ? Colors.blue : Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),

                                // Botão Editar Valor
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _editarValor(doc.id, valor),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.edit,
                                            size: 16,
                                            color: Colors.purple,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'EDITAR',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.purple,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),

                                // Botão Excluir
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _excluirCamisa(doc.id),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.delete,
                                            size: 16,
                                            color: Colors.red,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'EXCLUIR',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Datas (se houver)
                            if (camisa['data_pagamento'] != null || camisa['data_entrega'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (camisa['data_pagamento'] != null)
                                      Text(
                                        'Pago: ${_formatarData(camisa['data_pagamento'])}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    if (camisa['data_entrega'] != null)
                                      Text(
                                        'Entregue: ${_formatarData(camisa['data_entrega'])}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.blue.shade700,
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
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatarData(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      if (timestamp is Timestamp) {
        return DateFormat('dd/MM/yyyy').format(timestamp.toDate());
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _tamanhoController.dispose();
    _valorController.dispose();
    super.dispose();
  }
}