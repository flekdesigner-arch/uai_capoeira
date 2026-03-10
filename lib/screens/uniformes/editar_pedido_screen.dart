import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dialogs/selecionar_item_dialog.dart';

class EditarPedidoScreen extends StatefulWidget {
  final String pedidoId;
  final Map<String, dynamic> pedidoData;

  const EditarPedidoScreen({
    super.key,
    required this.pedidoId,
    required this.pedidoData,
  });

  @override
  State<EditarPedidoScreen> createState() => _EditarPedidoScreenState();
}

class _EditarPedidoScreenState extends State<EditarPedidoScreen> {
  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  // Controladores
  late TextEditingController _observacoesController;
  late TextEditingController _dataPrevisaoController;
  late String _status;
  late String _statusPagamento;
  late double _valorPago;
  late double _valorTotal;

  bool _isLoading = false;

  // Lista de itens (EDITÁVEL!)
  List<Map<String, dynamic>> _itens = [];

  // Para controle de quantidade
  final Map<int, TextEditingController> _quantidadeControllers = {};

  @override
  void initState() {
    super.initState();
    _observacoesController = TextEditingController(text: widget.pedidoData['observacoes'] ?? '');
    _dataPrevisaoController = TextEditingController(text: widget.pedidoData['data_previsao'] ?? '');
    _status = widget.pedidoData['status'] ?? 'pendente';
    _statusPagamento = widget.pedidoData['status_pagamento'] ?? 'pendente';
    _valorPago = (widget.pedidoData['valor_pago'] ?? 0).toDouble();
    _valorTotal = (widget.pedidoData['valor_total'] ?? 0).toDouble();

    // Carregar itens
    _itens = List<Map<String, dynamic>>.from(widget.pedidoData['itens'] ?? []);

    // Criar controladores para cada item
    for (int i = 0; i < _itens.length; i++) {
      _quantidadeControllers[i] = TextEditingController(
        text: _itens[i]['quantidade'].toString(),
      );
      _quantidadeControllers[i]!.addListener(() => _atualizarQuantidade(i));
    }
  }

  @override
  void dispose() {
    _observacoesController.dispose();
    _dataPrevisaoController.dispose();
    for (var controller in _quantidadeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _atualizarQuantidade(int index) {
    final controller = _quantidadeControllers[index];
    if (controller != null) {
      final novoValor = int.tryParse(controller.text);
      if (novoValor != null && novoValor > 0 && mounted) {
        setState(() {
          _itens[index]['quantidade'] = novoValor;
          _calcularTotal();
        });
      }
    }
  }

  void _calcularTotal() {
    _valorTotal = 0;
    for (var item in _itens) {
      _valorTotal += (item['quantidade'] * item['preco_unitario']);
    }
  }

  void _removerItem(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🗑️ Remover Item'),
        content: Text('Deseja remover "${_itens[index]['nome']}" do pedido?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              _quantidadeControllers[index]?.dispose();

              setState(() {
                _itens.removeAt(index);
                _calcularTotal();

                // Reorganizar controladores
                final novosControllers = <int, TextEditingController>{};
                for (int i = 0; i < _itens.length; i++) {
                  novosControllers[i] = _quantidadeControllers[i + 1]!;
                }
                _quantidadeControllers.clear();
                _quantidadeControllers.addAll(novosControllers);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('REMOVER'),
          ),
        ],
      ),
    );
  }

  Future<void> _selecionarItem() async {
    final itemSelecionado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const SelecionarItemDialog(),
    );

    if (itemSelecionado != null && mounted) {
      setState(() {
        final novoItem = {
          ...itemSelecionado,
          'quantidade': 1, // Começa com 1
        };
        _itens.add(novoItem);

        // Criar controller para o novo item
        final novoIndex = _itens.length - 1;
        _quantidadeControllers[novoIndex] = TextEditingController(text: '1');
        _quantidadeControllers[novoIndex]!.addListener(() => _atualizarQuantidade(novoIndex));

        _calcularTotal();
      });
    }
  }

