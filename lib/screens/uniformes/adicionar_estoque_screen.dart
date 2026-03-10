import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/services/uniformes_service.dart';

class AdicionarEstoqueScreen extends StatefulWidget {
  final String? itemId;
  final Map<String, dynamic>? itemData;

  const AdicionarEstoqueScreen({super.key, this.itemId, this.itemData});

  @override
  State<AdicionarEstoqueScreen> createState() => _AdicionarEstoqueScreenState();
}

class _AdicionarEstoqueScreenState extends State<AdicionarEstoqueScreen> {
  final _formKey = GlobalKey<FormState>();
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final UniformesService _uniformesService = UniformesService();
  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  // Controladores
  final _nomeController = TextEditingController();
  final _tamanhoController = TextEditingController();
  final _quantidadeController = TextEditingController();
  final _estoqueMinimoController = TextEditingController();
  final _precoCustoController = TextEditingController();
  final _precoVendaController = TextEditingController();
  final _fornecedorController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _codigoBarrasController = TextEditingController();

  String? _categoriaSelecionada;
  final List<String> _categorias = [
    'Camisa',
    'Calça',
    'Bermuda',
    'Abadá',
    'Corda',
    'Acessório',
    'Outro',
  ];

  bool _controlaEstoque = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.itemData != null) {
      _preencherDados();
    }
  }

  void _preencherDados() {
    _nomeController.text = widget.itemData!['nome'] ?? '';
    _categoriaSelecionada = widget.itemData!['categoria'];
    _tamanhoController.text = widget.itemData!['tamanho'] ?? '';
    _quantidadeController.text = widget.itemData!['quantidade']?.toString() ?? '0';
    _estoqueMinimoController.text = widget.itemData!['estoque_minimo']?.toString() ?? '5';
    _precoCustoController.text = widget.itemData!['preco_custo']?.toString() ?? '';
    _precoVendaController.text = widget.itemData!['preco_venda']?.toString() ?? '';
    _fornecedorController.text = widget.itemData!['fornecedor'] ?? '';
    _descricaoController.text = widget.itemData!['descricao'] ?? '';
    _codigoBarrasController.text = widget.itemData!['codigo_barras'] ?? '';
    _controlaEstoque = widget.itemData!['controla_estoque'] ?? true;
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _tamanhoController.dispose();
    _quantidadeController.dispose();
    _estoqueMinimoController.dispose();
    _precoCustoController.dispose();
    _precoVendaController.dispose();
    _fornecedorController.dispose();
    _descricaoController.dispose();
    _codigoBarrasController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      Map<String, dynamic> dados = {
        'nome': _nomeController.text.toUpperCase().trim(),
        'categoria': _categoriaSelecionada,
        'tamanho': _tamanhoController.text.toUpperCase().trim(),
        'quantidade': int.tryParse(_quantidadeController.text) ?? 0,
        'estoque_minimo': int.tryParse(_estoqueMinimoController.text) ?? 5,
        'preco_custo': double.tryParse(_precoCustoController.text.replaceAll(',', '.')) ?? 0,
        'preco_venda': double.tryParse(_precoVendaController.text.replaceAll(',', '.')) ?? 0,
        'fornecedor': _fornecedorController.text.toUpperCase().trim(),
        'descricao': _descricaoController.text.trim(),
        'codigo_barras': _codigoBarrasController.text.trim(),
        'controla_estoque': _controlaEstoque,
        'status': 'ativo',
      };

      await _uniformesService.adicionarItemEstoque(dados, itemId: widget.itemId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.itemId == null
                ? '✅ Item adicionado ao estoque!'
                : '✅ Item atualizado!'),
            backgroundColor: widget.itemId == null ? Colors.green : Colors.blue,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _calcularPrecoSugerido() async {
    double custo = double.tryParse(_precoCustoController.text.replaceAll(',', '.')) ?? 0;
    if (custo > 0) {
      double sugerido = custo * 2.5; // Margem de 150%
      _precoVendaController.text = sugerido.toStringAsFixed(2);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💡 Preço sugerido: ${_realFormat.format(sugerido)}'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.itemId == null ? 'NOVO ITEM' : 'EDITAR ITEM'),
        backgroundColor: Colors.green.shade900,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _salvar,
            icon: _isLoading
                ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
            )
                : const Icon(Icons.save, color: Colors.white),
            label: Text(
              _isLoading ? 'SALVANDO...' : 'SALVAR',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // INFORMAÇÕES BÁSICAS
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'INFORMAÇÕES BÁSICAS',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Divider(),

                    // Nome do Item
                    TextFormField(
                      controller: _nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do Item *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.inventory),
                        hintText: 'Ex: Camisa UAI Branca',
                      ),
                      textCapitalization: TextCapitalization.characters,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Campo obrigatório';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Categoria
                    DropdownButtonFormField<String>(
                      value: _categoriaSelecionada,
                      decoration: const InputDecoration(
                        labelText: 'Categoria *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category),
                      ),
                      items: _categorias.map((categoria) {
                        return DropdownMenuItem(
                          value: categoria,
                          child: Text(categoria),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _categoriaSelecionada = value;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Selecione uma categoria';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Tamanho e Código
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _tamanhoController,
                            decoration: const InputDecoration(
                              labelText: 'Tamanho',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.straighten),
                              hintText: 'P, M, G, GG, Único',
                            ),
                            textCapitalization: TextCapitalization.characters,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _codigoBarrasController,
                            decoration: const InputDecoration(
                              labelText: 'Código de Barras',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.qr_code),
                              hintText: 'SKU ou código',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ESTOQUE E PREÇOS
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ESTOQUE E PREÇOS',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Divider(),

                    // Switch Controlar Estoque
                    SwitchListTile(
                      title: const Text('Controlar Estoque'),
                      subtitle: const Text('Desative para itens sem controle (ex: serviços)'),
                      value: _controlaEstoque,
                      onChanged: (value) {
                        setState(() {
                          _controlaEstoque = value;
                        });
                      },
                    ),

                    if (_controlaEstoque) ...[
                      const SizedBox(height: 16),

                      // Quantidade e Estoque Mínimo
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _quantidadeController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Quantidade Inicial',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.numbers),
                                hintText: '0',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _estoqueMinimoController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Estoque Mínimo',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.warning),
                                hintText: '5',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Preços
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _precoCustoController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Preço de Custo',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.attach_money),
                              prefixText: 'R\$ ',
                              hintText: '0,00',
                            ),
                            onChanged: (value) {
                              if (value.isNotEmpty) {
                                _calcularPrecoSugerido();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _precoVendaController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Preço de Venda *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.sell),
                              prefixText: 'R\$ ',
                              hintText: '0,00',
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Campo obrigatório';
                              }
                              if (double.tryParse(value.replaceAll(',', '.')) == 0) {
                                return 'Preço deve ser maior que zero';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // INFORMAÇÕES ADICIONAIS
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'INFORMAÇÕES ADICIONAIS',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Divider(),

                    // Fornecedor
                    TextFormField(
                      controller: _fornecedorController,
                      decoration: const InputDecoration(
                        labelText: 'Fornecedor',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.business),
                        hintText: 'Nome do fornecedor',
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),

                    const SizedBox(height: 16),

                    // Descrição
                    TextFormField(
                      controller: _descricaoController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Descrição',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                        hintText: 'Descrição detalhada do item...',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // BOTÃO DE SALVAR (rodapé)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ElevatedButton(
                onPressed: _salvar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade900,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'SALVAR ITEM',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}