import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/services/uniformes_service.dart';
import 'dialogs/selecionar_aluno_dialog.dart';
import 'dialogs/selecionar_item_dialog.dart';

class NovoPedidoScreen extends StatefulWidget {
  const NovoPedidoScreen({super.key});

  @override
  State<NovoPedidoScreen> createState() => _NovoPedidoScreenState();
}

class _NovoPedidoScreenState extends State<NovoPedidoScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final UniformesService _uniformesService = UniformesService();
  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  String? _alunoSelecionadoId;
  String? _alunoSelecionadoNome;

  List<Map<String, dynamic>> _itensPedido = [];
  double _valorTotal = 0;

  final TextEditingController _observacoesController = TextEditingController();
  final TextEditingController _dataPrevisaoController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _observacoesController.dispose();
    _dataPrevisaoController.dispose();
    super.dispose();
  }

  void _adicionarItem() async {
    final itemSelecionado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const SelecionarItemPedidoDialog(),
    );

    if (itemSelecionado != null && mounted) {
      setState(() {
        _itensPedido.add(itemSelecionado);
        _calcularTotal();
      });
    }
  }

  void _removerItem(int index) {
    setState(() {
      _itensPedido.removeAt(index);
      _calcularTotal();
    });
  }

  void _calcularTotal() {
    _valorTotal = 0;
    for (var item in _itensPedido) {
      _valorTotal += (item['quantidade'] * item['preco_unitario']);
    }
  }

  Future<void> _selecionarAluno() async {
    final selecionado = await showDialog<Map<String, String>>(  // ← Tipo explícito
      context: context,
      builder: (context) => const SelecionarAlunoDialog(
        corTema: Colors.purple,
      ),
    );

    if (selecionado != null && mounted) {
      setState(() {
        _alunoSelecionadoId = selecionado['id'];
        _alunoSelecionadoNome = selecionado['nome'];
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
        _dataPrevisaoController.text = DateFormat('dd/MM/yyyy', 'pt_BR').format(data);
      });
    }
  }

  Future<void> _salvarPedido() async {
    if (_alunoSelecionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um aluno'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_itensPedido.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione pelo menos um item'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String idPedido = _uniformesService.gerarIdPedido();

      final dadosPedido = {
        'id_pedido': idPedido,
        'aluno_id': _alunoSelecionadoId,
        'aluno_nome': _alunoSelecionadoNome,
        'itens': _itensPedido,
        'valor_total': _valorTotal,
        'valor_pago': 0,
        'status': 'pendente',
        'status_pagamento': 'pendente',
        'data_previsao': _dataPrevisaoController.text,
        'observacoes': _observacoesController.text,
        'data_pedido': FieldValue.serverTimestamp(),
        'criado_por': currentUser?.uid,
      };

      await _uniformesService.criarPedido(dadosPedido);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Pedido $idPedido criado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao criar pedido: $e'),
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
        title: const Text('NOVO PEDIDO'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _salvarPedido,
            icon: _isLoading
                ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
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

            // Itens do Pedido
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
                          'ITENS DO PEDIDO',
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

                    if (_itensPedido.isEmpty)
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
                        itemCount: _itensPedido.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final item = _itensPedido[index];
                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.shopping_bag, color: Colors.purple),
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
                            color: Colors.purple,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Informações Adicionais
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'INFORMAÇÕES ADICIONAIS',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),

                    // Data de Previsão
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

                    const SizedBox(height: 16),

                    // Observações
                    TextField(
                      controller: _observacoesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Observações',
                        border: OutlineInputBorder(),
                        hintText: 'Observações sobre o pedido (tamanhos, cores, detalhes, etc)',
                        alignLabelWithHint: true,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Dica
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.purple.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'O status do pedido será "PENDENTE". Você poderá alterar para "EM CONFECÇÃO" e "FINALIZADO" depois.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.purple.shade700,
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

            const SizedBox(height: 16),

            // Botão de Salvar (rodapé)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ElevatedButton(
                onPressed: _salvarPedido,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'CRIAR PEDIDO',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Dialog específico para selecionar item em pedidos (sem restrição de estoque)
class SelecionarItemPedidoDialog extends StatefulWidget {
  const SelecionarItemPedidoDialog({super.key});

  @override
  State<SelecionarItemPedidoDialog> createState() => _SelecionarItemPedidoDialogState();
}

class _SelecionarItemPedidoDialogState extends State<SelecionarItemPedidoDialog> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            AppBar(
              title: const Text('SELECIONAR ITEM'),
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              automaticallyImplyLeading: false,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Pesquisar item...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                      : null,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('uniformes_estoque')
                    .where('status', isEqualTo: 'ativo')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  var itens = snapshot.data!.docs.where((doc) {
                    if (_searchQuery.isEmpty) return true;
                    var data = doc.data() as Map<String, dynamic>;
                    return (data['nome'] ?? '')
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase());
                  }).toList();

                  if (itens.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 50, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhum item encontrado',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Voltar'),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: itens.length,
                    itemBuilder: (context, index) {
                      var doc = itens[index];
                      var data = doc.data() as Map<String, dynamic>;

                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.shopping_bag, color: Colors.purple),
                        ),
                        title: Text(data['nome'] ?? 'Sem nome'),
                        subtitle: Text(
                          'Preço: ${_realFormat.format(data['preco_venda'] ?? 0)}',
                        ),
                        onTap: () {
                          _showQuantidadeDialog(context, doc.id, data);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuantidadeDialog(
      BuildContext context,
      String itemId,
      Map<String, dynamic> data,
      ) {
    final quantidadeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(data['nome'] ?? 'Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Preço unitário: ${_realFormat.format(data['preco_venda'] ?? 0)}'),
              const SizedBox(height: 16),
              TextField(
                controller: quantidadeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantidade',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                int quantidade = int.tryParse(quantidadeController.text) ?? 1;
                if (quantidade <= 0) quantidade = 1;

                Navigator.pop(context); // Fecha dialog de quantidade
                Navigator.pop(context, { // Fecha dialog de seleção e retorna item
                  'item_id': itemId,
                  'nome': data['nome'],
                  'quantidade': quantidade,
                  'preco_unitario': data['preco_venda'] ?? 0,
                });
              },
              child: const Text('Adicionar'),
            ),
          ],
        );
      },
    );
  }
}