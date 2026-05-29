import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/uniformes/services/uniformes_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/fornecedor_service.dart';

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
  final FornecedorService _fornecedorService = FornecedorService();
  final NumberFormat _realFormat =
  NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  // Controllers
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
  XFile? _fotoArquivo; // Agora XFile para compatibilidade web
  String? _fotoUrl;
  bool _possuiVariacoes = false;
  List<Map<String, dynamic>> _variacoes = [];
  final List<String> _tamanhosPadrao = [
    'PP', 'P', 'M', 'G', 'GG', 'XG', 'XXG',
    '4A', '6A', '8A', '10A', '12A', '14A', 'Único'
  ];

  String? _fornecedorId;
  String? _fornecedorNome;

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

    _fornecedorId = data['fornecedor_id'];
    if (_fornecedorId != null) {
      _carregarFornecedor(_fornecedorId!);
    }

    if (_possuiVariacoes && data['variacoes'] != null) {
      _variacoes = List<Map<String, dynamic>>.from(data['variacoes']);
    }
  }

  Future<void> _carregarFornecedor(String fornecedorId) async {
    final doc = await _fornecedorService.getFornecedor(fornecedorId);
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _fornecedorNome = data['nome'] ?? '';
        _fornecedorController.text = _fornecedorNome ?? '';
      });
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
        _fotoArquivo = imagem; // XFile
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
    Widget imagem;
    if (_fotoArquivo != null) {
      if (kIsWeb) {
        imagem = Image.network(_fotoArquivo!.path, fit: BoxFit.contain);
      } else {
        imagem = Image.file(File(_fotoArquivo!.path), fit: BoxFit.contain);
      }
    } else if (_fotoUrl != null && _fotoUrl!.isNotEmpty) {
      imagem = CachedNetworkImage(
        imageUrl: _fotoUrl!,
        fit: BoxFit.contain,
        placeholder: (_, __) =>
            Center(child: CircularProgressIndicator(color: context.uai.primary)),
        errorWidget: (_, __, ___) =>
            Icon(Icons.broken_image, size: 80, color: context.uai.textMuted),
      );
    } else {
      return;
    }
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: InteractiveViewer(child: imagem),
      ),
    );
  }

  void _adicionarVariacao() {
    final usedSizes = _variacoes.map((v) => v['tamanho'] as String).toSet();
    final available =
    _tamanhosPadrao.where((t) => !usedSizes.contains(t)).toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Todos os tamanhos já foram adicionados!',
            style: TextStyle(color: _readableOn(context.uai.warning)),
          ),
          backgroundColor: context.uai.warning,
        ),
      );
      return;
    }

    String corHerdada = '';
    if (_variacoes.isNotEmpty) {
      corHerdada = _variacoes.last['cor'] ?? '';
    }

    setState(() {
      _variacoes.add({
        'tamanho': available.first,
        'quantidade': 0,
        'estoque_minimo': _estoqueMinimoController.text.isNotEmpty
            ? int.tryParse(_estoqueMinimoController.text) ?? 5
            : 5,
        'cor': corHerdada,
      });
    });
  }

  void _removerVariacao(int index) {
    setState(() {
      _variacoes.removeAt(index);
    });
  }

  Future<void> _selecionarFornecedor() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _SelecionarFornecedorDialog(),
    );
    if (result != null) {
      setState(() {
        _fornecedorId = result['id'];
        _fornecedorNome = result['nome'];
        _fornecedorController.text = _fornecedorNome ?? '';
      });
    }
  }

  void _removerFornecedor() {
    setState(() {
      _fornecedorId = null;
      _fornecedorNome = null;
      _fornecedorController.clear();
    });
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      String? fotoFinal = _fotoUrl;
      if (_fotoArquivo != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('estoque/${DateTime.now().millisecondsSinceEpoch}.jpg');
        if (kIsWeb) {
          final bytes = await _fotoArquivo!.readAsBytes();
          await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        } else {
          await ref.putFile(File(_fotoArquivo!.path));
        }
        fotoFinal = await ref.getDownloadURL();
      }

      if (_possuiVariacoes && _variacoes.isNotEmpty) {
        Map<String, dynamic> dadosBase = {
          'nome': _nomeController.text.toUpperCase().trim(),
          'categoria': _categoriaSelecionada,
          'preco_custo':
          double.tryParse(_precoCustoController.text.replaceAll(',', '.')) ?? 0,
          'preco_venda':
          double.tryParse(_precoVendaController.text.replaceAll(',', '.')) ?? 0,
          'fornecedor': _fornecedorNome ?? _fornecedorController.text.trim(),
          'fornecedor_id': _fornecedorId,
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
          await _uniformesService.adicionarItemEstoque(dadosBase,
              itemId: widget.itemId);
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
            'nome':
            '${_nomeController.text.toUpperCase().trim()} ${variacao['tamanho']}',
            'categoria': _categoriaSelecionada,
            'tamanho': variacao['tamanho'],
            'quantidade': variacao['quantidade'],
            'estoque_minimo': variacao['estoque_minimo'],
            'cor': variacao['cor'] ?? '',
            'preco_custo': dadosBase['preco_custo'],
            'preco_venda': dadosBase['preco_venda'],
            'fornecedor': dadosBase['fornecedor'],
            'fornecedor_id': dadosBase['fornecedor_id'],
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
              content: Text(
                widget.itemId == null
                    ? '✅ Item com variações adicionado!'
                    : '✅ Item atualizado!',
                style: TextStyle(color: _readableOn(context.uai.success)),
              ),
              backgroundColor: context.uai.success,
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
          'estoque_minimo':
          int.tryParse(_estoqueMinimoController.text) ?? 5,
          'preco_custo':
          double.tryParse(_precoCustoController.text.replaceAll(',', '.')) ?? 0,
          'preco_venda':
          double.tryParse(_precoVendaController.text.replaceAll(',', '.')) ?? 0,
          'fornecedor': _fornecedorNome ?? _fornecedorController.text.trim(),
          'fornecedor_id': _fornecedorId,
          'descricao': _descricaoController.text.trim(),
          'codigo_barras': _codigoBarrasController.text.trim(),
          'controla_estoque': _controlaEstoque,
          'possui_variacoes': false,
          'foto_url': fotoFinal,
          'status': 'ativo',
        };

        await _uniformesService.adicionarItemEstoque(dados,
            itemId: widget.itemId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.itemId == null
                    ? '✅ Item adicionado ao estoque!'
                    : '✅ Item atualizado!',
                style: TextStyle(
                    color: _readableOn(widget.itemId == null
                        ? context.uai.success
                        : context.uai.info)),
              ),
              backgroundColor: widget.itemId == null
                  ? context.uai.success
                  : context.uai.info,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ Erro ao salvar: $e',
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

  Future<void> _calcularPrecoSugerido() async {
    double custo =
        double.tryParse(_precoCustoController.text.replaceAll(',', '.')) ?? 0;
    if (custo > 0) {
      double sugerido = custo * 2.5;
      _precoVendaController.text = sugerido.toStringAsFixed(2);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '💡 Preço sugerido: ${_realFormat.format(sugerido)}',
            style: TextStyle(color: _readableOn(context.uai.info)),
          ),
          backgroundColor: context.uai.info,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primario = context.uai.primary;
    final fgPrimario = _readableOn(primario);

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(
          widget.itemId == null ? 'NOVO ITEM' : 'EDITAR ITEM',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _salvar,
            icon: _isLoading
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: fgPrimario, strokeWidth: 2),
            )
                : Icon(Icons.save, color: fgPrimario),
            label: Text(
              _isLoading ? 'SALVANDO...' : 'SALVAR',
              style: TextStyle(color: fgPrimario),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primario))
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // FOTO
            _buildCard(
              titulo: 'FOTO DO ITEM',
              child: Column(
                children: [
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
                            border:
                            Border.all(color: context.uai.border),
                            color: context.uai.cardAlt,
                          ),
                          child: _buildFotoPreview(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            _outlinedButton(
                              icon: Icons.camera_alt,
                              label: 'Câmera',
                              onPressed: () => _escolherFoto(true),
                            ),
                            const SizedBox(height: 8),
                            _outlinedButton(
                              icon: Icons.photo_library,
                              label: 'Galeria',
                              onPressed: () => _escolherFoto(false),
                            ),
                            if (_fotoArquivo != null ||
                                (_fotoUrl != null &&
                                    _fotoUrl!.isNotEmpty))
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: TextButton.icon(
                                  icon: Icon(Icons.delete,
                                      size: 18,
                                      color: context.uai.error),
                                  label: Text(
                                    'Remover foto',
                                    style: TextStyle(
                                        color: context.uai.error),
                                  ),
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
            const SizedBox(height: 16),

            // INFORMAÇÕES BÁSICAS
            _buildCard(
              titulo: 'INFORMAÇÕES BÁSICAS',
              child: Column(
                children: [
                  _buildTextField(
                    controller: _nomeController,
                    label: 'Nome do Item *',
                    icon: Icons.inventory,
                    hint: 'Ex: Camisa UAI Branca',
                    validator: (v) =>
                    v == null || v.isEmpty ? 'Campo obrigatório' : null,
                    capital: true,
                  ),
                  const SizedBox(height: 16),
                  _buildDropdownCategoria(),
                  const SizedBox(height: 16),
                  _buildSwitchListTile(
                    title: 'Possui variações de tamanho?',
                    subtitle: 'Ex: Camisa com P, M, G, GG',
                    value: _possuiVariacoes,
                    onChanged: (v) {
                      setState(() {
                        _possuiVariacoes = v;
                        if (!v) _variacoes.clear();
                      });
                    },
                  ),
                  if (!_possuiVariacoes) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _tamanhoController,
                            label: 'Tamanho',
                            icon: Icons.straighten,
                            hint: 'P, M, G, GG, Único',
                            capital: true,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            controller: _codigoBarrasController,
                            label: 'Código de Barras',
                            icon: Icons.qr_code,
                            hint: 'SKU ou código',
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // VARIAÇÕES
            if (_possuiVariacoes) ...[
              const SizedBox(height: 16),
              _buildCard(
                titulo: 'VARIAÇÕES DE TAMANHO',
                trailing: TextButton.icon(
                  onPressed: _variacoes.length < _tamanhosPadrao.length
                      ? _adicionarVariacao
                      : null,
                  icon: Icon(Icons.add,
                      size: 18,
                      color: _variacoes.length < _tamanhosPadrao.length
                          ? primario
                          : context.uai.textMuted),
                  label: Text('Adicionar',
                      style: TextStyle(
                          color: primario.withOpacity(
                              _variacoes.length < _tamanhosPadrao.length
                                  ? 1.0
                                  : 0.5))),
                ),
                child: _variacoes.isEmpty
                    ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Nenhuma variação adicionada',
                    style: TextStyle(
                        color: context.uai.textMuted),
                  ),
                )
                    : Column(
                  children: [
                    ListView.builder(
                      shrinkWrap: true,
                      physics:
                      const NeverScrollableScrollPhysics(),
                      itemCount: _variacoes.length,
                      itemBuilder: (context, index) {
                        final variacao = _variacoes[index];
                        final usedSizes = <String>{};
                        for (int j = 0; j < _variacoes.length; j++) {
                          if (j != index) {
                            usedSizes.add(
                                _variacoes[j]['tamanho'] as String);
                          }
                        }
                        var availableSizes = _tamanhosPadrao
                            .where((t) =>
                        !usedSizes.contains(t))
                            .toList();
                        if (!availableSizes
                            .contains(variacao['tamanho']) &&
                            variacao['tamanho'] != null) {
                          availableSizes.insert(
                              0, variacao['tamanho']);
                        }
                        return Padding(
                          padding:
                          const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 90,
                                child: DropdownButtonFormField<
                                    String>(
                                  value: variacao['tamanho'],
                                  style: TextStyle(
                                      fontSize: 13,
                                      color:
                                      context.uai.textPrimary),
                                  decoration:
                                  _dropdownDecoration(
                                      'Tam.'),
                                  dropdownColor: context.uai.card,
                                  menuMaxHeight: 200,
                                  items: availableSizes.map((t) {
                                    return DropdownMenuItem(
                                      value: t,
                                      child: Text(t,
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: context.uai
                                                  .textPrimary)),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      _variacoes[index]['tamanho'] =
                                          val;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                flex: 2,
                                child: _buildVariacaoField(
                                  initial: variacao['quantidade']
                                      .toString(),
                                  label: 'Qtd.',
                                  onChanged: (val) {
                                    variacao['quantidade'] =
                                        int.tryParse(val) ?? 0;
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                flex: 2,
                                child: _buildVariacaoField(
                                  initial: variacao['estoque_minimo']
                                      .toString(),
                                  label: 'Min.',
                                  onChanged: (val) {
                                    variacao['estoque_minimo'] =
                                        int.tryParse(val) ?? 5;
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                flex: 3,
                                child: _buildVariacaoField(
                                  initial: variacao['cor'] ?? '',
                                  label: 'Cor',
                                  onChanged: (val) {
                                    variacao['cor'] = val.trim();
                                  },
                                  fontSize: 12,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.remove_circle,
                                    color: context.uai.error,
                                    size: 20),
                                onPressed: () =>
                                    _removerVariacao(index),
                                padding: EdgeInsets.zero,
                                constraints:
                                const BoxConstraints(),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '* Cada variação será um item separado no estoque',
                      style: TextStyle(
                          fontSize: 11,
                          color: context.uai.textMuted),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // ESTOQUE E PREÇOS
            _buildCard(
              titulo: 'ESTOQUE E PREÇOS',
              child: Column(
                children: [
                  _buildSwitchListTile(
                    title: 'Controlar Estoque',
                    subtitle:
                    'Desative para itens sem controle (ex: serviços)',
                    value: _controlaEstoque,
                    onChanged: (v) => setState(() => _controlaEstoque = v),
                  ),
                  if (!_possuiVariacoes && _controlaEstoque) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _quantidadeController,
                            label: 'Quantidade Inicial',
                            icon: Icons.numbers,
                            hint: '0',
                            keyboard: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            controller: _estoqueMinimoController,
                            label: 'Estoque Mínimo',
                            icon: Icons.warning,
                            hint: '5',
                            keyboard: TextInputType.number,
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
                        child: _buildTextField(
                          controller: _precoCustoController,
                          label: 'Preço de Custo',
                          icon: Icons.attach_money,
                          hint: '0,00',
                          prefix: 'R\$ ',
                          keyboard: TextInputType.number,
                          onChanged: (v) {
                            if (v.isNotEmpty) _calcularPrecoSugerido();
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildTextField(
                          controller: _precoVendaController,
                          label: 'Preço de Venda *',
                          icon: Icons.sell,
                          hint: '0,00',
                          prefix: 'R\$ ',
                          keyboard: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Campo obrigatório';
                            }
                            if (double.tryParse(
                                v.replaceAll(',', '.')) ==
                                0) {
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

            const SizedBox(height: 16),

            // INFORMAÇÕES ADICIONAIS
            _buildCard(
              titulo: 'INFORMAÇÕES ADICIONAIS',
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Fornecedor',
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: context.uai.textPrimary)),
                      TextButton.icon(
                        onPressed: _selecionarFornecedor,
                        icon: Icon(Icons.add,
                            size: 18, color: primario),
                        label: Text(
                          _fornecedorId == null
                              ? 'Selecionar'
                              : 'Trocar',
                          style: TextStyle(color: primario),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _fornecedorController,
                    label: 'Nome do fornecedor',
                    icon: Icons.business,
                    suffix: _fornecedorId != null
                        ? IconButton(
                      icon: Icon(Icons.clear,
                          color: context.uai.error),
                      onPressed: _removerFornecedor,
                    )
                        : null,
                    capital: true,
                    onChanged: (_) {
                      if (_fornecedorId != null) {
                        _fornecedorId = null;
                        _fornecedorNome = null;
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _descricaoController,
                    label: 'Descrição',
                    icon: Icons.description,
                    hint: 'Descrição detalhada do item...',
                    maxLines: 3,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ElevatedButton(
                onPressed: _salvar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primario,
                  foregroundColor: fgPrimario,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(context.uai.buttonRadius),
                  ),
                ),
                child: const Text(
                  'SALVAR ITEM',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Widgets auxiliares para manter a consistência ───
  Widget _buildCard({
    required String titulo,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        border: Border.all(color: context.uai.border),
        boxShadow: context.uai.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                titulo,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: context.uai.textPrimary),
              ),
              if (trailing != null) trailing,
            ],
          ),
          Divider(color: context.uai.border),
          child,
        ],
      ),
    );
  }

  Widget _outlinedButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.uai.primary,
        side: BorderSide(color: context.uai.primary.withOpacity(0.5)),
        minimumSize: const Size(double.infinity, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.uai.buttonRadius),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? prefix,
    TextInputType? keyboard,
    bool capital = false,
    int maxLines = 1,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: maxLines,
      textCapitalization:
      capital ? TextCapitalization.characters : TextCapitalization.none,
      style: TextStyle(color: context.uai.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: context.uai.primary),
        prefixText: prefix,
        suffixIcon: suffix,
        labelStyle: TextStyle(color: context.uai.textSecondary),
        hintStyle: TextStyle(color: context.uai.textMuted),
        filled: true,
        fillColor: context.uai.cardAlt,
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
          borderSide: BorderSide(color: context.uai.primary, width: 1.4),
        ),
        alignLabelWithHint: maxLines > 1,
      ),
      validator: validator,
      onChanged: onChanged,
    );
  }

  Widget _buildDropdownCategoria() {
    return DropdownButtonFormField<String>(
      value: _categoriaSelecionada,
      style: TextStyle(color: context.uai.textPrimary),
      decoration: InputDecoration(
        labelText: 'Categoria *',
        prefixIcon: Icon(Icons.category, color: context.uai.primary),
        labelStyle: TextStyle(color: context.uai.textSecondary),
        filled: true,
        fillColor: context.uai.cardAlt,
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
          borderSide: BorderSide(color: context.uai.primary, width: 1.4),
        ),
      ),
      dropdownColor: context.uai.card,
      items: _categorias
          .map((categoria) => DropdownMenuItem(
        value: categoria,
        child: Text(categoria),
      ))
          .toList(),
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
    );
  }

  InputDecoration _dropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle:
      TextStyle(color: context.uai.textSecondary, fontSize: 11),
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
        borderSide: BorderSide(color: context.uai.primary, width: 1.4),
      ),
      isDense: true,
      contentPadding:
      const EdgeInsets.only(left: 6, right: 2, top: 4, bottom: 4),
      filled: true,
      fillColor: context.uai.cardAlt,
    );
  }

  Widget _buildSwitchListTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title, style: TextStyle(color: context.uai.textPrimary)),
      subtitle: Text(subtitle, style: TextStyle(color: context.uai.textSecondary)),
      value: value,
      onChanged: onChanged,
      activeColor: context.uai.primary,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildVariacaoField({
    required String initial,
    required String label,
    required ValueChanged<String> onChanged,
    double fontSize = 13,
  }) {
    return TextFormField(
      initialValue: initial,
      keyboardType: TextInputType.number,
      style: TextStyle(fontSize: fontSize, color: context.uai.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 11, color: context.uai.textSecondary),
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
          borderSide: BorderSide(color: context.uai.primary, width: 1.4),
        ),
        isDense: true,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        filled: true,
        fillColor: context.uai.cardAlt,
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildFotoPreview() {
    if (_fotoArquivo != null) {
      if (kIsWeb) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            _fotoArquivo!.path,
            fit: BoxFit.cover,
            width: 120,
            height: 120,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.photo_camera, size: 40, color: context.uai.textMuted),
          ),
        );
      } else {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(_fotoArquivo!.path),
            fit: BoxFit.cover,
            width: 120,
            height: 120,
          ),
        );
      }
    } else if (_fotoUrl != null && _fotoUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: _fotoUrl!,
        imageBuilder: (context, imageProvider) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
          ),
        ),
        placeholder: (_, __) =>
            Center(child: CircularProgressIndicator(color: context.uai.primary)),
        errorWidget: (_, __, ___) =>
            Icon(Icons.photo_camera, size: 40, color: context.uai.textMuted),
      );
    }
    return Icon(Icons.photo_camera, size: 40, color: context.uai.textMuted);
  }
}

// ─── Diálogo de seleção de fornecedor (refatorado) ─────────────────
class _SelecionarFornecedorDialog extends StatefulWidget {
  @override
  State<_SelecionarFornecedorDialog> createState() =>
      _SelecionarFornecedorDialogState();
}

class _SelecionarFornecedorDialogState
    extends State<_SelecionarFornecedorDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _search = '';

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
              style: TextStyle(color: context.uai.textPrimary),
              decoration: InputDecoration(
                hintText: 'Pesquisar fornecedor...',
                hintStyle: TextStyle(color: context.uai.textMuted),
                prefixIcon: Icon(Icons.search, color: context.uai.textMuted),
                filled: true,
                fillColor: context.uai.cardAlt,
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
                  borderSide: BorderSide(color: context.uai.primary, width: 1.4),
                ),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('fornecedores')
                    .where('status', isEqualTo: 'ativo')
                    .orderBy('nome')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Center(
                      child: CircularProgressIndicator(
                          color: context.uai.primary),
                    );
                  }
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
                      child: Text(
                        'Nenhum fornecedor encontrado',
                        style: TextStyle(color: context.uai.textMuted),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      return ListTile(
                        leading: Icon(Icons.business,
                            color: context.uai.primary),
                        title: Text(data['nome'] ?? '',
                            style: TextStyle(
                                color: context.uai.textPrimary)),
                        subtitle: Text(data['contato'] ?? '',
                            style: TextStyle(
                                color: context.uai.textSecondary)),
                        onTap: () => Navigator.pop(
                            context,
                            <String, String>{
                              'id': docs[i].id,
                              'nome': (data['nome'] ?? '').toString(),
                            }),
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