import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/uniformes/dialogs/selecionar_item_dialog.dart';

class EditarVendaScreen extends StatefulWidget {
  final String vendaId;
  final Map<String, dynamic> vendaData;

  const EditarVendaScreen({
    super.key,
    required this.vendaId,
    required this.vendaData,
  });

  @override
  State<EditarVendaScreen> createState() => _EditarVendaScreenState();
}

class _EditarVendaScreenState extends State<EditarVendaScreen> {
  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  late TextEditingController _observacoesController;
  late String _statusPagamento;
  late double _valorPago;
  late double _valorTotal;
  bool _isLoading = false;

  List<Map<String, dynamic>> _itens = [];
  final Map<int, TextEditingController> _quantidadeControllers = {};

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
    _observacoesController = TextEditingController(text: widget.vendaData['observacoes'] ?? '');
    _statusPagamento = widget.vendaData['status_pagamento'] ?? 'pendente';
    _valorPago = (widget.vendaData['valor_pago'] ?? 0).toDouble();
    _valorTotal = (widget.vendaData['valor_total'] ?? 0).toDouble();

    _itens = List<Map<String, dynamic>>.from(widget.vendaData['itens'] ?? []);

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
      builder: (ctx) => AlertDialog(
        title: Text('🗑️ Remover Item', style: TextStyle(color: context.uai.textPrimary)),
        content: Text(
          'Deseja remover "${_itens[index]['nome']}" da venda?',
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCELAR', style: TextStyle(color: context.uai.primary)),
          ),
          ElevatedButton(
            onPressed: () {
              _quantidadeControllers[index]?.dispose();

              setState(() {
                _itens.removeAt(index);
                _calcularTotal();

                final novosControllers = <int, TextEditingController>{};
                for (int i = 0; i < _itens.length; i++) {
                  novosControllers[i] = _quantidadeControllers[i + 1]!;
                }
                _quantidadeControllers.clear();
                _quantidadeControllers.addAll(novosControllers);
              });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: _readableOn(context.uai.error),
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
          'quantidade': 1,
        };
        _itens.add(novoItem);

        final novoIndex = _itens.length - 1;
        _quantidadeControllers[novoIndex] = TextEditingController(text: '1');
        _quantidadeControllers[novoIndex]!.addListener(() => _atualizarQuantidade(novoIndex));

        _calcularTotal();
      });
    }
  }

  Future<void> _salvar() async {
    setState(() => _isLoading = true);

    try {
      Map<String, dynamic> dadosAtualizados = {
        'itens': _itens,
        'observacoes': _observacoesController.text,
        'status_pagamento': _statusPagamento,
        'valor_total': _valorTotal,
        'valor_pago': _statusPagamento == 'pago' ? _valorTotal : _valorPago,
        'ultima_edicao': FieldValue.serverTimestamp(),
        'editado_por': FirebaseAuth.instance.currentUser?.uid,
      };

      await FirebaseFirestore.instance
          .collection('vendas_uniformes')
          .doc(widget.vendaId)
          .update(dadosAtualizados);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Venda atualizada com sucesso!',
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
              '❌ Erro ao atualizar: $e',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.uai.primary;
    final onPrimary = _readableOn(primary);
    final cardBg = context.uai.card;
    final border = context.uai.border;
    final textPrimary = context.uai.textPrimary;
    final textSecondary = context.uai.textSecondary;
    final textMuted = context.uai.textMuted;
    final cardAlt = context.uai.cardAlt;
    final success = context.uai.success;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: const Text('EDITAR VENDA',
            style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _salvar,
            icon: _isLoading
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: onPrimary, strokeWidth: 2),
            )
                : Icon(Icons.save, color: onPrimary),
            label: Text(
              _isLoading ? 'SALVANDO...' : 'SALVAR',
              style: TextStyle(color: onPrimary),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primary))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Informações do Aluno
            Container(
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
                  Row(
                    children: [
                      Icon(Icons.person, color: primary),
                      const SizedBox(width: 8),
                      Text(
                        'ALUNO',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.vendaData['aluno_nome'] ?? 'Aluno não identificado',
                    style: TextStyle(fontSize: 16, color: textPrimary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Itens da Venda (EDITÁVEL!)
            Container(
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shopping_bag, color: success),
                          const SizedBox(width: 8),
                          Text(
                            'ITENS',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.add_circle, color: success),
                        onPressed: _selecionarItem,
                        tooltip: 'Adicionar item',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  ..._itens.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cardAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: border),
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
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Preço unitário: ${_realFormat.format(item['preco_unitario'])}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: success,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, color: context.uai.error, size: 20),
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
                                  style: TextStyle(color: textPrimary),
                                  decoration: InputDecoration(
                                    labelText: 'Quantidade',
                                    labelStyle: TextStyle(color: textSecondary),
                                    filled: true,
                                    fillColor: cardBg,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: border),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: border),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: success, width: 1.4),
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
                                    color: success.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Subtotal',
                                        style: TextStyle(fontSize: 10, color: textSecondary),
                                      ),
                                      Text(
                                        _realFormat.format(
                                            item['quantidade'] * item['preco_unitario']),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: success,
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

                  Divider(color: border),

                  // Total
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'TOTAL',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        _realFormat.format(_valorTotal),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: success,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Status do Pagamento
            Container(
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
                  Row(
                    children: [
                      Icon(Icons.payment, color: context.uai.warning),
                      const SizedBox(width: 8),
                      Text(
                        'STATUS DO PAGAMENTO',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'pendente',
                        label: Text('Pendente', style: TextStyle(color: textPrimary)),
                        icon: Icon(Icons.pending, color: context.uai.warning),
                      ),
                      ButtonSegment(
                        value: 'pago',
                        label: Text('Pago', style: TextStyle(color: textPrimary)),
                        icon: Icon(Icons.check_circle, color: success),
                      ),
                      ButtonSegment(
                        value: 'parcial',
                        label: Text('Parcial', style: TextStyle(color: textPrimary)),
                        icon: Icon(Icons.money_off, color: context.uai.info),
                      ),
                    ],
                    selected: {_statusPagamento},
                    onSelectionChanged: (Set<String> selected) {
                      setState(() {
                        _statusPagamento = selected.first;
                      });
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith(
                            (states) {
                          if (states.contains(WidgetState.selected)) {
                            return primary.withOpacity(0.1);
                          }
                          return cardAlt;
                        },
                      ),
                      foregroundColor: WidgetStateProperty.all(textPrimary),
                    ),
                  ),

                  if (_statusPagamento == 'parcial') ...[
                    const SizedBox(height: 16),
                    TextField(
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Valor pago',
                        labelStyle: TextStyle(color: textSecondary),
                        prefixText: 'R\$ ',
                        filled: true,
                        fillColor: cardAlt,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(context.uai.inputRadius),
                          borderSide: BorderSide(color: border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(context.uai.inputRadius),
                          borderSide: BorderSide(color: border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(context.uai.inputRadius),
                          borderSide: BorderSide(color: primary, width: 1.4),
                        ),
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

            const SizedBox(height: 16),

            // Observações
            Container(
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
                  Row(
                    children: [
                      Icon(Icons.note, color: primary),
                      const SizedBox(width: 8),
                      Text(
                        'OBSERVAÇÕES',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _observacoesController,
                    maxLines: 3,
                    style: TextStyle(color: textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Observações sobre a venda...',
                      hintStyle: TextStyle(color: textMuted),
                      filled: true,
                      fillColor: cardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(context.uai.inputRadius),
                        borderSide: BorderSide(color: border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(context.uai.inputRadius),
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(context.uai.inputRadius),
                        borderSide: BorderSide(color: primary, width: 1.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Informações adicionais
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardAlt,
                borderRadius: BorderRadius.circular(context.uai.cardRadius),
                border: Border.all(color: border),
                boxShadow: context.uai.softShadow,
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    context,
                    'Data da venda',
                    DateFormat('dd/MM/yyyy HH:mm').format(
                      (widget.vendaData['data_venda'] as Timestamp?)?.toDate() ?? DateTime.now(),
                    ),
                  ),
                  Divider(color: border),
                  _buildInfoRow(
                    context,
                    'Valor total',
                    _realFormat.format(_valorTotal),
                    isBold: true,
                  ),
                  Divider(color: border),
                  _buildInfoRow(
                    context,
                    'Valor pago',
                    _realFormat.format(_valorPago),
                    color: success,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value,
      {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: context.uai.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color ?? context.uai.textPrimary,
          ),
        ),
      ],
    );
  }
}