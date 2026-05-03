import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'editar_academia_screen.dart';
import '../../gerenciar_turmas_screen.dart';
import 'usuario_detalhe_screen.dart';
import '../../core/utils/responsive_utils.dart';

class GerenciarAcademiasScreen extends StatefulWidget {
  const GerenciarAcademiasScreen({super.key});

  @override
  State<GerenciarAcademiasScreen> createState() =>
      _GerenciarAcademiasScreenState();
}

class _GerenciarAcademiasScreenState
    extends State<GerenciarAcademiasScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Filtros
  String _searchQuery = '';
  String _filterCidade = 'Todas';
  String _filterModalidade = 'Todas';
  List<String> _cidades = ['Todas'];
  List<String> _modalidades = ['Todas'];

  // Controle de carregamento para o botão de cálculo
  bool _calculandoContadores = false;

  @override
  void initState() {
    super.initState();
    _carregarFiltros();
  }

  Future<void> _carregarFiltros() async {
    final snapshot = await _firestore
        .collection('academias')
        .orderBy('nome')
        .get();

    final cidadesUnicas = <String>{'Todas'};
    final modalidadesUnicas = <String>{'Todas'};

    for (var doc in snapshot.docs) {
      final cidade = doc['cidade'] as String?;
      final modalidade = doc['modalidade'] as String?;

      if (cidade != null && cidade.isNotEmpty) {
        cidadesUnicas.add(cidade);
      }
      if (modalidade != null && modalidade.isNotEmpty) {
        modalidadesUnicas.add(modalidade);
      }
    }

    setState(() {
      _cidades = cidadesUnicas.toList()..sort();
      _modalidades = modalidadesUnicas.toList()..sort();
    });
  }

  Widget _buildFiltroCidade() {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(_filterCidade),
        selected: _filterCidade != 'Todas',
        onSelected: (selected) {
          if (!selected) {
            setState(() => _filterCidade = 'Todas');
          } else {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Filtrar por Cidade'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _cidades.length,
                    itemBuilder: (context, index) {
                      final cidade = _cidades[index];
                      return ListTile(
                        title: Text(cidade),
                        trailing: _filterCidade == cidade
                            ? const Icon(Icons.check, color: Colors.red)
                            : null,
                        onTap: () {
                          setState(() => _filterCidade = cidade);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ),
            );
          }
        },
        avatar: const Icon(Icons.location_city, size: 18, color: Colors.red),
      ),
    );
  }

  Widget _buildFiltroModalidade() {
    return FilterChip(
      label: Text(_filterModalidade),
      selected: _filterModalidade != 'Todas',
      onSelected: (selected) {
        if (!selected) {
          setState(() => _filterModalidade = 'Todas');
        } else {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Filtrar por Modalidade'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _modalidades.length,
                  itemBuilder: (context, index) {
                    final modalidade = _modalidades[index];
                    return ListTile(
                      title: Text(modalidade),
                      trailing: _filterModalidade == modalidade
                          ? const Icon(Icons.check, color: Colors.red)
                          : null,
                      onTap: () {
                        setState(() => _filterModalidade = modalidade);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ),
          );
        }
      },
      avatar: const Icon(Icons.sports_martial_arts, size: 18, color: Colors.red),
    );
  }

  // Função para calcular e atualizar contadores
  Future<void> _calcularAtualizarContadores() async {
    setState(() {
      _calculandoContadores = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
            ),
            const SizedBox(height: 16),
            const Text('Calculando contadores...'),
            const SizedBox(height: 8),
            const Text(
              'Aguarde enquanto atualizamos os contadores de alunos',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );

    try {
      final academiasSnapshot = await _firestore
          .collection('academias')
          .get();

      int academiasProcessadas = 0;

      for (var academiaDoc in academiasSnapshot.docs) {
        final academiaId = academiaDoc.id;
        final academiaRef = academiaDoc.reference;

        final turmasSnapshot = await _firestore
            .collection('turmas')
            .where('academia_id', isEqualTo: academiaId)
            .get();

        int totalAlunosAcademia = 0;
        int totalTurmasAtivas = 0;

        for (var turmaDoc in turmasSnapshot.docs) {
          final turmaId = turmaDoc.id;
          final turmaRef = turmaDoc.reference;

          final alunosAtivosSnapshot = await _firestore
              .collection('alunos')
              .where('turma_id', isEqualTo: turmaId)
              .where('status_atividade', isEqualTo: 'ATIVO(A)')
              .get();

          final alunosAtivosCount = alunosAtivosSnapshot.docs.length;

          final alunosInativosSnapshot = await _firestore
              .collection('alunos')
              .where('turma_id', isEqualTo: turmaId)
              .where('status_atividade', isEqualTo: 'INATIVO(A)')
              .get();

          final alunosInativosCount = alunosInativosSnapshot.docs.length;
          final totalAlunosTurma = alunosAtivosCount + alunosInativosCount;

          totalAlunosAcademia += alunosAtivosCount;

          final statusTurma = turmaDoc['status'] as String?;
          if (statusTurma == 'ATIVA') {
            totalTurmasAtivas++;
          }

          await turmaRef.update({
            'alunos_ativos': alunosAtivosCount,
            'alunos_inativos': alunosInativosCount,
            'alunos_count': totalAlunosTurma,
            'atualizado_em': FieldValue.serverTimestamp(),
            'ultima_atualizacao': FieldValue.serverTimestamp(),
          });
        }

        await academiaRef.update({
          'turmas_count': turmasSnapshot.docs.length,
          'turmas_ativas_count': totalTurmasAtivas,
          'alunos_count': totalAlunosAcademia,
          'ultima_atualizacao': FieldValue.serverTimestamp(),
          'atualizado_em': FieldValue.serverTimestamp(),
        });

        academiasProcessadas++;
      }

      if (context.mounted) {
        Navigator.pop(context);
      }

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Sucesso!'),
              ],
            ),
            content: Text(
              'Contadores atualizados com sucesso!\n'
                  'Processadas $academiasProcessadas academias.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
      }

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Erro'),
              ],
            ),
            content: Text('Erro ao calcular contadores: ${e.toString()}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      setState(() {
        _calculandoContadores = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveUtils.isMobile(context);
    final isTablet = ResponsiveUtils.isTablet(context);
    final isDesktop = ResponsiveUtils.isDesktop(context);
    final padding = ResponsiveUtils.getResponsivePadding(context);

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Gerenciar Academias',
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, baseSize: 20),
            ),
          ),
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              onPressed: _calculandoContadores ? null : _calcularAtualizarContadores,
              icon: _calculandoContadores
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : const Icon(Icons.calculate),
              tooltip: 'Calcular contadores de alunos',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(100),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar academia...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (value) =>
                        setState(() => _searchQuery = value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      _buildFiltroCidade(),
                      _buildFiltroModalidade(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('academias').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.business,
                      size: 80,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhuma academia cadastrada',
                      style: TextStyle(
                        fontSize: ResponsiveUtils.getResponsiveFontSize(context, baseSize: 18),
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Clique no botão + para adicionar',
                      style: TextStyle(
                        fontSize: ResponsiveUtils.getResponsiveFontSize(context, baseSize: 14),
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              );
            }

            var academias = snapshot.data!.docs;

            if (_searchQuery.isNotEmpty) {
              academias = academias.where((doc) {
                final nome = doc['nome']?.toString().toLowerCase() ?? '';
                final cidade = doc['cidade']?.toString().toLowerCase() ?? '';
                final modalidade = doc['modalidade']?.toString().toLowerCase() ?? '';
                return nome.contains(_searchQuery.toLowerCase()) ||
                    cidade.contains(_searchQuery.toLowerCase()) ||
                    modalidade.contains(_searchQuery.toLowerCase());
              }).toList();
            }

            if (_filterCidade != 'Todas') {
              academias = academias
                  .where((doc) => doc['cidade'] == _filterCidade)
                  .toList();
            }

            if (_filterModalidade != 'Todas') {
              academias = academias
                  .where((doc) => doc['modalidade'] == _filterModalidade)
                  .toList();
            }

            return SingleChildScrollView(
              padding: padding,
              child: SizedBox(
                width: double.infinity,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount = 1;
                            if (isDesktop) {
                              crossAxisCount = 3;
                            } else if (isTablet) {
                              crossAxisCount = 2;
                            } else {
                              crossAxisCount = 1;
                            }

                            final spacing = 12.0;
                            final itemWidth = (constraints.maxWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount;

                            return Wrap(
                              alignment: WrapAlignment.center,
                              spacing: spacing,
                              runSpacing: spacing,
                              children: academias.map((academia) {
                                final data = academia.data() as Map<String, dynamic>;
                                final nome = data['nome'] ?? 'Sem nome';
                                final cidade = data['cidade'] ?? 'Sem cidade';
                                final modalidade = data['modalidade'] ?? 'Sem modalidade';
                                final responsavelNome = data['responsavel'] ?? 'Sem responsável';
                                final responsavelId = data['responsavel_id'] as String?;
                                final status = data['status'] ?? 'ativa';
                                final turmasCount = data['turmas_count'] ?? 0;
                                final alunosCount = data['alunos_count'] ?? 0;
                                final turmasAtivasCount = data['turmas_ativas_count'] ?? 0;
                                final ultimaAtualizacao = data['ultima_atualizacao'] as Timestamp?;

                                return SizedBox(
                                  width: itemWidth,
                                  child: Card(
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => EditarAcademiaScreen(
                                              academiaId: academia.id,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  width: 50,
                                                  height: 50,
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.shade900.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Icon(
                                                    Icons.business,
                                                    size: 28,
                                                    color: status == 'ativa' ? Colors.red : Colors.grey,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        nome,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: ResponsiveUtils.getResponsiveFontSize(context, baseSize: 16),
                                                          color: status == 'ativa' ? Colors.black : Colors.grey,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Row(
                                                        children: [
                                                          Icon(Icons.location_on,
                                                              size: 14, color: Colors.grey.shade600),
                                                          const SizedBox(width: 4),
                                                          Expanded(
                                                            child: Text(
                                                              '$cidade • $modalidade',
                                                              style: TextStyle(color: Colors.grey.shade600),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuButton<String>(
                                                  icon: const Icon(Icons.more_vert),
                                                  onSelected: (value) {
                                                    if (value == 'editar') {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (context) => EditarAcademiaScreen(
                                                            academiaId: academia.id,
                                                          ),
                                                        ),
                                                      );
                                                    } else if (value == 'turmas') {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (context) => GerenciarTurmasScreen(
                                                            academiaId: academia.id,
                                                            academiaNome: nome,
                                                          ),
                                                        ),
                                                      );
                                                    } else if (value == 'calcular') {
                                                      _calcularContadoresAcademia(academia.id, nome);
                                                    }
                                                  },
                                                  itemBuilder: (context) => [
                                                    const PopupMenuItem(
                                                      value: 'editar',
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.edit, color: Colors.blue),
                                                          SizedBox(width: 8),
                                                          Text('Editar Academia'),
                                                        ],
                                                      ),
                                                    ),
                                                    const PopupMenuItem(
                                                      value: 'turmas',
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.group, color: Colors.green),
                                                          SizedBox(width: 8),
                                                          Text('Gerenciar Turmas'),
                                                        ],
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'calcular',
                                                      child: Row(
                                                        children: [
                                                          const Icon(Icons.calculate, color: Colors.orange),
                                                          const SizedBox(width: 8),
                                                          const Text('Recalcular Contadores'),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                _buildInfoChip(
                                                  icon: Icons.group,
                                                  label: '$turmasCount turma${turmasCount != 1 ? 's' : ''}',
                                                  color: Colors.blue.shade700,
                                                ),
                                                if (turmasAtivasCount > 0)
                                                  _buildInfoChip(
                                                    icon: Icons.check_circle,
                                                    label: '$turmasAtivasCount ativa${turmasAtivasCount != 1 ? 's' : ''}',
                                                    color: Colors.green.shade700,
                                                  ),
                                                _buildInfoChip(
                                                  icon: Icons.person,
                                                  label: '$alunosCount aluno${alunosCount != 1 ? 's' : ''}',
                                                  color: Colors.red.shade700,
                                                ),
                                                _buildStatusChip(status),
                                              ],
                                            ),
                                            if (responsavelNome.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              GestureDetector(
                                                onTap: responsavelId != null ? () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => UsuarioDetalheScreen(
                                                        userId: responsavelId,
                                                      ),
                                                    ),
                                                  );
                                                } : null,
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.person_outline,
                                                        size: 14,
                                                        color: responsavelId != null
                                                            ? Colors.blue.shade600
                                                            : Colors.grey.shade600),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        'Resp: $responsavelNome',
                                                        style: TextStyle(
                                                          color: responsavelId != null
                                                              ? Colors.blue.shade600
                                                              : Colors.grey.shade600,
                                                          fontWeight: responsavelId != null
                                                              ? FontWeight.w500
                                                              : FontWeight.normal,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (responsavelId != null) ...[
                                                      const SizedBox(width: 4),
                                                      Icon(Icons.open_in_new,
                                                          size: 12,
                                                          color: Colors.blue.shade600),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ],
                                            if (ultimaAtualizacao != null) ...[
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Icon(Icons.update,
                                                      size: 12, color: Colors.grey.shade500),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Atualizado: ${_formatarData(ultimaAtualizacao)}',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey.shade500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const EditarAcademiaScreen(),
              ),
            );
          },
          backgroundColor: Colors.red.shade900,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final isActive = status == 'ativa';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.check_circle : Icons.block,
            size: 12,
            color: isActive ? Colors.green.shade800 : Colors.grey.shade600,
          ),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.green.shade800 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatarData(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'agora há pouco';
        }
        return 'há ${difference.inMinutes} min';
      }
      return 'há ${difference.inHours} h';
    } else if (difference.inDays == 1) {
      return 'ontem';
    } else if (difference.inDays < 7) {
      return 'há ${difference.inDays} dias';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<void> _calcularContadoresAcademia(String academiaId, String academiaNome) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
            ),
            const SizedBox(height: 16),
            Text('Calculando $academiaNome...'),
          ],
        ),
      ),
    );

    try {
      final academiaRef = _firestore.collection('academias').doc(academiaId);

      final turmasSnapshot = await _firestore
          .collection('turmas')
          .where('academia_id', isEqualTo: academiaId)
          .get();

      int totalAlunosAcademia = 0;
      int totalTurmasAtivas = 0;

      for (var turmaDoc in turmasSnapshot.docs) {
        final turmaId = turmaDoc.id;
        final turmaRef = turmaDoc.reference;

        final alunosAtivosSnapshot = await _firestore
            .collection('alunos')
            .where('turma_id', isEqualTo: turmaId)
            .where('status_atividade', isEqualTo: 'ATIVO(A)')
            .get();

        final alunosAtivosCount = alunosAtivosSnapshot.docs.length;

        final alunosInativosSnapshot = await _firestore
            .collection('alunos')
            .where('turma_id', isEqualTo: turmaId)
            .where('status_atividade', isEqualTo: 'INATIVO(A)')
            .get();

        final alunosInativosCount = alunosInativosSnapshot.docs.length;
        final totalAlunosTurma = alunosAtivosCount + alunosInativosCount;

        totalAlunosAcademia += alunosAtivosCount;

        final statusTurma = turmaDoc['status'] as String?;
        if (statusTurma == 'ATIVA') {
          totalTurmasAtivas++;
        }

        await turmaRef.update({
          'alunos_ativos': alunosAtivosCount,
          'alunos_inativos': alunosInativosCount,
          'alunos_count': totalAlunosTurma,
          'atualizado_em': FieldValue.serverTimestamp(),
          'ultima_atualizacao': FieldValue.serverTimestamp(),
        });
      }

      await academiaRef.update({
        'turmas_count': turmasSnapshot.docs.length,
        'turmas_ativas_count': totalTurmasAtivas,
        'alunos_count': totalAlunosAcademia,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
        'atualizado_em': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        Navigator.pop(context);
      }

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Sucesso!'),
              ],
            ),
            content: Text(
              'Contadores da academia "$academiaNome" atualizados!\n'
                  'Total de alunos: $totalAlunosAcademia\n'
                  'Total de turmas: ${turmasSnapshot.docs.length}\n'
                  'Turmas ativas: $totalTurmasAtivas',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }

      setState(() {});
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Erro'),
              ],
            ),
            content: Text('Erro ao calcular: ${e.toString()}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }
}