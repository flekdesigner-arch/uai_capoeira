import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uai_capoeira/services/uniformes_service.dart';
import 'package:uai_capoeira/services/remessa_service.dart';
import 'package:uai_capoeira/screens/uniformes/screens/remessa_pdf_service.dart';
import 'pedido_card.dart';
import 'dialogs/pagamento_dialog.dart';
import 'dialogs/selecionar_aluno_dialog.dart';

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

  @override
  Widget build(BuildContext context) {
    final data = widget.remessaData;
    final itensEstoque = (data['itens_estoque'] as List?)
        ?.map((e) => Map<String, dynamic>.from(e))
        .toList() ??
        [];

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
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Pedidos vinculados
                  StreamBuilder<QuerySnapshot>(
                    stream: _remessaService.getPedidosDaRemessa(widget.remessaId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final pedidos = snapshot.data!.docs;
                      if (pedidos.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Nenhum pedido vinculado'),
                        );
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: pedidos.length,
                        itemBuilder: (_, i) {
                          final pedidoData = pedidos[i].data() as Map<String, dynamic>;
                          return PedidoCard(
                            docId: pedidos[i].id,
                            data: pedidoData,
                            realFormat: _realFormat,
                            onMarcarConfeccao: _marcarPedidoComoConfeccao,
                            onFinalizar: _marcarPedidoComoFinalizado,
                            onRegistrarPagamento: _registrarPagamentoPedido,
                            onTap: (id, d) {},
                          );
                        },
                      );
                    },
                  ),
                  // Itens de estoque
                  if (itensEstoque.isNotEmpty) ...[
                    const Divider(thickness: 2),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Itens para estoque',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green.shade800),
                      ),
                    ),
                    ...itensEstoque.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: ListTile(
                          title: Text('${item['nome']} (${item['tamanho'] ?? 'Único'})'),
                          subtitle: Text(
                              'Qtd: ${item['quantidade']} - R\$ ${(item['preco_venda'] ?? 0).toStringAsFixed(2)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                onPressed: () => _atribuirItemEstoque(index, item, itensEstoque),
                                icon: const Icon(Icons.person_add, size: 18),
                                label: const Text('Atribuir'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  final confirmar = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Remover item'),
                                      content: const Text('Remover este item do estoque da remessa?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
                                      ],
                                    ),
                                  );
                                  if (confirmar == true) {
                                    itensEstoque.removeAt(index);
                                    await _remessaService.atualizarRemessa(
                                      widget.remessaId,
                                      {'itens_estoque': itensEstoque},
                                    );
                                    setState(() {});
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
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
          children: [
            Text('Status: ${data['status']}'.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (data['data_prevista'] != null)
              Text(
                  'Previsão: ${DateFormat('dd/MM/yyyy').format((data['data_prevista'] as Timestamp).toDate())}'),
            if (data['observacoes'] != null) Text('Obs: ${data['observacoes']}'),
          ],
        ),
      ),
    );
  }

  // ─── Atribuir item de estoque a um aluno ─────────────────────
  Future<void> _atribuirItemEstoque(
      int index, Map<String, dynamic> item, List<Map<String, dynamic>> itensEstoque) async {
    final aluno = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const SelecionarAlunoDialog(corTema: Colors.purple),
    );
    if (aluno == null || !mounted) return;

    // Criar pedido com os dados do item
    final novoPedido = {
      'id_pedido': 'PED-ESTOQUE-${DateTime.now().millisecondsSinceEpoch}',
      'aluno_id': aluno['id'],
      'aluno_nome': aluno['nome'],
      'itens': [
        {
          'nome': item['nome'],
          'tamanho': item['tamanho'] ?? 'Único',
          'quantidade': item['quantidade'],
          'preco_unitario': item['preco_venda'] ?? 0,
          'cor': item['cor'] ?? '',
        }
      ],
      'valor_total': (item['quantidade'] * (item['preco_venda'] ?? 0)),
      'valor_pago': 0,
      'status': 'pendente',
      'status_pagamento': 'pendente',
      'remessa_id': widget.remessaId,
      'data_pedido': FieldValue.serverTimestamp(),
      'criado_por': FirebaseAuth.instance.currentUser?.uid,
    };

    try {
      final pedidoRef =
      await FirebaseFirestore.instance.collection('pedidos_uniformes').add(novoPedido);

      itensEstoque.removeAt(index);

      await _remessaService.atualizarRemessa(widget.remessaId, {
        'itens_estoque': itensEstoque,
        'pedidos_ids': FieldValue.arrayUnion([pedidoRef.id]),
      });

      await _remessaService.vincularPedido(pedidoRef.id, widget.remessaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item convertido em pedido para o aluno!')),
        );
        setState(() {});
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ─── Finalização com atualização de estoque ─────────────────
  Future<void> _finalizarRemessa() async {
    // Verificar pedidos normais
    final pedidos = await FirebaseFirestore.instance
        .collection('pedidos_uniformes')
        .where('remessa_id', isEqualTo: widget.remessaId)
        .get();
    bool todosOk = pedidos.docs.every((doc) {
      final d = doc.data();
      return d['status'] == 'finalizado' && d['status_pagamento'] == 'pago';
    });
    if (!todosOk) {
      _mostrarDialogoPedidosPendentes();
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Remessa'),
        content: const Text(
            'Todos os pedidos estão pagos e finalizados. Deseja finalizar e adicionar os itens de estoque?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Finalizar')),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final itensEstoque =
      List<Map<String, dynamic>>.from(widget.remessaData['itens_estoque'] ?? []);

      for (var item in itensEstoque) {
        // Procurar item existente no estoque com mesmo nome e tamanho
        final query = await FirebaseFirestore.instance
            .collection('uniformes_estoque')
            .where('nome', isEqualTo: item['nome'])
            .where('tamanho', isEqualTo: item['tamanho'] ?? 'Único')
            .where('status', isEqualTo: 'ativo')
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          await query.docs.first.reference.update({
            'quantidade': FieldValue.increment(item['quantidade']),
          });
        } else {
          // Criar novo item no estoque
          await FirebaseFirestore.instance.collection('uniformes_estoque').add({
            'nome': item['nome'],
            'tamanho': item['tamanho'] ?? 'Único',
            'quantidade': item['quantidade'],
            'preco_venda': item['preco_venda'] ?? 0,
            'preco_custo': (item['preco_venda'] != null)
                ? ((item['preco_venda'] as num) * 0.5)
                : 0,
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

      await _remessaService.atualizarRemessa(widget.remessaId, {'status': 'finalizada'});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Remessa finalizada e estoque atualizado!')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _mostrarDialogoPedidosPendentes() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ação não permitida'),
        content:
        const Text('Todos os pedidos devem estar finalizados e pagos antes de finalizar a remessa.'),
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
    bool todosOk = pedidos.docs.every((doc) {
      final d = doc.data();
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