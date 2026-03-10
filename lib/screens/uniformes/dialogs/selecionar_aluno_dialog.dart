import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
                    if (_searchQuery.isEmpty) return true;
                    var data = doc.data() as Map<String, dynamic>;
                    return (data['nome'] ?? '')
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase());
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

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: widget.corTema.withOpacity(0.2),
                          child: Text(
                            (data['nome'] ?? '?')[0].toUpperCase(),
                            style: TextStyle(color: widget.corTema),
                          ),
                        ),
                        title: Text(data['nome'] ?? 'Sem nome'),
                        subtitle: Text(data['turma'] ?? 'Sem turma'),
                        onTap: () {
                          // CORREÇÃO: Retornar Map<String, String> explicitamente
                          final resultado = <String, String>{
                            'id': doc.id,
                            'nome': data['nome']?.toString() ?? '',
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
}