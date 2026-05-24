import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/services/fornecedor_service.dart';
import 'fornecedor_form_screen.dart';

class FornecedoresListScreen extends StatefulWidget {
  const FornecedoresListScreen({super.key});

  @override
  State<FornecedoresListScreen> createState() => _FornecedoresListScreenState();
}

class _FornecedoresListScreenState extends State<FornecedoresListScreen> {
  final FornecedorService _fornecedorService = FornecedorService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _excluirFornecedor(String fornecedorId, String nome) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir fornecedor'),
        content: Text('Tem certeza que deseja excluir "$nome"?'),
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
      await _fornecedorService.excluirFornecedor(fornecedorId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Fornecedor excluído!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _abrirFormulario({String? fornecedorId, Map<String, dynamic>? fornecedorData}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FornecedorFormScreen(
          fornecedorId: fornecedorId,
          fornecedorData: fornecedorData,
        ),
      ),
    );
    if (result == true) {
      // Recarregar a lista (StreamBuilder já atualiza automaticamente)
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FORNECEDORES'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Novo fornecedor',
            onPressed: () => _abrirFormulario(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar fornecedor...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _fornecedorService.getFornecedoresAtivos(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Erro: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var fornecedores = snapshot.data!.docs;
                if (_searchQuery.isNotEmpty) {
                  fornecedores = fornecedores.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final nome = data['nome']?.toString().toLowerCase() ?? '';
                    return nome.contains(_searchQuery.toLowerCase());
                  }).toList();
                }

                if (fornecedores.isEmpty) {
                  return const Center(child: Text('Nenhum fornecedor encontrado'));
                }

                return ListView.builder(
                  itemCount: fornecedores.length,
                  itemBuilder: (_, index) {
                    final doc = fornecedores[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final nome = data['nome'] ?? 'Sem nome';
                    final contato = data['contato'] ?? '';
                    final telefone = data['telefone'] ?? '';

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.business),
                        ),
                        title: Text(nome),
                        subtitle: Text('$contato${telefone.isNotEmpty ? ' • $telefone' : ''}'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'editar') {
                              _abrirFormulario(fornecedorId: doc.id, fornecedorData: data);
                            } else if (value == 'excluir') {
                              _excluirFornecedor(doc.id, nome);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'editar', child: Text('Editar')),
                            PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                          ],
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
}