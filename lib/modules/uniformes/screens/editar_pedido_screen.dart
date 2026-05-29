import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/uniformes/services/remessa_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/uniformes_service.dart';

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

  late TextEditingController _observacoesController;
  late TextEditingController _dataPrevisaoController;
  late String _status;
  late String _statusPagamento;
  late double _valorPago;
  late double _valorTotal;

  bool _isLoading = false;

  List<Map<String, dynamic>> _itens = [];
  final Map<int, TextEditingController> _quantidadeControllers = {};

  String? _remessaId;
  String? _remessaNome;
  String? _fotoAlunoUrl;

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
    _observacoesController = TextEditingController(text: widget.pedidoData['observacoes'] ?? '');
    _dataPrevisaoController = TextEditingController(text: widget.pedidoData['data_previsao'] ?? '');
    _status = widget.pedidoData['status'] ?? 'pendente';
    _statusPagamento = widget.pedidoData['status_pagamento'] ?? 'pendente';
    _valorPago = (widget.pedidoData['valor_pago'] ?? 0).toDouble();
    _valorTotal = (widget.pedidoData['valor_total'] ?? 0).toDouble();

    _itens = List<Map<String, dynamic>>.from(widget.pedidoData['itens'] ?? []);

    _remessaId = widget.pedidoData['remessa_id'];
    if (_remessaId != null) {
      _carregarNomeRemessa();
    }

    _carregarFotoAluno();

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
      builder: (ctx) => AlertDialog(
        title: Text('Remover Item', style: TextStyle(color: context.uai.textPrimary)),
        content: Text('Deseja remover "${_itens[index]['nome']}" do pedido?',
            style: TextStyle(color: context.uai.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: TextStyle(color: context.uai.primary)),
          ),
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
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: _readableOn(context.uai.error),
            ),
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

  Future<void> _selecionarRemessa() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SelecionarRemessaDialog(),
    );
    if (result != null && mounted) {
      setState(() {
        _remessaId = result['id'] as String?;
        _remessaNome = result['nome'] as String?;

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
          SnackBar(
            content: Text('✅ Pedido atualizado com sucesso!',
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
            content: Text('❌ Erro ao atualizar: $e',
                style: TextStyle(color: _readableOn(context.uai.error))),
            backgroundColor: context.uai.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Build principal ────────────────────────────────────────────────────
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
    final alunoNome = widget.pedidoData['aluno_nome'] ?? 'Aluno não identificado';

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: const Text('EDITAR PEDIDO',
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
            // Aluno
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(context.uai.cardRadius),
                border: Border.all(color: border),
                boxShadow: context.uai.softShadow,
              ),
              child: Row(
                children: [
                  if (_fotoAlunoUrl != null && _fotoAlunoUrl!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: _fotoAlunoUrl!,
                      imageBuilder: (ctx, imageProvider) =>
                          CircleAvatar(backgroundImage: imageProvider, radius: 20),
                      placeholder: (_, __) => CircleAvatar(
                        radius: 20,
                        backgroundColor: cardAlt,
                        child: Icon(Icons.person, color: textMuted),
                      ),
                      errorWidget: (_, __, ___) => CircleAvatar(
                        radius: 20,
                        backgroundColor: cardAlt,
                        child: Icon(Icons.person, color: textMuted),
                      ),
                    )
                  else
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: cardAlt,
                      child: Icon(Icons.person, color: textMuted),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(alunoNome,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textPrimary)),
                        Text(
                          'Pedido: ${widget.pedidoData['id_pedido'] ?? 'N/I'}',
                          style: TextStyle(color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Itens
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
                      Text('ITENS DO PEDIDO',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: textPrimary)),
                      IconButton(
                        icon: Icon(Icons.add_circle, color: primary),
                        onPressed: _selecionarItem,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_itens.isEmpty)
                    Center(
                      child: Text('Nenhum item',
                          style: TextStyle(color: textMuted)),
                    )
                  else
                    ..._itens.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final tamanho = item['tamanho'] as String?;
                      final descricao = tamanho != null
                          ? '${item['nome']} - Tam. $tamanho'
                          : item['nome'];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cardAlt,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(descricao ?? '',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: textPrimary)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Preço: ${_realFormat.format(item['preco_unitario'])}',
                                    style: TextStyle(
                                        color: primary,
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 70,
                              child: TextFormField(
                                controller: _quantidadeControllers[index],
                                keyboardType: TextInputType.number,
                                style: TextStyle(color: textPrimary),
                                decoration: InputDecoration(
                                  labelText: 'Qtd',
                                  isDense: true,
                                  labelStyle: TextStyle(color: textSecondary),
                                  filled: true,
                                  fillColor: cardBg,
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
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _realFormat.format(item['quantidade'] * item['preco_unitario']),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, color: context.uai.error),
                              onPressed: () => _removerItem(index),
                            ),
                          ],
                        ),
                      );
                    }),
                  if (_itens.isNotEmpty) ...[
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
                              color: primary),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Remessa (opcional)
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
                  Text('REMESSA (opcional)',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: textPrimary)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _selecionarRemessa,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.local_shipping, color: primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _remessaNome ?? 'Vincular a uma remessa',
                              style: TextStyle(
                                color: _remessaNome == null
                                    ? textMuted
                                    : textPrimary,
                              ),
                            ),
                          ),
                          if (_remessaId != null)
                            IconButton(
                              icon: Icon(Icons.close, color: context.uai.error),
                              onPressed: _removerRemessa,
                            )
                          else
                            Icon(Icons.arrow_drop_down, color: textMuted),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Status do Pedido
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
                  Text('STATUS',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: textPrimary)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'pendente',
                        label: Text('Pendente', style: TextStyle(color: textPrimary)),
                        icon: Icon(Icons.pending, color: context.uai.warning),
                      ),
                      ButtonSegment(
                        value: 'em_confeccao',
                        label: Text('Em Confecção', style: TextStyle(color: textPrimary)),
                        icon: Icon(Icons.build, color: context.uai.info),
                      ),
                      ButtonSegment(
                        value: 'finalizado',
                        label: Text('Finalizado', style: TextStyle(color: textPrimary)),
                        icon: Icon(Icons.check_circle, color: context.uai.success),
                      ),
                    ],
                    selected: {_status},
                    onSelectionChanged: (Set<String> selected) =>
                        setState(() => _status = selected.first),
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
                  const SizedBox(height: 16),
                  Text('PAGAMENTO',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: textPrimary)),
                  const SizedBox(height: 8),
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
                        icon: Icon(Icons.check_circle, color: context.uai.success),
                      ),
                      ButtonSegment(
                        value: 'parcial',
                        label: Text('Parcial', style: TextStyle(color: textPrimary)),
                        icon: Icon(Icons.money_off, color: context.uai.info),
                      ),
                    ],
                    selected: {_statusPagamento},
                    onSelectionChanged: (Set<String> selected) =>
                        setState(() => _statusPagamento = selected.first),
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
                    const SizedBox(height: 12),
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
                      onChanged: (v) =>
                      _valorPago = double.tryParse(v.replaceAll(',', '.')) ?? 0,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Previsão
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(context.uai.cardRadius),
                border: Border.all(color: border),
                boxShadow: context.uai.softShadow,
              ),
              child: InkWell(
                onTap: _selecionarDataPrevisao,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Data de previsão',
                    labelStyle: TextStyle(color: textSecondary),
                    border: InputBorder.none,
                  ),
                  child: Text(
                    _dataPrevisaoController.text.isEmpty
                        ? 'Selecionar data'
                        : _dataPrevisaoController.text,
                    style: TextStyle(color: textPrimary),
                  ),
                ),
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
              child: TextField(
                controller: _observacoesController,
                maxLines: 3,
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  labelText: 'Observações',
                  labelStyle: TextStyle(color: textSecondary),
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
                  alignLabelWithHint: true,
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
// Diálogo para selecionar remessa (refatorado)
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

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.uai.primary;
    final textPrimary = context.uai.textPrimary;
    final textSecondary = context.uai.textSecondary;
    final textMuted = context.uai.textMuted;
    final cardAlt = context.uai.cardAlt;
    final border = context.uai.border;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
      ),
      backgroundColor: context.uai.surface,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              style: TextStyle(color: textPrimary),
              decoration: InputDecoration(
                hintText: 'Pesquisar remessa...',
                hintStyle: TextStyle(color: textMuted),
                prefixIcon: Icon(Icons.search, color: textMuted),
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
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('remessas')
                    .orderBy('criado_em', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: primary));
                  var docs = snapshot.data!.docs;
                  if (_search.isNotEmpty) {
                    docs = docs.where((d) {
                      final nome = (d.data() as Map<String, dynamic>)['nome'] ?? '';
                      return nome.toLowerCase().contains(_search);
                    }).toList();
                  }
                  if (docs.isEmpty) return Center(child: Text('Nenhuma remessa encontrada', style: TextStyle(color: textMuted)));
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      return ListTile(
                        leading: Icon(Icons.local_shipping, color: primary),
                        title: Text(data['nome'] ?? 'Sem nome', style: TextStyle(color: textPrimary)),
                        subtitle: Text('Status: ${data['status']}', style: TextStyle(color: textSecondary)),
                        onTap: () {
                          Navigator.pop(context, {
                            'id': docs[i].id,
                            'nome': data['nome'],
                            'data_prevista': data['data_prevista'],
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
// Diálogo de seleção de item para pedido (refatorado, com suporte a variações)
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

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  void _showQuantidadeDialog(
      BuildContext context,
      String itemId,
      Map<String, dynamic> data, {
        String? tamanho,
      }) {
    final quantidadeController = TextEditingController();
    final primary = context.uai.primary;
    final textPrimary = context.uai.textPrimary;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(data['nome'] ?? 'Item', style: TextStyle(color: textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Preço unitário: ${_realFormat.format(data['preco_venda'] ?? 0)}',
                  style: TextStyle(color: textPrimary)),
              if (tamanho != null) Text('Tamanho: $tamanho', style: TextStyle(color: textPrimary)),
              const SizedBox(height: 16),
              TextField(
                controller: quantidadeController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  labelText: 'Quantidade',
                  labelStyle: TextStyle(color: context.uai.textSecondary),
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
                    borderSide: BorderSide(color: primary, width: 1.4),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar', style: TextStyle(color: primary)),
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
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: _readableOn(primary),
              ),
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
          SnackBar(
            content: const Text('Nenhuma variação encontrada para este item'),
            backgroundColor: context.uai.warning,
          ),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Tamanhos disponíveis - ${baseData['nome']}',
              style: TextStyle(color: context.uai.textPrimary)),
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
                    backgroundColor: context.uai.primary.withOpacity(0.1),
                    child: Text(tamanho.toString().toUpperCase(),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.uai.primary)),
                  ),
                  title: Text('Tamanho $tamanho',
                      style: TextStyle(color: context.uai.textPrimary)),
                  subtitle: Text('Estoque: $quantidadeEstoque un',
                      style: TextStyle(color: context.uai.textSecondary)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showQuantidadeDialog(context, snapshot.docs[i].id, variacao,
                        tamanho: tamanho.toString());
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar', style: TextStyle(color: context.uai.primary)),
            ),
          ],
        ),
      );
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar variações: $e'),
            backgroundColor: context.uai.error,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.uai.primary;
    final onPrimary = _readableOn(primary);
    final textPrimary = context.uai.textPrimary;
    final textSecondary = context.uai.textSecondary;
    final textMuted = context.uai.textMuted;
    final cardAlt = context.uai.cardAlt;
    final border = context.uai.border;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: context.uai.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
      ),
      child: Container(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            // AppBar interna do diálogo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: context.uai.primary,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(context.uai.cardRadius),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: onPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'SELECIONAR ITEM',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.white, // fix? onPrimary
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: onPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'Pesquisar item...',
                  hintStyle: TextStyle(color: textMuted),
                  prefixIcon: Icon(Icons.search, color: textMuted),
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
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: Icon(Icons.clear, color: textMuted),
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
                  if (!snapshot.hasData)
                    return Center(child: CircularProgressIndicator(color: primary));

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
                          Icon(Icons.inventory_2_outlined, size: 50, color: textMuted),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty ? 'Nenhum item cadastrado' : 'Nenhum item encontrado',
                            style: TextStyle(color: textSecondary),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: onPrimary,
                            ),
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
                            color: primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: fotoUrl != null && fotoUrl.isNotEmpty
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: fotoUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  Icon(Icons.shopping_bag, color: primary),
                              errorWidget: (_, __, ___) =>
                                  Icon(Icons.shopping_bag, color: primary),
                            ),
                          )
                              : Icon(Icons.shopping_bag, color: primary),
                        ),
                        title: Text(data['nome'] ?? 'Sem nome',
                            style: TextStyle(color: textPrimary)),
                        subtitle: Text(
                            'Preço: ${_realFormat.format(data['preco_venda'] ?? 0)}',
                            style: TextStyle(color: textSecondary)),
                        trailing: possuiVariacoes
                            ? Icon(Icons.arrow_forward_ios, size: 14, color: textMuted)
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