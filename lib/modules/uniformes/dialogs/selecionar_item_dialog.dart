import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class SelecionarItemDialog extends StatefulWidget {
  const SelecionarItemDialog({super.key});

  @override
  State<SelecionarItemDialog> createState() => _SelecionarItemDialogState();
}

class _SelecionarItemDialogState extends State<SelecionarItemDialog> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _realFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers de contraste
  // ---------------------------------------------------------------------------
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }



  @override
  Widget build(BuildContext context) {
    final Color headerBg = context.uai.primary;
    final Color headerFg = _readableOn(headerBg);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: context.uai.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
      ),
      child: Container(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.7,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.uai.cardRadius),
        ),
        child: Column(
          children: [
            // Cabeçalho (substitui AppBar fixa)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: headerBg,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(context.uai.cardRadius),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: headerFg),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'SELECIONAR ITEM',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: headerFg,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: headerFg),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Campo de busca
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: context.uai.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Pesquisar item...',
                  hintStyle: TextStyle(color: context.uai.textMuted),
                  prefixIcon: Icon(
                    Icons.search,
                    color: context.uai.textSecondary,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: context.uai.textSecondary,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
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
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),

            // Lista de itens
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('uniformes_estoque')
                    .where('status', isEqualTo: 'ativo')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  var itens = snapshot.data!.docs.where((doc) {
                    if (_searchQuery.isEmpty) return true;
                    var data = doc.data() as Map<String, dynamic>;
                    return (data['nome'] ?? '').toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    );
                  }).toList();

                  if (itens.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 50,
                            color: context.uai.textMuted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhum item encontrado',
                            style: TextStyle(color: context.uai.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.uai.primary,
                              foregroundColor: _readableOn(context.uai.primary),
                            ),
                            child: const Text('Voltar'),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: itens.length,
                    itemBuilder: (context, index) {
                      var doc = itens[index];
                      var data = doc.data() as Map<String, dynamic>;

                      int quantidade = data['quantidade'] ?? 0;
                      bool controlaEstoque = data['controla_estoque'] ?? true;
                      bool semEstoque = controlaEstoque && quantidade <= 0;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        child: Material(
                          color: context.uai.card,
                          borderRadius: BorderRadius.circular(
                            context.uai.cardRadius,
                          ),
                          clipBehavior: Clip.antiAlias,
                          elevation: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                context.uai.cardRadius,
                              ),
                              border: Border.all(color: context.uai.border),
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: semEstoque
                                      ? context.uai.textMuted.withAlpha(38)
                                      : context.uai.success.withAlpha(38),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.shopping_bag,
                                  color: semEstoque
                                      ? context.uai.textMuted
                                      : context.uai.success,
                                ),
                              ),
                              title: Text(
                                data['nome'] ?? 'Sem nome',
                                style: TextStyle(
                                  color: semEstoque
                                      ? context.uai.textMuted
                                      : context.uai.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                controlaEstoque
                                    ? 'Estoque: $quantidade | Preço: ${_realFormat.format(data['preco_venda'] ?? 0)}'
                                    : 'Preço: ${_realFormat.format(data['preco_venda'] ?? 0)}',
                                style: TextStyle(
                                  color: semEstoque
                                      ? context.uai.textMuted
                                      : context.uai.textSecondary,
                                ),
                              ),
                              onTap: () {
                                _showQuantidadeDialog(context, doc.id, data);
                              },
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
      ),
    );
  }

  void _showQuantidadeDialog(
    BuildContext context,
    String itemId,
    Map<String, dynamic> data,
  ) {
    final quantidadeController = TextEditingController(text: '1');
    final quantidadeMaxima = (data['quantidade'] as num?)?.toInt() ?? 0;
    String origem = quantidadeMaxima > 0 ? 'estoque' : 'fora_do_estoque';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocalState) {
          final usandoEstoque = origem == 'estoque';
          return AlertDialog(
            backgroundColor: context.uai.surface,
            title: Text(data['nome'] ?? 'Item', style: TextStyle(color: context.uai.textPrimary, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Preço unitário: ${_realFormat.format(data['preco_venda'] ?? 0)}', style: TextStyle(color: context.uai.textSecondary)),
                  const SizedBox(height: 16),
                  Text('ORIGEM DO ITEM', style: TextStyle(color: context.uai.textPrimary, fontWeight: FontWeight.w800, fontSize: 12)),
                  RadioGroup<String>(
                    groupValue: origem,
                    onChanged: (v) {
                      if (v != null) setLocalState(() => origem = v);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: 'estoque',
                          enabled: quantidadeMaxima > 0,
                          title: const Text('Estoque'),
                          subtitle: Text(
                            quantidadeMaxima > 0
                                ? 'Retira automaticamente. Saldo: $quantidadeMaxima'
                                : 'Sem saldo registrado',
                          ),
                        ),
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: 'fora_do_estoque',
                          title: const Text('Fora do estoque'),
                          subtitle: const Text(
                            'Registra a venda sem alterar o saldo.',
                          ),
                        ),
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: 'encomenda',
                          title: const Text('Encomenda'),
                          subtitle: const Text(
                            'Produto será providenciado para entrega.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: quantidadeController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Quantidade', helperText: usandoEstoque ? 'Máximo: $quantidadeMaxima' : 'Não altera o estoque')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () {
                  final quantidade = int.tryParse(quantidadeController.text) ?? 0;
                  if (quantidade <= 0 || (usandoEstoque && quantidade > quantidadeMaxima)) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(usandoEstoque ? 'Quantidade inválida. Disponível: $quantidadeMaxima' : 'Informe uma quantidade válida.'), backgroundColor: context.uai.error));
                    return;
                  }
                  Navigator.pop(ctx);
                  Navigator.pop(context, {
                    'item_id': itemId,
                    'produto_id': itemId,
                    'nome': data['nome'],
                    'produto_nome': data['nome'],
                    'categoria': data['categoria'] ?? '',
                    'tamanho': data['tamanho'] ?? '',
                    'quantidade': quantidade,
                    'preco_unitario': (data['preco_venda'] as num?)?.toDouble() ?? 0,
                    'origem': origem,
                    'controla_estoque': origem == 'estoque',
                    'status_entrega': 'aguardando',
                  });
                },
                child: const Text('Adicionar'),
              ),
            ],
          );
        },
      ),
    );
  }
}
