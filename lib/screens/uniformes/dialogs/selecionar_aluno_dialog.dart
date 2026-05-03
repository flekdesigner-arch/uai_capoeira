import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SelecionarAlunoDialog extends StatefulWidget {
  final Color corTema;

  const SelecionarAlunoDialog({
    super.key,
    this.corTema = Colors.green,
  });

  @override
  State<SelecionarAlunoDialog> createState() => _SelecionarAlunoDialogState();
}

class _SelecionarAlunoDialogState extends State<SelecionarAlunoDialog> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  String? _selectedTurmaId; // null = Todas as turmas
  List<Map<String, dynamic>> _turmasDisponiveis = []; // { 'id': ..., 'nome': ... }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 🔥 LONG PRESS: exibe foto ampliada com zoom
  Future<void> _mostrarFotoAmpliada(String? fotoUrl, String nome) async {
    if (fotoUrl == null || fotoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$nome não possui foto'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Container(
          color: Colors.black87,
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 5.0,
            child: CachedNetworkImage(
              imageUrl: fotoUrl,
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image, color: Colors.white, size: 80),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            AppBar(
              title: const Text('SELECIONAR ALUNO'),
              backgroundColor: widget.corTema,
              foregroundColor: Colors.white,
              automaticallyImplyLeading: false,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.maybePop(context),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ],
            ),
            // 🔥 FILTRO POR TURMA (CHIPS)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('alunos')
                    .where('status_atividade', isEqualTo: 'ATIVO(A)')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  // Extrair turmas únicas
                  final turmas = <String, String>{};
                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final turmaId = data['turma_id'] as String?;
                    final turmaNome = data['turma'] as String?;
                    if (turmaId != null && turmaNome != null) {
                      turmas[turmaId] = turmaNome;
                    }
                  }
                  _turmasDisponiveis = turmas.entries
                      .map((e) => {'id': e.key, 'nome': e.value})
                      .toList()
                    ..sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildTurmaChip(null, 'Todas'),
                        ..._turmasDisponiveis.map((turma) {
                          return _buildTurmaChip(turma['id'] as String, turma['nome'] as String);
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Campo de busca por nome
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Pesquisar aluno...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                      : null,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
            // Lista de alunos
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('alunos')
                    .where('status_atividade', isEqualTo: 'ATIVO(A)')
                    .orderBy('nome')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 50, color: Colors.red.shade300),
                          const SizedBox(height: 16),
                          Text('Erro: ${snapshot.error}'),
                          ElevatedButton(
                            onPressed: () => Navigator.maybePop(context),
                            child: const Text('Voltar'),
                          ),
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
                          Icon(Icons.people_outline, size: 50, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhum aluno ativo encontrado',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.maybePop(context),
                            child: const Text('Voltar'),
                          ),
                        ],
                      ),
                    );
                  }

                  var alunos = snapshot.data!.docs.where((doc) {
                    var data = doc.data() as Map<String, dynamic>;
                    // Filtrar por turma
                    if (_selectedTurmaId != null && data['turma_id'] != _selectedTurmaId) {
                      return false;
                    }
                    // Filtrar por busca
                    if (_searchQuery.isNotEmpty) {
                      final nome = data['nome']?.toString().toLowerCase() ?? '';
                      return nome.contains(_searchQuery.toLowerCase());
                    }
                    return true;
                  }).toList();

                  if (alunos.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 50, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhum aluno encontrado',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          if (_selectedTurmaId != null)
                            TextButton(
                              onPressed: () => setState(() => _selectedTurmaId = null),
                              child: const Text('Mostrar todas as turmas'),
                            )
                          else
                            ElevatedButton(
                              onPressed: () => Navigator.maybePop(context),
                              child: const Text('Voltar'),
                            ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: alunos.length,
                    itemBuilder: (context, index) {
                      var doc = alunos[index];
                      var data = doc.data() as Map<String, dynamic>;
                      final nome = data['nome']?.toString() ?? 'Sem nome';
                      final turma = data['turma']?.toString() ?? 'Sem turma';
                      final fotoUrl = data['foto_perfil_aluno'] as String?;
                      final apelido = data['apelido'] as String?;

                      // Avatar com foto ou inicial
                      Widget avatar = fotoUrl != null && fotoUrl.isNotEmpty
                          ? GestureDetector(
                        onLongPress: () => _mostrarFotoAmpliada(fotoUrl, nome),
                        child: CachedNetworkImage(
                          imageUrl: fotoUrl,
                          imageBuilder: (context, imageProvider) => CircleAvatar(
                            backgroundImage: imageProvider,
                            radius: 24,
                          ),
                          placeholder: (_, __) => CircleAvatar(
                            backgroundColor: widget.corTema.withOpacity(0.2),
                            radius: 24,
                            child: Text(
                              nome[0].toUpperCase(),
                              style: TextStyle(color: widget.corTema),
                            ),
                          ),
                          errorWidget: (_, __, ___) => CircleAvatar(
                            backgroundColor: widget.corTema.withOpacity(0.2),
                            radius: 24,
                            child: Text(
                              nome[0].toUpperCase(),
                              style: TextStyle(color: widget.corTema),
                            ),
                          ),
                        ),
                      )
                          : CircleAvatar(
                        backgroundColor: widget.corTema.withOpacity(0.2),
                        radius: 24,
                        child: Text(
                          nome[0].toUpperCase(),
                          style: TextStyle(color: widget.corTema),
                        ),
                      );

                      return ListTile(
                        leading: avatar,
                        title: Text(nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          apelido != null && apelido.isNotEmpty ? '$turma • $apelido' : turma,
                        ),
                        onTap: () {
                          final resultado = <String, String>{
                            'id': doc.id,
                            'nome': nome,
                            'foto_url': fotoUrl ?? '',
                          };
                          Navigator.pop(context, resultado);
                        },
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

  // Widget para chip de turma
  Widget _buildTurmaChip(String? turmaId, String label) {
    final isSelected = _selectedTurmaId == turmaId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
        selected: isSelected,
        selectedColor: widget.corTema,
        backgroundColor: Colors.grey.shade200,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
        ),
        onSelected: (selected) {
          setState(() {
            _selectedTurmaId = selected ? turmaId : null;
            _searchQuery = '';
            _searchController.clear();
          });
        },
      ),
    );
  }
}