  Future<void> _selecionarDataPrevisao() async {
    DateTime? data = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 15)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
      locale: const Locale('pt', 'BR'),
    );

    if (data != null) {
      setState(() {
        _dataPrevisaoController.text = _dateFormat.format(data);
      });
    }
  }

  Future<void> _salvar() async {
    setState(() => _isLoading = true);

    try {
      Map<String, dynamic> dadosAtualizados = {
        'itens': _itens,
        'observacoes': _observacoesController.text,
        'data_previsao': _dataPrevisaoController.text,
        'status': _status,
        'status_pagamento': _statusPagamento,
        'valor_total': _valorTotal,
        'valor_pago': _statusPagamento == 'pago' ? _valorTotal : _valorPago,
        'ultima_edicao': FieldValue.serverTimestamp(),
        'editado_por': FirebaseAuth.instance.currentUser?.uid,
      };

      await FirebaseFirestore.instance
          .collection('pedidos_uniformes')
          .doc(widget.pedidoId)
          .update(dadosAtualizados);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Pedido atualizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao atualizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EDITAR PEDIDO'),
        backgroundColor: Colors.purple.shade900,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _salvar,
            icon: _isLoading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
                : const Icon(Icons.save, color: Colors.white),
            label: Text(
              _isLoading ? 'SALVANDO...' : 'SALVAR',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Informações do Aluno
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, color: Colors.purple.shade900),
                        const SizedBox(width: 8),
                        const Text(
                          'ALUNO',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.pedidoData['aluno_nome'] ?? 'Aluno não identificado',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pedido: ${widget.pedidoData['id_pedido'] ?? 'N/I'}',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Itens do Pedido (EDITÁVEL!)
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shopping_bag, color: Colors.purple.shade900),
                            const SizedBox(width: 8),
                            const Text(
                              'ITENS DO PEDIDO',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Colors.purple),
                          onPressed: _selecionarItem,
                          tooltip: 'Adicionar item',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Lista de itens com controle de quantidade
                    if (_itens.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text(
                                'Nenhum item no pedido',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._itens.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['nome'] ?? 'Item',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Preço unitário: ${_realFormat.format(item['preco_unitario'])}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.purple.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.red, size: 20),
                                    onPressed: () => _removerItem(index),
                                    tooltip: 'Remover item',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: _quantidadeControllers[index],
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Quantidade',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        children: [
                                          const Text(
                                            'Subtotal',
                                            style: TextStyle(fontSize: 10),
                                          ),
                                          Text(
                                            _realFormat.format(
                                                item['quantidade'] * item['preco_unitario']
                                            ),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: Colors.purple.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),

                    if (_itens.isNotEmpty) ...[
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TOTAL DO PEDIDO',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            _realFormat.format(_valorTotal),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.purple,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Status do Pedido e Pagamento
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.event, color: Colors.blue.shade900),
                        const SizedBox(width: 8),
                        const Text(
                          'STATUS DO PEDIDO',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'pendente',
                          label: Text('Pendente'),
                          icon: Icon(Icons.pending),
                        ),
                        ButtonSegment(
                          value: 'em_confeccao',
                          label: Text('Em Confecção'),
                          icon: Icon(Icons.build),
                        ),
                        ButtonSegment(
                          value: 'finalizado',
                          label: Text('Finalizado'),
                          icon: Icon(Icons.check_circle),
                        ),
                      ],
                      selected: {_status},
                      onSelectionChanged: (Set<String> selected) {
                        setState(() {
                          _status = selected.first;
                        });
                      },
                    ),

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Icon(Icons.payment, color: Colors.orange.shade900),
                        const SizedBox(width: 8),
                        const Text(
                          'STATUS DO PAGAMENTO',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'pendente',
                          label: Text('Pendente'),
                          icon: Icon(Icons.pending),
                        ),
                        ButtonSegment(
                          value: 'pago',
                          label: Text('Pago'),
                          icon: Icon(Icons.check_circle),
                        ),
                        ButtonSegment(
                          value: 'parcial',
                          label: Text('Parcial'),
                          icon: Icon(Icons.money_off),
                        ),
                      ],
                      selected: {_statusPagamento},
                      onSelectionChanged: (Set<String> selected) {
                        setState(() {
                          _statusPagamento = selected.first;
                        });
                      },
                    ),

                    if (_statusPagamento == 'parcial') ...[
                      const SizedBox(height: 16),
                      TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Valor pago',
                          border: OutlineInputBorder(),
                          prefixText: 'R\$ ',
                        ),
                        onChanged: (value) {
                          setState(() {
                            _valorPago = double.tryParse(value.replaceAll(',', '.')) ?? 0;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Data de Previsão
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_today, color: Colors.green.shade900),
                        const SizedBox(width: 8),
                        const Text(
                          'PREVISÃO DE ENTREGA',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _selecionarDataPrevisao,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, size: 20, color: Colors.grey.shade600),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _dataPrevisaoController,
                                enabled: false,
                                decoration: const InputDecoration(
                                  labelText: 'Data de previsão',
                                  border: InputBorder.none,
                                  hintText: 'Selecionar data',
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Observações
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.note, color: Colors.teal.shade900),
                        const SizedBox(width: 8),
                        const Text(
                          'OBSERVAÇÕES',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _observacoesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Observações sobre o pedido...',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Informações adicionais
            Card(
              color: Colors.grey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildInfoRow(
                      'Data do pedido',
                      DateFormat('dd/MM/yyyy HH:mm').format(
                        (widget.pedidoData['data_pedido'] as Timestamp?)?.toDate() ?? DateTime.now(),
                      ),
                    ),
                    const Divider(),
                    _buildInfoRow(
                      'Valor total',
                      _realFormat.format(_valorTotal),
                      isBold: true,
                    ),
                    const Divider(),
                    _buildInfoRow(
                      'Valor pago',
                      _realFormat.format(_valorPago),
                      color: Colors.green,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade700),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }
}