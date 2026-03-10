// lib/screens/uniformes/screens/nova_venda_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/services/uniformes_service.dart';
import 'dialogs/selecionar_aluno_dialog.dart';  // ← CORRIGIDO: caminho relativo
import 'dialogs/selecionar_item_dialog.dart';  // ← CORRIGIDO: caminho relativo

// ... resto do código continua igual
class NovaVendaScreen extends StatefulWidget {
  const NovaVendaScreen({super.key});

  @override
  State<NovaVendaScreen> createState() => _NovaVendaScreenState();
}

class _NovaVendaScreenState extends State<NovaVendaScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final UniformesService _uniformesService = UniformesService();
  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  String? _alunoSelecionadoId;
  String? _alunoSelecionadoNome;
  String? _statusPagamento = 'pendente';

  List<Map<String, dynamic>> _itensVenda = [];
  double _valorTotal = 0;
  double _valorPago = 0;

  final TextEditingController _observacoesController = TextEditingController();

  @override
  void dispose() {
    _observacoesController.dispose();
    super.dispose();
  }

  void _adicionarItem() async {
    final itemSelecionado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const SelecionarItemDialog(),
    );

    if (itemSelecionado != null && mounted) {
      setState(() {
        _itensVenda.add(itemSelecionado);
        _calcularTotal();
      });
    }
  }

  void _removerItem(int index) {
    setState(() {
      _itensVenda.removeAt(index);
      _calcularTotal();
    });
  }

  void _calcularTotal() {
    _valorTotal = 0;
    for (var item in _itensVenda) {
      _valorTotal += (item['quantidade'] * item['preco_unitario']);
    }
  }

  Future<void> _finalizarVenda() async {
    if (_alunoSelecionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um aluno'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_itensVenda.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione pelo menos um item'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final dadosVenda = {
        'aluno_id': _alunoSelecionadoId,
        'aluno_nome': _alunoSelecionadoNome,
        'itens': _itensVenda,
        'valor_total': _valorTotal,
        'valor_pago': _statusPagamento == 'pago' ? _valorTotal : _valorPago,
        'status_pagamento': _statusPagamento,
        'observacoes': _observacoesController.text,
        'data_venda': FieldValue.serverTimestamp(),
        'vendedor_id': currentUser?.uid,
      };

      await _uniformesService.registrarVenda(dadosVenda);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Venda registrada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao registrar venda: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selecionarAluno() async {
    final selecionado = await showDialog<Map<String, String>>(  // ← Tipo explícito
      context: context,
      builder: (context) => const SelecionarAlunoDialog(
        corTema: Colors.green,
      ),
    );

    if (selecionado != null && mounted) {
      setState(() {
        _alunoSelecionadoId = selecionado['id'];      // ← Agora é String com certeza
        _alunoSelecionadoNome = selecionado['nome'];  // ← Agora é String com certeza
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NOVA VENDA'),
        backgroundColor: Colors.green.shade900,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton.icon(
            onPressed: _finalizarVenda,
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text('FINALIZAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Seleção de Aluno
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ALUNO',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _selecionarAluno,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.person, color: Colors.grey.shade600),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _alunoSelecionadoNome ?? 'Selecionar aluno',
                                style: TextStyle(
                                  color: _alunoSelecionadoNome == null
                                      ? Colors.grey
                                      : Colors.black,
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

            // Itens da Venda
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
                        const Text(
                          'ITENS',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: _adicionarItem,
                          icon: const Icon(Icons.add),
                          label: const Text('Adicionar Item'),
                        ),
                      ],
                    ),
                    const Divider(),

                    if (_itensVenda.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text(
                                'Nenhum item adicionado',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _itensVenda.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final item = _itensVenda[index];
                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.shopping_bag, color: Colors.green),
                            ),
                            title: Text(item['nome']),
                            subtitle: Text('${item['quantidade']} x ${_realFormat.format(item['preco_unitario'])}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _realFormat.format(item['quantidade'] * item['preco_unitario']),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () => _removerItem(index),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                    const Divider(),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _realFormat.format(_valorTotal),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Status do Pagamento
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PAGAMENTO',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
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
                      selected: {_statusPagamento!},
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
                          _valorPago = double.tryParse(value.replaceAll(',', '.')) ?? 0;
                        },
                      ),
                    ],

                    const SizedBox(height: 16),

                    TextField(
                      controller: _observacoesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Observações',
                        border: OutlineInputBorder(),
                        hintText: 'Observações sobre a venda...',
                      ),
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
}