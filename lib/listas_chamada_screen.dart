import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ListasChamadaScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;

  const ListasChamadaScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
  });

  @override
  State<ListasChamadaScreen> createState() => _ListasChamadaScreenState();
}

class _ListasChamadaScreenState extends State<ListasChamadaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 🔄 CONTROLE DE PAGINAÇÃO
  List<QueryDocumentSnapshot> _chamadas = [];
  DocumentSnapshot? _ultimoDocumento;
  bool _isLoading = true;
  bool _isLoadingMais = false;
  bool _hasError = false;
  bool _temMaisChamadas = true;
  static const int _limitePorPagina = 10;

  Map<String, dynamic> _permissoes = {};

  @override
  void initState() {
    super.initState();
    _carregarPermissoes();
    _carregarPrimeirasChamadas();
  }

  // 🔐 CARREGAR PERMISSÕES
  Future<void> _carregarPermissoes() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final permissoesDoc = await _firestore
          .collection('usuarios')
          .doc(user.uid)
          .collection('permissoes_usuario')
          .doc('configuracoes')
          .get();

      if (permissoesDoc.exists) {
        setState(() {
          _permissoes = permissoesDoc.data() ?? {};
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar permissões: $e');
    }
  }

  // 🔐 VERIFICAR PERMISSÃO
  bool _temPermissao(String permissao) {
    return _permissoes[permissao] == true;
  }

  // 📄 CARREGAR PRIMEIRAS CHAMADAS
  Future<void> _carregarPrimeirasChamadas() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _chamadas = [];
      _ultimoDocumento = null;
      _temMaisChamadas = true;
    });

    try {
      final querySnapshot = await _firestore
          .collection('chamadas')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('academia_id', isEqualTo: widget.academiaId)
          .orderBy('data_chamada', descending: true)
          .limit(_limitePorPagina)
          .get();

      setState(() {
        _chamadas = querySnapshot.docs;
        if (querySnapshot.docs.isNotEmpty) {
          _ultimoDocumento = querySnapshot.docs.last;
        }
        _temMaisChamadas = querySnapshot.docs.length == _limitePorPagina;
      });
    } catch (e) {
      debugPrint('Erro ao carregar chamadas: $e');
      setState(() {
        _hasError = true;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 📄 CARREGAR MAIS CHAMADAS (PAGINAÇÃO)
  Future<void> _carregarMaisChamadas() async {
    if (_isLoadingMais || !_temMaisChamadas || _ultimoDocumento == null) return;

    setState(() {
      _isLoadingMais = true;
    });

    try {
      final querySnapshot = await _firestore
          .collection('chamadas')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('academia_id', isEqualTo: widget.academiaId)
          .orderBy('data_chamada', descending: true)
          .startAfterDocument(_ultimoDocumento!)
          .limit(_limitePorPagina)
          .get();

      setState(() {
        if (querySnapshot.docs.isNotEmpty) {
          _chamadas.addAll(querySnapshot.docs);
          _ultimoDocumento = querySnapshot.docs.last;
        }
        _temMaisChamadas = querySnapshot.docs.length == _limitePorPagina;
      });
    } catch (e) {
      debugPrint('Erro ao carregar mais chamadas: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar mais chamadas: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoadingMais = false;
      });
    }
  }

  // ✏️ EDITAR CHAMADA - DIALOG
  Future<void> _editarChamada(QueryDocumentSnapshot chamada) async {
    if (!_temPermissao('pode_editar_chamada')) {
      _mostrarSnackBarSemPermissao();
      return;
    }

    final data = chamada.data() as Map<String, dynamic>;
    final alunos = List<Map<String, dynamic>>.from(data['alunos'] ?? []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditarChamadaDialog(
        chamadaId: chamada.id,
        chamadaData: data,
        alunos: alunos,
        turmaNome: widget.turmaNome,
        onChamadaEditada: () {
          _carregarPrimeirasChamadas();
        },
      ),
    );
  }

  void _mostrarSnackBarSemPermissao() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.lock, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Você não tem permissão para editar chamadas'),
          ],
        ),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatarData(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final chamadaDay = DateTime(date.year, date.month, date.day);

    if (chamadaDay == today) {
      return 'Hoje • ${DateFormat('HH:mm').format(date)}';
    } else if (chamadaDay == today.subtract(const Duration(days: 1))) {
      return 'Ontem • ${DateFormat('HH:mm').format(date)}';
    } else {
      return DateFormat("dd/MM/yyyy • HH:mm").format(date);
    }
  }

  Widget _buildCardChamada(QueryDocumentSnapshot chamada, int index) {
    final data = chamada.data() as Map<String, dynamic>;
    final dataChamada = data['data_chamada'] as Timestamp;
    final presentes = data['presentes'] ?? 0;
    final ausentes = data['ausentes'] ?? 0;
    final totalAlunos = data['total_alunos'] ?? 0;
    final alunos = data['alunos'] as List? ?? [];
    final percentualPresenca = totalAlunos > 0 ? (presentes / totalAlunos) : 0;
    final tipoAula = data['tipo_aula']?.toString() ?? 'Não informado';
    final professorNome = data['professor_nome']?.toString() ?? 'Não informado';
    final bool podeEditar = _temPermissao('pode_editar_chamada');

    return Card(
      margin: EdgeInsets.fromLTRB(16, index == 0 ? 16 : 8, 16, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      shadowColor: Colors.red.shade900.withOpacity(0.1),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.all(20),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(
                      value: percentualPresenca,
                      strokeWidth: 4,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(percentualPresenca)),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${(percentualPresenca * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _getStatusColor(percentualPresenca),
                        ),
                      ),
                      Text(
                        '$presentes/$totalAlunos',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatarData(dataChamada),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade100),
                          ),
                          child: Text(
                            tipoAula,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.person,
                        size: 12,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          professorNome,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (podeEditar)
              Container(
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: Colors.blue.shade700,
                  ),
                  onPressed: () => _editarChamada(chamada),
                  tooltip: 'Editar chamada',
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              _buildMiniStatItem(
                icon: Icons.check_circle_rounded,
                value: presentes.toString(),
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 12),
              _buildMiniStatItem(
                icon: Icons.cancel_rounded,
                value: ausentes.toString(),
                color: Colors.red.shade700,
              ),
            ],
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.shade900.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: Colors.red.shade900,
          ),
        ),
        children: [
          if (alunos.isNotEmpty) ...[
            const Divider(height: 20),
            Row(
              children: [
                Icon(
                  Icons.people_alt_rounded,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  'Lista de Alunos (${alunos.length})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...alunos.map((aluno) {
              final alunoMap = aluno as Map<String, dynamic>;
              final nome = alunoMap['aluno_nome'] ?? 'Sem nome';
              final presente = alunoMap['presente'] ?? false;
              final observacao = alunoMap['observacao']?.toString() ?? '';

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: presente ? Colors.green.shade700 : Colors.red.shade700,
                        shape: BoxShape.circle,
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
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: presente ? FontWeight.w500 : FontWeight.normal,
                              decoration: !presente ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          if (observacao.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.note_rounded,
                                    size: 10,
                                    color: Colors.amber.shade700,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      observacao,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.amber.shade800,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: presente ? Colors.green.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        presente ? 'PRESENTE' : 'AUSENTE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: presente ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red.shade900,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DetalhesChamadaScreen(
                          chamadaId: chamada.id,
                          data: data,
                          turmaNome: widget.turmaNome,
                        ),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ver detalhes completos',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniStatItem({
    required IconData icon,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(double percentual) {
    if (percentual >= 0.8) return Colors.green.shade700;
    if (percentual >= 0.6) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Listas de Chamada',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              widget.turmaNome,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        actions: [
          IconButton(
            onPressed: _carregarPrimeirasChamadas,
            icon: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(6),
              child: const Icon(Icons.refresh_rounded, size: 20),
            ),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingScreen()
          : _hasError
          ? _buildErrorScreen()
          : _chamadas.isEmpty
          ? _buildEmptyScreen()
          : RefreshIndicator(
        onRefresh: _carregarPrimeirasChamadas,
        color: Colors.red.shade900,
        backgroundColor: Colors.white,
        displacement: 40,
        child: ListView.builder(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          itemCount: _chamadas.length + (_temMaisChamadas ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _chamadas.length) {
              return _buildLoadingMaisItem();
            }
            return _buildCardChamada(_chamadas[index], index);
          },
        ),
      ),
      floatingActionButton: _chamadas.isNotEmpty
          ? FloatingActionButton.extended(
        onPressed: () {
          PrimaryScrollController.of(context).animateTo(
            0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        },
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.arrow_upward_rounded),
        label: const Text('Topo'),
      )
          : null,
    );
  }

  Widget _buildLoadingMaisItem() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _isLoadingMais
            ? Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              'Carregando mais chamadas...',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        )
            : ElevatedButton(
          onPressed: _carregarMaisChamadas,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey.shade100,
            foregroundColor: Colors.red.shade900,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, size: 16),
              const SizedBox(width: 8),
              const Text('Carregar histórico completo'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              children: [
                Center(
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.red.shade900),
                      backgroundColor: Colors.red.shade100,
                    ),
                  ),
                ),
                Center(
                  child: Icon(
                    Icons.list_alt_rounded,
                    size: 30,
                    color: Colors.red.shade900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Carregando chamadas...',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Preparando experiência premium',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 50,
                color: Colors.red.shade400,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Ops! Algo deu errado',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade400),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Não foi possível carregar as listas de chamada. Verifique sua conexão e tente novamente.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 25),
            Container(
              decoration: BoxDecoration(
                color: Colors.red.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton(
                onPressed: _carregarPrimeirasChamadas,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Tentar novamente',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.list_alt_rounded,
                size: 60,
                color: Colors.red.shade900,
              ),
            ),
            const SizedBox(height: 25),
            Text(
              'Nenhuma chamada registrada',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Esta turma ainda não possui registros de chamada. Faça a primeira chamada para começar o histórico.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
              ),
            ),
            const SizedBox(height: 30),
            Container(
              decoration: BoxDecoration(
                color: Colors.red.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 18, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Voltar para turma',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// DIALOG DE EDIÇÃO DE CHAMADA
// =====================================================
class _EditarChamadaDialog extends StatefulWidget {
  final String chamadaId;
  final Map<String, dynamic> chamadaData;
  final List<Map<String, dynamic>> alunos;
  final String turmaNome;
  final VoidCallback onChamadaEditada;

  const _EditarChamadaDialog({
    required this.chamadaId,
    required this.chamadaData,
    required this.alunos,
    required this.turmaNome,
    required this.onChamadaEditada,
  });

  @override
  State<_EditarChamadaDialog> createState() => _EditarChamadaDialogState();
}

class _EditarChamadaDialogState extends State<_EditarChamadaDialog> with SingleTickerProviderStateMixin {
  late List<Map<String, dynamic>> _alunosEdit;
  late Map<String, TextEditingController> _observacaoControllers;
  bool _isSaving = false;
  bool _isDeleting = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  Map<String, dynamic>? _alunoAtualProcessando;
  bool _mostrarProgresso = false;
  int _alunoIndexAtual = 0;
  int _totalAlunos = 0;
  String _operacaoAtual = 'Preparando...';
  String _detalheOperacao = '';

  String _statusContador = '⏳';
  String _statusLog = '⏳';
  String _statusUltimaPresenca = '⏳';
  String _statusUltimaChamada = '⏳';
  Color _corContador = Colors.grey;
  Color _corLog = Colors.grey;
  Color _corUltimaPresenca = Colors.grey;
  Color _corUltimaChamada = Colors.grey;

  int _logsExcluidos = 0;
  int _contadoresDecrementados = 0;
  int _ultimasPresencasAtualizadas = 0;
  int _ultimasChamadasAtualizadas = 0;

  @override
  void initState() {
    super.initState();
    _alunosEdit = widget.alunos.map((aluno) => Map<String, dynamic>.from(aluno)).toList();
    _observacaoControllers = {};
    for (var aluno in _alunosEdit) {
      final alunoId = aluno['aluno_id'] as String;
      _observacaoControllers[alunoId] = TextEditingController(text: aluno['observacao'] ?? '');
    }
    _totalAlunos = widget.alunos.length;

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    for (var controller in _observacaoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _getDiaSemanaAbrev(DateTime data) {
    switch (data.weekday) {
      case DateTime.monday: return 'seg';
      case DateTime.tuesday: return 'ter';
      case DateTime.wednesday: return 'qua';
      case DateTime.thursday: return 'qui';
      case DateTime.friday: return 'sex';
      case DateTime.saturday: return 'sab';
      case DateTime.sunday: return 'dom';
      default: return 'seg';
    }
  }

  Future<void> _mostrarPreviewExclusao() async {
    final dataChamada = (widget.chamadaData['data_chamada'] as Timestamp).toDate();
    final presentes = widget.alunos.where((a) => a['presente'] == true).length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📋 Prévia da Exclusão'),
        content: Container(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Esta ação irá:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              _buildBulletPoint('Deletar a chamada do dia ${DateFormat('dd/MM/yyyy').format(dataChamada)}'),
              _buildBulletPoint('Remover ${widget.alunos.length} registros de log (um por aluno)'),
              _buildBulletPoint('Decrementar contadores de presença dos $presentes alunos presentes'),
              _buildBulletPoint('Recalcular a ÚLTIMA PRESENÇA de cada aluno'),
              _buildBulletPoint('Recalcular a ÚLTIMA CHAMADA de cada aluno'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Esta operação é um "CTRL+Z" completo: tudo volta exatamente como era antes desta chamada.',
                        style: TextStyle(color: Colors.blue.shade800, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'ATENÇÃO: Esta operação NÃO pode ser desfeita!',
                        style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmarExclusao();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            child: const Text('Continuar com Exclusão'),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Future<void> _confirmarExclusao() async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🗑️ Confirmar Exclusão'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tem certeza absoluta que deseja excluir esta chamada?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Esta ação não poderá ser desfeita. Todos os dados serão permanentemente removidos.',
                      style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade600))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            child: const Text('Sim, Excluir Permanentemente'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      _excluirChamadaComAnimacao();
    }
  }

  Future<void> _excluirChamadaComAnimacao() async {
    setState(() {
      _mostrarProgresso = true;
      _isDeleting = true;
      _operacaoAtual = 'Enviando para exclusão...';
    });

    _animationController.forward();

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('excluirChamada');
      await callable.call({
        'chamadaId': widget.chamadaId,
        'turmaId': widget.chamadaData['turma_id'],
      });

      setState(() {
        _operacaoAtual = '✅ EXCLUSÃO CONCLUÍDA!';
      });
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        widget.onChamadaEditada();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.delete_forever, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('Chamada excluída com sucesso! Todos os dados foram revertidos.')),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Erro ao excluir chamada: $e');
      setState(() {
        _isDeleting = false;
        _mostrarProgresso = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _mostrarProgresso = false;
        });
      }
    }
  }

  Future<void> _salvarEdicao() async {
    setState(() => _isSaving = true);

    try {
      for (var aluno in _alunosEdit) {
        final alunoId = aluno['aluno_id'] as String;
        aluno['observacao'] = _observacaoControllers[alunoId]?.text ?? '';
      }

      final presentes = _alunosEdit.where((a) => a['presente'] == true).length;
      final ausentes = _alunosEdit.where((a) => a['presente'] == false).length;
      final totalAlunos = _alunosEdit.length;
      final porcentagem = totalAlunos > 0 ? ((presentes / totalAlunos) * 100).round() : 0;

      await FirebaseFirestore.instance.collection('chamadas').doc(widget.chamadaId).update({
        'alunos': _alunosEdit,
        'presentes': presentes,
        'ausentes': ausentes,
        'total_alunos': totalAlunos,
        'porcentagem_frequencia': porcentagem,
        'atualizado_em': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        widget.onChamadaEditada();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Chamada atualizada com sucesso!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentes = _alunosEdit.where((a) => a['presente'] == true).length;
    final ausentes = _alunosEdit.where((a) => a['presente'] == false).length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: _mostrarProgresso
          ? FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(position: _slideAnimation, child: _buildProgressScreen()),
      )
          : _buildEditScreen(presentes, ausentes),
    );
  }

  Widget _buildEditScreen(int presentes, int ausentes) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.edit_calendar_rounded, color: Colors.red.shade900, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Editar Chamada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                        const SizedBox(height: 4),
                        Text(widget.turmaNome, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  if (!_isDeleting && !_isSaving)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
                      child: IconButton(
                        icon: Icon(Icons.delete_rounded, color: Colors.red.shade700, size: 22),
                        onPressed: _mostrarPreviewExclusao,
                        tooltip: 'Excluir chamada',
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  if (_isDeleting)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red.shade700)),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSaving || _isDeleting ? null : () => Navigator.pop(context),
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        children: [
                          Text('$presentes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                          Text('Presentes', style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        children: [
                          Text('$ausentes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                          Text('Ausentes', style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _alunosEdit.length,
            itemBuilder: (context, index) {
              final aluno = _alunosEdit[index];
              final alunoId = aluno['aluno_id'] as String;
              final nome = aluno['aluno_nome'] as String;
              final presente = aluno['presente'] as bool;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(shape: BoxShape.circle, color: presente ? Colors.green.shade50 : Colors.red.shade50),
                            child: Checkbox(
                              value: presente,
                              onChanged: _isSaving || _isDeleting
                                  ? null
                                  : (value) {
                                setState(() {
                                  aluno['presente'] = value ?? false;
                                });
                              },
                              shape: const CircleBorder(),
                              activeColor: Colors.green.shade700,
                              checkColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              nome,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: presente ? FontWeight.w600 : FontWeight.normal,
                                color: presente ? Colors.green.shade900 : Colors.grey.shade700,
                                decoration: !presente ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (aluno['observacao'] != null || _observacaoControllers[alunoId]!.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 44),
                          child: TextField(
                            controller: _observacaoControllers[alunoId],
                            enabled: !_isSaving && !_isDeleting,
                            decoration: InputDecoration(
                              hintText: 'Adicionar observação...',
                              prefixIcon: Icon(Icons.note_rounded, size: 16, color: Colors.amber.shade700),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.blue.shade700)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                            maxLines: null,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: (_isSaving || _isDeleting) ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Cancelar', style: TextStyle(fontSize: 15, color: Colors.grey.shade700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_isSaving || _isDeleting) ? null : _salvarEdicao,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Salvar alterações', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressScreen() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.red.shade900, Colors.red.shade700]),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Excluindo Chamada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(widget.turmaNome, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      children: [
                        Icon(Icons.people_rounded, size: 14, color: Colors.white.withOpacity(0.9)),
                        const SizedBox(width: 4),
                        Text('$_alunoIndexAtual/$_totalAlunos', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _alunoIndexAtual / _totalAlunos,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            boxShadow: [BoxShadow(color: Colors.blue.shade100.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Icon(Icons.sync_rounded, color: Colors.blue.shade700, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_operacaoAtual, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    if (_detalheOperacao.isNotEmpty) Text(_detalheOperacao, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    Icon(Icons.data_usage, size: 14, color: Colors.blue.shade700),
                    const SizedBox(width: 4),
                    Text('$_logsExcluidos logs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 🔥 ESTATÍSTICAS CORRIGIDAS - SEM OVERFLOW
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildStatChip(icon: Icons.data_usage, label: 'Logs', value: _logsExcluidos.toString(), color: Colors.purple),
              _buildStatChip(icon: Icons.exposure_minus_1, label: 'Contadores', value: _contadoresDecrementados.toString(), color: Colors.orange),
              _buildStatChip(icon: Icons.history, label: 'Últ. Presença', value: _ultimasPresencasAtualizadas.toString(), color: Colors.green),
              _buildStatChip(icon: Icons.call_received, label: 'Últ. Chamada', value: _ultimasChamadasAtualizadas.toString(), color: Colors.blue),
            ],
          ),
        ),
        if (_alunoAtualProcessando != null)
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.red.shade700, Colors.red.shade500]),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [BoxShadow(color: Colors.red.shade900.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))],
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.person_rounded, size: 60, color: Colors.white),
                            const SizedBox(height: 16),
                            Text(
                              _alunoAtualProcessando!['aluno_nome'],
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                _alunoAtualProcessando!['presente'] == true ? '✅ ESTAVA PRESENTE' : '❌ ESTAVA AUSENTE',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 10, offset: const Offset(0, 5))],
                        ),
                        child: Column(
                          children: [
                            _buildStatusRow(icon: Icons.exposure_minus_1, label: 'Decrementar contador', status: _statusContador, color: _corContador),
                            const Divider(height: 20),
                            _buildStatusRow(icon: Icons.history, label: 'Recalcular última presença', status: _statusUltimaPresenca, color: _corUltimaPresenca),
                            const Divider(height: 20),
                            _buildStatusRow(icon: Icons.data_usage, label: 'Excluir log', status: _statusLog, color: _corLog),
                            const Divider(height: 20),
                            _buildStatusRow(icon: Icons.call_received, label: 'Recalcular última chamada', status: _statusUltimaChamada, color: _corUltimaChamada),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatChip({required IconData icon, required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text('$label: $value', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildStatusRow({required IconData icon, required String label, required String status, required Color color}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Text(status, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ),
      ],
    );
  }
}

// TELA DE DETALHES CHAMADA
class DetalhesChamadaScreen extends StatelessWidget {
  final String chamadaId;
  final Map<String, dynamic> data;
  final String turmaNome;

  const DetalhesChamadaScreen({
    super.key,
    required this.chamadaId,
    required this.data,
    required this.turmaNome,
  });

  String _formatarData(Timestamp timestamp) {
    final date = timestamp.toDate();
    return DateFormat("EEEE, dd 'de' MMMM 'de' yyyy 'às' HH:mm", 'pt_BR').format(date);
  }

  Color _getStatusColor(double percentual) {
    if (percentual >= 0.8) return Colors.green.shade700;
    if (percentual >= 0.6) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final dataChamada = data['data_chamada'] as Timestamp?;
    final presentes = data['presentes'] ?? 0;
    final ausentes = data['ausentes'] ?? 0;
    final totalAlunos = data['total_alunos'] ?? 0;
    final alunos = data['alunos'] as List? ?? [];
    final percentual = totalAlunos > 0 ? (presentes / totalAlunos) : 0;
    final tipoAula = data['tipo_aula']?.toString() ?? 'Não informado';
    final professorNome = data['professor_nome']?.toString() ?? 'Não informado';

    final alunosPresentes = alunos.where((a) => (a['presente'] ?? false)).toList();
    final alunosAusentes = alunos.where((a) => !(a['presente'] ?? false)).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Detalhes da Chamada', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(turmaNome, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: Colors.white)),
          ],
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
        centerTitle: false,
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.red.shade100, blurRadius: 15, offset: const Offset(0, 4))],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Chamada Registrada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                            const SizedBox(height: 4),
                            Text(
                              dataChamada != null ? _formatarData(dataChamada) : 'Data não registrada',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.red.shade200, blurRadius: 10)]),
                        child: Icon(Icons.assignment_turned_in_rounded, size: 28, color: Colors.red.shade900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade100)),
                        child: Row(
                          children: [
                            Icon(Icons.school_rounded, size: 14, color: Colors.blue.shade700),
                            const SizedBox(width: 6),
                            Text(tipoAula, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.purple.shade100)),
                          child: Row(
                            children: [
                              Icon(Icons.person, size: 14, color: Colors.purple.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Prof. $professorNome',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple.shade700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: percentual,
                          strokeWidth: 12,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(percentual)),
                        ),
                      ),
                      Column(
                        children: [
                          Text('${(percentual * 100).toInt()}%', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _getStatusColor(percentual))),
                          Text('Presença', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSimpleStatDetail(value: presentes.toString(), label: 'Presentes', color: Colors.green.shade700, icon: Icons.check_circle_rounded),
                      _buildSimpleStatDetail(value: ausentes.toString(), label: 'Ausentes', color: Colors.red.shade700, icon: Icons.cancel_rounded),
                      _buildSimpleStatDetail(value: totalAlunos.toString(), label: 'Total', color: Colors.blue.shade700, icon: Icons.people_rounded),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Alunos Presentes (${alunosPresentes.length})',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade800),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final aluno = alunosPresentes[index];
                final nome = aluno['aluno_nome']?.toString() ?? 'Sem nome';
                final observacao = aluno['observacao']?.toString() ?? '';
                return _buildAlunoTile(nome: nome, presente: true, observacao: observacao);
              },
              childCount: alunosPresentes.length,
            ),
          ),
          if (alunosAusentes.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Alunos Ausentes (${alunosAusentes.length})',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final aluno = alunosAusentes[index];
                  final nome = aluno['aluno_nome']?.toString() ?? 'Sem nome';
                  final observacao = aluno['observacao']?.toString() ?? '';
                  return _buildAlunoTile(nome: nome, presente: false, observacao: observacao);
                },
                childCount: alunosAusentes.length,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.pop(context),
          backgroundColor: Colors.white,
          foregroundColor: Colors.red.shade900,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Voltar'),
        ),
      ),
    );
  }

  Widget _buildSimpleStatDetail({required String value, required String label, required Color color, required IconData icon}) {
    return SizedBox(
      width: 70,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildAlunoTile({required String nome, required bool presente, required String observacao}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: presente ? Colors.green.shade50 : Colors.red.shade50, shape: BoxShape.circle),
                child: Icon(presente ? Icons.check_rounded : Icons.close_rounded, color: presente ? Colors.green.shade700 : Colors.red.shade700, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade800,
                        decoration: !presente ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (observacao.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.note_rounded, size: 12, color: Colors.amber.shade700),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                observacao,
                                style: TextStyle(fontSize: 11, color: Colors.amber.shade800, fontStyle: FontStyle.italic),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: presente ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  presente ? 'PRESENTE' : 'AUSENTE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: presente ? Colors.green.shade700 : Colors.red.shade700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}