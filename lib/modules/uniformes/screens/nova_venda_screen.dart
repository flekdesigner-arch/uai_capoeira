import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/uniformes/services/uniformes_service.dart';
import 'package:uai_capoeira/modules/uniformes/dialogs/selecionar_aluno_dialog.dart';
import 'package:uai_capoeira/modules/uniformes/dialogs/selecionar_item_dialog.dart';

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
  String? _fotoAlunoUrl;
  String? _statusPagamento = 'pendente';

  List<Map<String, dynamic>> _itensVenda = [];
  double _valorTotal = 0;
  double _valorPago = 0;

  final TextEditingController _observacoesController = TextEditingController();

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
        SnackBar(
          content: Text(
            'Selecione um aluno',
            style: TextStyle(color: _readableOn(context.uai.warning)),
          ),
          backgroundColor: context.uai.warning,
        ),
      );
      return;
    }

    if (_itensVenda.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Adicione pelo menos um item',
            style: TextStyle(color: _readableOn(context.uai.warning)),
          ),
          backgroundColor: context.uai.warning,
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
          SnackBar(
            content: Text(
              '✅ Venda registrada com sucesso!',
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
              '❌ Erro ao registrar venda: $e',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  Future<void> _selecionarAluno() async {
    final selecionado = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => SelecionarAlunoDialog(
        corTema: context.uai.success, // Tema do módulo de uniformes
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardBg = context.uai.card;
    final border = context.uai.border;
    final primary = context.uai.success; // Uniformes usa cor de sucesso como primária
    final onPrimary = _readableOn(primary);
    final textPrimary = context.uai.textPrimary;
    final textSecondary = context.uai.textSecondary;
    final textMuted = context.uai.textMuted;
    final cardAlt = context.uai.cardAlt;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: const Text('NOVA VENDA',
            style: TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton.icon(
            onPressed: _finalizarVenda,
            icon: Icon(Icons.check, color: onPrimary),
            label: Text('FINALIZAR', style: TextStyle(color: onPrimary)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Seleção de Aluno
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
                  Text('ALUNO',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: textPrimary)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _selecionarAluno,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          if (_fotoAlunoUrl != null &&
                              _fotoAlunoUrl!.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: _fotoAlunoUrl!,
                              imageBuilder: (ctx, imageProvider) =>
                                  CircleAvatar(
                                    backgroundImage: imageProvider,
                                    radius: 16,
                                  ),
                              placeholder: (_, __) => CircleAvatar(
                                radius: 16,
                                backgroundColor: cardAlt,
                                child: Icon(Icons.person,
                                    size: 18, color: textMuted),
                              ),
                              errorWidget: (_, __, ___) => CircleAvatar(
                                radius: 16,
                                backgroundColor: cardAlt,
                                child: Icon(Icons.person, color: textMuted),
                              ),
                            )
                          else
                            Icon(Icons.person, color: textMuted),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _alunoSelecionadoNome ?? 'Selecionar aluno',
                              style: TextStyle(
                                color: _alunoSelecionadoNome == null
                                    ? textMuted
                                    : textPrimary,
                                fontWeight: _alunoSelecionadoNome != null
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: textMuted),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Itens da Venda
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
                      Text('ITENS',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: textPrimary)),
                      TextButton.icon(
                        onPressed: _adicionarItem,
                        icon: Icon(Icons.add, color: primary),
                        label: Text('Adicionar Item',
                            style: TextStyle(color: primary)),
                      ),
                    ],
                  ),
                  Divider(color: border),

                  if (_itensVenda.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.shopping_cart_outlined,
                                size: 48, color: textMuted),
                            const SizedBox(height: 8),
                            Text('Nenhum item adicionado',
                                style: TextStyle(color: textMuted)),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _itensVenda.length,
                      separatorBuilder: (_, __) => Divider(color: border),
                      itemBuilder: (context, index) {
                        final item = _itensVenda[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.shopping_bag, color: primary),
                          ),
                          title: Text(item['nome'],
                              style: TextStyle(color: textPrimary)),
                          subtitle: Text(
                            '${item['quantidade']} x ${_realFormat.format(item['preco_unitario'])}',
                            style: TextStyle(color: textSecondary),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _realFormat.format(
                                    item['quantidade'] * item['preco_unitario']),
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: textPrimary),
                              ),
                              IconButton(
                                icon: Icon(Icons.close,
                                    size: 16, color: context.uai.error),
                                onPressed: () => _removerItem(index),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  Divider(color: border),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('TOTAL',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textPrimary)),
                      Text(
                        _realFormat.format(_valorTotal),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: primary,
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
                  Text('PAGAMENTO',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: textPrimary)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'pendente',
                        label: Text('Pendente',
                            style: TextStyle(color: textPrimary)),
                        icon: Icon(Icons.pending, color: context.uai.warning),
                      ),
                      ButtonSegment(
                        value: 'pago',
                        label:
                        Text('Pago', style: TextStyle(color: textPrimary)),
                        icon: Icon(Icons.check_circle, color: primary),
                      ),
                      ButtonSegment(
                        value: 'parcial',
                        label: Text('Parcial',
                            style: TextStyle(color: textPrimary)),
                        icon: Icon(Icons.money_off, color: context.uai.info),
                      ),
                    ],
                    selected: {_statusPagamento!},
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
                      foregroundColor:
                      WidgetStateProperty.all(textPrimary),
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
                          borderRadius:
                          BorderRadius.circular(context.uai.inputRadius),
                          borderSide: BorderSide(color: border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                          BorderRadius.circular(context.uai.inputRadius),
                          borderSide: BorderSide(color: border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                          BorderRadius.circular(context.uai.inputRadius),
                          borderSide:
                          BorderSide(color: primary, width: 1.4),
                        ),
                      ),
                      onChanged: (value) {
                        _valorPago =
                            double.tryParse(value.replaceAll(',', '.')) ?? 0;
                      },
                    ),
                  ],

                  const SizedBox(height: 16),

                  TextField(
                    controller: _observacoesController,
                    maxLines: 2,
                    style: TextStyle(color: textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Observações',
                      hintText: 'Observações sobre a venda...',
                      labelStyle: TextStyle(color: textSecondary),
                      hintStyle: TextStyle(color: textMuted),
                      filled: true,
                      fillColor: cardAlt,
                      border: OutlineInputBorder(
                        borderRadius:
                        BorderRadius.circular(context.uai.inputRadius),
                        borderSide: BorderSide(color: border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                        BorderRadius.circular(context.uai.inputRadius),
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                        BorderRadius.circular(context.uai.inputRadius),
                        borderSide: BorderSide(color: primary, width: 1.4),
                      ),
                      alignLabelWithHint: true,
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
}