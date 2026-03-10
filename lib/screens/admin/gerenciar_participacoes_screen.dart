import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class GerenciarParticipacoesScreen extends StatefulWidget {
  const GerenciarParticipacoesScreen({super.key});

  @override
  State<GerenciarParticipacoesScreen> createState() => _GerenciarParticipacoesScreenState();
}

class _GerenciarParticipacoesScreenState extends State<GerenciarParticipacoesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _filtroEvento;
  List<String> _eventosList = ['Todos'];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    _carregarEventos();
  }

  Future<void> _carregarEventos() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('eventos')
          .orderBy('nome')
          .get();

      final eventos = ['Todos', ...snapshot.docs.map((doc) => doc['nome'] as String).toList()];
      setState(() {
        _eventosList = eventos;
      });
    } catch (e) {
      debugPrint('Erro ao carregar eventos: $e');
    }
  }

  Future<void> _excluirParticipacao(String participacaoId, String alunoNome, String eventoNome) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Participação'),
        content: Text('Remover participação de "$alunoNome" no evento "$eventoNome"?'),
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
            .collection('participacoes_eventos')
            .doc(participacaoId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Participação excluída com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao excluir: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _editarParticipacao(Map<String, dynamic> participacao, String id) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: FormularioParticipacao(
          participacao: participacao,
          participacaoId: id,
          onSalvo: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Participação atualizada!'),
                backgroundColor: Colors.green,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _adicionarParticipacao() {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: FormularioParticipacao(
          onSalvo: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Participação adicionada!'),
                backgroundColor: Colors.green,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Participações'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _adicionarParticipacao,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar por aluno...',
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.2),
                    hintStyle: const TextStyle(color: Colors.white70),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white70),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                        : null,
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: DropdownButtonFormField<String>(
                  value: _filtroEvento,
                  decoration: InputDecoration(
                    labelText: 'Filtrar por Evento',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.2),
                  ),
                  dropdownColor: Colors.red.shade900,
                  style: const TextStyle(color: Colors.white),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  items: _eventosList.map((evento) {
                    return DropdownMenuItem(
                      value: evento == 'Todos' ? null : evento,
                      child: Text(
                        evento,
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _filtroEvento = value;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('participacoes_eventos')
            .orderBy('data_evento', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Text('Erro: ${snapshot.error}'),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text(
                    'Nenhuma participação cadastrada',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _adicionarParticipacao,
                    icon: const Icon(Icons.add),
                    label: const Text('ADICIONAR PARTICIPAÇÃO'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                    ),
                  ),
                ],
              ),
            );
          }

          var docs = snapshot.data!.docs;

          // Filtrar por busca
          if (_searchQuery.isNotEmpty) {
            docs = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return (data['aluno_nome']?.toLowerCase().contains(_searchQuery) ?? false);
            }).toList();
          }

          // Filtrar por evento
          if (_filtroEvento != null) {
            docs = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['evento_nome'] == _filtroEvento;
            }).toList();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final participacao = doc.data() as Map<String, dynamic>;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Aluno e Evento
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.person, color: Colors.amber),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  participacao['aluno_nome'] ?? 'Aluno não informado',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  participacao['evento_nome'] ?? 'Evento não informado',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Data e Tipo
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            participacao['data_evento'] ?? 'Data não informada',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.category, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              participacao['tipo_evento'] ?? 'Tipo não informado',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Graduação e Certificado
                      Row(
                        children: [
                          Icon(Icons.emoji_events, size: 14, color: Colors.amber.shade600),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              participacao['graduacao'] ?? 'Graduação não informada',
                              style: TextStyle(fontSize: 12, color: Colors.amber.shade700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (participacao['link_certificado']?.isNotEmpty ?? false)
                            IconButton(
                              icon: Icon(Icons.verified, color: Colors.green.shade600, size: 18),
                              onPressed: () => _abrirLink(participacao['link_certificado']),
                              tooltip: 'Ver certificado',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),

                      const Divider(height: 16),

                      // Botões de ação
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _editarParticipacao(participacao, doc.id),
                            tooltip: 'Editar',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _excluirParticipacao(
                              doc.id,
                              participacao['aluno_nome'] ?? '',
                              participacao['evento_nome'] ?? '',
                            ),
                            tooltip: 'Excluir',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _abrirLink(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir link: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

// =====================================================
// FORMULÁRIO DE PARTICIPAÇÃO
// =====================================================
class FormularioParticipacao extends StatefulWidget {
  final Map<String, dynamic>? participacao;
  final String? participacaoId;
  final VoidCallback onSalvo;

  const FormularioParticipacao({
    super.key,
    this.participacao,
    this.participacaoId,
    required this.onSalvo,
  });

  @override
  State<FormularioParticipacao> createState() => _FormularioParticipacaoState();
}

class _FormularioParticipacaoState extends State<FormularioParticipacao> {
  final _formKey = GlobalKey<FormState>();

  final _alunoNomeController = TextEditingController();
  final _eventoNomeController = TextEditingController();
  final _dataController = TextEditingController();
  final _tipoController = TextEditingController();
  final _graduacaoController = TextEditingController();
  final _certificadoController = TextEditingController();

  String? _alunoId;
  String? _eventoId;
  bool _isLoading = false;
  bool _isLoadingAlunos = false;
  bool _isLoadingEventos = false;

  List<Map<String, dynamic>> _alunosList = [];
  List<Map<String, dynamic>> _eventosList = [];

  @override
  void initState() {
    super.initState();
    _carregarAlunos();
    _carregarEventos();
    if (widget.participacao != null) {
      _preencherFormulario();
    }
  }

  Future<void> _carregarAlunos() async {
    setState(() => _isLoadingAlunos = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('alunos')
          .orderBy('nome')
          .get();

      _alunosList = snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'nome': doc['nome'] ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint('Erro ao carregar alunos: $e');
    } finally {
      setState(() => _isLoadingAlunos = false);
    }
  }

  Future<void> _carregarEventos() async {
    setState(() => _isLoadingEventos = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('eventos')
          .orderBy('nome')
          .get();

      _eventosList = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'nome': data['nome'] ?? '',
          'data': data['data'] ?? '',
          'tipo_evento': data['tipo_evento'] ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint('Erro ao carregar eventos: $e');
    } finally {
      setState(() => _isLoadingEventos = false);
    }
  }

  void _preencherFormulario() {
    final p = widget.participacao!;
    _alunoNomeController.text = p['aluno_nome'] ?? '';
    _eventoNomeController.text = p['evento_nome'] ?? '';
    _dataController.text = p['data_evento'] ?? '';
    _tipoController.text = p['tipo_evento'] ?? '';
    _graduacaoController.text = p['graduacao'] ?? '';
    _certificadoController.text = p['link_certificado'] ?? '';
    _alunoId = p['aluno_id'];
    _eventoId = p['evento_id'];
  }

  void _selecionarAluno() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        height: 400,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Selecione o Aluno',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoadingAlunos
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                itemCount: _alunosList.length,
                itemBuilder: (context, index) {
                  final aluno = _alunosList[index];
                  return ListTile(
                    leading: const Icon(Icons.person, color: Colors.blue),
                    title: Text(aluno['nome']),
                    onTap: () {
                      setState(() {
                        _alunoNomeController.text = aluno['nome'];
                        _alunoId = aluno['id'];
                      });
                      Navigator.pop(context);
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

  void _selecionarEvento() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        height: 400,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Selecione o Evento',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoadingEventos
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                itemCount: _eventosList.length,
                itemBuilder: (context, index) {
                  final evento = _eventosList[index];
                  return ListTile(
                    leading: const Icon(Icons.event, color: Colors.green),
                    title: Text(evento['nome']),
                    subtitle: Text('${evento['data']} • ${evento['tipo_evento']}'),
                    onTap: () {
                      setState(() {
                        _eventoNomeController.text = evento['nome'];
                        _eventoId = evento['id'];
                        _dataController.text = evento['data'] ?? '';
                        _tipoController.text = evento['tipo_evento'] ?? '';
                      });
                      Navigator.pop(context);
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

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final data = {
        'aluno_id': _alunoId,
        'aluno_nome': _alunoNomeController.text.trim(),
        'evento_id': _eventoId,
        'evento_nome': _eventoNomeController.text.trim(),
        'data_evento': _dataController.text.trim(),
        'tipo_evento': _tipoController.text.trim(),
        'graduacao': _graduacaoController.text.trim(),
        'link_certificado': _certificadoController.text.trim(),
        'atualizado_em': FieldValue.serverTimestamp(),
      };

      if (widget.participacaoId == null) {
        data['criado_em'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance
            .collection('participacoes_eventos')
            .add(data);
      } else {
        await FirebaseFirestore.instance
            .collection('participacoes_eventos')
            .doc(widget.participacaoId)
            .update(data);
      }

      widget.onSalvo();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Dados da Participação',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Aluno
            InkWell(
              onTap: _selecionarAluno,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Aluno *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person, color: Colors.blue),
                ),
                child: Text(
                  _alunoNomeController.text.isEmpty
                      ? 'Selecione um aluno'
                      : _alunoNomeController.text,
                  style: TextStyle(
                    color: _alunoNomeController.text.isEmpty
                        ? Colors.grey
                        : Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Evento
            InkWell(
              onTap: _selecionarEvento,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Evento *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.event, color: Colors.green),
                ),
                child: Text(
                  _eventoNomeController.text.isEmpty
                      ? 'Selecione um evento'
                      : _eventoNomeController.text,
                  style: TextStyle(
                    color: _eventoNomeController.text.isEmpty
                        ? Colors.grey
                        : Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Data e Tipo
            TextFormField(
              controller: _dataController,
              decoration: const InputDecoration(
                labelText: 'Data do Evento',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _tipoController,
              decoration: const InputDecoration(
                labelText: 'Tipo do Evento',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category, color: Colors.purple),
              ),
            ),
            const SizedBox(height: 12),

            // Graduação
            TextFormField(
              controller: _graduacaoController,
              decoration: const InputDecoration(
                labelText: 'Graduação na época',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.emoji_events, color: Colors.amber),
              ),
            ),
            const SizedBox(height: 12),

            // Certificado
            TextFormField(
              controller: _certificadoController,
              decoration: const InputDecoration(
                labelText: 'Link do Certificado',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link, color: Colors.green),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            // Botões
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCELAR'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _salvar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('SALVAR'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _alunoNomeController.dispose();
    _eventoNomeController.dispose();
    _dataController.dispose();
    _tipoController.dispose();
    _graduacaoController.dispose();
    _certificadoController.dispose();
    super.dispose();
  }
}