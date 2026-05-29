import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/uniformes/services/remessa_service.dart';
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

  final _nomeController = TextEditingController();
  final _observacoesController = TextEditingController();
  DateTime? _dataEnvio;
  DateTime? _dataPrevista;
  String _status = 'pendente';
  List<String> _pedidosSelecionados = [];
  bool _isLoading = false;

  String? _fornecedorId;
  String? _fornecedorNome;
  Map<String, dynamic>? _fornecedorDetalhes;

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
    if (widget.remessaData != null) {
      _nomeController.text = widget.remessaData!['nome'] ?? '';
      _observacoesController.text = widget.remessaData!['observacoes'] ?? '';
      _status = widget.remessaData!['status'] ?? 'pendente';
      if (widget.remessaData!['data_envio'] != null) {
        _dataEnvio = (widget.remessaData!['data_envio'] as Timestamp).toDate();
      }
      if (widget.remessaData!['data_prevista'] != null) {
        _dataPrevista = (widget.remessaData!['data_prevista'] as Timestamp).toDate();
      }
      _pedidosSelecionados = List<String>.from(widget.remessaData!['pedidos_ids'] ?? []);
      _fornecedorId = widget.remessaData!['fornecedor_id'];
      if (_fornecedorId != null) {
        _carregarFornecedor(_fornecedorId!);
      }
    }
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
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final dados = {
        'nome': _nomeController.text.trim(),
        'data_envio': _dataEnvio != null ? Timestamp.fromDate(_dataEnvio!) : null,
        'data_prevista': _dataPrevista != null ? Timestamp.fromDate(_dataPrevista!) : null,
        'status': _status,
        'observacoes': _observacoesController.text.trim(),
        'pedidos_ids': _pedidosSelecionados,
        'fornecedor_id': _fornecedorId,
      };

      if (widget.remessaId == null) {
        final remessaId = await _remessaService.criarRemessa(dados);
        for (var pedidoId in _pedidosSelecionados) {
          await _remessaService.vincularPedido(pedidoId, remessaId);
        }
        if (_status == 'em_confeccao') {
          await _atualizarPedidosParaConfeccao(_pedidosSelecionados);
        }
      } else {
        await _remessaService.atualizarRemessa(widget.remessaId!, dados);
        final atuais = widget.remessaData!['pedidos_ids'] ?? [];
        for (var id in _pedidosSelecionados) {
          if (!atuais.contains(id)) {
            await _remessaService.vincularPedido(id, widget.remessaId!);
          }
        }
        for (var id in atuais) {
          if (!_pedidosSelecionados.contains(id)) {
            await _remessaService.desvincularPedido(id, widget.remessaId!);
          }
        }
        if (_status == 'em_confeccao') {
          await _atualizarPedidosParaConfeccao(_pedidosSelecionados);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            widget.remessaId == null ? 'Remessa criada!' : 'Remessa atualizada!',
            style: TextStyle(color: _readableOn(context.uai.success)),
          ),
          backgroundColor: context.uai.success,
        ));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e', style: TextStyle(color: _readableOn(context.uai.error))),
            backgroundColor: context.uai.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _atualizarPedidosParaConfeccao(List<String> pedidosIds) async {
    for (var id in pedidosIds) {
      await FirebaseFirestore.instance.collection('pedidos_uniformes').doc(id).update({
        'status': 'em_confeccao',
      });
    }
  }

  Future<void> _selecionarPedidos() async {
    final selecionados = await showDialog<List<String>>(
      context: context,
      builder: (_) => _SelecionarPedidosDialog(selectedIds: _pedidosSelecionados),
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
              child: CircularProgressIndicator(color: onPrimary, strokeWidth: 2),
            )
                : Icon(Icons.save, color: onPrimary),
            label: Text(
              'SALVAR',
              style: TextStyle(color: onPrimary),
            ),
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
                      Text('Fornecedor',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: textPrimary)),
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
                          child: Text(_fornecedorNome!,
                              style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: textPrimary)),
                        ),
                        IconButton(
                          icon: Icon(Icons.clear,
                              color: context.uai.error, size: 18),
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
                    Text('Nenhum fornecedor selecionado',
                        style: TextStyle(color: textMuted)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _status,
              style: TextStyle(color: textPrimary),
              decoration: InputDecoration(
                labelText: 'Status',
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
              ),
              dropdownColor: cardBg,
              items: const [
                DropdownMenuItem(value: 'pendente', child: Text('Pendente')),
                DropdownMenuItem(value: 'em_producao', child: Text('Em produção')),
                DropdownMenuItem(value: 'finalizada', child: Text('Finalizada')),
                DropdownMenuItem(value: 'cancelada', child: Text('Cancelada')),
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
                  borderRadius: BorderRadius.circular(context.uai.buttonRadius),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_pedidosSelecionados.isNotEmpty) ...[
              Text('Pedidos incluídos:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: textPrimary)),
              ..._pedidosSelecionados.map((id) => FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('pedidos_uniformes')
                    .doc(id)
                    .get(),
                builder: (_, snap) {
                  if (!snap.hasData) return const SizedBox.shrink();
                  final pedido = snap.data!.data() as Map<String, dynamic>?;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(pedido?['aluno_nome'] ?? id,
                        style: TextStyle(color: textPrimary)),
                    subtitle: Text('Pedido ${pedido?['id_pedido'] ?? ''}',
                        style: TextStyle(color: textSecondary)),
                    trailing: IconButton(
                      icon: Icon(Icons.remove_circle_outline,
                          color: context.uai.error),
                      onPressed: () {
                        setState(() => _pedidosSelecionados.remove(id));
                      },
                    ),
                  );
                },
              )),
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

  Widget _buildDateField(String label, DateTime? date, ValueChanged<DateTime?> onChanged) {
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
          date != null ? DateFormat('dd/MM/yyyy').format(date!) : 'Selecionar data',
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
  State<_SelecionarPedidosDialog> createState() => _SelecionarPedidosDialogState();
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
                  if (!snapshot.hasData)
                    return Center(child: CircularProgressIndicator(color: primary));
                  var docs = snapshot.data!.docs;
                  if (_search.isNotEmpty) {
                    docs = docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return (data['id_pedido'] ?? '').toLowerCase().contains(_search) ||
                          (data['aluno_nome'] ?? '').toLowerCase().contains(_search);
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
                        title: Text('${data['id_pedido']} - ${data['aluno_nome']}',
                            style: TextStyle(color: textPrimary)),
                        subtitle: Text('Status: ${data['status']}',
                            style: TextStyle(color: textSecondary)),
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
  State<_SelecionarFornecedorDialog> createState() => _SelecionarFornecedorDialogState();
}

class _SelecionarFornecedorDialogState extends State<_SelecionarFornecedorDialog> {
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
                  if (!snapshot.hasData)
                    return Center(child: CircularProgressIndicator(color: primary));
                  var docs = snapshot.data!.docs;
                  if (_search.isNotEmpty) {
                    docs = docs.where((d) {
                      final nome = (d.data() as Map<String, dynamic>)['nome'] ?? '';
                      return nome.toLowerCase().contains(_search);
                    }).toList();
                  }
                  if (docs.isEmpty)
                    return Center(
                        child: Text('Nenhum fornecedor encontrado',
                            style: TextStyle(color: textMuted)));
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      return ListTile(
                        leading: Icon(Icons.business, color: primary),
                        title: Text(data['nome'] ?? '',
                            style: TextStyle(color: textPrimary)),
                        subtitle: Text(data['contato'] ?? '',
                            style: TextStyle(color: textSecondary)),
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