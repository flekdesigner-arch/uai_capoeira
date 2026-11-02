import '../dialogs/uniformes_motivo_dialog.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/uniformes/services/remessa_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/uniformes_admin_service.dart';
import 'package:uai_capoeira/modules/uniformes/widgets/remessa_precificacao_editor.dart';
import 'package:uai_capoeira/modules/uniformes/services/fornecedor_service.dart';

class RemessaFormScreen extends StatefulWidget {
  final String? remessaId;
  final Map<String, dynamic>? remessaData;
  const RemessaFormScreen({super.key, this.remessaId, this.remessaData});

  @override
  State<RemessaFormScreen> createState() => _RemessaFormScreenState();
}

class _RemessaFormScreenState extends State<RemessaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final RemessaService _remessaService = RemessaService();
  final FornecedorService _fornecedorService = FornecedorService();
  final UniformesAdminService _admin = UniformesAdminService();
  final _pricingKey = GlobalKey<RemessaPrecificacaoEditorState>();
  bool _pricingLocked = false;
  String _capaModo = 'icone';
  String _capaIcone = 'remessa';
  String? _imagemSugerida;

  final _nomeController = TextEditingController();
  final _observacoesController = TextEditingController();
  final _custosExtrasController = TextEditingController(text: '0');
  DateTime? _dataEnvio;
  DateTime? _dataPrevista;
  String _status = 'pendente';
  List<String> _pedidosSelecionados = [];
  bool _isLoading = false;

  XFile? _capaArquivo;
  String? _capaUrl;

  String? _fornecedorId;
  String? _fornecedorNome;
  Map<String, dynamic>? _fornecedorDetalhes;

  // Helpers de contraste
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  @override
  void initState() {
    super.initState();
    if (widget.remessaData != null) {
      _nomeController.text = widget.remessaData!['nome'] ?? '';
      _observacoesController.text = widget.remessaData!['observacoes'] ?? '';
      _custosExtrasController.text = ((widget.remessaData!['custos_extras_centavos'] as num? ?? 0) / 100).toStringAsFixed(2);
      _status = widget.remessaData!['status'] ?? 'pendente';
      _capaUrl = (widget.remessaData!['capa_url'] ?? '').toString().trim();
      _capaModo = (widget.remessaData!['capa_modo'] ?? (_capaUrl!.isNotEmpty ? 'imagem' : 'icone')).toString();
      _capaIcone = (widget.remessaData!['capa_icone'] ?? 'remessa').toString();
      _pricingLocked = true; // até verificar se há pedidos ou pagamentos
      _verificarPedidosVinculados();
      if (_capaUrl != null && _capaUrl!.isEmpty) {
        _capaUrl = null;
      }
      if (widget.remessaData!['data_envio'] != null) {
        _dataEnvio = (widget.remessaData!['data_envio'] as Timestamp).toDate();
      }
      if (widget.remessaData!['data_prevista'] != null) {
        _dataPrevista = (widget.remessaData!['data_prevista'] as Timestamp)
            .toDate();
      }
      _pedidosSelecionados = List<String>.from(
        widget.remessaData!['pedidos_ids'] ?? [],
      );
      _fornecedorId = widget.remessaData!['fornecedor_id'];
      if (_fornecedorId != null) {
        _carregarFornecedor(_fornecedorId!);
      }
    }
  }

  Future<void> _verificarPedidosVinculados() async {
    if (widget.remessaId == null) return;
    try {
      final result = await FirebaseFirestore.instance.collection('pedidos_uniformes')
          .where('remessa_id', isEqualTo: widget.remessaId).limit(1).get();
      final paid = (widget.remessaData?['total_pago_fornecedor_centavos'] as num? ?? 0) > 0;
      final closed = ['finalizada', 'recebida', 'cancelada'].contains(_status);
      if (mounted) setState(() => _pricingLocked = paid || closed || result.docs.isNotEmpty);
    } catch (_) {
      // Modo conservador: sem verificar o histórico, não editar valores.
      if (mounted) setState(() => _pricingLocked = true);
    }
  }

  Future<void> _selecionarCapa() async {
    final arquivo = await ImagePicker().pickImage(source: ImageSource.gallery,
      maxWidth: 1400, imageQuality: 86);
    if (arquivo != null && mounted) {
      setState(() { _capaArquivo = arquivo; _capaModo = 'imagem'; });
    }
  }

  void _usarImagemCatalogo(String url) {
    if (url.isEmpty || _capaArquivo != null || _capaUrl != null) return;
    if (mounted) {
      setState(() {
        _imagemSugerida = url;
        _capaModo = 'imagem';
      });
    }
  }

  IconData _iconeCapa(String tipo) => switch (tipo) {
    'camisa' => Icons.checkroom_rounded,
    'calca' => Icons.dry_cleaning_outlined,
    'estoque' => Icons.inventory_2_rounded,
    'uniforme' => Icons.sports_martial_arts_rounded,
    _ => Icons.local_shipping_rounded,
  };

  Widget _editorCapa() {
    final t = context.uai;
    final imagem = _capaUrl ?? _imagemSugerida;
    return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Identidade visual da remessa', style: TextStyle(
        fontWeight: FontWeight.w900, fontSize: 16, color: t.textPrimary)),
      const SizedBox(height: 6),
      Text('Use a foto do catálogo, envie outra imagem ou escolha um ícone.',
        style: TextStyle(color: t.textSecondary, fontSize: 12)),
      const SizedBox(height: 12),
      Center(child: ClipRRect(borderRadius: BorderRadius.circular(16),
        child: Container(width: 110, height: 105, alignment: Alignment.center,
          color: t.primary.withAlpha(22),
          child: _capaModo == 'imagem' && _capaArquivo != null
            ? FutureBuilder(future: _capaArquivo!.readAsBytes(), builder: (ctx, snap) =>
                snap.hasData ? Image.memory(snap.data!, fit: BoxFit.cover,
                  width: 110, height: 105) : const CircularProgressIndicator())
            : _capaModo == 'imagem' && imagem != null && imagem.isNotEmpty
            ? Image.network(imagem, fit: BoxFit.cover, width: 110, height: 105,
                errorBuilder: (_, error, stack) => Icon(Icons.image_not_supported, color: t.primary))
            : Icon(_iconeCapa(_capaIcone), size: 52, color: t.primary)))),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        OutlinedButton.icon(onPressed: _selecionarCapa, icon: const Icon(Icons.upload_file),
          label: const Text('Enviar imagem')),
        if (imagem != null && imagem.isNotEmpty)
          OutlinedButton.icon(onPressed: () => setState(() {
            _capaModo = 'imagem'; _capaArquivo = null;
          }), icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Usar imagem do catálogo')),
        PopupMenuButton<String>(tooltip: 'Selecionar ícone da remessa',
          onSelected: (v) => setState(() { _capaModo = 'icone'; _capaIcone = v; }),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'camisa', child: Text('Camisa')),
            PopupMenuItem(value: 'calca', child: Text('Calça')),
            PopupMenuItem(value: 'uniforme', child: Text('Uniforme')),
            PopupMenuItem(value: 'estoque', child: Text('Estoque')),
            PopupMenuItem(value: 'remessa', child: Text('Caminhão / Remessa')),
          ], child: const Chip(avatar: Icon(Icons.palette_outlined), label: Text('Ícone'))),
      ]),
    ])));
  }

  Future<void> _carregarFornecedor(String fornecedorId) async {
    final doc = await _fornecedorService.getFornecedor(fornecedorId);
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _fornecedorDetalhes = data;
        _fornecedorNome = data['nome'] ?? 'Fornecedor sem nome';
      });
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _observacoesController.dispose();
    _custosExtrasController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    List<Map<String, dynamic>>? precificacao;
    if (!_pricingLocked) {
      try {
        precificacao = _pricingKey.currentState!.validarEObterItens();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        return;
      }
    }
    if (_fornecedorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selecione o fornecedor da remessa.')));
      return;
    }
    final extraInput = _custosExtrasController.text.trim().replaceAll(',', '.');
    final extras = num.tryParse(extraInput);
    if (extras == null || extras < 0 || !extras.isFinite ||
        ((extras * 100).round() - extras * 100).abs() > 0.000001) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Informe custos extras válidos, com até duas casas decimais.')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      String? capaFinal = _capaUrl ?? _imagemSugerida;

      if (_capaArquivo != null) {
        final bytes = await _capaArquivo!.readAsBytes();
        final storageRef = FirebaseStorage.instance.ref().child(
          'uniformes/remessas/${widget.remessaId ?? DateTime.now().millisecondsSinceEpoch}.jpg',
        );

        await storageRef.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );

        capaFinal = await storageRef.getDownloadURL();
        _capaUrl = capaFinal;
        _capaArquivo = null;
      }

      String? motivo;
      if (_status == 'cancelada') {
        if (!mounted) return;
        motivo = await solicitarMotivoUniformes(
          context,
          'Justificativa do cancelamento',
        );
        if (motivo == null) return;
      }
      final dados = {
        'motivo': ?motivo,
        'nome': _nomeController.text.trim(),
        'capa_url': capaFinal,
        'capa_modo': _capaModo,
        'capa_icone': _capaIcone,
        'data_envio': _dataEnvio != null
            ? Timestamp.fromDate(_dataEnvio!)
            : null,
        'data_prevista': _dataPrevista != null
            ? Timestamp.fromDate(_dataPrevista!)
            : null,
        'status': _status,
        'observacoes': _observacoesController.text.trim(),
        'pedidos_ids': _pedidosSelecionados,
        'fornecedor_id': _fornecedorId,
      };

      String? createdId;
      if (widget.remessaId == null) {
        createdId = await _remessaService.criarRemessa(dados);
      } else {
        await _remessaService.atualizarRemessa(widget.remessaId!, dados);
      }
      // O editor de custos pertence ao próprio formulário da remessa.
      // A callable valida cada variação e congela os preços históricos.
      if (precificacao != null) {
        try {
          await _admin.call('configurarCustosRemessaUniformes', {
            'remessaId': createdId ?? widget.remessaId,
            'itens': precificacao,
            'custosExtras': extras.toDouble(),
          });
        } catch (e) {
          // O cadastro pode já ter sido criado: nunca dizer que foi salvo
          // integralmente quando a segunda operação falhou.
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            'A remessa foi cadastrada, mas a precificação não foi confirmada. '
            'Abra Editar Remessa e tente novamente. Detalhe: $e')));
          Navigator.pop(context, true);
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.remessaId == null
                  ? 'Remessa criada!'
                  : 'Remessa atualizada!',
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
              'Erro: $e',
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

  Future<void> _selecionarPedidos() async {
    final selecionados = await showDialog<List<String>>(
      context: context,
      builder: (_) =>
          _SelecionarPedidosDialog(selectedIds: _pedidosSelecionados),
    );
    if (selecionados != null) {
      setState(() => _pedidosSelecionados = selecionados);
    }
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
        _fornecedorDetalhes = null;
      });
    }
  }

  void _removerFornecedor() {
    setState(() {
      _fornecedorId = null;
      _fornecedorNome = null;
      _fornecedorDetalhes = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.uai.primary;
    final onPrimary = _readableOn(primary);
    final textPrimary = context.uai.textPrimary;
    final textSecondary = context.uai.textSecondary;
    final textMuted = context.uai.textMuted;
    final cardBg = context.uai.card;
    final border = context.uai.border;
    final cardAlt = context.uai.cardAlt;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(
          widget.remessaId == null ? 'NOVA REMESSA' : 'EDITAR REMESSA',
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
                      color: onPrimary,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(Icons.save, color: onPrimary),
            label: Text('SALVAR', style: TextStyle(color: onPrimary)),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildTextField(
                    controller: _nomeController,
                    label: 'Nome da remessa *',
                    icon: Icons.label,
                    validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDateField(
                          'Data de envio',
                          _dataEnvio,
                          (d) => setState(() => _dataEnvio = d),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildDateField(
                          'Data prevista',
                          _dataPrevista,
                          (d) => setState(() => _dataPrevista = d),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // FORNECEDOR
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(
                        context.uai.cardRadius,
                      ),
                      border: Border.all(color: border),
                      boxShadow: context.uai.softShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Fornecedor',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _selecionarFornecedor,
                              icon: Icon(Icons.add, size: 18, color: primary),
                              label: Text(
                                _fornecedorId == null ? 'Selecionar' : 'Trocar',
                                style: TextStyle(color: primary),
                              ),
                            ),
                          ],
                        ),
                        if (_fornecedorNome != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.business, size: 16, color: textMuted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _fornecedorNome!,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.clear,
                                  color: context.uai.error,
                                  size: 18,
                                ),
                                onPressed: _removerFornecedor,
                              ),
                            ],
                          ),
                          if (_fornecedorDetalhes != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Contato: ${_fornecedorDetalhes!['contato'] ?? 'N/I'} • ${_fornecedorDetalhes!['telefone'] ?? ''}',
                              style: TextStyle(fontSize: 12, color: textMuted),
                            ),
                          ],
                        ] else
                          Text(
                            'Nenhum fornecedor selecionado',
                            style: TextStyle(color: textMuted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  RemessaPrecificacaoEditor(
                    key: _pricingKey,
                    initialRows: widget.remessaData?['precificacao_itens'] as List<dynamic>? ?? const [],
                    locked: _pricingLocked,
                    onImagemSugerida: _usarImagemCatalogo,
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _custosExtrasController,
                    enabled: !_pricingLocked,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Custos extras da remessa (R\$)',
                      helperText: 'Frete, transporte ou taxas da confecção (opcional)',
                      prefixIcon: Icon(Icons.local_shipping_outlined))),
                  const SizedBox(height: 12),
                  Card(child: ExpansionTile(
                    initiallyExpanded: false,
                    maintainState: true,
                    leading: Icon(Icons.photo_library_outlined, color: primary),
                    title: const Text('Identidade visual da remessa',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('Imagem do catálogo, upload ou ícone'),
                    children: [_editorCapa()],
                  )),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    style: TextStyle(color: textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Status',
                      labelStyle: TextStyle(color: textSecondary),
                      filled: true,
                      fillColor: cardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          context.uai.inputRadius,
                        ),
                        borderSide: BorderSide(color: border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          context.uai.inputRadius,
                        ),
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          context.uai.inputRadius,
                        ),
                        borderSide: BorderSide(color: primary, width: 1.4),
                      ),
                    ),
                    dropdownColor: cardBg,
                    items: const [
                      DropdownMenuItem(
                        value: 'pendente',
                        child: Text('Pendente'),
                      ),
                      DropdownMenuItem(
                        value: 'em_producao',
                        child: Text('Em produção'),
                      ),
                      DropdownMenuItem(
                        value: 'finalizada',
                        child: Text('Finalizada'),
                      ),
                      DropdownMenuItem(
                        value: 'cancelada',
                        child: Text('Cancelada'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _status = v!),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _observacoesController,
                    label: 'Observações',
                    icon: Icons.notes,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _selecionarPedidos,
                    icon: Icon(Icons.list_alt, color: onPrimary),
                    label: Text(
                      'Pedidos vinculados: ${_pedidosSelecionados.length}',
                      style: TextStyle(color: onPrimary),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          context.uai.buttonRadius,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_pedidosSelecionados.isNotEmpty) ...[
                    Text(
                      'Pedidos incluídos:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    ..._pedidosSelecionados.map(
                      (id) => FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('pedidos_uniformes')
                            .doc(id)
                            .get(),
                        builder: (_, snap) {
                          if (!snap.hasData) return const SizedBox.shrink();
                          final pedido =
                              snap.data!.data() as Map<String, dynamic>?;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              pedido?['aluno_nome'] ?? id,
                              style: TextStyle(color: textPrimary),
                            ),
                            subtitle: Text(
                              'Pedido ${pedido?['id_pedido'] ?? ''}',
                              style: TextStyle(color: textSecondary),
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.remove_circle_outline,
                                color: context.uai.error,
                              ),
                              onPressed: () {
                                setState(() => _pedidosSelecionados.remove(id));
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: context.uai.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.uai.textSecondary),
        prefixIcon: Icon(icon, color: context.uai.primary),
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
    );
  }

  Widget _buildDateField(
    String label,
    DateTime? date,
    ValueChanged<DateTime?> onChanged,
  ) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
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
            borderSide: BorderSide(color: context.uai.primary, width: 1.4),
          ),
          filled: true,
          fillColor: context.uai.cardAlt,
        ),
        child: Text(
          date != null
              ? DateFormat('dd/MM/yyyy').format(date)
              : 'Selecionar data',
          style: TextStyle(color: context.uai.textPrimary),
        ),
      ),
    );
  }
}

