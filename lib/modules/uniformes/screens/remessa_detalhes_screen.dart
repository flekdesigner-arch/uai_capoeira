import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/uniformes/services/uniformes_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/remessa_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/fornecedor_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/remessa_pdf_service.dart';
import 'package:uai_capoeira/modules/uniformes/widgets/pedido_card.dart';
import 'package:uai_capoeira/modules/uniformes/dialogs/pagamento_dialog.dart';
import 'package:uai_capoeira/modules/uniformes/screens/editar_pedido_screen.dart';
import 'package:uai_capoeira/modules/uniformes/screens/remessa_form_screen.dart';

class RemessaDetalhesScreen extends StatefulWidget {
  final String remessaId;
  final Map<String, dynamic> remessaData;
  final bool podeEditar;
  final bool podeExcluir;

  const RemessaDetalhesScreen({
    super.key,
    required this.remessaId,
    required this.remessaData,
    this.podeEditar = false,
    this.podeExcluir = false,
  });

  @override
  State<RemessaDetalhesScreen> createState() => _RemessaDetalhesScreenState();
}

class _RemessaDetalhesScreenState extends State<RemessaDetalhesScreen> {
  final NumberFormat _realFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
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
    final info = context.uai.info;
    final cardBg = context.uai.card;
    final border = context.uai.border;
    final cardAlt = context.uai.cardAlt;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(
          data['nome'] ?? 'Remessa',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: onPrimary),
            onSelected: (value) async {
              if (value == 'pdf_resumido') {
                await RemessaPdfService.gerarPdfResumido(
                  widget.remessaId,
                  data,
                );
              } else if (value == 'pdf_completo') {
                await RemessaPdfService.gerarPdfCompleto(
                  widget.remessaId,
                  data,
                );
              } else if (value == 'editar') {
                _editarRemessa();
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
                child: Text(
                  '📄 PDF resumido (confecção)',
                  style: TextStyle(color: textPrimary),
                ),
              ),
              PopupMenuItem(
                value: 'pdf_completo',
                child: Text(
                  '📊 PDF completo (associação)',
                  style: TextStyle(color: textPrimary),
                ),
              ),
              const PopupMenuDivider(),
              if (widget.podeEditar)
                PopupMenuItem(
                  value: 'editar',
                  child: Text(
                    '✏️ Editar remessa',
                    style: TextStyle(color: textPrimary),
                  ),
                ),
              PopupMenuItem(
                value: 'alterar_status',
                child: Text(
                  '🔄 Alterar status',
                  style: TextStyle(color: textPrimary),
                ),
              ),
              PopupMenuItem(
                value: 'finalizar',
                child: Text(
                  '✅ Finalizar remessa',
                  style: TextStyle(color: textPrimary),
                ),
              ),
              if (widget.podeExcluir)
                PopupMenuItem(
                  value: 'excluir',
                  child: Text(
                    '🗑️ Excluir remessa',
                    style: TextStyle(color: error),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCabecalho(
            data,
            primary,
            textPrimary,
            textSecondary,
            textMuted,
            cardBg,
            border,
            cardAlt,
            warning,
            error,
            info,
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _remessaService.getPedidosDaRemessa(widget.remessaId),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  { return Center(
                    child: CircularProgressIndicator(color: primary),
                  ); }
                final pedidos = snapshot.data!.docs;
                if (pedidos.isEmpty) {
                  return Center(
                    child: Text(
                      'Nenhum pedido vinculado',
                      style: TextStyle(color: textMuted),
                    ),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final colunas = width >= 1700
                        ? 4
                        : width >= 1250
                            ? 3
                            : width >= 900
                                ? 2
                                : 1;

                    Widget buildPedido(QueryDocumentSnapshot pedido) {
                      final pedidoData =
                          pedido.data() as Map<String, dynamic>;
                      final bool ehEstoque =
                          pedidoData['tipo_estoque'] == true;

                      final card = PedidoCard(
                        docId: pedido.id,
                        data: pedidoData,
                        realFormat: _realFormat,
                        onMarcarConfeccao: _marcarPedidoComoConfeccao,
                        onFinalizar: _marcarPedidoComoFinalizado,
                        onRegistrarPagamento: _registrarPagamentoPedido,
                        onEditar: widget.podeEditar ? _editarPedido : null,
                        onExcluir: widget.podeExcluir ? _excluirPedido : null,
                        podeEditar: widget.podeEditar,
                        podeExcluir: widget.podeExcluir,
                        podeRegistrarPagamento: widget.podeEditar,
                        podeAlterarStatus: widget.podeEditar,
                        onTap: (id, d) {},
                      );

                      if (!ehEstoque) return card;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: warning.withAlpha(26),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.inventory_2_rounded,
                                  size: 14,
                                  color: warning,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    'Item para estoque • entra ao finalizar',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: warning,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          card,
                        ],
                      );
                    }

                    if (colunas == 1) {
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: pedidos.length,
                        itemBuilder: (_, i) => buildPedido(pedidos[i]),
                      );
                    }

                    const spacing = 12.0;
                    final maxWidth = width >= 1700
                        ? 1500.0
                        : width >= 1250
                            ? 1220.0
                            : 920.0;
                    final contentWidth =
                        width < maxWidth ? width : maxWidth;
                    final cardWidth =
                        (contentWidth -
                                24 -
                                (spacing * (colunas - 1))) /
                            colunas;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            alignment: WrapAlignment.start,
                            children: pedidos.map((pedido) {
                              return SizedBox(
                                width: cardWidth,
                                child: buildPedido(pedido),
                              );
                            }).toList(),
                          ),
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
    final pedidosIds = (data['pedidos_ids'] as List?) ?? const [];
    final status = (data['status'] ?? 'pendente').toString();
    final statusColor = switch (status) {
      'finalizada' => context.uai.success,
      'em_producao' => info,
      'cancelada' => error,
      _ => warning,
    };
    final statusLabel = switch (status) {
      'finalizada' => 'Finalizada',
      'em_producao' => 'Em produção',
      'cancelada' => 'Cancelada',
      _ => 'Pendente',
    };

    Widget metric({
      required IconData icon,
      required String label,
      required String value,
      required Color color,
    }) {
      return Container(
        constraints: const BoxConstraints(minWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: cardAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha(31),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 650;

        Widget compactMetric({
          required IconData icon,
          required String label,
          required String value,
          required Color color,
        }) {
          return Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: cardAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color.withAlpha(31),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 14, color: color),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 8.8,
                            color: textMuted,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.7,
                            fontWeight: FontWeight.w900,
                            color: textPrimary,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (compacto) {
          return Container(
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(context.uai.cardRadius),
              border: Border.all(color: border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data['nome'] ?? 'Remessa',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(31),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    compactMetric(
                      icon: Icons.shopping_bag_rounded,
                      label: 'Pedidos',
                      value: '${pedidosIds.length}',
                      color: primary,
                    ),
                    const SizedBox(width: 6),
                    compactMetric(
                      icon: Icons.event_available_rounded,
                      label: 'Previsão',
                      value: data['data_prevista'] != null
                          ? DateFormat('dd/MM/yyyy').format(
                              (data['data_prevista'] as Timestamp).toDate(),
                            )
                          : 'Não informada',
                      color: info,
                    ),
                    const SizedBox(width: 6),
                    compactMetric(
                      icon: Icons.business_rounded,
                      label: 'Fornecedor',
                      value: _carregandoFornecedor
                          ? '...'
                          : (_fornecedorNome ?? 'Não informado'),
                      color: warning,
                    ),
                  ],
                ),
                if (_carregandoFornecedor) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    minHeight: 2,
                    color: primary,
                  ),
                ],
                if (data['observacoes'] != null &&
                    data['observacoes'].toString().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(
                        Icons.sticky_note_2_rounded,
                        size: 14,
                        color: textMuted,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          data['observacoes'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
            border: Border.all(color: border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['nome'] ?? 'Remessa',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withAlpha(31),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.flag_circle_rounded,
                                size: 14,
                                color: statusColor,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (data['observacoes'] != null &&
                            data['observacoes'].toString().isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              data['observacoes'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    Expanded(
                      child: metric(
                        icon: Icons.shopping_bag_rounded,
                        label: 'Pedidos vinculados',
                        value: '${pedidosIds.length}',
                        color: primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: metric(
                        icon: Icons.event_available_rounded,
                        label: 'Previsão',
                        value: data['data_prevista'] != null
                            ? DateFormat('dd/MM/yyyy').format(
                                (data['data_prevista'] as Timestamp).toDate(),
                              )
                            : 'Não informada',
                        color: info,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: metric(
                        icon: Icons.business_rounded,
                        label: 'Fornecedor',
                        value: _carregandoFornecedor
                            ? 'Carregando...'
                            : (_fornecedorNome ?? 'Não informado'),
                        color: warning,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
      final data = doc.data();
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
        title: Text(
          'Finalizar Remessa',
          style: TextStyle(color: context.uai.textPrimary),
        ),
        content: Text(
          mensagem,
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: context.uai.primary),
            ),
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

      await _remessaService.atualizarRemessa(widget.remessaId, {
        'status': 'finalizada',
      });

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
            content: Text(
              'Erro: $e',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
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
        title: Text(
          'Ação não permitida',
          style: TextStyle(color: context.uai.textPrimary),
        ),
        content: Text(
          'Todos os pedidos com aluno devem estar finalizados e pagos antes de finalizar a remessa.',
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Entendi',
              style: TextStyle(color: context.uai.primary),
            ),
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
              title: Text(
                'Alterar status da remessa',
                style: TextStyle(color: context.uai.textPrimary),
              ),
              content: DropdownButtonFormField<String>(
                initialValue: novoStatus,
                style: TextStyle(color: context.uai.textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: context.uai.cardAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      context.uai.inputRadius,
                    ),
                    borderSide: BorderSide(color: context.uai.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      context.uai.inputRadius,
                    ),
                    borderSide: BorderSide(color: context.uai.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      context.uai.inputRadius,
                    ),
                    borderSide: BorderSide(
                      color: context.uai.primary,
                      width: 1.4,
                    ),
                  ),
                ),
                dropdownColor: context.uai.card,
                items: const [
                  DropdownMenuItem(value: 'pendente', child: Text('Pendente')),
                  DropdownMenuItem(
                    value: 'em_producao',
                    child: Text('Em produção'),
                  ),
                  DropdownMenuItem(
                    value: 'finalizada',
                    child: Text('Finalizada'),
                  ),
                  DropdownMenuItem(
                    value: 'cancelada',
                    child: Text('Cancelada'),
                  ),
                ],
                onChanged: (v) => setState(() => novoStatus = v!),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(color: context.uai.primary),
                  ),
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
      await _remessaService.atualizarRemessa(widget.remessaId, {
        'status': novoStatus,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Status atualizado!',
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
            content: Text(
              'Erro: $e',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
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
        .where(
          (doc) => (doc.data())['tipo_estoque'] != true,
        )
        .every((doc) {
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
        title: Text(
          'Excluir Remessa',
          style: TextStyle(color: context.uai.textPrimary),
        ),
        content: Text(
          'Deseja excluir a remessa? Os pedidos não serão deletados.',
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: context.uai.primary),
            ),
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
            content: Text(
              'Remessa excluída!',
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
            content: Text(
              'Erro: $e',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  // ─── Callbacks para os cards de pedido ────────────────────────
  Future<void> _marcarPedidoComoConfeccao(
    String docId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _uniformesService.atualizarStatusPedido(docId, 'em_confeccao');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pedido em confecção',
              style: TextStyle(color: _readableOn(context.uai.info)),
            ),
            backgroundColor: context.uai.info,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro: $e',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  Future<void> _marcarPedidoComoFinalizado(
    String docId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _uniformesService.atualizarStatusPedido(docId, 'finalizado');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pedido finalizado',
              style: TextStyle(color: _readableOn(context.uai.success)),
            ),
            backgroundColor: context.uai.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro: $e',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

    Future<void> _editarRemessa() async {
    if (!widget.podeEditar) return;

    final doc = await FirebaseFirestore.instance
        .collection('remessas')
        .doc(widget.remessaId)
        .get();

    final atual = doc.data() ?? widget.remessaData;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemessaFormScreen(
          remessaId: widget.remessaId,
          remessaData: atual,
        ),
      ),
    );

    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _editarPedido(
    String docId,
    Map<String, dynamic> data,
  ) async {
    if (!widget.podeEditar) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditarPedidoScreen(
          pedidoId: docId,
          pedidoData: data,
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido atualizado!',
            style: TextStyle(color: _readableOn(context.uai.success)),
          ),
          backgroundColor: context.uai.success,
        ),
      );
    }
  }

  Future<void> _excluirPedido(
    String docId,
    Map<String, dynamic> data,
  ) async {
    if (!widget.podeExcluir) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Excluir pedido',
          style: TextStyle(color: context.uai.textPrimary),
        ),
        content: Text(
          'Excluir definitivamente o pedido de '
          '${data['aluno_nome'] ?? 'aluno não identificado'}?',
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
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
      await _remessaService.excluirPedidoDefinitivamente(
        docId,
        remessaId: widget.remessaId,
      );

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pedido excluído.',
              style: TextStyle(color: _readableOn(context.uai.success)),
            ),
            backgroundColor: context.uai.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível excluir o pedido agora.',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

Future<void> _registrarPagamentoPedido(
    String docId,
    Map<String, dynamic> data,
  ) async {
    double total = (data['valor_total'] ?? 0).toDouble();
    double pago = (data['valor_pago'] ?? 0).toDouble();
    double restante = total - pago;
    if (restante <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido já pago!',
            style: TextStyle(color: _readableOn(context.uai.warning)),
          ),
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
                  content: Text(
                    'Pagamento registrado',
                    style: TextStyle(color: _readableOn(context.uai.success)),
                  ),
                  backgroundColor: context.uai.success,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Erro: $e',
                    style: TextStyle(color: _readableOn(context.uai.error)),
                  ),
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
