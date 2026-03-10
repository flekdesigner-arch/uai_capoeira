import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class VincularAlunoInativoTurmaScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;

  const VincularAlunoInativoTurmaScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
  });

  @override
  State<VincularAlunoInativoTurmaScreen> createState() => _VincularAlunoInativoTurmaScreenState();
}

class _VincularAlunoInativoTurmaScreenState extends State<VincularAlunoInativoTurmaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  bool _carregandoAlunos = false;
  List<Map<String, dynamic>> _alunosInativos = [];
  List<String> _alunosSelecionadosIds = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _carregarAlunosInativos();
  }

  Future<void> _carregarAlunosInativos() async {
    setState(() => _carregandoAlunos = true);
    try {
      final alunosSnapshot = await _firestore
          .collection('alunos')
          .where('academia_id', isEqualTo: widget.academiaId)
          .where('status_atividade', isEqualTo: 'INATIVO(A)')
          .orderBy('nome')
          .get();

      setState(() {
        _alunosInativos = alunosSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'nome': data['nome'] ?? 'Sem nome',
            'apelido': data['apelido'] ?? '',
            'graduacao': data['graduacao_atual'] ?? 'Sem graduação',
            'foto_url': data['foto_perfil_aluno'] ?? '',
            'idade': data['idade'] ?? '',
            'telefone': data['telefone'] ?? '',
            'selecionado': false,
          };
        }).toList();
        _alunosSelecionadosIds.clear();
      });
    } catch (e) {
      debugPrint('Erro ao carregar alunos inativos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar alunos inativos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _carregandoAlunos = false);
    }
  }

  Future<void> _vincularAlunosSelecionados() async {
    if (_alunosSelecionadosIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione pelo menos um aluno'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final batch = _firestore.batch();

      for (final alunoId in _alunosSelecionadosIds) {
        final alunoRef = _firestore.collection('alunos').doc(alunoId);
        batch.update(alunoRef, {
          'turma_id': widget.turmaId,
          'turma': widget.turmaNome,
          'status_atividade': 'ATIVO(A)',
          'atualizado_em': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      // Atualizar contador de alunos na turma
      await _atualizarContadorTurma();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_alunosSelecionadosIds.length} aluno(s) vinculado(s) e ativado(s)!'),
            backgroundColor: Colors.green,
          ),
        );

        // Voltar para tela anterior
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Erro ao vincular alunos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao vincular alunos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _atualizarContadorTurma() async {
    try {
      // Contar alunos ativos nesta turma
      final snapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();

      final alunosCount = snapshot.docs.length;

      // Atualizar contador na turma
      await _firestore.collection('turmas').doc(widget.turmaId).update({
        'alunos_count': alunosCount,
        'alunos_ativos': alunosCount,
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Erro ao atualizar contador da turma: $e');
    }
  }

  void _toggleSelecaoAluno(String alunoId, bool selecionado) {
    setState(() {
      if (selecionado) {
        _alunosSelecionadosIds.add(alunoId);
      } else {
        _alunosSelecionadosIds.remove(alunoId);
      }

      // Atualizar estado no array de alunos
      final index = _alunosInativos.indexWhere((aluno) => aluno['id'] == alunoId);
      if (index != -1) {
        _alunosInativos[index]['selecionado'] = selecionado;
      }
    });
  }

  void _selecionarTodos() {
    setState(() {
      _alunosSelecionadosIds = _alunosInativos.map((aluno) => aluno['id'].toString()).toList();
      for (var aluno in _alunosInativos) {
        aluno['selecionado'] = true;
      }
    });
  }

  void _limparSelecao() {
    setState(() {
      _alunosSelecionadosIds.clear();
      for (var aluno in _alunosInativos) {
        aluno['selecionado'] = false;
      }
    });
  }

  List<Map<String, dynamic>> _filtrarAlunos() {
    if (_searchQuery.isEmpty) return _alunosInativos;

    return _alunosInativos.where((aluno) {
      final nome = aluno['nome'].toString().toLowerCase();
      final apelido = aluno['apelido'].toString().toLowerCase();
      final graduacao = aluno['graduacao'].toString().toLowerCase();

      return nome.contains(_searchQuery.toLowerCase()) ||
          apelido.contains(_searchQuery.toLowerCase()) ||
          graduacao.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Widget _buildAlunoCard(Map<String, dynamic> aluno) {
    final bool selecionado = aluno['selecionado'] == true;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 1,
      color: selecionado ? Colors.blue.shade50 : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selecionado ? Colors.blue : Colors.grey.shade300,
              width: selecionado ? 2 : 1,
            ),
          ),
          child: CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: aluno['foto_url'] != null && aluno['foto_url'].isNotEmpty
                ? NetworkImage(aluno['foto_url'])
                : null,
            child: aluno['foto_url'] != null && aluno['foto_url'].isNotEmpty
                ? null
                : Icon(Icons.person, color: Colors.grey.shade600),
          ),
        ),
        title: Text(
          aluno['nome'],
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: selecionado ? Colors.blue.shade800 : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (aluno['apelido'] != null && aluno['apelido'].isNotEmpty)
              Text(
                'Apelido: ${aluno['apelido']}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            Text(
              'Graduação: ${aluno['graduacao']}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            if (aluno['idade'] != null && aluno['idade'].toString().isNotEmpty)
              Text(
                'Idade: ${aluno['idade']} anos',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
          ],
        ),
        trailing: Checkbox(
          value: selecionado,
          onChanged: (value) {
            _toggleSelecaoAluno(aluno['id'], value ?? false);
          },
          fillColor: MaterialStateProperty.resolveWith<Color>(
                (Set<MaterialState> states) {
              if (states.contains(MaterialState.selected)) {
                return Colors.red.shade900;
              }
              return Colors.grey;
            },
          ),
        ),
        onTap: () {
          _toggleSelecaoAluno(aluno['id'], !selecionado);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alunosFiltrados = _filtrarAlunos();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'VINCULAR ALUNOS INATIVOS',
              style: TextStyle(fontSize: 16),
            ),
            Text(
              'Turma: ${widget.turmaNome}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar aluno inativo...',
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
      body: _carregandoAlunos
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Cabeçalho com informações e contadores
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade50,
            child: Row(
              children: [
                // Informações à esquerda
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ALUNOS INATIVOS: ${_alunosInativos.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'SELECIONADOS: ${_alunosSelecionadosIds.length}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Botões à direita
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _alunosInativos.isNotEmpty ? _selecionarTodos : null,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                      child: const Text(
                        'TODOS',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: _alunosSelecionadosIds.isNotEmpty ? _limparSelecao : null,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                      child: const Text(
                        'LIMPAR',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Lista de alunos inativos
          Expanded(
            child: _alunosInativos.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_off,
                    size: 80,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Nenhum aluno inativo',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _carregarAlunosInativos,
                    child: const Text('RECARREGAR'),
                  ),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: _carregarAlunosInativos,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: alunosFiltrados.length,
                itemBuilder: (context, index) {
                  return _buildAlunoCard(alunosFiltrados[index]);
                },
              ),
            ),
          ),
        ],
      ),
      // Botão flutuante para vincular
      floatingActionButton: _alunosSelecionadosIds.isNotEmpty
          ? Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: FloatingActionButton.extended(
          onPressed: _isLoading ? null : _vincularAlunosSelecionados,
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          icon: _isLoading
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: Colors.white),
          )
              : const Icon(Icons.check),
          label: Text(
            _isLoading ? 'PROCESSANDO...' : 'VINCULAR (${_alunosSelecionadosIds.length})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}