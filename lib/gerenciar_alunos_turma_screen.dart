import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class GerenciarAlunosTurmaScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaNome;

  const GerenciarAlunosTurmaScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaNome,
  });

  @override
  State<GerenciarAlunosTurmaScreen> createState() => _GerenciarAlunosTurmaScreenState();
}

class _GerenciarAlunosTurmaScreenState extends State<GerenciarAlunosTurmaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  List<Map<String, dynamic>> _alunosVinculados = [];
  List<Map<String, dynamic>> _alunosDisponiveis = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _carregarAlunos();
  }

  Future<void> _carregarAlunos() async {
    setState(() => _isLoading = true);
    try {
      // 1. Carregar alunos vinculados à turma (onde turma_id é igual ao widget.turmaId)
      final alunosVinculadosSnapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();

      setState(() {
        _alunosVinculados = alunosVinculadosSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'nome': data['nome'] ?? 'Sem nome',
            'apelido': data['apelido'] ?? '',
            'graduacao': data['graduacao_atual'] ?? 'Sem graduação',
            'foto_url': data['foto_perfil_aluno'] ?? '',
          };
        }).toList();
      });

      // 2. Carregar alunos disponíveis (alunos ativos sem turma ou com turma diferente)
      final todosAlunosSnapshot = await _firestore
          .collection('alunos')
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();

      final alunosVinculadosIds = alunosVinculadosSnapshot.docs.map((doc) => doc.id).toList();

      setState(() {
        _alunosDisponiveis = todosAlunosSnapshot.docs.map((doc) {
          final data = doc.data();
          final bool jaVinculado = alunosVinculadosIds.contains(doc.id);
          final bool temTurma = data['turma_id'] != null && data['turma_id'].toString().isNotEmpty;
          final bool turmaDiferente = temTurma && data['turma_id'] != widget.turmaId;

          return {
            'id': doc.id,
            'nome': data['nome'] ?? 'Sem nome',
            'apelido': data['apelido'] ?? '',
            'graduacao': data['graduacao_atual'] ?? 'Sem graduação',
            'foto_url': data['foto_perfil_aluno'] ?? '',
            'ja_vinculado': jaVinculado,
            'tem_turma_atual': temTurma,
            'turma_atual': turmaDiferente ? data['turma'] : '',
            'turma_id_atual': turmaDiferente ? data['turma_id'] : null,
          };
        }).where((aluno) {
          // Filtrar apenas alunos que não estão vinculados a ESTA turma
          return !aluno['ja_vinculado'];
        }).toList();
      });

    } catch (e) {
      debugPrint('Erro ao carregar alunos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar alunos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _vincularAluno(String alunoId, Map<String, dynamic> alunoData) async {
    setState(() => _isLoading = true);
    try {
      await _firestore.collection('alunos').doc(alunoId).update({
        'turma_id': widget.turmaId,
        'turma': widget.turmaNome,
        'atualizado_em': FieldValue.serverTimestamp(),
        'atualizado_por': 'Sistema', // Você pode ajustar para pegar o usuário atual
      });

      // Atualizar contador de alunos na turma (se necessário)
      await _atualizarContadorAlunos();

      // Recarregar lista
      await _carregarAlunos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Aluno ${alunoData['nome']} vinculado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao vincular aluno: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao vincular aluno: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removerVinculoAluno(String alunoId, Map<String, dynamic> alunoData) async {
    setState(() => _isLoading = true);
    try {
      await _firestore.collection('alunos').doc(alunoId).update({
        'turma_id': null,
        'turma': null,
        'atualizado_em': FieldValue.serverTimestamp(),
        'atualizado_por': 'Sistema', // Você pode ajustar para pegar o usuário atual
      });

      // Atualizar contador de alunos na turma (se necessário)
      await _atualizarContadorAlunos();

      // Recarregar lista
      await _carregarAlunos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Aluno ${alunoData['nome']} removido da turma!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao remover vínculo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao remover aluno: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _atualizarContadorAlunos() async {
    try {
      // Contar alunos ativos na turma
      final alunosAtivosSnapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();

      // Atualizar contador na turma (se sua coleção turmas tiver este campo)
      await _firestore
          .collection('turmas')
          .doc(widget.turmaId)
          .update({
        'alunos_count': alunosAtivosSnapshot.docs.length,
        'alunos_ativos': alunosAtivosSnapshot.docs.length,
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Erro ao atualizar contador: $e');
    }
  }

  Widget _buildAlunoVinculadoCard(Map<String, dynamic> aluno) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: Colors.grey.shade200,
          backgroundImage: aluno['foto_url'] != null && aluno['foto_url'].isNotEmpty
              ? NetworkImage(aluno['foto_url'])
              : null,
          child: aluno['foto_url'] != null && aluno['foto_url'].isNotEmpty
              ? null
              : Icon(Icons.person, color: Colors.grey.shade600),
        ),
        title: Text(
          aluno['nome'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (aluno['apelido'] != null && aluno['apelido'].isNotEmpty)
              Text('Apelido: ${aluno['apelido']}'),
            Text('Graduação: ${aluno['graduacao']}'),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close, color: Colors.red),
          onPressed: () {
            _showConfirmacaoRemocao(aluno['id'], aluno);
          },
          tooltip: 'Remover da turma',
        ),
      ),
    );
  }

  Widget _buildAlunoDisponivelCard(Map<String, dynamic> aluno) {
    final bool temTurmaAtual = aluno['tem_turma_atual'] ?? false;
    final String turmaAtual = aluno['turma_atual'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      color: temTurmaAtual ? Colors.orange.shade50 : null,
      child: ListTile(
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: Colors.grey.shade200,
          backgroundImage: aluno['foto_url'] != null && aluno['foto_url'].isNotEmpty
              ? NetworkImage(aluno['foto_url'])
              : null,
          child: aluno['foto_url'] != null && aluno['foto_url'].isNotEmpty
              ? null
              : Icon(Icons.person, color: Colors.grey.shade600),
        ),
        title: Text(
          aluno['nome'],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (aluno['apelido'] != null && aluno['apelido'].isNotEmpty)
              Text('Apelido: ${aluno['apelido']}'),
            Text('Graduação: ${aluno['graduacao']}'),
            if (temTurmaAtual && turmaAtual.isNotEmpty)
              Text(
                'Turma atual: $turmaAtual',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () {
            _showConfirmacaoVinculo(aluno['id'], aluno);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: temTurmaAtual ? Colors.orange.shade700 : Colors.red.shade900,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: Text(
            temTurmaAtual ? 'TROCAR' : 'VINCULAR',
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
      ),
    );
  }

  void _showConfirmacaoRemocao(String alunoId, Map<String, dynamic> aluno) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Aluno'),
        content: Text('Tem certeza que deseja remover ${aluno['nome']} da turma ${widget.turmaNome}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removerVinculoAluno(alunoId, aluno);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  void _showConfirmacaoVinculo(String alunoId, Map<String, dynamic> aluno) {
    final bool temTurmaAtual = aluno['tem_turma_atual'] ?? false;
    final String turmaAtual = aluno['turma_atual'] ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vincular Aluno'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Deseja vincular ${aluno['nome']} à turma ${widget.turmaNome}?'),
            if (temTurmaAtual && turmaAtual.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'ATENÇÃO: Este aluno já está na turma "$turmaAtual".\nAo vincular aqui, ele será automaticamente removido da turma anterior.',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _vincularAluno(alunoId, aluno);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filtrarAlunosDisponiveis() {
    if (_searchQuery.isEmpty) return _alunosDisponiveis;

    return _alunosDisponiveis.where((aluno) {
      final nome = aluno['nome'].toString().toLowerCase();
      final apelido = aluno['apelido'].toString().toLowerCase();
      final graduacao = aluno['graduacao'].toString().toLowerCase();

      return nome.contains(_searchQuery.toLowerCase()) ||
          apelido.contains(_searchQuery.toLowerCase()) ||
          graduacao.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Gerenciar Alunos'),
            Text(
              widget.turmaNome,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
            Text(
              widget.academiaNome,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar aluno por nome, apelido ou graduação...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white.withOpacity(0.2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Material(
              color: Colors.white,
              child: TabBar(
                labelColor: Colors.red.shade900,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.red.shade900,
                tabs: const [
                  Tab(
                    text: 'VINCULADOS',
                    icon: Icon(Icons.group),
                  ),
                  Tab(
                    text: 'DISPONÍVEIS',
                    icon: Icon(Icons.person_add),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // ABA 1: Alunos Vinculados
                  _alunosVinculados.isEmpty
                      ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.group_off,
                          size: 80,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Nenhum aluno vinculado',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Vá para a aba "Disponíveis" para adicionar alunos',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                      : RefreshIndicator(
                    onRefresh: _carregarAlunos,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _alunosVinculados.length,
                      itemBuilder: (context, index) {
                        return _buildAlunoVinculadoCard(_alunosVinculados[index]);
                      },
                    ),
                  ),

                  // ABA 2: Alunos Disponíveis
                  RefreshIndicator(
                    onRefresh: _carregarAlunos,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filtrarAlunosDisponiveis().length,
                      itemBuilder: (context, index) {
                        return _buildAlunoDisponivelCard(_filtrarAlunosDisponiveis()[index]);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}