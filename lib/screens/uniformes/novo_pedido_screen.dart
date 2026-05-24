import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/services/uniformes_service.dart';
import 'package:uai_capoeira/services/remessa_service.dart';
import 'package:uai_capoeira/services/fornecedor_service.dart';
import 'dialogs/selecionar_aluno_dialog.dart';

class NovoPedidoScreen extends StatefulWidget {
  const NovoPedidoScreen({super.key});

  @override
  State<NovoPedidoScreen> createState() => _NovoPedidoScreenState();
}

class _NovoPedidoScreenState extends State<NovoPedidoScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final UniformesService _uniformesService = UniformesService();
  final RemessaService _remessaService = RemessaService();
  final FornecedorService _fornecedorService = FornecedorService();
  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  String? _alunoSelecionadoId;
  String? _alunoSelecionadoNome;
  String? _fotoAlunoUrl;

  List<Map<String, dynamic>> _itensPedido = [];
  double _valorTotal = 0;

  final TextEditingController _observacoesController = TextEditingController();
  final TextEditingController _dataPrevisaoController = TextEditingController();

  bool _isLoading = false;

  String? _remessaId;
  String? _remessaNome;
  String? _fornecedorRemessa;

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
    final selecionado = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const SelecionarAlunoDialog(
        corTema: Colors.purple,
      ),
    );

    if (selecionado != null && mounted) {
      setState(() {
        _alunoSelecionadoId = selecionado['id'];
        _alunoSelecionadoNome = selecionado['nome'];
        _fotoAlunoUrl = selecionado['foto_url'];
      });
    }
  }

  void _limparAluno() {
    setState(() {
      _alunoSelecionadoId = null;
      _alunoSelecionadoNome = null;
      _fotoAlunoUrl = null;
    });
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

  Future<void> _selecionarRemessa() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SelecionarRemessaDialog(),
    );
    if (result != null && mounted) {
      setState(() {
        _remessaId = result['id'] as String?;
        _remessaNome = result['nome'] as String?;
        _fornecedorRemessa = result['fornecedor_nome'] as String?;

        final dataPrevista = result['data_prevista'];
        if (dataPrevista is Timestamp) {
          _dataPrevisaoController.text =
              DateFormat('dd/MM/yyyy', 'pt_BR').format(dataPrevista.toDate());
        } else if (dataPrevista is String && dataPrevista.isNotEmpty) {
          _dataPrevisaoController.text = dataPrevista;
        }
      });
    }
  }

  void _removerRemessa() {
    setState(() {
      _remessaId = null;
      _remessaNome = null;
      _fornecedorRemessa = null;
    });
  }

  Future<void> _salvarPedido() async {
    if (_remessaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione uma remessa para o pedido'),
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
      final bool ehEstoque = _alunoSelecionadoId == null;

      final dadosPedido = {
        'id_pedido': idPedido,
        'aluno_id': _alunoSelecionadoId ?? '',
        'aluno_nome': _alunoSelecionadoNome ?? 'Item para Estoque',
        'itens': _itensPedido,
        'valor_total': _valorTotal,
        'valor_pago': 0,
        'status': 'pendente',
        'status_pagamento': 'pendente',
        'data_previsao': _dataPrevisaoController.text,
        'observacoes': _observacoesController.text,
        'data_pedido': FieldValue.serverTimestamp(),
        'criado_por': currentUser?.uid,
        'remessa_id': _remessaId,
        'tipo_estoque': ehEstoque,
      };

      final pedidoIdCriado = await _uniformesService.criarPedido(dadosPedido);
      await _remessaService.vincularPedido(pedidoIdCriado, _remessaId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ehEstoque
                ? '✅ Pedido para estoque criado!'
                : '✅ Pedido $idPedido criado com sucesso!'),
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
    final bool semAluno = _alunoSelecionadoId == null;

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
                ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
            // REMESSA (obrigatória)
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: _remessaId == null ? Colors.red.shade50 : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_shipping, size: 18, color: Colors.brown),
                        const SizedBox(width: 8),
                        const Text('REMESSA (obrigatória)',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _selecionarRemessa,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.local_shipping, color: Colors.brown.shade300),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _remessaNome ?? 'Selecionar remessa',
                                style: TextStyle(
                                  color: _remessaNome == null ? Colors.red : Colors.black,
                                  fontWeight: _remessaNome == null ? FontWeight.normal : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (_remessaId != null)
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: _removerRemessa,
                                tooltip: 'Remover vínculo',
                              )
                            else
                              const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                    if (_remessaNome != null) ...[
                      const SizedBox(height: 4),
                      Text('O pedido será vinculado à remessa $_remessaNome.',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      if (_fornecedorRemessa != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.business, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text('Fornecedor: $_fornecedorRemessa',
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ALUNO (opcional)
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
                        const Text('ALUNO', style: TextStyle(fontWeight: FontWeight.bold)),
                        if (!semAluno)
                          TextButton.icon(
                            onPressed: _limparAluno,
                            icon: const Icon(Icons.clear, size: 16),
                            label: const Text('Remover', style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _selecionarAluno,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: semAluno ? Colors.amber.shade50 : null,
                        ),
                        child: Row(
                          children: [
                            if (semAluno)
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.inventory_2, color: Colors.amber.shade800, size: 20),
                              )
                            else if (_fotoAlunoUrl != null && _fotoAlunoUrl!.isNotEmpty)
                              CachedNetworkImage(
                                imageUrl: _fotoAlunoUrl!,
                                imageBuilder: (ctx, imageProvider) => CircleAvatar(
                                  backgroundImage: imageProvider,
                                  radius: 16,
                                ),
                                placeholder: (_, __) => CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.grey.shade200,
                                  child: const Icon(Icons.person, size: 18),
                                ),
                                errorWidget: (_, __, ___) => CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.grey.shade100,
                                  child: Icon(Icons.person, color: Colors.grey.shade600),
                                ),
                              )
                            else
                              Icon(Icons.person, color: Colors.grey.shade600),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                semAluno ? 'Item para Estoque (sem aluno)' : (_alunoSelecionadoNome ?? 'Selecionar aluno'),
                                style: TextStyle(
                                  color: semAluno
                                      ? Colors.amber.shade800
                                      : _alunoSelecionadoNome == null
                                      ? Colors.grey
                                      : Colors.black,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                    if (semAluno)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '⚠️ Pedido será marcado como item para estoque. Na finalização da remessa, será adicionado automaticamente.',
                          style: TextStyle(fontSize: 11, color: Colors.amber.shade800),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ITENS
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
                        const Text('ITENS DO PEDIDO', style: TextStyle(fontWeight: FontWeight.bold)),
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
                              Text('Nenhum item adicionado', style: TextStyle(color: Colors.grey.shade600)),
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
                          final tamanho = item['tamanho'] as String?;
                          final cor = item['cor'] as String?;
                          final String nomeExibicao = [
                            item['nome'] ?? 'Item',
                            if (tamanho != null && tamanho.isNotEmpty) 'Tam. $tamanho',
                            if (cor != null && cor.isNotEmpty) 'Cor: $cor',
                          ].join(' - ');
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
                            title: Text(nomeExibicao),
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
                        const Text('TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(
                          _realFormat.format(_valorTotal),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // INFORMAÇÕES ADICIONAIS
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('INFORMAÇÕES ADICIONAIS', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Divider(),
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
                              style: TextStyle(fontSize: 12, color: Colors.purple.shade700),
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ElevatedButton(
                onPressed: _salvarPedido,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _alunoSelecionadoId == null ? 'CRIAR ITEM PARA ESTOQUE' : 'CRIAR PEDIDO',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// DIÁLOGO DE SELEÇÃO DE REMESSA (com fornecedor)
// =============================================================================
class _SelecionarRemessaDialog extends StatefulWidget {
  @override
  State<_SelecionarRemessaDialog> createState() => _SelecionarRemessaDialogState();
}

class _SelecionarRemessaDialogState extends State<_SelecionarRemessaDialog> {
  String _search = '';
  final TextEditingController _searchController = TextEditingController();
  final FornecedorService _fornecedorService = FornecedorService();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String?> _getFornecedorNome(String? fornecedorId) async {
    if (fornecedorId == null) return null;
    final doc = await _fornecedorService.getFornecedor(fornecedorId);
    if (doc.exists) {
      return (doc.data() as Map<String, dynamic>)['nome'] as String?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Pesquisar remessa...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('remessas')
                    .orderBy('criado_em', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  var docs = snapshot.data!.docs;
                  if (_search.isNotEmpty) {
                    docs = docs.where((d) {
                      final nome = (d.data() as Map<String, dynamic>)['nome'] ?? '';
                      return nome.toLowerCase().contains(_search);
                    }).toList();
                  }
                  if (docs.isEmpty) {
                    return const Center(child: Text('Nenhuma remessa encontrada'));
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      return FutureBuilder<String?>(
                        future: _getFornecedorNome(data['fornecedor_id']),
                        builder: (context, snap) {
                          final String? fornecedorNome = snap.data;
                          return ListTile(
                            leading: Icon(Icons.local_shipping, color: Colors.brown.shade300),
                            title: Text(data['nome'] ?? 'Sem nome'),
                            subtitle: Text(
                              'Status: ${data['status']}${fornecedorNome != null ? ' • Fornecedor: $fornecedorNome' : ''}',
                            ),
                            onTap: () {
                              Navigator.pop(context, {
                                'id': docs[i].id,
                                'nome': data['nome'],
                                'data_prevista': data['data_prevista'],
                                'fornecedor_nome': fornecedorNome,
                              });
                            },
                          );
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
}

// =============================================================================
// DIÁLOGO DE SELEÇÃO DE ITEM (COM VARIAÇÕES) – CORRIGIDO PARA HERDAR COR
// =============================================================================
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

  void _showQuantidadeDialog(
      BuildContext context,
      String itemId,
      Map<String, dynamic> data, {
        String? tamanho,
      }) {
    final quantidadeController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(data['nome'] ?? 'Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Preço unitário: ${_realFormat.format(data['preco_venda'] ?? 0)}'),
              if (tamanho != null) Text('Tamanho: $tamanho'),
              if (data['cor'] != null && data['cor'].toString().isNotEmpty)
                Text('Cor: ${data['cor']}'),
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                int quantidade = int.tryParse(quantidadeController.text) ?? 1;
                if (quantidade <= 0) quantidade = 1;

                Navigator.pop(ctx);
                Navigator.pop(context, {
                  'item_id': itemId,
                  'nome': data['nome'],
                  'tamanho': tamanho,
                  'quantidade': quantidade,
                  'preco_unitario': data['preco_venda'] ?? 0,
                  'cor': data['cor'] ?? '',   // 🔥 HERDA A COR
                });
              },
              child: const Text('Adicionar'),
            ),
          ],
        );
      },
    );
  }

  void _mostrarDialogoVariacoes(
      BuildContext context,
      String baseId,
      Map<String, dynamic> baseData,
      ) {
    FirebaseFirestore.instance
        .collection('uniformes_estoque')
        .where('item_base_id', isEqualTo: baseId)
        .get()
        .then((snapshot) {
      if (!mounted) return;

      if (snapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma variação encontrada para este item')),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Tamanhos disponíveis - ${baseData['nome']}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: snapshot.docs.length,
              itemBuilder: (_, i) {
                final variacao = snapshot.docs[i].data();
                final tamanho = variacao['tamanho'] ?? '?';
                final quantidadeEstoque = variacao['quantidade'] ?? 0;
                final cor = variacao['cor']?.toString() ?? '';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.purple.shade50,
                    child: Text(
                      tamanho.toString().toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text('Tamanho $tamanho'),
                  subtitle: Text('Estoque: $quantidadeEstoque un${cor.isNotEmpty ? ' - Cor: $cor' : ''}'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showQuantidadeDialog(
                      context,
                      snapshot.docs[i].id,
                      variacao,  // 🔥 já contém o campo 'cor'
                      tamanho: tamanho.toString(),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar variações: $e')),
        );
      }
    });
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                  var docs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final tipo = data['tipo'] as String?;
                    return (tipo == null || tipo == 'base');
                  }).toList();

                  if (_searchQuery.isNotEmpty) {
                    docs = docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final nome = data['nome']?.toString().toLowerCase() ?? '';
                      return nome.contains(_searchQuery.toLowerCase());
                    }).toList();
                  }

                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 50, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty ? 'Nenhum item cadastrado' : 'Nenhum item encontrado',
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
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      var doc = docs[index];
                      var data = doc.data() as Map<String, dynamic>;
                      final bool possuiVariacoes = data['possui_variacoes'] == true;
                      final String? fotoUrl = data['foto_url'];

                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: fotoUrl != null && fotoUrl.isNotEmpty
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: fotoUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const Icon(Icons.shopping_bag, color: Colors.purple),
                              errorWidget: (_, __, ___) => const Icon(Icons.shopping_bag, color: Colors.purple),
                            ),
                          )
                              : const Icon(Icons.shopping_bag, color: Colors.purple),
                        ),
                        title: Text(data['nome'] ?? 'Sem nome'),
                        subtitle: Text('Preço: ${_realFormat.format(data['preco_venda'] ?? 0)}'),
                        trailing: possuiVariacoes
                            ? const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey)
                            : null,
                        onTap: () {
                          if (possuiVariacoes) {
                            _mostrarDialogoVariacoes(context, doc.id, data);
                          } else {
                            _showQuantidadeDialog(context, doc.id, data);
                          }
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
}