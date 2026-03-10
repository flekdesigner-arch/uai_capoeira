import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GruposConvidadosScreen extends StatefulWidget {
  const GruposConvidadosScreen({super.key});

  @override
  State<GruposConvidadosScreen> createState() => _GruposConvidadosScreenState();
}

class _GruposConvidadosScreenState extends State<GruposConvidadosScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _nomeGrupoController = TextEditingController();
  final TextEditingController _contatoController = TextEditingController();
  final TextEditingController _observacoesController = TextEditingController();

  bool _isLoading = false;
  String? _editandoId;

  @override
  void dispose() {
    _nomeGrupoController.dispose();
    _contatoController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _salvarGrupo() async {
    if (_nomeGrupoController.text.trim().isEmpty) {
      _mostrarMensagem('Nome do grupo é obrigatório', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dados = {
        'nome': _nomeGrupoController.text.trim().toUpperCase(),
        'contato': _contatoController.text.trim(),
        'observacoes': _observacoesController.text.trim(),
        'ativo': true,
        'criado_em': FieldValue.serverTimestamp(),
      };

      if (_editandoId != null) {
        // Atualizar existente
        await _firestore
            .collection('configuracoes')
            .doc('campeonato')
            .collection('grupos_convidados')
            .doc(_editandoId)
            .update({
          ...dados,
          'atualizado_em': FieldValue.serverTimestamp(),
        });
        _mostrarMensagem('Grupo atualizado!', Colors.green);
      } else {
        // Criar novo
        await _firestore
            .collection('configuracoes')
            .doc('campeonato')
            .collection('grupos_convidados')
            .add(dados);
        _mostrarMensagem('Grupo adicionado!', Colors.green);
      }

      _limparCampos();
    } catch (e) {
      _mostrarMensagem('Erro: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _editarGrupo(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    setState(() {
      _editandoId = doc.id;
      _nomeGrupoController.text = data['nome'] ?? '';
      _contatoController.text = data['contato'] ?? '';
      _observacoesController.text = data['observacoes'] ?? '';
    });
  }

  Future<void> _toggleAtivo(String id, bool ativo) async {
    try {
      await _firestore
          .collection('configuracoes')
          .doc('campeonato')
          .collection('grupos_convidados')
          .doc(id)
          .update({'ativo': !ativo});
    } catch (e) {
      _mostrarMensagem('Erro ao alterar status', Colors.red);
    }
  }

  Future<void> _excluirGrupo(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar exclusão'),
        content: const Text('Tem certeza que deseja excluir este grupo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _firestore
          .collection('configuracoes')
          .doc('campeonato')
          .collection('grupos_convidados')
          .doc(id)
          .delete();
      _mostrarMensagem('Grupo excluído!', Colors.orange);
    } catch (e) {
      _mostrarMensagem('Erro ao excluir', Colors.red);
    }
  }

  void _limparCampos() {
    setState(() {
      _editandoId = null;
      _nomeGrupoController.clear();
      _contatoController.clear();
      _observacoesController.clear();
    });
  }

  void _mostrarMensagem(String msg, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: cor),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('👥 Grupos Convidados'),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          // FORMULÁRIO
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.amber.shade50,
            child: Column(
              children: [
                TextField(
                  controller: _nomeGrupoController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do Grupo *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.group),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _contatoController,
                  decoration: const InputDecoration(
                    labelText: 'Contato (opcional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _observacoesController,
                  decoration: const InputDecoration(
                    labelText: 'Observações (opcional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (_editandoId != null)
                      Expanded(
                        child: TextButton(
                          onPressed: _limparCampos,
                          child: const Text('CANCELAR'),
                        ),
                      ),
                    if (_editandoId != null) const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _salvarGrupo,
                        icon: _isLoading
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : Icon(_editandoId == null ? Icons.add : Icons.save),
                        label: Text(_editandoId == null ? 'ADICIONAR' : 'SALVAR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade900,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // LISTA DE GRUPOS
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('configuracoes')
                  .doc('campeonato')
                  .collection('grupos_convidados')
                  .orderBy('nome')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Erro: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.group_off, size: 80, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text(
                          'Nenhum grupo cadastrado',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Adicione grupos convidados para o campeonato',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final bool ativo = data['ativo'] ?? true;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: ativo ? Colors.white : Colors.grey.shade100,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: ativo ? Colors.amber.shade100 : Colors.grey.shade300,
                          child: Text(
                            data['nome']?[0] ?? '?',
                            style: TextStyle(
                              color: ativo ? Colors.amber.shade900 : Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          data['nome'] ?? '',
                          style: TextStyle(
                            decoration: ativo ? null : TextDecoration.lineThrough,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (data['contato']?.isNotEmpty ?? false)
                              Text('📞 ${data['contato']}', style: const TextStyle(fontSize: 11)),
                            if (data['observacoes']?.isNotEmpty ?? false)
                              Text('📝 ${data['observacoes']}', style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                ativo ? Icons.visibility : Icons.visibility_off,
                                color: ativo ? Colors.green : Colors.grey,
                              ),
                              onPressed: () => _toggleAtivo(doc.id, ativo),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editarGrupo(doc),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _excluirGrupo(doc.id),
                            ),
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