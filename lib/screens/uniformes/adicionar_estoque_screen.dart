import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/services/uniformes_service.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';

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

  // Foto e Variações
  File? _fotoArquivo;
  String? _fotoUrl;
  bool _possuiVariacoes = false;
  List<Map<String, dynamic>> _variacoes = [];
  final List<String> _tamanhosPadrao = [
    'PP', 'P', 'M', 'G', 'GG', 'XG', 'XXG',
    '4A', '6A', '8A', '10A', '12A', '14A', 'Único'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.itemData != null) {
      _preencherDados();
    }
  }

  void _preencherDados() {
    final data = widget.itemData!;
    _nomeController.text = data['nome'] ?? '';
    _categoriaSelecionada = data['categoria'];
    _tamanhoController.text = data['tamanho'] ?? '';
    _quantidadeController.text = data['quantidade']?.toString() ?? '0';
    _estoqueMinimoController.text = data['estoque_minimo']?.toString() ?? '5';
    _precoCustoController.text = data['preco_custo']?.toString() ?? '';
    _precoVendaController.text = data['preco_venda']?.toString() ?? '';
    _fornecedorController.text = data['fornecedor'] ?? '';
    _descricaoController.text = data['descricao'] ?? '';
    _codigoBarrasController.text = data['codigo_barras'] ?? '';
    _controlaEstoque = data['controla_estoque'] ?? true;
    _fotoUrl = data['foto_url'];
    _possuiVariacoes = data['possui_variacoes'] ?? false;

    if (_possuiVariacoes && data['variacoes'] != null) {
      _variacoes = List<Map<String, dynamic>>.from(data['variacoes']);
    }
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

  Future<void> _escolherFoto(bool daCamera) async {
    final picker = ImagePicker();
    final XFile? imagem = daCamera
        ? await picker.pickImage(source: ImageSource.camera)
        : await picker.pickImage(source: ImageSource.gallery);
    if (imagem != null) {
      setState(() {
        _fotoArquivo = File(imagem.path);
        _fotoUrl = null;
      });
    }
  }

  void _removerFoto() {
    setState(() {
      _fotoArquivo = null;
      _fotoUrl = null;
    });
  }

  void _mostrarFotoAmpliada() {
    if (_fotoArquivo != null) {
      showDialog(
        context: context,
        builder: (_) => InteractiveViewer(
          child: Image.file(_fotoArquivo!, fit: BoxFit.contain),
        ),
      );
    } else if (_fotoUrl != null && _fotoUrl!.isNotEmpty) {
      showDialog(
        context: context,
        builder: (_) => InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: _fotoUrl!,
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 80),
          ),
        ),
      );
    }
  }

  void _adicionarVariacao() {
    setState(() {
      _variacoes.add({
        'tamanho': 'P',
        'quantidade': 0,
        'estoque_minimo': _estoqueMinimoController.text.isNotEmpty
            ? int.tryParse(_estoqueMinimoController.text) ?? 5
            : 5,
      });
    });
  }

  void _removerVariacao(int index) {
    setState(() {
      _variacoes.removeAt(index);
    });
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      String? fotoFinal = _fotoUrl;
      if (_fotoArquivo != null) {
        fotoFinal = _fotoArquivo!.path;
      }

      if (_possuiVariacoes && _variacoes.isNotEmpty) {
        Map<String, dynamic> dadosBase = {
          'nome': _nomeController.text.toUpperCase().trim(),
          'categoria': _categoriaSelecionada,
          'preco_custo': double.tryParse(_precoCustoController.text.replaceAll(',', '.')) ?? 0,
          'preco_venda': double.tryParse(_precoVendaController.text.replaceAll(',', '.')) ?? 0,
          'fornecedor': _fornecedorController.text.toUpperCase().trim(),
          'descricao': _descricaoController.text.trim(),
          'codigo_barras': _codigoBarrasController.text.trim(),
          'controla_estoque': _controlaEstoque,
          'possui_variacoes': true,
          'variacoes': _variacoes,
          'foto_url': fotoFinal,
          'status': 'ativo',
          'tipo': 'base',
        };

        String baseId;
        if (widget.itemId != null) {
          await _uniformesService.adicionarItemEstoque(dadosBase, itemId: widget.itemId);
          baseId = widget.itemId!;
          final variacoesAntigas = await FirebaseFirestore.instance
              .collection('uniformes_estoque')
              .where('item_base_id', isEqualTo: baseId)
              .get();
          for (var doc in variacoesAntigas.docs) {
            await doc.reference.delete();
          }
        } else {
          baseId = await _uniformesService.adicionarItemEstoque(dadosBase);
        }

        for (var variacao in _variacoes) {
          Map<String, dynamic> dadosVariacao = {
            'nome': '${_nomeController.text.toUpperCase().trim()} ${variacao['tamanho']}',
            'categoria': _categoriaSelecionada,
            'tamanho': variacao['tamanho'],
            'quantidade': variacao['quantidade'],
            'estoque_minimo': variacao['estoque_minimo'],
            'preco_custo': dadosBase['preco_custo'],
            'preco_venda': dadosBase['preco_venda'],
            'fornecedor': dadosBase['fornecedor'],
            'descricao': dadosBase['descricao'],
            'codigo_barras': dadosBase['codigo_barras'],
            'controla_estoque': _controlaEstoque,
            'possui_variacoes': false,
            'item_base_id': baseId,
            'foto_url': fotoFinal,
            'status': 'ativo',
            'tipo': 'variacao',
          };
          await _uniformesService.adicionarItemEstoque(dadosVariacao);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.itemId == null
                  ? '✅ Item com variações adicionado!'
                  : '✅ Item atualizado!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
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
          'possui_variacoes': false,
          'foto_url': fotoFinal,
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
      double sugerido = custo * 2.5;
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
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
            // FOTO
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FOTO DO ITEM',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _mostrarFotoAmpliada,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                              color: Colors.grey.shade100,
                            ),
                            child: _buildFotoPreview(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Câmera'),
                                onPressed: () => _escolherFoto(true),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 44),
                                ),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.photo_library),
                                label: const Text('Galeria'),
                                onPressed: () => _escolherFoto(false),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 44),
                                ),
                              ),
                              if (_fotoArquivo != null || (_fotoUrl != null && _fotoUrl!.isNotEmpty))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                    label: const Text('Remover foto', style: TextStyle(color: Colors.red)),
                                    onPressed: _removerFoto,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

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

                    SwitchListTile(
                      title: const Text('Possui variações de tamanho?'),
                      subtitle: const Text('Ex: Camisa com P, M, G, GG'),
                      value: _possuiVariacoes,
                      onChanged: (value) {
                        setState(() {
                          _possuiVariacoes = value;
                          if (!value) _variacoes.clear();
                        });
                      },
                    ),

                    if (!_possuiVariacoes) ...[
                      const SizedBox(height: 8),
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
                  ],
                ),
              ),
            ),

            // VARIAÇÕES (CORRIGIDO: texto preto + menu com scroll)
            if (_possuiVariacoes) ...[
              const SizedBox(height: 16),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'VARIAÇÕES DE TAMANHO',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          TextButton.icon(
                            onPressed: _adicionarVariacao,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Adicionar'),
                          ),
                        ],
                      ),
                      const Divider(),
                      if (_variacoes.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Nenhuma variação adicionada',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _variacoes.length,
                          itemBuilder: (context, index) {
                            final variacao = _variacoes[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  // 🔧 DROPDOWN COM TEXTO PRETO, FUNDO BRANCO E SCROLL (menuMaxHeight)
                                  SizedBox(
                                    width: 100,
                                    child: DropdownButtonFormField<String>(
                                      value: variacao['tamanho'],
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.black87,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'Tam.',
                                        labelStyle: TextStyle(color: Colors.black87),
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        contentPadding: EdgeInsets.only(left: 6, right: 2, top: 4, bottom: 4),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                      dropdownColor: Colors.white,
                                      menuMaxHeight: 200, // scroll depois de ~5 itens
                                      items: _tamanhosPadrao.map((t) {
                                        return DropdownMenuItem(
                                          value: t,
                                          child: Text(
                                            t,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        setState(() {
                                          _variacoes[index]['tamanho'] = val;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Quantidade
                                  Expanded(
                                    child: TextFormField(
                                      keyboardType: TextInputType.number,
                                      initialValue: variacao['quantidade'].toString(),
                                      decoration: const InputDecoration(
                                        labelText: 'Qtd.',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      ),
                                      style: const TextStyle(fontSize: 13),
                                      onChanged: (val) {
                                        variacao['quantidade'] = int.tryParse(val) ?? 0;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Estoque mínimo
                                  Expanded(
                                    child: TextFormField(
                                      keyboardType: TextInputType.number,
                                      initialValue: variacao['estoque_minimo'].toString(),
                                      decoration: const InputDecoration(
                                        labelText: 'Min.',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      ),
                                      style: const TextStyle(fontSize: 13),
                                      onChanged: (val) {
                                        variacao['estoque_minimo'] = int.tryParse(val) ?? 5;
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                                    onPressed: () => _removerVariacao(index),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 8),
                      Text(
                        '* Cada variação será um item separado no estoque',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            ],

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

                    if (!_possuiVariacoes && _controlaEstoque) ...[
                      const SizedBox(height: 16),
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

  Widget _buildFotoPreview() {
    if (_fotoArquivo != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(_fotoArquivo!, fit: BoxFit.cover, width: 120, height: 120),
      );
    } else if (_fotoUrl != null && _fotoUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: _fotoUrl!,
        imageBuilder: (context, imageProvider) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
          ),
        ),
        placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
        errorWidget: (_, __, ___) => const Icon(Icons.photo_camera, size: 40, color: Colors.grey),
      );
    }
    return const Icon(Icons.photo_camera, size: 40, color: Colors.grey);
  }
}