import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/uniformes/services/uniformes_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/remessa_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/fornecedor_service.dart';
import 'package:uai_capoeira/modules/uniformes/dialogs/selecionar_aluno_dialog.dart';

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
  final NumberFormat _realFormat =
  NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

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

  // Helpers de contraste
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();
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
      builder: (context) => SelecionarAlunoDialog(
        corTema: context.uai.primary,
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
        _dataPrevisaoController.text =
            DateFormat('dd/MM/yyyy', 'pt_BR').format(data);
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
        SnackBar(
          content: Text(
            'Selecione uma remessa para o pedido',
            style: TextStyle(color: _readableOn(context.uai.warning)),
          ),
          backgroundColor: context.uai.warning,
        ),
      );
      return;
    }

    if (_itensPedido.isEmpty) {
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
            content: Text(
              ehEstoque
                  ? '✅ Pedido para estoque criado!'
                  : '✅ Pedido $idPedido criado com sucesso!',
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
              '❌ Erro ao criar pedido: $e',
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
    final bool semAluno = _alunoSelecionadoId == null;

    final primary = context.uai.primary;
    final onPrimary = _readableOn(primary);
    final cardBg = context.uai.card;
    final border = context.uai.border;
    final textPrimary = context.uai.textPrimary;
    final textSecondary = context.uai.textSecondary;
    final textMuted = context.uai.textMuted;
    final cardAlt = context.uai.cardAlt;
    final warning = context.uai.warning;
    final error = context.uai.error;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: const Text('NOVO PEDIDO',
            style: TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _salvarPedido,
            icon: _isLoading
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: onPrimary, strokeWidth: 2),
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
          children: [
            // REMESSA (obrigatória)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _remessaId == null
                    ? error.withOpacity(0.05)
                    : cardBg,
                borderRadius:
                BorderRadius.circular(context.uai.cardRadius),
                border: Border.all(
                    color: _remessaId == null
                        ? error.withOpacity(0.3)
                        : border),
                boxShadow: context.uai.softShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_shipping,
                          size: 18, color: primary),
                      const SizedBox(width: 8),
                      Text('REMESSA (obrigatória)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: textPrimary)),
                    ],
                  ),
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
                          Icon(Icons.local_shipping,
                              color: primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _remessaNome ?? 'Selecionar remessa',
                              style: TextStyle(
                                color: _remessaNome == null
                                    ? error
                                    : textPrimary,
                                fontWeight:
                                _remessaNome == null
                                    ? FontWeight.normal
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (_remessaId != null)
                            IconButton(
                              icon: Icon(Icons.close,
                                  color: error),
                              onPressed: _removerRemessa,
                              tooltip: 'Remover vínculo',
                            )
                          else
                            Icon(Icons.arrow_drop_down,
                                color: textMuted),
                        ],
                      ),
                    ),
                  ),
                  if (_remessaNome != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'O pedido será vinculado à remessa $_remessaNome.',
                      style: TextStyle(
                          fontSize: 11, color: textSecondary),
                    ),
                    if (_fornecedorRemessa != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.business,
                              size: 14, color: textMuted),
                          const SizedBox(width: 4),
                          Text(
                            'Fornecedor: $_fornecedorRemessa',
                            style: TextStyle(
                                fontSize: 11, color: textMuted),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ALUNO (opcional)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius:
                BorderRadius.circular(context.uai.cardRadius),
                border: Border.all(color: border),
                boxShadow: context.uai.softShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('ALUNO',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: textPrimary)),
                      if (!semAluno)
                        TextButton.icon(
                          onPressed: _limparAluno,
                          icon: Icon(Icons.clear, size: 16, color: error),
                          label: Text('Remover',
                              style: TextStyle(
                                  fontSize: 12, color: error)),
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
                        border: Border.all(color: border),
                        borderRadius: BorderRadius.circular(8),
                        color: semAluno
                            ? warning.withOpacity(0.1)
                            : null,
                      ),
                      child: Row(
                        children: [
                          if (semAluno)
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: warning.withOpacity(0.2),
                                borderRadius:
                                BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.inventory_2,
                                  color: warning, size: 20),
                            )
                          else if (_fotoAlunoUrl != null &&
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
                              errorWidget: (_, __, ___) =>
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: cardAlt,
                                    child: Icon(Icons.person,
                                        color: textMuted),
                                  ),
                            )
                          else
                            Icon(Icons.person, color: textMuted),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              semAluno
                                  ? 'Item para Estoque (sem aluno)'
                                  : (_alunoSelecionadoNome ??
                                  'Selecionar aluno'),
                              style: TextStyle(
                                color: semAluno
                                    ? warning
                                    : _alunoSelecionadoNome == null
                                    ? textMuted
                                    : textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(Icons.arrow_drop_down,
                              color: textMuted),
                        ],
                      ),
                    ),
                  ),
                  if (semAluno)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '⚠️ Pedido será marcado como item para estoque. Na finalização da remessa, será adicionado automaticamente.',
                        style: TextStyle(
                            fontSize: 11, color: warning),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ITENS
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius:
                BorderRadius.circular(context.uai.cardRadius),
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
                  if (_itensPedido.isEmpty)
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
                      itemCount: _itensPedido.length,
                      separatorBuilder: (_, __) => Divider(color: border),
                      itemBuilder: (context, index) {
                        final item = _itensPedido[index];
                        final tamanho = item['tamanho'] as String?;
                        final cor = item['cor'] as String?;
                        final String nomeExibicao = [
                          item['nome'] ?? 'Item',
                          if (tamanho != null && tamanho.isNotEmpty)
                            'Tam. $tamanho',
                          if (cor != null && cor.isNotEmpty)
                            'Cor: $cor',
                        ].join(' - ');
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.shopping_bag,
                                color: primary),
                          ),
                          title: Text(nomeExibicao,
                              style: TextStyle(color: textPrimary)),
                          subtitle: Text(
                            '${item['quantidade']} x ${_realFormat.format(item['preco_unitario'])}',
                            style: TextStyle(color: textSecondary),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _realFormat.format(item['quantidade'] *
                                    item['preco_unitario']),
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: textPrimary),
                              ),
                              IconButton(
                                icon: Icon(Icons.close,
                                    size: 16, color: error),
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

            // INFORMAÇÕES ADICIONAIS
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius:
                BorderRadius.circular(context.uai.cardRadius),
                border: Border.all(color: border),
                boxShadow: context.uai.softShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('INFORMAÇÕES ADICIONAIS',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textPrimary)),
                  Divider(color: border),
                  InkWell(
                    onTap: _selecionarDataPrevisao,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 20, color: textSecondary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _dataPrevisaoController,
                              enabled: false,
                              style: TextStyle(color: textPrimary),
                              decoration: InputDecoration(
                                labelText: 'Data de previsão',
                                labelStyle: TextStyle(
                                    color: textSecondary),
                                border: InputBorder.none,
                                hintText: 'Selecionar data',
                                hintStyle:
                                TextStyle(color: textMuted),
                                disabledBorder: InputBorder.none,
                              ),
                            ),
                          ),
                          Icon(Icons.arrow_drop_down,
                              color: textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _observacoesController,
                    maxLines: 3,
                    style: TextStyle(color: textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Observações',
                      hintText:
                      'Observações sobre o pedido (tamanhos, cores, detalhes, etc)',
                      labelStyle: TextStyle(color: textSecondary),
                      hintStyle: TextStyle(color: textMuted),
                      filled: true,
                      fillColor: cardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            context.uai.inputRadius),
                        borderSide: BorderSide(color: border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            context.uai.inputRadius),
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            context.uai.inputRadius),
                        borderSide: BorderSide(
                            color: primary, width: 1.4),
                      ),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'O status do pedido será "PENDENTE". Você poderá alterar para "EM CONFECÇÃO" e "FINALIZADO" depois.',
                            style: TextStyle(
                                fontSize: 12, color: primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ElevatedButton(
                onPressed: _salvarPedido,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: onPrimary,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                        context.uai.buttonRadius),
                  ),
                ),
                child: Text(
                  _alunoSelecionadoId == null
                      ? 'CRIAR ITEM PARA ESTOQUE'
                      : 'CRIAR PEDIDO',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
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
// DIÁLOGO DE SELEÇÃO DE REMESSA (refatorado)
// =============================================================================
class _SelecionarRemessaDialog extends StatefulWidget {
  @override
  State<_SelecionarRemessaDialog> createState() =>
      _SelecionarRemessaDialogState();
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
                  if (!snapshot.hasData)
                    return Center(
                        child: CircularProgressIndicator(
                            color: primary));
                  var docs = snapshot.data!.docs;
                  if (_search.isNotEmpty) {
                    docs = docs.where((d) {
                      final nome =
                          (d.data() as Map<String, dynamic>)['nome'] ?? '';
                      return nome.toLowerCase().contains(_search);
                    }).toList();
                  }
                  if (docs.isEmpty) {
                    return Center(
                      child: Text('Nenhuma remessa encontrada',
                          style: TextStyle(color: textMuted)),
                    );
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
                            leading: Icon(Icons.local_shipping,
                                color: primary),
                            title: Text(data['nome'] ?? 'Sem nome',
                                style: TextStyle(color: textPrimary)),
                            subtitle: Text(
                              'Status: ${data['status']}${fornecedorNome != null ? ' • Fornecedor: $fornecedorNome' : ''}',
                              style: TextStyle(color: textSecondary),
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
// DIÁLOGO DE SELEÇÃO DE ITEM (COM VARIAÇÕES) – refatorado
// =============================================================================
class SelecionarItemPedidoDialog extends StatefulWidget {
  const SelecionarItemPedidoDialog({super.key});

  @override
  State<SelecionarItemPedidoDialog> createState() =>
      _SelecionarItemPedidoDialogState();
}

class _SelecionarItemPedidoDialogState
    extends State<SelecionarItemPedidoDialog> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _realFormat =
  NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

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
    final border = context.uai.border;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(data['nome'] ?? 'Item',
              style: TextStyle(color: textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Preço unitário: ${_realFormat.format(data['preco_venda'] ?? 0)}',
                style: TextStyle(color: textPrimary),
              ),
              if (tamanho != null)
                Text('Tamanho: $tamanho',
                    style: TextStyle(color: textPrimary)),
              if (data['cor'] != null &&
                  data['cor'].toString().isNotEmpty)
                Text('Cor: ${data['cor']}',
                    style: TextStyle(color: textPrimary)),
              const SizedBox(height: 16),
              TextField(
                controller: quantidadeController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  labelText: 'Quantidade',
                  labelStyle:
                  TextStyle(color: context.uai.textSecondary),
                  filled: true,
                  fillColor: context.uai.cardAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                        context.uai.inputRadius),
                    borderSide: BorderSide(color: border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                        context.uai.inputRadius),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                        context.uai.inputRadius),
                    borderSide: BorderSide(
                        color: primary, width: 1.4),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar',
                  style: TextStyle(color: primary)),
            ),
            ElevatedButton(
              onPressed: () {
                int quantidade =
                    int.tryParse(quantidadeController.text) ?? 1;
                if (quantidade <= 0) quantidade = 1;

                Navigator.pop(ctx);
                Navigator.pop(context, {
                  'item_id': itemId,
                  'nome': data['nome'],
                  'tamanho': tamanho,
                  'quantidade': quantidade,
                  'preco_unitario': data['preco_venda'] ?? 0,
                  'cor': data['cor'] ?? '',
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
          SnackBar(
            content: const Text(
                'Nenhuma variação encontrada para este item'),
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
                final cor = variacao['cor']?.toString() ?? '';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                    context.uai.primary.withOpacity(0.1),
                    child: Text(
                      tamanho.toString().toUpperCase(),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: context.uai.primary),
                    ),
                  ),
                  title: Text('Tamanho $tamanho',
                      style:
                      TextStyle(color: context.uai.textPrimary)),
                  subtitle: Text(
                    'Estoque: $quantidadeEstoque un${cor.isNotEmpty ? ' - Cor: $cor' : ''}',
                    style: TextStyle(
                        color: context.uai.textSecondary),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showQuantidadeDialog(
                      context,
                      snapshot.docs[i].id,
                      variacao,
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
              child: Text('Cancelar',
                  style: TextStyle(color: context.uai.primary)),
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
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: primary,
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
                        color: Colors.white,
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
                    borderRadius: BorderRadius.circular(
                        context.uai.inputRadius),
                    borderSide: BorderSide(color: border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                        context.uai.inputRadius),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                        context.uai.inputRadius),
                    borderSide:
                    BorderSide(color: primary, width: 1.4),
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
                onChanged: (value) =>
                    setState(() => _searchQuery = value),
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
                    return Center(
                        child: CircularProgressIndicator(
                            color: primary));

                  var docs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final tipo = data['tipo'] as String?;
                    return (tipo == null || tipo == 'base');
                  }).toList();

                  if (_searchQuery.isNotEmpty) {
                    docs = docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final nome =
                          data['nome']?.toString().toLowerCase() ?? '';
                      return nome
                          .contains(_searchQuery.toLowerCase());
                    }).toList();
                  }

                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 50, color: textMuted),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'Nenhum item cadastrado'
                                : 'Nenhum item encontrado',
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
                      final bool possuiVariacoes =
                          data['possui_variacoes'] == true;
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
                            borderRadius:
                            BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: fotoUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  Icon(Icons.shopping_bag,
                                      color: primary),
                              errorWidget: (_, __, ___) =>
                                  Icon(Icons.shopping_bag,
                                      color: primary),
                            ),
                          )
                              : Icon(Icons.shopping_bag,
                              color: primary),
                        ),
                        title: Text(data['nome'] ?? 'Sem nome',
                            style: TextStyle(color: textPrimary)),
                        subtitle: Text(
                            'Preço: ${_realFormat.format(data['preco_venda'] ?? 0)}',
                            style: TextStyle(color: textSecondary)),
                        trailing: possuiVariacoes
                            ? Icon(Icons.arrow_forward_ios,
                            size: 14, color: textMuted)
                            : null,
                        onTap: () {
                          if (possuiVariacoes) {
                            _mostrarDialogoVariacoes(
                                context, doc.id, data);
                          } else {
                            _showQuantidadeDialog(
                                context, doc.id, data);
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