// ─── Diálogo para selecionar múltiplos pedidos (refatorado) ─────────────────
class _SelecionarPedidosDialog extends StatefulWidget {
  final List<String> selectedIds;
  const _SelecionarPedidosDialog({required this.selectedIds});
  @override
  State<_SelecionarPedidosDialog> createState() =>
      _SelecionarPedidosDialogState();
}

class _SelecionarPedidosDialogState extends State<_SelecionarPedidosDialog> {
  late List<String> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.uai.primary;
    final onPrimary = _readableOn(context.uai.primary);
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
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              style: TextStyle(color: textPrimary),
              decoration: InputDecoration(
                hintText: 'Pesquisar pedido ou aluno...',
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
                    .collection('pedidos_uniformes')
                    .orderBy('data_pedido', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Center(
                      child: CircularProgressIndicator(color: primary),
                    );
                  }
                  var docs = snapshot.data!.docs;
                  if (_search.isNotEmpty) {
                    docs = docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return (data['id_pedido'] ?? '').toLowerCase().contains(
                            _search,
                          ) ||
                          (data['aluno_nome'] ?? '').toLowerCase().contains(
                            _search,
                          );
                    }).toList();
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final doc = docs[i];
                      final data = doc.data() as Map<String, dynamic>;
                      final bool isSelected = _selected.contains(doc.id);
                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: primary,
                        title: Text(
                          '${data['id_pedido']} - ${data['aluno_nome']}',
                          style: TextStyle(color: textPrimary),
                        ),
                        subtitle: Text(
                          'Status: ${data['status']}',
                          style: TextStyle(color: textSecondary),
                        ),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selected.add(doc.id);
                            } else {
                              _selected.remove(doc.id);
                            }
                          });
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, _selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: onPrimary,
              ),
              child: Text('Confirmar (${_selected.length} selecionados)'),
            ),
          ],
        ),
      ),
    );
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
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
                hintText: 'Pesquisar fornecedor...',
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
                    .collection('fornecedores')
                    .where('status', isEqualTo: 'ativo')
                    .orderBy('nome')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Center(
                      child: CircularProgressIndicator(color: primary),
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
                        style: TextStyle(color: textMuted),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      return ListTile(
                        leading: Icon(Icons.business, color: primary),
                        title: Text(
                          data['nome'] ?? '',
                          style: TextStyle(color: textPrimary),
                        ),
                        subtitle: Text(
                          data['contato'] ?? '',
                          style: TextStyle(color: textSecondary),
                        ),
                        onTap: () => Navigator.pop(context, <String, String>{
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
