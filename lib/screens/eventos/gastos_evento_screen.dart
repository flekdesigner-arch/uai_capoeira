import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GastosEventoScreen extends StatefulWidget {
  final String eventoId;
  final String eventoNome;

  const GastosEventoScreen({
    super.key,
    required this.eventoId,
    required this.eventoNome,
  });

  @override
  State<GastosEventoScreen> createState() => _GastosEventoScreenState();
}

class _GastosEventoScreenState extends State<GastosEventoScreen> {
  final TextEditingController _descricaoController = TextEditingController();
  final TextEditingController _valorController = TextEditingController();
  final TextEditingController _categoriaController = TextEditingController();
  double _totalGastos = 0;

  Future<void> _adicionarGasto() async {
    if (_descricaoController.text.isEmpty || _valorController.text.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('gastos_eventos')
          .add({
        'evento_id': widget.eventoId,
        'evento_nome': widget.eventoNome,
        'descricao': _descricaoController.text.trim(),
        'valor': double.tryParse(_valorController.text.replaceAll(',', '.')) ?? 0,
        'categoria': _categoriaController.text.trim(),
        'data': FieldValue.serverTimestamp(),
      });

      _descricaoController.clear();
      _valorController.clear();
      _categoriaController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gasto adicionado!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao adicionar gasto: $e');
    }
  }

  Future<void> _excluirGasto(String gastoId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Gasto'),
        content: const Text('Remover este gasto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('gastos_eventos')
            .doc(gastoId)
            .delete();
      } catch (e) {
        debugPrint('Erro ao excluir gasto: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Gastos - ${widget.eventoNome}',
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // FORMULÁRIO PARA ADICIONAR GASTO
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              children: [
                TextField(
                  controller: _descricaoController,
                  decoration: const InputDecoration(
                    labelText: 'Descrição do gasto',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _valorController,
                        decoration: const InputDecoration(
                          labelText: 'Valor (R\$)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _categoriaController,
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _adicionarGasto,
                  icon: const Icon(Icons.add),
                  label: const Text('ADICIONAR GASTO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size(double.infinity, 45),
                  ),
                ),
              ],
            ),
          ),

          // LISTA DE GASTOS
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('gastos_eventos')
                  .where('evento_id', isEqualTo: widget.eventoId)
                  .orderBy('data', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Erro: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                double total = 0;

                for (var doc in docs) {
                  total += (doc['valor'] as num?)?.toDouble() ?? 0;
                }

                return Column(
                  children: [
                    // TOTAL
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.green.shade50,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TOTAL:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'R\$ ${total.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: docs.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt, size: 60, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text(
                              'Nenhum gasto registrado',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                          : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final gasto = doc.data() as Map<String, dynamic>;
                          final valor = (gasto['valor'] as num?)?.toDouble() ?? 0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.receipt, color: Colors.green),
                              ),
                              title: Text(gasto['descricao'] ?? ''),
                              subtitle: Text(gasto['categoria'] ?? 'Sem categoria'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'R\$ ${valor.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _excluirGasto(doc.id),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}