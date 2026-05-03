import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/services/remessa_service.dart';

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

  final _nomeController = TextEditingController();
  final _observacoesController = TextEditingController();
  DateTime? _dataEnvio;
  DateTime? _dataPrevista;
  String _status = 'pendente';
  List<String> _pedidosSelecionados = [];
  List<Map<String, dynamic>> _itensEstoque = [];
  bool _isLoading = false;

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
      _itensEstoque = List<Map<String, dynamic>>.from(widget.remessaData!['itens_estoque'] ?? []);
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
        'itens_estoque': _itensEstoque,
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
          content: Text(widget.remessaId == null ? 'Remessa criada!' : 'Remessa atualizada!'),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
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

  Future<void> _adicionarItemEstoque() async {
    final item = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _ItemEstoqueDialog(),
    );
    if (item != null) {
      setState(() {
        _itensEstoque.add(item);
      });
    }
  }

  void _removerItemEstoque(int index) {
    setState(() {
      _itensEstoque.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.remessaId == null ? 'NOVA REMESSA' : 'EDITAR REMESSA'),
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _salvar,
            icon: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
                : const Icon(Icons.save),
            label: const Text('SALVAR'),
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nomeController,
              decoration: const InputDecoration(
                labelText: 'Nome da remessa *',
                border: OutlineInputBorder(),
              ),
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
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'pendente', child: Text('Pendente')),
                DropdownMenuItem(value: 'em_producao', child: Text('Em produção')),
                DropdownMenuItem(value: 'finalizada', child: Text('Finalizada')),
                DropdownMenuItem(value: 'cancelada', child: Text('Cancelada')),
              ],
              onChanged: (v) => setState(() => _status = v!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _observacoesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observações',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _selecionarPedidos,
              icon: const Icon(Icons.list_alt),
              label: Text('Pedidos vinculados: ${_pedidosSelecionados.length}'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 8),
            if (_pedidosSelecionados.isNotEmpty) ...[
              const Text('Pedidos incluídos:'),
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
                    title: Text(pedido?['aluno_nome'] ?? id),
                    subtitle: Text('Pedido ${pedido?['id_pedido'] ?? ''}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                      onPressed: () {
                        setState(() => _pedidosSelecionados.remove(id));
                      },
                    ),
                  );
                },
              )),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Itens para estoque',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: _adicionarItemEstoque,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            if (_itensEstoque.isNotEmpty) ...[
              const Divider(),
              ..._itensEstoque.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return ListTile(
                  dense: true,
                  title: Text('${item['nome']} (${item['tamanho'] ?? 'Único'})'),
                  subtitle: Text('Qtd: ${item['quantidade']} - R\$ ${item['preco_venda']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                    onPressed: () => _removerItemEstoque(index),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
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
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        child: Text(date != null ? DateFormat('dd/MM/yyyy').format(date!) : 'Selecionar data'),
      ),
    );
  }
}

// ─── Diálogo para selecionar múltiplos pedidos ─────────────────
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
    return Dialog(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Pesquisar pedido ou aluno...',
                prefixIcon: Icon(Icons.search),
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
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
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
                        title: Text('${data['id_pedido']} - ${data['aluno_nome']}'),
                        subtitle: Text('Status: ${data['status']}'),
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
            ElevatedButton(
              onPressed: () => Navigator.pop(context, _selected),
              child: Text('Confirmar (${_selected.length} selecionados)'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Diálogo para novo item de estoque ─────────────────────────
class _ItemEstoqueDialog extends StatefulWidget {
  const _ItemEstoqueDialog();

  @override
  State<_ItemEstoqueDialog> createState() => _ItemEstoqueDialogState();
}

class _ItemEstoqueDialogState extends State<_ItemEstoqueDialog> {
  final _form = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _tamanhoCtrl = TextEditingController(text: 'Único');
  final _qtdCtrl = TextEditingController(text: '1');
  final _precoCtrl = TextEditingController();
  final _corCtrl = TextEditingController();

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _tamanhoCtrl.dispose();
    _qtdCtrl.dispose();
    _precoCtrl.dispose();
    _corCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo item para estoque'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nomeCtrl,
                decoration: const InputDecoration(labelText: 'Nome *'),
                validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _tamanhoCtrl,
                decoration: const InputDecoration(labelText: 'Tamanho'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _qtdCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantidade *'),
                validator: (v) => v!.isEmpty || int.tryParse(v) == null ? 'Número inválido' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _precoCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Preço venda (R\$)'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _corCtrl,
                decoration: const InputDecoration(labelText: 'Cor (opcional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            if (_form.currentState!.validate()) {
              final item = <String, dynamic>{
                'nome': _nomeCtrl.text.trim(),
                'tamanho': _tamanhoCtrl.text.trim(),
                'quantidade': int.tryParse(_qtdCtrl.text) ?? 1,
                'preco_venda': double.tryParse(_precoCtrl.text.replaceAll(',', '.')) ?? 0,
                'cor': _corCtrl.text.trim(),
              };
              Navigator.pop(context, item);
            }
          },
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}