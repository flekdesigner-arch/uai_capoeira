import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/services/remessa_service.dart';
import 'package:uai_capoeira/services/uniformes_service.dart';

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
  final RemessaService _remessaService = RemessaService();
  final UniformesService _uniformesService = UniformesService();

  // Controladores existentes
  late TextEditingController _observacoesController;
  late TextEditingController _dataPrevisaoController;
  late String _status;
  late String _statusPagamento;
  late double _valorPago;
  late double _valorTotal;

  bool _isLoading = false;

  // Lista de itens editável
  List<Map<String, dynamic>> _itens = [];
  final Map<int, TextEditingController> _quantidadeControllers = {};

  // Remessa selecionada (opcional)
  String? _remessaId;
  String? _remessaNome;

  // Foto do aluno
  String? _fotoAlunoUrl;

  @override
  void initState() {
    super.initState();
    _observacoesController = TextEditingController(text: widget.pedidoData['observacoes'] ?? '');
    _dataPrevisaoController = TextEditingController(text: widget.pedidoData['data_previsao'] ?? '');
    _status = widget.pedidoData['status'] ?? 'pendente';
    _statusPagamento = widget.pedidoData['status_pagamento'] ?? 'pendente';
    _valorPago = (widget.pedidoData['valor_pago'] ?? 0).toDouble();
    _valorTotal = (widget.pedidoData['valor_total'] ?? 0).toDouble();

    _itens = List<Map<String, dynamic>>.from(widget.pedidoData['itens'] ?? []);

    // Remessa vinculada (se houver)
    _remessaId = widget.pedidoData['remessa_id'];
    if (_remessaId != null) {
      _carregarNomeRemessa();
    }

    // Buscar foto do aluno
    _carregarFotoAluno();

    // Criar controladores de quantidade
    for (int i = 0; i < _itens.length; i++) {
      _quantidadeControllers[i] = TextEditingController(
        text: _itens[i]['quantidade'].toString(),
      );
      _quantidadeControllers[i]!.addListener(() => _atualizarQuantidade(i));
    }
  }

  Future<void> _carregarNomeRemessa() async {
    if (_remessaId == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('remessas').doc(_remessaId!).get();
      if (doc.exists) {
        final data = doc.data()!;
        _remessaNome = data['nome'] ?? 'Remessa ${_remessaId!.substring(0, 5)}';
      }
    } catch (e) {
      debugPrint('Erro ao carregar nome da remessa: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _carregarFotoAluno() async {
    final alunoId = widget.pedidoData['aluno_id'] as String?;
    if (alunoId == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('alunos').doc(alunoId).get();
      if (doc.exists) {
        final data = doc.data()!;
        _fotoAlunoUrl = data['foto_perfil_aluno'] as String?;
      }
    } catch (e) {
      debugPrint('Erro ao carregar foto do aluno: $e');
    }
    if (mounted) setState(() {});
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
        title: const Text('Remover Item'),
        content: Text('Deseja remover "${_itens[index]['nome']}" do pedido?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              _quantidadeControllers[index]?.dispose();
              setState(() {
                _itens.removeAt(index);
                _calcularTotal();
                final novosControllers = <int, TextEditingController>{};
                for (int i = 0; i < _itens.length; i++) {
                  if (_quantidadeControllers.containsKey(i + 1)) {
                    novosControllers[i] = _quantidadeControllers[i + 1]!;
                  }
                }
                _quantidadeControllers.clear();
                _quantidadeControllers.addAll(novosControllers);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  Future<void> _selecionarItem() async {
    final itemSelecionado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const SelecionarItemPedidoDialog(),
    );

    if (itemSelecionado != null && mounted) {
      setState(() {
        final novoItem = {
          ...itemSelecionado,
          'quantidade': itemSelecionado['quantidade'] ?? 1,
        };
        _itens.add(novoItem);

        final novoIndex = _itens.length - 1;
        _quantidadeControllers[novoIndex] = TextEditingController(text: novoItem['quantidade'].toString());
        _quantidadeControllers[novoIndex]!.addListener(() => _atualizarQuantidade(novoIndex));

        _calcularTotal();
      });
    }
  }

  // 🔥 Selecionar/alterar remessa (CORRIGIDO)
  Future<void> _selecionarRemessa() async {
    final result = await showDialog<Map<String, dynamic>>( // ← Map<String, dynamic>
      context: context,
      builder: (_) => _SelecionarRemessaDialog(),
    );
    if (result != null && mounted) {
      setState(() {
        _remessaId = result['id'] as String?;
        _remessaNome = result['nome'] as String?;

        // Preencher data de previsão automaticamente se a remessa tiver data prevista
        final dataPrevista = result['data_prevista'] as Timestamp?;
        if (dataPrevista != null) {
          _dataPrevisaoController.text = DateFormat('dd/MM/yyyy', 'pt_BR').format(dataPrevista.toDate());
        }
      });
    }
  }

  void _removerRemessa() {
    setState(() {
      _remessaId = null;
      _remessaNome = null;
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
        _dataPrevisaoController.text = DateFormat('dd/MM/yyyy').format(data);
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
        'remessa_id': _remessaId,
        'ultima_edicao': FieldValue.serverTimestamp(),
        'editado_por': FirebaseAuth.instance.currentUser?.uid,
      };

      await FirebaseFirestore.instance
          .collection('pedidos_uniformes')
          .doc(widget.pedidoId)
          .update(dadosAtualizados);

      // Gerenciar vínculo com remessa (adicionar/remover)
      final remessaAtual = widget.pedidoData['remessa_id'];
      if (remessaAtual != _remessaId) {
        if (remessaAtual != null && remessaAtual.isNotEmpty) {
          await _remessaService.desvincularPedido(widget.pedidoId, remessaAtual);
        }
        if (_remessaId != null && _remessaId!.isNotEmpty) {
          await _remessaService.vincularPedido(widget.pedidoId, _remessaId!);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Pedido atualizado com sucesso!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro ao atualizar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alunoNome = widget.pedidoData['aluno_nome'] ?? 'Aluno não identificado';
    return Scaffold(
      appBar: AppBar(
        title: const Text('EDITAR PEDIDO'),
        backgroundColor: Colors.purple.shade900,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _salvar,
            icon: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save, color: Colors.white),
            label: Text(_isLoading ? 'SALVANDO...' : 'SALVAR', style: const TextStyle(color: Colors.white)),
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
            // Aluno
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _fotoAlunoUrl != null && _fotoAlunoUrl!.isNotEmpty
                        ? CachedNetworkImage(
                      imageUrl: _fotoAlunoUrl!,
                      imageBuilder: (ctx, imageProvider) => CircleAvatar(backgroundImage: imageProvider, radius: 20),
                      placeholder: (_, __) => const CircleAvatar(radius: 20, child: Icon(Icons.person)),
                      errorWidget: (_, __, ___) => const CircleAvatar(radius: 20, child: Icon(Icons.person)),
                    )
                        : const CircleAvatar(radius: 20, child: Icon(Icons.person, color: Colors.grey)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(alunoNome, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('Pedido: ${widget.pedidoData['id_pedido'] ?? 'N/I'}', style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Itens
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
                        IconButton(icon: const Icon(Icons.add_circle, color: Colors.purple), onPressed: _selecionarItem),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_itens.isEmpty)
                      const Center(child: Text('Nenhum item', style: TextStyle(color: Colors.grey)))
                    else
                      ..._itens.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        final tamanho = item['tamanho'] as String?;
                        final descricao = tamanho != null ? '${item['nome']} - Tam. $tamanho' : item['nome'];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(descricao ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text('Preço: ${_realFormat.format(item['preco_unitario'])}', style: TextStyle(color: Colors.purple.shade700, fontSize: 12)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 70,
                                child: TextFormField(
                                  controller: _quantidadeControllers[index],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'Qtd', isDense: true, border: OutlineInputBorder()),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(_realFormat.format(item['quantidade'] * item['preco_unitario'])),
                              IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _removerItem(index)),
                            ],
                          ),
                        );
                      }),
                    if (_itens.isNotEmpty) ...[
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(_realFormat.format(_valorTotal), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Remessa (opcional)
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('REMESSA (opcional)', style: TextStyle(fontWeight: FontWeight.bold)),
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
                            Expanded(child: Text(_remessaNome ?? 'Vincular a uma remessa', style: TextStyle(color: _remessaNome == null ? Colors.grey : Colors.black))),
                            if (_remessaId != null)
                              IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: _removerRemessa)
                            else
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

            // Status do Pedido
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'pendente', label: Text('Pendente'), icon: Icon(Icons.pending)),
                        ButtonSegment(value: 'em_confeccao', label: Text('Em Confecção'), icon: Icon(Icons.build)),
                        ButtonSegment(value: 'finalizado', label: Text('Finalizado'), icon: Icon(Icons.check_circle)),
                      ],
                      selected: {_status},
                      onSelectionChanged: (Set<String> selected) => setState(() => _status = selected.first),
                    ),
                    const SizedBox(height: 16),
                    const Text('PAGAMENTO', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'pendente', label: Text('Pendente'), icon: Icon(Icons.pending)),
                        ButtonSegment(value: 'pago', label: Text('Pago'), icon: Icon(Icons.check_circle)),
                        ButtonSegment(value: 'parcial', label: Text('Parcial'), icon: Icon(Icons.money_off)),
                      ],
                      selected: {_statusPagamento},
                      onSelectionChanged: (Set<String> selected) => setState(() => _statusPagamento = selected.first),
                    ),
                    if (_statusPagamento == 'parcial') ...[
                      const SizedBox(height: 12),
                      TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Valor pago', border: OutlineInputBorder(), prefixText: 'R\$ '),
                        onChanged: (v) => _valorPago = double.tryParse(v.replaceAll(',', '.')) ?? 0,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Previsão
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: InkWell(
                  onTap: _selecionarDataPrevisao,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Data de previsão'),
                    child: Text(_dataPrevisaoController.text.isEmpty ? 'Selecionar data' : _dataPrevisaoController.text),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Observações
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _observacoesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Observações', border: OutlineInputBorder()),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Diálogo para selecionar remessa (CORRIGIDO: retorna Map<String, dynamic>)
// ──────────────────────────────────────────────────────────────────────────────
class _SelecionarRemessaDialog extends StatefulWidget {
  @override
  State<_SelecionarRemessaDialog> createState() => _SelecionarRemessaDialogState();
}

class _SelecionarRemessaDialogState extends State<_SelecionarRemessaDialog> {
  String _search = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
              decoration: const InputDecoration(hintText: 'Pesquisar remessa...', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('remessas').orderBy('criado_em', descending: true).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  var docs = snapshot.data!.docs;
                  if (_search.isNotEmpty) {
                    docs = docs.where((d) {
                      final nome = (d.data() as Map<String, dynamic>)['nome'] ?? '';
                      return nome.toLowerCase().contains(_search);
                    }).toList();
                  }
                  if (docs.isEmpty) return const Center(child: Text('Nenhuma remessa encontrada'));
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      return ListTile(
                        leading: const Icon(Icons.local_shipping),
                        title: Text(data['nome'] ?? 'Sem nome'),
                        subtitle: Text('Status: ${data['status']}'),
                        onTap: () {
                          Navigator.pop(context, {
                            'id': docs[i].id,
                            'nome': data['nome'],
                            'data_prevista': data['data_prevista'], // Timestamp
                          });
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

// ──────────────────────────────────────────────────────────────────────────────
// Diálogo de seleção de item para pedido (com suporte a variações)
// (O restante permanece igual ao que já estava)
// ──────────────────────────────────────────────────────────────────────────────
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
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
                });
              },
              child: const Text('Adicionar'),
            ),
          ],
        );
      },
    );
  }

  void _mostrarDialogoVariacoes(BuildContext context, String baseId, Map<String, dynamic> baseData) {
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
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.purple.shade50,
                    child: Text(tamanho.toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  title: Text('Tamanho $tamanho'),
                  subtitle: Text('Estoque: $quantidadeEstoque un'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showQuantidadeDialog(context, snapshot.docs[i].id, variacao, tamanho: tamanho.toString());
                  },
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))],
        ),
      );
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar variações: $e')));
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
              leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
              actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))],
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
                stream: FirebaseFirestore.instance.collection('uniformes_estoque').where('status', isEqualTo: 'ativo').snapshots(),
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
                          Text(_searchQuery.isEmpty ? 'Nenhum item cadastrado' : 'Nenhum item encontrado', style: TextStyle(color: Colors.grey.shade600)),
                          const SizedBox(height: 8),
                          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
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
                          decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
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
                        trailing: possuiVariacoes ? const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey) : null,
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