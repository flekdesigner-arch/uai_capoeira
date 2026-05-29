import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/uniformes/services/uniformes_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/remessa_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/fornecedor_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/remessa_pdf_service.dart';
import 'package:uai_capoeira/modules/uniformes/widgets/pedido_card.dart';
import 'package:uai_capoeira/modules/uniformes/dialogs/pagamento_dialog.dart';

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

  // Helpers de contraste
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

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
    final primary = context.uai.primary;
    final onPrimary = _readableOn(primary);
    final textPrimary = context.uai.textPrimary;
    final textSecondary = context.uai.textSecondary;
    final textMuted = context.uai.textMuted;
    final warning = context.uai.warning;
    final error = context.uai.error;
    final success = context.uai.success;
    final info = context.uai.info;
    final cardBg = context.uai.card;
    final border = context.uai.border;
    final cardAlt = context.uai.cardAlt;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(data['nome'] ?? 'Remessa',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: onPrimary),
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
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pdf_resumido',
                child: Text('📄 PDF resumido (confecção)',
                    style: TextStyle(color: textPrimary)),
              ),
              PopupMenuItem(
                value: 'pdf_completo',
                child: Text('📊 PDF completo (associação)',
                    style: TextStyle(color: textPrimary)),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'alterar_status',
                child: Text('🔄 Alterar status',
                    style: TextStyle(color: textPrimary)),
              ),
              PopupMenuItem(
                value: 'finalizar',
                child: Text('✅ Finalizar remessa',
                    style: TextStyle(color: textPrimary)),
              ),
              PopupMenuItem(
                value: 'excluir',
                child: Text('🗑️ Excluir remessa',
                    style: TextStyle(color: error)),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCabecalho(data, primary, textPrimary, textSecondary, textMuted, cardBg, border, cardAlt, warning, error, info),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _remessaService.getPedidosDaRemessa(widget.remessaId),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return Center(child: CircularProgressIndicator(color: primary));
                final pedidos = snapshot.data!.docs;
                if (pedidos.isEmpty) {
                  return Center(
                    child: Text('Nenhum pedido vinculado',
                        style: TextStyle(color: textMuted)),
                  );
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
                            color: warning.withOpacity(0.1),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inventory_2, size: 16, color: warning),
                                const SizedBox(width: 4),
                                Text(
                                  'Item para estoque – será adicionado ao finalizar',
                                  style: TextStyle(fontSize: 11, color: warning),
                                ),
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

  Widget _buildCabecalho(
      Map<String, dynamic> data,
      Color primary,
      Color textPrimary,
      Color textSecondary,
      Color textMuted,
      Color cardBg,
      Color border,
      Color cardAlt,
      Color warning,
      Color error,
      Color info,
      ) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        border: Border.all(color: border),
        boxShadow: context.uai.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status: ${data['status']}'.toUpperCase(),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: textPrimary),
          ),
          const SizedBox(height: 4),
          if (data['data_prevista'] != null)
            Text(
              'Previsão: ${DateFormat('dd/MM/yyyy').format((data['data_prevista'] as Timestamp).toDate())}',
              style: TextStyle(color: textSecondary),
            ),
          if (_fornecedorNome != null)
            Row(
              children: [
                Icon(Icons.business, size: 16, color: textMuted),
                const SizedBox(width: 4),
                Text('Fornecedor: $_fornecedorNome',
                    style: TextStyle(color: textPrimary)),
              ],
            ),
          if (_carregandoFornecedor)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(color: primary),
            ),
          if (data['observacoes'] != null &&
              data['observacoes'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Obs: ${data['observacoes']}',
                  style: TextStyle(color: textSecondary)),
            ),
        ],
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
        title: Text('Finalizar Remessa',
            style: TextStyle(color: context.uai.textPrimary)),
        content: Text(mensagem,
            style: TextStyle(color: context.uai.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: TextStyle(color: context.uai.primary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.success,
              foregroundColor: _readableOn(context.uai.success),
            ),
            child: const Text('Finalizar'),
          ),
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
          SnackBar(
            content: Text(
              '✅ Remessa finalizada! ${qtdEstoque > 0 ? "$qtdEstoque itens de estoque adicionados." : ""}',
              style: TextStyle(color: _readableOn(context.uai.success)),
            ),
            backgroundColor: context.uai.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e',
                style: TextStyle(color: _readableOn(context.uai.error))),
            backgroundColor: context.uai.error,
          ),
        );
      }
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
        title: Text('Ação não permitida',
            style: TextStyle(color: context.uai.textPrimary)),
        content: Text(
            'Todos os pedidos com aluno devem estar finalizados e pagos antes de finalizar a remessa.',
            style: TextStyle(color: context.uai.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Entendi',
                style: TextStyle(color: context.uai.primary)),
          ),
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
              title: Text('Alterar status da remessa',
                  style: TextStyle(color: context.uai.textPrimary)),
              content: DropdownButtonFormField<String>(
                value: novoStatus,
                style: TextStyle(color: context.uai.textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: context.uai.cardAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.uai.inputRadius),
                    borderSide: BorderSide(color: context.uai.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.uai.inputRadius),
                    borderSide: BorderSide(color: context.uai.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.uai.inputRadius),
                    borderSide: BorderSide(color: context.uai.primary, width: 1.4),
                  ),
                ),
                dropdownColor: context.uai.card,
                items: const [
                  DropdownMenuItem(value: 'pendente', child: Text('Pendente')),
                  DropdownMenuItem(value: 'em_producao', child: Text('Em produção')),
                  DropdownMenuItem(value: 'finalizada', child: Text('Finalizada')),
                  DropdownMenuItem(value: 'cancelada', child: Text('Cancelada')),
                ],
                onChanged: (v) => setState(() => novoStatus = v!),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancelar',
                      style: TextStyle(color: context.uai.primary)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _alterarStatusRemessa(novoStatus);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.uai.primary,
                    foregroundColor: _readableOn(context.uai.primary),
                  ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status atualizado!',
                style: TextStyle(color: _readableOn(context.uai.success))),
            backgroundColor: context.uai.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e',
                style: TextStyle(color: _readableOn(context.uai.error))),
            backgroundColor: context.uai.error,
          ),
        );
      }
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
        title: Text('Excluir Remessa',
            style: TextStyle(color: context.uai.textPrimary)),
        content: Text('Deseja excluir a remessa? Os pedidos não serão deletados.',
            style: TextStyle(color: context.uai.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: TextStyle(color: context.uai.primary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: _readableOn(context.uai.error),
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _remessaService.excluirRemessa(widget.remessaId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Remessa excluída!',
                style: TextStyle(color: _readableOn(context.uai.success))),
            backgroundColor: context.uai.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e',
                style: TextStyle(color: _readableOn(context.uai.error))),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  // ─── Callbacks para os cards de pedido ────────────────────────
  Future<void> _marcarPedidoComoConfeccao(String docId, Map<String, dynamic> data) async {
    try {
      await _uniformesService.atualizarStatusPedido(docId, 'em_confeccao');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pedido em confecção',
                style: TextStyle(color: _readableOn(context.uai.info))),
            backgroundColor: context.uai.info,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e',
                style: TextStyle(color: _readableOn(context.uai.error))),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  Future<void> _marcarPedidoComoFinalizado(String docId, Map<String, dynamic> data) async {
    try {
      await _uniformesService.atualizarStatusPedido(docId, 'finalizado');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pedido finalizado',
                style: TextStyle(color: _readableOn(context.uai.success))),
            backgroundColor: context.uai.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e',
                style: TextStyle(color: _readableOn(context.uai.error))),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  Future<void> _registrarPagamentoPedido(String docId, Map<String, dynamic> data) async {
    double total = (data['valor_total'] ?? 0).toDouble();
    double pago = (data['valor_pago'] ?? 0).toDouble();
    double restante = total - pago;
    if (restante <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pedido já pago!',
              style: TextStyle(color: _readableOn(context.uai.warning))),
          backgroundColor: context.uai.warning,
        ),
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
                SnackBar(
                  content: Text('Pagamento registrado',
                      style: TextStyle(color: _readableOn(context.uai.success))),
                  backgroundColor: context.uai.success,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Erro: $e',
                      style: TextStyle(color: _readableOn(context.uai.error))),
                  backgroundColor: context.uai.error,
                ),
              );
            }
          }
        },
      ),
    );
  }
}