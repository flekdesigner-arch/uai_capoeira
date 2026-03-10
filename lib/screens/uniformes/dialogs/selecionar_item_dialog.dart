import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SelecionarItemDialog extends StatefulWidget {
  const SelecionarItemDialog({super.key});

  @override
  State<SelecionarItemDialog> createState() => _SelecionarItemDialogState();
}

class _SelecionarItemDialogState extends State<SelecionarItemDialog> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
              backgroundColor: Colors.green.shade900,
              foregroundColor: Colors.white,
              automaticallyImplyLeading: false,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Pesquisar item...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
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
                    return (data['nome'] ?? '')
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase());
                  }).toList();

                  if (itens.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 50, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhum item encontrado',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
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

                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: semEstoque ? Colors.grey.shade200 : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.shopping_bag,
                            color: semEstoque ? Colors.grey : Colors.green,
                          ),
                        ),
                        title: Text(
                          data['nome'] ?? 'Sem nome',
                          style: TextStyle(
                            color: semEstoque ? Colors.grey : Colors.black,
                          ),
                        ),
                        subtitle: Text(
                          controlaEstoque
                              ? 'Estoque: $quantidade | Preço: ${_realFormat.format(data['preco_venda'] ?? 0)}'
                              : 'Preço: ${_realFormat.format(data['preco_venda'] ?? 0)}',
                          style: TextStyle(
                            color: semEstoque ? Colors.grey : Colors.black54,
                          ),
                        ),
                        enabled: !semEstoque,
                        onTap: semEstoque
                            ? null
                            : () {
                          _showQuantidadeDialog(context, doc.id, data);
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

  void _showQuantidadeDialog(
      BuildContext context,
      String itemId,
      Map<String, dynamic> data,
      ) {
    final quantidadeController = TextEditingController();
    int quantidadeMaxima = data['quantidade'] ?? 999;
    bool controlaEstoque = data['controla_estoque'] ?? true;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(data['nome'] ?? 'Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Preço unitário: ${_realFormat.format(data['preco_venda'] ?? 0)}'),
              const SizedBox(height: 16),
              TextField(
                controller: quantidadeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Quantidade',
                  border: const OutlineInputBorder(),
                  helperText: controlaEstoque ? 'Máximo: $quantidadeMaxima' : null,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                int quantidade = int.tryParse(quantidadeController.text) ?? 1;
                if (quantidade <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Quantidade deve ser maior que 0'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (controlaEstoque && quantidade > quantidadeMaxima) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Quantidade máxima disponível: $quantidadeMaxima'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                Navigator.pop(context); // Fecha dialog de quantidade
                Navigator.pop(context, { // Fecha dialog de seleção e retorna item
                  'item_id': itemId,
                  'nome': data['nome'],
                  'quantidade': quantidade,
                  'preco_unitario': data['preco_venda'] ?? 0,
                  'controla_estoque': controlaEstoque,
                });
              },
              child: const Text('Adicionar'),
            ),
          ],
        );
      },
    );
  }
}