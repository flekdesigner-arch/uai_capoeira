import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:confetti/confetti.dart';

import 'aluno_detalhe_screen.dart';
import 'arte_aniversario_screen.dart';

// =====================================================
// 🎂 ANIVERSARIANTES PAGE — VERSÃO PIKA DAS GALÁXIAS
// =====================================================
// Melhorias:
// - Header premium com resumo do dia, próximos 7 dias e mês atual
// - Busca por nome, apelido e turma
// - Filtros rápidos: Todos, Hoje, Próximos 7 dias, Mês atual
// - Grid dos meses com contador real por mês
// - Cards mais bonitos, claros e rápidos
// - Dialog de aniversário com confetes e ações
// - Permissão antes de abrir perfil
// - Datas mais seguras: Timestamp, DateTime, String ISO ou dd/MM/yyyy

class AniversariantesPage extends StatefulWidget {
  const AniversariantesPage({super.key});

  @override
  State<AniversariantesPage> createState() => _AniversariantesPageState();
}

class _AniversariantesPageState extends State<AniversariantesPage>
    with SingleTickerProviderStateMixin {
  int? _selectedMonth;
  late DateTime _today;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filtroRapido = 'Todos';

  late ConfettiController _confettiController;
  Timer? _confettiTimer;
  bool _mostrarConfetes = false;

  final List<String> _filtrosRapidos = const [
    'Todos',
    'Hoje',
    '7 dias',
    'Mês atual',
  ];

  @override
  void initState() {
    super.initState();
    _today = _normalizarData(DateTime.now());
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _confettiController.dispose();
    _confettiTimer?.cancel();
    super.dispose();
  }

  // =====================================================
  // DATAS
  // =====================================================

  DateTime _normalizarData(DateTime data) {
    return DateTime(data.year, data.month, data.day);
  }

  DateTime? _parseDataNascimento(dynamic value) {
    if (value == null) return null;

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      final texto = value.trim();
      if (texto.isEmpty) return null;

      final iso = DateTime.tryParse(texto);
      if (iso != null) return iso;

      try {
        return DateFormat('dd/MM/yyyy').parseStrict(texto);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  bool _isAniversarioHoje(DateTime dataNascimento) {
    final hoje = _normalizarData(DateTime.now());
    final nascimento = _normalizarData(dataNascimento);

    return nascimento.month == hoje.month && nascimento.day == hoje.day;
  }

  int _calcularIdade(DateTime dataNascimento) {
    final hoje = _normalizarData(DateTime.now());
    final nascimento = _normalizarData(dataNascimento);

    int idade = hoje.year - nascimento.year;

    if (hoje.month < nascimento.month ||
        (hoje.month == nascimento.month && hoje.day < nascimento.day)) {
      idade--;
    }

    return idade < 0 ? 0 : idade;
  }

  int _calcularDiasAteAniversario(DateTime dataNascimento) {
    final hoje = _normalizarData(DateTime.now());

    DateTime proximoAniversario = DateTime(
      hoje.year,
      dataNascimento.month,
      dataNascimento.day,
    );

    if (proximoAniversario.isBefore(hoje)) {
      proximoAniversario = DateTime(
        hoje.year + 1,
        dataNascimento.month,
        dataNascimento.day,
      );
    }

    return proximoAniversario.difference(hoje).inDays;
  }

  String _formatarDataNascimento(DateTime data) {
    return DateFormat('dd/MM/yyyy').format(data);
  }

  String _formatarDiaMes(DateTime data) {
    return DateFormat('dd/MM').format(data);
  }

  String _getMonthName(int month) {
    final date = DateTime(2024, month);
    final name = DateFormat.MMMM('pt_BR').format(date);
    return name.substring(0, 1).toUpperCase() + name.substring(1);
  }

  String _getMonthAbbreviation(int month) {
    final date = DateTime(2024, month);
    final name = DateFormat.MMM('pt_BR').format(date);
    return name.substring(0, 1).toUpperCase() + name.substring(1);
  }

  // =====================================================
  // FIRESTORE
  // =====================================================

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _getAlunosAtivosStream() {
    return FirebaseFirestore.instance
        .collection('alunos')
        .where('status_atividade', whereIn: ['ATIVO(A)', 'ATIVO'])
        .snapshots()
        .map((snapshot) {
      final docs = snapshot.docs.where((doc) {
        final data = doc.data();
        return _parseDataNascimento(data['data_nascimento']) != null;
      }).toList();

      docs.sort((a, b) {
        final aDate = _parseDataNascimento(a.data()['data_nascimento']);
        final bDate = _parseDataNascimento(b.data()['data_nascimento']);

        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;

        final da = _calcularDiasAteAniversario(aDate);
        final db = _calcularDiasAteAniversario(bDate);

        return da.compareTo(db);
      });

      return docs;
    });
  }

  // =====================================================
  // FILTROS
  // =====================================================

  String _normalizarTexto(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');
  }

  bool _matchesSearch(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    if (_searchQuery.trim().isEmpty) return true;

    final data = doc.data();
    final query = _normalizarTexto(_searchQuery);

    final campos = [
      data['nome'],
      data['apelido'],
      data['turma'],
      data['responsavel'],
      data['nome_responsavel'],
    ].whereType<Object>().map((e) => _normalizarTexto(e.toString())).join(' ');

    return campos.contains(query);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _aplicarBusca(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos,
      ) {
    return alunos.where(_matchesSearch).toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterTodayBirthdays(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos,
      ) {
    return alunos.where((doc) {
      final birthDate = _parseDataNascimento(doc.data()['data_nascimento']);
      if (birthDate == null) return false;
      return _isAniversarioHoje(birthDate);
    }).toList()
      ..sort((a, b) {
        final nomeA = a.data()['nome']?.toString() ?? '';
        final nomeB = b.data()['nome']?.toString() ?? '';
        return nomeA.compareTo(nomeB);
      });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterWeekBirthdays(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos,
      ) {
    return alunos.where((doc) {
      final birthDate = _parseDataNascimento(doc.data()['data_nascimento']);
      if (birthDate == null) return false;

      final dias = _calcularDiasAteAniversario(birthDate);
      return dias > 0 && dias <= 7;
    }).toList()
      ..sort((a, b) {
        final dateA = _parseDataNascimento(a.data()['data_nascimento']);
        final dateB = _parseDataNascimento(b.data()['data_nascimento']);
        if (dateA == null || dateB == null) return 0;

        final diasA = _calcularDiasAteAniversario(dateA);
        final diasB = _calcularDiasAteAniversario(dateB);

        return diasA.compareTo(diasB);
      });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterMonthBirthdays(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos,
      int month,
      ) {
    return alunos.where((doc) {
      final birthDate = _parseDataNascimento(doc.data()['data_nascimento']);
      if (birthDate == null) return false;
      return birthDate.month == month;
    }).toList()
      ..sort((a, b) {
        final dateA = _parseDataNascimento(a.data()['data_nascimento']);
        final dateB = _parseDataNascimento(b.data()['data_nascimento']);
        if (dateA == null || dateB == null) return 0;
        return dateA.day.compareTo(dateB.day);
      });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterCurrentMonth(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos,
      ) {
    return _filterMonthBirthdays(alunos, DateTime.now().month);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _getListaFiltroRapido(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos,
      ) {
    switch (_filtroRapido) {
      case 'Hoje':
        return _filterTodayBirthdays(alunos);
      case '7 dias':
        return _filterWeekBirthdays(alunos);
      case 'Mês atual':
        return _filterCurrentMonth(alunos);
      case 'Todos':
      default:
        return alunos;
    }
  }

  Map<int, int> _contarPorMes(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos,
      ) {
    final counts = <int, int>{
      for (int i = 1; i <= 12; i++) i: 0,
    };

    for (final doc in alunos) {
      final birthDate = _parseDataNascimento(doc.data()['data_nascimento']);
      if (birthDate == null) continue;

      counts[birthDate.month] = (counts[birthDate.month] ?? 0) + 1;
    }

    return counts;
  }

  // =====================================================
  // PERMISSÃO
  // =====================================================

  Future<void> _verificarPermissaoEAbrirPerfil(
      BuildContext context,
      String alunoId,
      ) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      _mostrarSnackBar(context, 'Usuário não autenticado', Colors.red);
      return;
    }

    try {
      final permissoesDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(currentUser.uid)
          .collection('permissoes_usuario')
          .doc('configuracoes')
          .get();

      final permissoes = permissoesDoc.data() ?? {};
      final podeVisualizarAlunos =
          permissoes['pode_visualizar_alunos'] == true;

      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(currentUser.uid)
          .get();

      final pesoPermissao = userDoc.data()?['peso_permissao'] as int? ?? 0;
      final isAdmin = pesoPermissao >= 90;

      if (!podeVisualizarAlunos && !isAdmin) {
        _mostrarDialogoSemPermissao(context, 'visualizar alunos');
        return;
      }

      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AlunoDetalheScreen(alunoId: alunoId),
        ),
      );
    } catch (e) {
      _mostrarSnackBar(context, 'Erro ao verificar permissão', Colors.red);
    }
  }

  void _mostrarDialogoSemPermissao(BuildContext context, String acao) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: [
              Icon(Icons.lock_rounded, color: Colors.red.shade900),
              const SizedBox(width: 10),
              const Text(
                'Sem Permissão',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text('Você não tem permissão para $acao.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Entendi',
                style: TextStyle(color: Colors.red.shade900),
              ),
            ),
          ],
        );
      },
    );
  }

  void _mostrarSnackBar(BuildContext context, String mensagem, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // =====================================================
  // CONFETES / ARTE
  // =====================================================

  void _explodirConfetes() {
    setState(() {
      _mostrarConfetes = true;
    });

    _confettiController.play();

    _confettiTimer?.cancel();
    _confettiTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _mostrarConfetes = false;
      });
    });
  }

  void _abrirArteAniversario(
      BuildContext context,
      Map<String, dynamic> aluno,
      String alunoId,
      ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArteAniversarioScreen(
          alunoId: alunoId,
          nomeAluno: aluno['nome'] ?? 'Aluno',
          fotoUrl: aluno['foto_perfil_aluno'],
        ),
      ),
    );
  }

  // =====================================================
  // DIALOG
  // =====================================================

  void _mostrarDialogAniversario(
      BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final aluno = doc.data();
    final alunoId = doc.id;
    final nome = aluno['nome']?.toString() ?? 'Aniversariante';
    final apelido = aluno['apelido']?.toString();
    final fotoUrl = aluno['foto_perfil_aluno'] as String?;
    final birthDate = _parseDataNascimento(aluno['data_nascimento']);
    final idade = birthDate == null ? 0 : _calcularIdade(birthDate);

    _explodirConfetes();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            if (_mostrarConfetes)
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  colors: const [
                    Colors.red,
                    Colors.blue,
                    Colors.green,
                    Colors.yellow,
                    Colors.purple,
                    Colors.orange,
                    Colors.pink,
                  ],
                  numberOfParticles: 45,
                  gravity: 0.18,
                  emissionFrequency: 0.05,
                  minimumSize: const Size(8, 8),
                  maximumSize: const Size(18, 18),
                ),
              ),
            Dialog(
              insetPadding: const EdgeInsets.all(18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.red.shade900,
                            Colors.red.shade700,
                            Colors.deepOrange.shade500,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Text('🎉', style: TextStyle(fontSize: 24)),
                              SizedBox(width: 8),
                              Text(
                                'FELIZ ANIVERSÁRIO!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('🎂', style: TextStyle(fontSize: 24)),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _buildAvatar(
                            fotoUrl: fotoUrl,
                            nome: nome,
                            size: 112,
                            borderColor: Colors.white,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            nome,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (apelido != null && apelido.trim().isNotEmpty)
                            Text(
                              '"$apelido"',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                              ),
                            ),
                            child: Text(
                              '$idade anos hoje',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Text(
                            'Que seja um dia cheio de axé, alegria e boas energias!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDialogButton(
                                  onPressed: () {
                                    Navigator.of(dialogContext).pop();
                                    Future.delayed(Duration.zero, () {
                                      if (context.mounted) {
                                        _verificarPermissaoEAbrirPerfil(
                                          context,
                                          alunoId,
                                        );
                                      }
                                    });
                                  },
                                  icon: Icons.person_rounded,
                                  label: 'PERFIL',
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildDialogButton(
                                  onPressed: () {
                                    Navigator.of(dialogContext).pop();
                                    Future.delayed(Duration.zero, () {
                                      if (context.mounted) {
                                        _abrirArteAniversario(
                                          context,
                                          aluno,
                                          alunoId,
                                        );
                                      }
                                    });
                                  },
                                  icon: Icons.auto_awesome_rounded,
                                  label: 'CRIAR ARTE',
                                  color: Colors.red.shade800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: Text(
                              'FECHAR',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDialogButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.82)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.28),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              children: [
                Icon(icon, color: Colors.white, size: 25),
                const SizedBox(height: 5),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectedMonth != null) {
          setState(() => _selectedMonth = null);
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: _selectedMonth != null
            ? AppBar(
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          title: Text(_getMonthName(_selectedMonth!)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _selectedMonth = null),
          ),
        )
            : null,
        body: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          stream: _getAlunosAtivosStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoading();
            }

            if (snapshot.hasError) {
              return _buildErrorState(snapshot.error.toString());
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _buildEmptyState();
            }

            final alunosOriginais = snapshot.data!;
            final alunosComBusca = _aplicarBusca(alunosOriginais);

            if (_selectedMonth != null) {
              final monthlyBirthdays = _filterMonthBirthdays(
                alunosComBusca,
                _selectedMonth!,
              );
              return _buildMonthView(
                monthlyBirthdays,
                _selectedMonth!,
                alunosOriginais,
              );
            }

            return _buildMainView(alunosOriginais, alunosComBusca);
          },
        ),
      ),
    );
  }

  Widget _buildMainView(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> alunosOriginais,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> alunosFiltradosBusca,
      ) {
    final todayBirthdays = _filterTodayBirthdays(alunosFiltradosBusca);
    final weeklyBirthdays = _filterWeekBirthdays(alunosFiltradosBusca);
    final monthBirthdays = _filterCurrentMonth(alunosFiltradosBusca);
    final listaFiltro = _getListaFiltroRapido(alunosFiltradosBusca);
    final monthCounts = _contarPorMes(alunosFiltradosBusca);

    return RefreshIndicator(
      color: Colors.red.shade900,
      onRefresh: () async {
        setState(() {
          _today = _normalizarData(DateTime.now());
        });
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _buildSliverHeader(
            total: alunosOriginais.length,
            hoje: todayBirthdays.length,
            semana: weeklyBirthdays.length,
            mes: monthBirthdays.length,
          ),
          SliverToBoxAdapter(
            child: _buildSearchAndFilters(),
          ),
          if (_searchQuery.isNotEmpty || _filtroRapido != 'Todos')
            SliverToBoxAdapter(
              child: _buildFilteredListHeader(listaFiltro.length),
            ),
          if (_searchQuery.isNotEmpty || _filtroRapido != 'Todos')
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final doc = listaFiltro[index];
                  final birthDate =
                  _parseDataNascimento(doc.data()['data_nascimento']);
                  if (birthDate == null) return const SizedBox.shrink();

                  return _buildBirthdayCard(
                    doc,
                    birthDate,
                    isHoje: _isAniversarioHoje(birthDate),
                  );
                },
                childCount: listaFiltro.length,
              ),
            )
          else ...[
            if (todayBirthdays.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildBirthdaySection(
                  title: 'Aniversariantes de Hoje',
                  subtitle: 'Aproveite para mandar uma mensagem especial',
                  count: todayBirthdays.length,
                  icon: Icons.celebration_rounded,
                  color: Colors.red.shade800,
                ),
              ),
            if (todayBirthdays.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final doc = todayBirthdays[index];
                    final birthDate =
                    _parseDataNascimento(doc.data()['data_nascimento']);
                    if (birthDate == null) return const SizedBox.shrink();

                    return _buildBirthdayCard(
                      doc,
                      birthDate,
                      isHoje: true,
                    );
                  },
                  childCount: todayBirthdays.length,
                ),
              ),
            if (weeklyBirthdays.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildBirthdaySection(
                  title: 'Próximos 7 dias',
                  subtitle: 'Prepare artes e mensagens com antecedência',
                  count: weeklyBirthdays.length,
                  icon: Icons.upcoming_rounded,
                  color: Colors.orange.shade800,
                ),
              ),
            if (weeklyBirthdays.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final doc = weeklyBirthdays[index];
                    final birthDate =
                    _parseDataNascimento(doc.data()['data_nascimento']);
                    if (birthDate == null) return const SizedBox.shrink();

                    return _buildBirthdayCard(
                      doc,
                      birthDate,
                      isHoje: false,
                    );
                  },
                  childCount: weeklyBirthdays.length,
                ),
              ),
            SliverToBoxAdapter(
              child: _buildMonthGridSection(monthCounts),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  SliverAppBar _buildSliverHeader({
    required int total,
    required int hoje,
    required int semana,
    required int mes,
  }) {
    return SliverAppBar(
      backgroundColor: Colors.red.shade900,
      foregroundColor: Colors.white,
      elevation: 0,
      pinned: true,
      expandedHeight: 235,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        titlePadding: const EdgeInsets.only(left: 16, bottom: 12),
        title: const Text(
          'Aniversariantes',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.red.shade900,
                Colors.red.shade700,
                Colors.deepOrange.shade500,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 54),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.16),
                          ),
                        ),
                        child: const Icon(
                          Icons.cake_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Central de Aniversários',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              DateFormat(
                                "EEEE, dd 'de' MMMM",
                                'pt_BR',
                              ).format(_today),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.84),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: _buildHeaderStat(
                          icon: Icons.celebration_rounded,
                          value: '$hoje',
                          label: 'Hoje',
                          color: Colors.amber.shade300,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildHeaderStat(
                          icon: Icons.calendar_month_rounded,
                          value: '$semana',
                          label: '7 dias',
                          color: Colors.lightBlue.shade200,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildHeaderStat(
                          icon: Icons.groups_rounded,
                          value: '$mes',
                          label: 'Mês',
                          color: Colors.greenAccent.shade100,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildHeaderStat(
                          icon: Icons.people_alt_rounded,
                          value: '$total',
                          label: 'Ativos',
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderStat({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Buscar aluno, apelido ou turma...',
              prefixIcon: Icon(Icons.search_rounded, color: Colors.red.shade900),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                },
                icon: const Icon(Icons.close_rounded),
              ),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filtrosRapidos.map((filtro) {
                final ativo = _filtroRapido == filtro;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: ativo,
                    label: Text(filtro),
                    selectedColor: Colors.red.shade900,
                    backgroundColor: Colors.grey.shade100,
                    labelStyle: TextStyle(
                      color: ativo ? Colors.white : Colors.grey.shade800,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _filtroRapido = filtro;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredListHeader(int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_alt_rounded, color: Colors.red.shade900),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count resultado${count == 1 ? '' : 's'} encontrado${count == 1 ? '' : 's'}',
              style: TextStyle(
                color: Colors.red.shade900,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty || _filtroRapido != 'Todos')
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _filtroRapido = 'Todos';
                });
              },
              child: const Text('Limpar'),
            ),
        ],
      ),
    );
  }

  Widget _buildBirthdaySection({
    required String title,
    required String subtitle,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.20)),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBirthdayCard(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      DateTime birthDate, {
        bool isMonthView = false,
        bool isHoje = false,
      }) {
    final aluno = doc.data();
    final alunoId = doc.id;
    final nome = aluno['nome']?.toString() ?? 'Nome não informado';
    final apelido = aluno['apelido']?.toString();
    final turma = aluno['turma']?.toString();
    final fotoUrl = aluno['foto_perfil_aluno'] as String?;
    final idadeAtual = _calcularIdade(birthDate);
    final idadeQueVaiFazer = _isAniversarioHoje(birthDate)
        ? idadeAtual
        : idadeAtual + (_calcularDiasAteAniversario(birthDate) > 0 ? 1 : 0);
    final dias = _calcularDiasAteAniversario(birthDate);

    final Color destaque = isHoje
        ? Colors.red.shade900
        : dias <= 7
        ? Colors.orange.shade800
        : Colors.grey.shade800;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: isHoje
            ? LinearGradient(
          colors: [
            Colors.red.shade50,
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
            : null,
        color: isHoje ? null : Colors.white,
        border: Border.all(
          color: isHoje ? Colors.red.shade300 : Colors.grey.shade200,
          width: isHoje ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isHoje
                ? Colors.red.shade900.withOpacity(0.13)
                : Colors.black.withOpacity(0.045),
            blurRadius: isHoje ? 14 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            if (isHoje) {
              _mostrarDialogAniversario(context, doc);
            } else {
              _verificarPermissaoEAbrirPerfil(context, alunoId);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _buildAvatar(
                      fotoUrl: fotoUrl,
                      nome: nome,
                      size: 62,
                      borderColor:
                      isHoje ? Colors.red.shade700 : Colors.grey.shade300,
                    ),
                    if (isHoje)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.red.shade800,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.cake_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.5,
                          color: destaque,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (apelido != null && apelido.trim().isNotEmpty)
                        Text(
                          '"$apelido"',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: [
                          _buildSmallChip(
                            icon: Icons.calendar_today_rounded,
                            text: _formatarDiaMes(birthDate),
                            color: Colors.blue.shade700,
                          ),
                          _buildSmallChip(
                            icon: Icons.cake_rounded,
                            text: isHoje
                                ? '$idadeAtual anos'
                                : 'fará $idadeQueVaiFazer',
                            color: Colors.purple.shade700,
                          ),
                          if (turma != null && turma.trim().isNotEmpty)
                            _buildSmallChip(
                              icon: Icons.groups_rounded,
                              text: turma,
                              color: Colors.green.shade700,
                            ),
                          if (!isHoje)
                            _buildSmallChip(
                              icon: Icons.hourglass_bottom_rounded,
                              text: dias == 0
                                  ? 'Hoje'
                                  : 'faltam $dias dia${dias == 1 ? '' : 's'}',
                              color: Colors.orange.shade800,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isHoje)
                  Column(
                    children: [
                      IconButton(
                        tooltip: 'Criar arte',
                        onPressed: () => _abrirArteAniversario(
                          context,
                          aluno,
                          alunoId,
                        ),
                        icon: Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.red.shade900,
                        ),
                      ),
                      Text(
                        'Arte',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey.shade400,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar({
    required String? fotoUrl,
    required String nome,
    required double size,
    required Color borderColor,
  }) {
    final inicial = nome.trim().isEmpty ? '?' : nome.trim()[0].toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2.4),
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.22),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: fotoUrl != null && fotoUrl.isNotEmpty
            ? CachedNetworkImage(
          imageUrl: fotoUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: Colors.grey.shade100,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.red.shade900,
              ),
            ),
          ),
          errorWidget: (context, url, error) => _avatarFallback(inicial),
        )
            : _avatarFallback(inicial),
      ),
    );
  }

  Widget _avatarFallback(String inicial) {
    return Container(
      color: Colors.grey.shade100,
      child: Center(
        child: Text(
          inicial,
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade500,
          ),
        ),
      ),
    );
  }

  // =====================================================
  // MONTH VIEW
  // =====================================================

  Widget _buildMonthView(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> monthlyBirthdays,
      int month,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> allAlunos,
      ) {
    final nomeMes = _getMonthName(month);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.red.shade900,
                Colors.red.shade700,
                Colors.deepOrange.shade500,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red.shade900.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.white,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nomeMes,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${monthlyBirthdays.length} aniversariante${monthlyBirthdays.length == 1 ? '' : 's'} encontrado${monthlyBirthdays.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.82),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.16)),
                  ),
                  child: Text(
                    '${monthlyBirthdays.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: monthlyBirthdays.isEmpty
              ? _buildEmptyMonthState(month)
              : RefreshIndicator(
            color: Colors.red.shade900,
            onRefresh: () async => setState(() {}),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
              itemCount: monthlyBirthdays.length,
              itemBuilder: (context, index) {
                final doc = monthlyBirthdays[index];
                final birthDate =
                _parseDataNascimento(doc.data()['data_nascimento']);
                if (birthDate == null) return const SizedBox.shrink();

                return _buildBirthdayCard(
                  doc,
                  birthDate,
                  isMonthView: true,
                  isHoje: _isAniversarioHoje(birthDate),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthGridSection(Map<int, int> monthCounts) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_view_month_rounded,
                  color: Colors.red.shade900),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Buscar por mês',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '12 meses',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.22,
            ),
            itemCount: 12,
            itemBuilder: (context, index) {
              final month = index + 1;
              return _buildMonthCard(month, monthCounts[month] ?? 0);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthCard(int month, int count) {
    final isCurrentMonth = month == DateTime.now().month;
    final hasBirthdays = count > 0;

    final colors = isCurrentMonth
        ? [Colors.red.shade900, Colors.red.shade700]
        : hasBirthdays
        ? [Colors.deepOrange.shade600, Colors.orange.shade500]
        : [Colors.grey.shade200, Colors.grey.shade100];

    return Material(
      borderRadius: BorderRadius.circular(15),
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedMonth = month),
        borderRadius: BorderRadius.circular(15),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isCurrentMonth
                  ? Colors.red.shade200
                  : Colors.grey.shade200,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _getMonthAbbreviation(month).toUpperCase(),
                      style: TextStyle(
                        color: hasBirthdays || isCurrentMonth
                            ? Colors.white
                            : Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      month.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: hasBirthdays || isCurrentMonth
                            ? Colors.white70
                            : Colors.grey.shade500,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 7,
                top: 7,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: hasBirthdays || isCurrentMonth
                        ? Colors.white.withOpacity(0.22)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: hasBirthdays || isCurrentMonth
                          ? Colors.white
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // EMPTY / LOADING / ERROR
  // =====================================================

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: Colors.red.shade900,
            strokeWidth: 2.5,
          ),
          const SizedBox(height: 16),
          Text(
            'Carregando aniversariantes...',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 70, color: Colors.red.shade300),
            const SizedBox(height: 14),
            const Text(
              'Erro ao carregar aniversariantes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.red.shade900, Colors.red.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const SafeArea(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cake_rounded, color: Colors.white, size: 30),
                  SizedBox(width: 10),
                  Text(
                    'Aniversariantes',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.celebration_outlined,
                    size: 86,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Nenhum aniversariante encontrado',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Não há alunos ativos com data de nascimento cadastrada.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyMonthState(int month) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cake_outlined, size: 82, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Nenhum aniversariante em ${_getMonthName(month)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tente buscar outro mês ou conferir os cadastros dos alunos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: () => setState(() => _selectedMonth = null),
              icon: Icon(Icons.arrow_back, color: Colors.red.shade900),
              label: Text(
                'Voltar',
                style: TextStyle(
                  color: Colors.red.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}