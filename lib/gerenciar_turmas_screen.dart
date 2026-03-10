import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'editar_turma_screen.dart';
import 'gerenciar_alunos_turma_screen.dart';

class GerenciarTurmasScreen extends StatefulWidget {
  final String academiaId;
  final String academiaNome;

  const GerenciarTurmasScreen({
    super.key,
    required this.academiaId,
    required this.academiaNome,
  });

  @override
  State<GerenciarTurmasScreen> createState() => _GerenciarTurmasScreenState();
}

class _GerenciarTurmasScreenState extends State<GerenciarTurmasScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _searchQuery = '';
  String _filterStatus = 'Todas';
  String _filterFaixaEtaria = 'Todas';
  List<String> _statusOptions = ['Todas', 'ATIVA', 'INATIVA', 'ESGOTADA'];
  List<String> _faixaEtariaOptions = ['Todas', 'INFANTIL', 'JUVENIL', 'ADULTO', 'SENIOR', 'MISTA'];

  void _showDeleteConfirmation(String turmaId, String turmaNome) async {
    final turmaDoc = await _firestore.collection('turmas').doc(turmaId).get();
    final alunosCount = turmaDoc['alunos_count'] ?? 0;

    final confirmacaoController = TextEditingController();
    bool nomeConfere = false;

    await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                'Confirmar Exclusão',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alunosCount > 0
                        ? 'A turma "$turmaNome" possui $alunosCount aluno(s) matriculado(s).\n\nTodos os vínculos com alunos serão removidos.'
                        : 'Tem certeza que deseja excluir a turma "$turmaNome"?\n\nEsta ação não pode ser desfeita.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Para confirmar, digite o nome da turma:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Center(
                      child: Text(
                        '"$turmaNome"',
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: confirmacaoController,
                    decoration: InputDecoration(
                      labelText: 'Digite o nome da turma',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.warning, color: Colors.orange),
                      suffixIcon: confirmacaoController.text.isNotEmpty
                          ? Icon(
                        confirmacaoController.text.trim() == turmaNome
                            ? Icons.check_circle
                            : Icons.error,
                        color: confirmacaoController.text.trim() == turmaNome
                            ? Colors.green
                            : Colors.red,
                      )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        nomeConfere = value.trim() == turmaNome;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: nomeConfere
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red,
                    disabledBackgroundColor: Colors.grey.shade200,
                    disabledForegroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Excluir Turma',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            );
          },
        );
      },
    ).then((confirmado) async {
      if (confirmado == true) {
        await _realizarExclusaoTurma(turmaId, turmaNome, alunosCount);
      }
    });
  }

  Future<void> _realizarExclusaoTurma(String turmaId, String turmaNome, int alunosCount) async {
    try {
      if (alunosCount > 0) {
        final vinculosSnapshot = await _firestore
            .collection('alunos_turmas')
            .where('turma_id', isEqualTo: turmaId)
            .get();

        for (var vinculo in vinculosSnapshot.docs) {
          await vinculo.reference.delete();
        }
      }

      await _firestore.collection('turmas').doc(turmaId).delete();

      await _atualizarContadorTurmas();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Turma "$turmaNome" excluída com sucesso!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _atualizarContadorTurmas() async {
    try {
      final turmasSnapshot = await _firestore
          .collection('turmas')
          .where('academia_id', isEqualTo: widget.academiaId)
          .get();

      await _firestore
          .collection('academias')
          .doc(widget.academiaId)
          .update({
        'turmas_count': turmasSnapshot.docs.length,
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Erro ao atualizar contador: $e');
    }
  }

  Widget _buildFiltroStatus() {
    return FilterChip(
      label: Text(
        _filterStatus,
        style: TextStyle(
          color: _filterStatus != 'Todas' ? Colors.white : Colors.grey.shade700,
          fontWeight: FontWeight.w500,
        ),
      ),
      selected: _filterStatus != 'Todas',
      selectedColor: Colors.red.shade800,
      backgroundColor: Colors.grey.shade100,
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: _filterStatus != 'Todas' ? Colors.red.shade800 : Colors.grey.shade300,
        width: 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      onSelected: (selected) {
        setState(() {
          _filterStatus = selected ? 'ATIVA' : 'Todas';
        });
      },
      avatar: Icon(
        Icons.circle,
        size: 14,
        color: _filterStatus != 'Todas' ? Colors.white : Colors.grey.shade600,
      ),
    );
  }

  Widget _buildFiltroFaixaEtaria() {
    return FilterChip(
      label: Text(
        _filterFaixaEtaria,
        style: TextStyle(
          color: _filterFaixaEtaria != 'Todas' ? Colors.white : Colors.grey.shade700,
          fontWeight: FontWeight.w500,
        ),
      ),
      selected: _filterFaixaEtaria != 'Todas',
      selectedColor: Colors.red.shade800,
      backgroundColor: Colors.grey.shade100,
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: _filterFaixaEtaria != 'Todas' ? Colors.red.shade800 : Colors.grey.shade300,
        width: 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      onSelected: (selected) {
        if (!selected) {
          setState(() => _filterFaixaEtaria = 'Todas');
        } else {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Text(
                      'Filtrar por Faixa Etária',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade800,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  SizedBox(
                    width: double.maxFinite,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _faixaEtariaOptions.length,
                      itemBuilder: (context, index) {
                        final faixa = _faixaEtariaOptions[index];
                        return ListTile(
                          title: Text(
                            faixa,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: _filterFaixaEtaria == faixa
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: _filterFaixaEtaria == faixa
                                  ? Colors.red.shade800
                                  : Colors.grey.shade800,
                            ),
                          ),
                          trailing: _filterFaixaEtaria == faixa
                              ? Icon(Icons.check, color: Colors.red.shade800)
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          onTap: () {
                            setState(() => _filterFaixaEtaria = faixa);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade50,
                          foregroundColor: Colors.red.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Fechar'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      },
      avatar: Icon(
        Icons.people,
        size: 16,
        color: _filterFaixaEtaria != 'Todas' ? Colors.white : Colors.grey.shade600,
      ),
    );
  }

  String _getStatusColor(String status) {
    switch (status) {
      case 'ATIVA':
        return '#10B981'; // verde
      case 'ESGOTADA':
        return '#F59E0B'; // amarelo/laranja
      case 'INATIVA':
        return '#6B7280'; // cinza
      default:
        return '#EF4444'; // vermelho
    }
  }

  String _getFaixaEtariaIcon(String faixa) {
    switch (faixa) {
      case 'INFANTIL':
        return '👶';
      case 'JUVENIL':
        return '🧒';
      case 'ADULTO':
        return '👨';
      case 'SENIOR':
        return '👴';
      case 'MISTA':
        return '👥';
      default:
        return '👥';
    }
  }

  String _getDiasSemanaAbreviados(List<dynamic> dias) {
    if (dias.isEmpty) return 'Sem horário';

    final Map<String, String> abreviacoes = {
      'SEGUNDA': 'SEG',
      'TERCA': 'TER',
      'QUARTA': 'QUA',
      'QUINTA': 'QUI',
      'SEXTA': 'SEX',
      'SABADO': 'SAB',
      'DOMINGO': 'DOM'
    };

    return dias.map((dia) => abreviacoes[dia] ?? dia).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Gerenciar Turmas',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.academiaNome,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                  color: Colors.white.withOpacity(0.9),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          backgroundColor: Colors.red.shade900, // Vermelho mais escuro
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 2,
        ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('turmas')
            .where('academia_id', isEqualTo: widget.academiaId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Colors.red,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Carregando turmas...',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.group_outlined,
                      size: 80,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Nenhuma turma cadastrada',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Clique no botão + para adicionar sua primeira turma',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          var turmas = snapshot.data!.docs;

          if (_searchQuery.isNotEmpty) {
            turmas = turmas.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final nome = data['nome']?.toString().toLowerCase() ?? '';
              final nivel = data['nivel']?.toString().toLowerCase() ?? '';
              final professor = data['professor']?.toString().toLowerCase() ?? '';
              return nome.contains(_searchQuery.toLowerCase()) ||
                  nivel.contains(_searchQuery.toLowerCase()) ||
                  professor.contains(_searchQuery.toLowerCase());
            }).toList();
          }

          if (_filterStatus != 'Todas') {
            turmas = turmas
                .where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['status'] == _filterStatus;
            })
                .toList();
          }

          if (_filterFaixaEtaria != 'Todas') {
            turmas = turmas
                .where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['faixa_etaria'] == _filterFaixaEtaria;
            })
                .toList();
          }

          turmas.sort((a, b) {
            final dataA = a.data() as Map<String, dynamic>;
            final dataB = b.data() as Map<String, dynamic>;

            final statusA = dataA['status'] ?? '';
            final statusB = dataB['status'] ?? '';

            if (statusA == 'ATIVA' && statusB != 'ATIVA') return -1;
            if (statusA != 'ATIVA' && statusB == 'ATIVA') return 1;

            final nomeA = dataA['nome']?.toString().toLowerCase() ?? '';
            final nomeB = dataB['nome']?.toString().toLowerCase() ?? '';
            return nomeA.compareTo(nomeB);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: turmas.length,
            itemBuilder: (context, index) {
              final turma = turmas[index];
              final data = turma.data() as Map<String, dynamic>;

              final nome = data['nome'] ?? 'Sem nome';
              final nivel = data['nivel'] ?? 'Sem nível';
              final faixaEtaria = data['faixa_etaria'] ?? 'Sem faixa';
              final professor = data['professor_principal'] ?? data['professor'] ?? 'Sem professor';
              final status = data['status'] ?? 'INATIVA';
              final horarioDisplay = data['horario_display'] ?? 'Sem horário';
              final diasSemana = (data['dias_semana'] as List<dynamic>? ?? []);
              final alunosCount = data['alunos_count'] ?? 0;
              final capacidade = data['capacidade_maxima'] ?? 0;
              final ocupacao = capacidade > 0
                  ? ((alunosCount / capacidade) * 100).toInt()
                  : 0;
              final corTurma = data['cor_turma'] ?? '#059669';
              final logoUrl = data['logo_url'];

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditarTurmaScreen(
                            academiaId: widget.academiaId,
                            academiaNome: widget.academiaNome,
                            turmaId: turma.id,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.grey.shade200,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: logoUrl != null && logoUrl.toString().isNotEmpty
                                  ? Image.network(
                                logoUrl.toString(),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Color(int.parse(corTurma.replaceFirst('#', '0xFF'))).withOpacity(0.1),
                                    child: Center(
                                      child: Text(
                                        _getFaixaEtariaIcon(faixaEtaria),
                                        style: const TextStyle(fontSize: 28),
                                      ),
                                    ),
                                  );
                                },
                              )
                                  : Container(
                                color: Color(int.parse(corTurma.replaceFirst('#', '0xFF'))).withOpacity(0.1),
                                child: Center(
                                  child: Text(
                                    _getFaixaEtariaIcon(faixaEtaria),
                                    style: const TextStyle(fontSize: 28),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        nome,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: status == 'ATIVA' ? Colors.black : Colors.grey.shade600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Color(int.parse(
                                            _getStatusColor(status).replaceFirst('#', '0xFF'))
                                        ).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Color(int.parse(
                                              _getStatusColor(status).replaceFirst('#', '0xFF'))
                                          ).withOpacity(0.3),
                                        ),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(int.parse(
                                              _getStatusColor(status).replaceFirst('#', '0xFF'))
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '$horarioDisplay • ${_getDiasSemanaAbreviados(diasSemana)}',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.category, size: 16, color: Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '$nivel • $faixaEtaria',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.person_outline, size: 16, color: Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        professor,
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: LinearProgressIndicator(
                                            value: ocupacao / 100,
                                            backgroundColor: Colors.grey.shade200,
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                                ocupacao >= 90
                                                    ? Colors.red.shade600
                                                    : ocupacao >= 70
                                                    ? Colors.orange.shade600
                                                    : Colors.green.shade600
                                            ),
                                            borderRadius: BorderRadius.circular(10),
                                            minHeight: 10,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '$alunosCount/$capacidade',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: ocupacao >= 90
                                                ? Colors.red.shade700
                                                : ocupacao >= 70
                                                ? Colors.orange.shade700
                                                : Colors.green.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '($ocupacao% ocupado)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              color: Colors.grey.shade600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onSelected: (value) {
                              if (value == 'editar') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EditarTurmaScreen(
                                      academiaId: widget.academiaId,
                                      academiaNome: widget.academiaNome,
                                      turmaId: turma.id,
                                    ),
                                  ),
                                );
                              } else if (value == 'excluir') {
                                _showDeleteConfirmation(turma.id, nome);
                              } else if (value == 'alunos') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => GerenciarAlunosTurmaScreen(
                                      turmaId: turma.id,
                                      turmaNome: nome,
                                      academiaNome: widget.academiaNome,
                                    ),
                                  ),
                                );
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'editar',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, color: Colors.blue.shade700, size: 20),
                                    const SizedBox(width: 10),
                                    const Text(
                                      'Editar Turma',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'alunos',
                                child: Row(
                                  children: [
                                    Icon(Icons.group_add, color: Colors.green.shade700, size: 20),
                                    const SizedBox(width: 10),
                                    const Text(
                                      'Gerenciar Alunos',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                    if (alunosCount > 0)
                                      Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          alunosCount.toString(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'excluir',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, color: Colors.red.shade700, size: 20),
                                    const SizedBox(width: 10),
                                    const Text(
                                      'Excluir Turma',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditarTurmaScreen(
                academiaId: widget.academiaId,
                academiaNome: widget.academiaNome,
              ),
            ),
          );
        },
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }
}