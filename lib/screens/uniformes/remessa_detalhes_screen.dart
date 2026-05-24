import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uai_capoeira/services/uniformes_service.dart';
import 'package:uai_capoeira/services/remessa_service.dart';
import 'package:uai_capoeira/services/fornecedor_service.dart';
import 'package:uai_capoeira/screens/uniformes/screens/remessa_pdf_service.dart';
import 'pedido_card.dart';
import 'dialogs/pagamento_dialog.dart';

class RemessaDetalhesScreen extends StatefulWidget {
  final String remessaId;
  final Map<String, dynamic> remessaData;
  const RemessaDetalhesScreen({super.key, required this.remessaId, required this.remessaData});

  @override
  State<RemessaDetalhesScreen> createState() => _RemessaDetalhesScreenState();
}

class _RemessaDetalhesScreenState extends State<RemessaDetalhesScreen> {
  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final UniformesService _uniformesService = UniformesService();
  final RemessaService _remessaService = RemessaService();
  final FornecedorService _fornecedorService = FornecedorService();

  String? _fornecedorNome;
  bool _carregandoFornecedor = false;

  @override
  void initState() {
    super.initState();
    _carregarFornecedor();
  }

  Future<void> _carregarFornecedor() async {
    final fornecedorId = widget.remessaData['fornecedor_id'] as String?;
    if (fornecedorId == null) return;

    setState(() => _carregandoFornecedor = true);
    try {
      final doc = await _fornecedorService.getFornecedor(fornecedorId);
      if (doc.exists) {
        // 🔧 Conversão explícita para Map<String, dynamic>
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _fornecedorNome = data['nome'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar fornecedor: $e');
    } finally {
      if (mounted) setState(() => _carregandoFornecedor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.remessaData;
    return Scaffold(
      appBar: AppBar(
        title: Text(data['nome'] ?? 'Remessa'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'pdf_resumido') {
                await RemessaPdfService.gerarPdfResumido(widget.remessaId, data);
              } else if (value == 'pdf_completo') {
                await RemessaPdfService.gerarPdfCompleto(widget.remessaId, data);
              } else if (value == 'alterar_status') {
                _mostrarAlterarStatus();
              } else if (value == 'finalizar') {
                _finalizarRemessa();
              } else if (value == 'excluir') {
                _excluirRemessa();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf_resumido', child: Text('📄 PDF resumido (confecção)')),
              PopupMenuItem(value: 'pdf_completo', child: Text('📊 PDF completo (associação)')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'alterar_status', child: Text('🔄 Alterar status')),
              PopupMenuItem(value: 'finalizar', child: Text('✅ Finalizar remessa')),
              PopupMenuItem(value: 'excluir', child: Text('🗑️ Excluir remessa')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCabecalho(data),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _remessaService.getPedidosDaRemessa(widget.remessaId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final pedidos = snapshot.data!.docs;
                if (pedidos.isEmpty) {
                  return const Center(child: Text('Nenhum pedido vinculado'));
                }
                return ListView.builder(
                  itemCount: pedidos.length,
                  itemBuilder: (_, i) {
                    final pedidoData = pedidos[i].data() as Map<String, dynamic>;
                    final bool ehEstoque = pedidoData['tipo_estoque'] == true;

                    return Column(
                      children: [
                        if (ehEstoque)
                          Container(
                            color: Colors.amber.shade50,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.inventory_2, size: 16, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text('Item para estoque – será adicionado ao finalizar',
                                    style: TextStyle(fontSize: 11, color: Colors.amber.shade800)),
                              ],
                            ),
                          ),
                        PedidoCard(
                          docId: pedidos[i].id,
                          data: pedidoData,
                          realFormat: _realFormat,
                          onMarcarConfeccao: _marcarPedidoComoConfeccao,
                          onFinalizar: _marcarPedidoComoFinalizado,
                          onRegistrarPagamento: _registrarPagamentoPedido,
                          onTap: (id, d) {},
                        ),
                      ],
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

  Widget _buildCabecalho(Map<String, dynamic> data) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${data['status']}'.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (data['data_prevista'] != null)
              Text(
                  'Previsão: ${DateFormat('dd/MM/yyyy').format((data['data_prevista'] as Timestamp).toDate())}'),
            if (_fornecedorNome != null)
              Row(
                children: [
                  const Icon(Icons.business, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('Fornecedor: $_fornecedorNome'),
                ],
              ),
            if (_carregandoFornecedor)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(),
              ),
            if (data['observacoes'] != null && data['observacoes'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Obs: ${data['observacoes']}'),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Finalização com lógica de estoque integrada ─────────────
  Future<void> _finalizarRemessa() async {
    final todosPedidos = await FirebaseFirestore.instance
        .collection('pedidos_uniformes')
        .where('remessa_id', isEqualTo: widget.remessaId)
        .get();

    final pedidosAluno = <QueryDocumentSnapshot>[];
    final pedidosEstoque = <QueryDocumentSnapshot>[];
    for (var doc in todosPedidos.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['tipo_estoque'] == true) {
        pedidosEstoque.add(doc);
      } else {
        pedidosAluno.add(doc);
      }
    }

    bool todosAlunosOk = pedidosAluno.every((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return d['status'] == 'finalizado' && d['status_pagamento'] == 'pago';
    });

    if (!todosAlunosOk) {
      _mostrarDialogoPedidosPendentes();
      return;
    }

    final int qtdEstoque = pedidosEstoque.length;
    final String mensagem = qtdEstoque > 0
        ? 'Todos os pedidos de aluno estão finalizados. $qtdEstoque pedido(s) de estoque serão adicionados ao estoque. Deseja finalizar?'
        : 'Todos os pedidos estão finalizados e pagos. Deseja finalizar a remessa?';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Remessa'),
        content: Text(mensagem),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Finalizar')),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      for (var doc in pedidosEstoque) {
        final pedido = doc.data() as Map<String, dynamic>;
        final itens = pedido['itens'] as List? ?? [];
        for (var item in itens) {
          await _adicionarAoEstoque(item);
        }
        await doc.reference.delete();
      }

      await _remessaService.atualizarRemessa(widget.remessaId, {'status': 'finalizada'});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Remessa finalizada! ${qtdEstoque > 0 ? "$qtdEstoque itens de estoque adicionados." : ""}')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _adicionarAoEstoque(Map<String, dynamic> item) async {
    final nome = item['nome'] ?? 'Item sem nome';
    final tamanho = item['tamanho'] ?? 'Único';
    final quantidade = item['quantidade'] ?? 0;
    if (quantidade <= 0) return;

    final query = await FirebaseFirestore.instance
        .collection('uniformes_estoque')
        .where('nome', isEqualTo: nome)
        .where('tamanho', isEqualTo: tamanho)
        .where('status', isEqualTo: 'ativo')
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      await query.docs.first.reference.update({
        'quantidade': FieldValue.increment(quantidade),
      });
    } else {
      await FirebaseFirestore.instance.collection('uniformes_estoque').add({
        'nome': nome,
        'tamanho': tamanho,
        'quantidade': quantidade,
        'preco_venda': item['preco_unitario'] ?? 0,
        'preco_custo': 0,
        'categoria': 'Geral',
        'controla_estoque': true,
        'status': 'ativo',
        'fornecedor': '',
        'descricao': 'Adicionado via remessa ${widget.remessaData['nome']}',
        'possui_variacoes': false,
        'tipo': 'base',
      });
    }
  }

  void _mostrarDialogoPedidosPendentes() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ação não permitida'),
        content: const Text(
            'Todos os pedidos com aluno devem estar finalizados e pagos antes de finalizar a remessa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendi')),
        ],
      ),
    );
  }

  void _mostrarAlterarStatus() {
    final statusAtual = (widget.remessaData['status'] as String?) ?? 'pendente';
    showDialog(
      context: context,
      builder: (ctx) {
        String novoStatus = statusAtual;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Alterar status da remessa'),
              content: DropdownButtonFormField<String>(
                value: novoStatus,
                items: const [
                  DropdownMenuItem(value: 'pendente', child: Text('Pendente')),
                  DropdownMenuItem(value: 'em_producao', child: Text('Em produção')),
                  DropdownMenuItem(value: 'finalizada', child: Text('Finalizada')),
                  DropdownMenuItem(value: 'cancelada', child: Text('Cancelada')),
                ],
                onChanged: (v) => setState(() => novoStatus = v!),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _alterarStatusRemessa(novoStatus);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _alterarStatusRemessa(String novoStatus) async {
    try {
      if (novoStatus == 'em_producao') {
        final pedidos = await FirebaseFirestore.instance
            .collection('pedidos_uniformes')
            .where('remessa_id', isEqualTo: widget.remessaId)
            .get();
        for (var doc in pedidos.docs) {
          await doc.reference.update({'status': 'em_confeccao'});
        }
      }
      await _remessaService.atualizarRemessa(widget.remessaId, {'status': novoStatus});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status atualizado!')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _excluirRemessa() async {
    final pedidos = await FirebaseFirestore.instance
        .collection('pedidos_uniformes')
        .where('remessa_id', isEqualTo: widget.remessaId)
        .get();
    bool todosOk = pedidos.docs
        .where((doc) => (doc.data() as Map<String, dynamic>)['tipo_estoque'] != true)
        .every((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return d['status'] == 'finalizado' && d['status_pagamento'] == 'pago';
    });
    if (!todosOk) {
      _mostrarDialogoPedidosPendentes();
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Remessa'),
        content: const Text('Deseja excluir a remessa? Os pedidos não serão deletados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _remessaService.excluirRemessa(widget.remessaId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Remessa excluída!')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ─── Callbacks para os cards de pedido ────────────────────────
  Future<void> _marcarPedidoComoConfeccao(String docId, Map<String, dynamic> data) async {
    try {
      await _uniformesService.atualizarStatusPedido(docId, 'em_confeccao');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido em confecção'), backgroundColor: Colors.blue),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _marcarPedidoComoFinalizado(String docId, Map<String, dynamic> data) async {
    try {
      await _uniformesService.atualizarStatusPedido(docId, 'finalizado');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido finalizado'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _registrarPagamentoPedido(String docId, Map<String, dynamic> data) async {
    double total = (data['valor_total'] ?? 0).toDouble();
    double pago = (data['valor_pago'] ?? 0).toDouble();
    double restante = total - pago;
    if (restante <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido já pago!'), backgroundColor: Colors.orange),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => PagamentoDialog(
        alunoNome: data['aluno_nome'] ?? 'Aluno',
        valorTotal: total,
        valorPago: pago,
        valorRestante: restante,
        onConfirm: (valor, formaPagamento) async {
          try {
            await _uniformesService.registrarPagamentoPedido(
              pedidoId: docId,
              valorPagamento: valor,
              formaPagamento: formaPagamento,
              pedidoData: data,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pagamento registrado'), backgroundColor: Colors.green),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
            );
          }
        },
      ),
    );
  }
}