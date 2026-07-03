import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
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
  AniversariantesPage({super.key});

  @override
  State<AniversariantesPage> createState() => _AniversariantesPageState();
}

class _AniversariantesPageState extends State<AniversariantesPage>
    with SingleTickerProviderStateMixin {
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _onPrimary() {
    final t = context.uai;
    final themeIsDark =
        t.background.computeLuminance() < 0.45 ||
            t.surface.computeLuminance() < 0.45 ||
            t.card.computeLuminance() < 0.45;

    // Em temas escuros com primary muito claro/neon, o contraste matemático
    // tende a escolher texto preto, mas visualmente o header fica pesado.
    // Para cards hero/gradiente nesses temas, branco mantém melhor leitura.
    if (themeIsDark && t.primary.computeLuminance() > 0.45) {
      return const Color(0xFFFFFFFF);
    }

    return _readableOn(t.primary);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onCard() => _readableOn(context.uai.card);
  Color _onCardMuted() => _onCard().withOpacity(0.68);

  bool get _isWideDashboard {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 900;
  }

  bool get _isDesktopDashboard {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 1180;
  }

  double get _dashboardMaxWidth {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1600) return 1320;
    if (width >= 1180) return 1180;
    if (width >= 900) return 1040;
    return width;
  }

  EdgeInsets get _dashboardPagePadding {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1180) return const EdgeInsets.fromLTRB(22, 18, 22, 28);
    if (width >= 900) return const EdgeInsets.fromLTRB(18, 16, 18, 24);
    return const EdgeInsets.fromLTRB(16, 14, 16, 22);
  }

  Widget _dashboardWidthLimiter(Widget child) {
    if (!_isWideDashboard) return child;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _dashboardMaxWidth),
        child: child,
      ),
    );
  }

  int _dashboardColumns(
      double width, {
        double minItemWidth = 360,
        int maxColumns = 4,
      }) {
    if (width <= 0) return 1;
    return (width / minItemWidth).floor().clamp(1, maxColumns).toInt();
  }

  Widget _dashboardResponsiveWrap({
    required List<Widget> children,
    double minItemWidth = 360,
    int maxColumns = 4,
    double spacing = 12,
    double runSpacing = 12,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(children.length, (index) {
              final isLast = index == children.length - 1;
              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : runSpacing),
                child: SizedBox(width: double.infinity, child: children[index]),
              );
            }),
          );
        }

        final columns = _dashboardColumns(
          width,
          minItemWidth: minItemWidth,
          maxColumns: maxColumns,
        );
        final itemWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }


  Widget _headerStatsResponsiveWrap({
    required List<Widget> children,
    double spacing = 8,
    double runSpacing = 8,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 720 ? 4 : 2;
        final itemWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }

  int? _selectedMonth;
  late DateTime _today;

  String _searchQuery = '';
  String _filtroRapido = 'Todos';

  final TextEditingController _searchController = TextEditingController();

  late ConfettiController _confettiController;
  Timer? _confettiTimer;
  bool _mostrarConfetes = false;

  final List<String> _filtrosRapidos = ['Todos', 'Hoje', '7 dias', 'Mês atual'];

  @override
  void initState() {
    super.initState();
    _today = _normalizarData(DateTime.now());
    _confettiController = ConfettiController(duration: Duration(seconds: 3));
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
    }).toList()..sort((a, b) {
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
    }).toList()..sort((a, b) {
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
    }).toList()..sort((a, b) {
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
    final counts = <int, int>{for (int i = 1; i <= 12; i++) i: 0};

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
      _mostrarSnackBar(context, 'Usuário não autenticado', context.uai.error);
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
      final podeVisualizarAlunos = permissoes['pode_visualizar_alunos'] == true;

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
      _mostrarSnackBar(
        context,
        'Erro ao verificar permissão',
        context.uai.error,
      );
    }
  }

  void _mostrarDialogoSemPermissao(BuildContext context, String acao) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: context.uai.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: [
              Icon(Icons.lock_rounded, color: context.uai.primary),
              SizedBox(width: 10),
              Text(
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
                style: TextStyle(color: context.uai.primary),
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
    _confettiTimer = Timer(Duration(seconds: 3), () {
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
                  colors: [
                    context.uai.error,
                    context.uai.info,
                    context.uai.success,
                    context.uai.warning,
                    context.uai.associacao,
                    context.uai.warning,
                    context.uai.error,
                  ],
                  numberOfParticles: 45,
                  gravity: 0.18,
                  emissionFrequency: 0.05,
                  minimumSize: Size(8, 8),
                  maximumSize: Size(18, 18),
                ),
              ),
            Dialog(
              backgroundColor: context.uai.surface,
              insetPadding: EdgeInsets.all(18),
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
                      padding: EdgeInsets.fromLTRB(20, 24, 20, 22),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            context.uai.primary,
                            context.uai.primaryDark,
                            context.uai.warning.withOpacity(0.10),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('🎉', style: TextStyle(fontSize: 24)),
                              SizedBox(width: 8),
                              Text(
                                'FELIZ ANIVERSÁRIO!',
                                style: TextStyle(
                                  color: _onPrimary(),
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('🎂', style: TextStyle(fontSize: 24)),
                            ],
                          ),
                          SizedBox(height: 18),
                          _buildAvatar(
                            fotoUrl: fotoUrl,
                            nome: nome,
                            size: 112,
                            borderColor: context.uai.card,
                          ),
                          SizedBox(height: 14),
                          Text(
                            nome,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _onPrimary(),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (apelido != null && apelido.trim().isNotEmpty)
                            Text(
                              '"$apelido"',
                              style: TextStyle(
                                color: _onPrimary().withOpacity(0.72),
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          SizedBox(height: 10),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _onPrimary().withOpacity(0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _onPrimary().withOpacity(0.20),
                              ),
                            ),
                            child: Text(
                              '$idade anos hoje',
                              style: TextStyle(
                                color: _onPrimary(),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Text(
                            'Que seja um dia cheio de axé, alegria e boas energias!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: context.uai.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 18),
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
                                  color: context.uai.info,
                                ),
                              ),
                              SizedBox(width: 10),
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
                                  color: context.uai.primaryDark,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: Text(
                              'FECHAR',
                              style: TextStyle(
                                color: context.uai.textSecondary,
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
    final fg = _readableOn(color);

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
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              children: [
                Icon(icon, color: fg, size: 25),
                SizedBox(height: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
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
        backgroundColor: context.uai.background,
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
      color: context.uai.primary,
      onRefresh: () async {
        setState(() {
          _today = _normalizarData(DateTime.now());
        });
      },
      child: CustomScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        slivers: [
          _buildSliverHeader(
            total: alunosOriginais.length,
            hoje: todayBirthdays.length,
            semana: weeklyBirthdays.length,
            mes: monthBirthdays.length,
          ),
          SliverToBoxAdapter(child: _buildFiltersOnly()),
          if (_filtroRapido != 'Todos') ...[
            SliverToBoxAdapter(
              child: _buildFilteredListHeader(listaFiltro.length),
            ),
            if (listaFiltro.isEmpty)
              SliverToBoxAdapter(
                child: _buildNoResultsState(),
              )
            else
              SliverToBoxAdapter(
                child: _buildBirthdayCardsResponsive(listaFiltro),
              ),
          ] else ...[
            if (todayBirthdays.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildBirthdaySection(
                  title: 'Aniversariantes de Hoje',
                  subtitle: 'Aproveite para mandar uma mensagem especial',
                  count: todayBirthdays.length,
                  icon: Icons.celebration_rounded,
                  color: context.uai.primary,
                ),
              ),
            if (todayBirthdays.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildBirthdayCardsResponsive(
                  todayBirthdays,
                  isHojeForcado: true,
                ),
              ),
            if (weeklyBirthdays.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildBirthdaySection(
                  title: 'Próximos 7 dias',
                  subtitle: 'Prepare artes e mensagens com antecedência',
                  count: weeklyBirthdays.length,
                  icon: Icons.upcoming_rounded,
                  color: context.uai.warning,
                ),
              ),
            if (weeklyBirthdays.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildBirthdayCardsResponsive(weeklyBirthdays),
              ),
            SliverToBoxAdapter(child: _buildMonthGridSection(monthCounts)),
          ],
          SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  Widget _buildSliverHeader({
    required int total,
    required int hoje,
    required int semana,
    required int mes,
  }) {
    final t = context.uai;
    final onPrimary = _onPrimary();
    final pad = _dashboardPagePadding;

    return SliverToBoxAdapter(
      child: Container(
        color: t.background,
        padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 12),
        child: _dashboardWidthLimiter(
          Container(
            padding: EdgeInsets.all(_isDesktopDashboard ? 20 : 15),
            decoration: BoxDecoration(
              gradient: t.primaryGradient,
              borderRadius: BorderRadius.circular(t.cardRadius + 6),
              border: Border.all(color: onPrimary.withOpacity(0.13)),
              boxShadow: t.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: onPrimary.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: onPrimary.withOpacity(0.12)),
                      ),
                      child: Icon(
                        Icons.cake_rounded,
                        color: onPrimary,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Central de Aniversários',
                            style: TextStyle(
                              color: onPrimary,
                              fontSize: _isDesktopDashboard ? 22 : 18.5,
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            DateFormat(
                              "EEEE, dd 'de' MMMM",
                              'pt_BR',
                            ).format(_today),
                            style: TextStyle(
                              color: onPrimary.withOpacity(0.82),
                              fontSize: _isDesktopDashboard ? 13 : 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (_isWideDashboard)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: onPrimary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: onPrimary.withOpacity(0.14)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: context.uai.warning,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Aniversários ativos',
                              style: TextStyle(
                                color: onPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _headerStatsResponsiveWrap(
                  children: [
                    _buildHeaderStat(
                      icon: Icons.celebration_rounded,
                      value: '$hoje',
                      label: 'Hoje',
                    ),
                    _buildHeaderStat(
                      icon: Icons.calendar_month_rounded,
                      value: '$semana',
                      label: '7 dias',
                    ),
                    _buildHeaderStat(
                      icon: Icons.groups_rounded,
                      value: '$mes',
                      label: 'Mês',
                    ),
                    _buildHeaderStat(
                      icon: Icons.people_alt_rounded,
                      value: '$total',
                      label: 'Ativos',
                    ),
                  ],
                ),
              ],
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
    Color? color,
  }) {
    final onPrimary = _onPrimary();
    final iconColor = color ?? onPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: onPrimary.withOpacity(0.13)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor.withOpacity(0.92), size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: onPrimary,
              fontSize: 18,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: onPrimary.withOpacity(0.78),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersOnly() {
    final t = context.uai;
    final pad = _dashboardPagePadding;

    return Container(
      color: t.background,
      padding: EdgeInsets.fromLTRB(pad.left, 2, pad.right, 10),
      child: _dashboardWidthLimiter(
        Container(
          padding: EdgeInsets.all(_isDesktopDashboard ? 14 : 12),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                style: TextStyle(
                  color: _onCard(),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                cursorColor: t.primary,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar por nome, apelido, turma ou responsável...',
                  hintStyle: TextStyle(
                    color: _onCardMuted(),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: _ensureVisible(t.primary, t.card),
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.trim().isEmpty
                      ? null
                      : IconButton(
                    tooltip: 'Limpar busca',
                    onPressed: () {
                      setState(() {
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      color: t.textMuted,
                      size: 18,
                    ),
                  ),
                  filled: true,
                  fillColor: t.cardAlt,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: t.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: t.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: t.primary.withOpacity(0.55)),
                  ),
                ),
              ),
              SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: BouncingScrollPhysics(),
                child: Row(
                  children: _filtrosRapidos.map((filtro) {
                    final ativo = _filtroRapido == filtro;
                    final accent = filtro == 'Hoje'
                        ? t.primary
                        : filtro == '7 dias'
                        ? t.warning
                        : filtro == 'Mês atual'
                        ? t.info
                        : t.associacao;
                    final visibleAccent = _ensureVisible(accent, t.card);
                    final bg = ativo
                        ? visibleAccent
                        : Color.alphaBlend(
                      visibleAccent.withOpacity(0.08),
                      t.cardAlt,
                    );
                    final fg = ativo ? _readableOn(visibleAccent) : visibleAccent;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: ativo,
                        showCheckmark: true,
                        checkmarkColor: fg,
                        label: Text(filtro),
                        selectedColor: bg,
                        backgroundColor: bg,
                        side: BorderSide(
                          color: ativo
                              ? visibleAccent.withOpacity(0.38)
                              : t.border,
                        ),
                        labelStyle: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w900,
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
        ),
      ),
    );
  }

  Widget _buildFilteredListHeader(int count) {
    final t = context.uai;
    final accent = _ensureVisible(t.info, t.card);
    final pad = _dashboardPagePadding;

    return Container(
      color: t.background,
      padding: EdgeInsets.fromLTRB(pad.left, 12, pad.right, 6),
      child: _dashboardWidthLimiter(
        Container(
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Color.alphaBlend(accent.withOpacity(0.10), t.card),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withOpacity(0.16)),
          ),
          child: Row(
            children: [
              Icon(Icons.filter_alt_rounded, color: accent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$count resultado${count == 1 ? '' : 's'} encontrado${count == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: _onCard(),
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _searchController.clear();
                    _filtroRapido = 'Todos';
                  });
                },
                child: Text(
                  'Limpar',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
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
    final t = context.uai;
    final visibleColor = _ensureVisible(color, t.card);
    final pad = _dashboardPagePadding;

    return Container(
      color: t.background,
      padding: EdgeInsets.fromLTRB(pad.left, 14, pad.right, 8),
      child: _dashboardWidthLimiter(
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: visibleColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: visibleColor.withOpacity(0.28)),
                ),
                child: Icon(icon, color: visibleColor, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: _onCard(),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: _onCardMuted(),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: visibleColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: visibleColor.withOpacity(0.32)),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: visibleColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBirthdayCardsResponsive(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos, {
        bool isHojeForcado = false,
        bool isMonthView = false,
      }) {
    final cards = <Widget>[];

    for (final doc in alunos) {
      final birthDate = _parseDataNascimento(doc.data()['data_nascimento']);
      if (birthDate == null) continue;
      cards.add(
        _buildBirthdayCard(
          doc,
          birthDate,
          isMonthView: isMonthView,
          isHoje: isHojeForcado || _isAniversarioHoje(birthDate),
          compactMargin: true,
        ),
      );
    }

    final pad = _dashboardPagePadding;

    return Container(
      color: context.uai.background,
      padding: EdgeInsets.fromLTRB(pad.left, 6, pad.right, 8),
      child: _dashboardWidthLimiter(
        _dashboardResponsiveWrap(
          children: cards,
          minItemWidth: 370,
          maxColumns: _isDesktopDashboard ? 3 : 2,
          spacing: 12,
          runSpacing: 12,
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    final t = context.uai;
    final pad = _dashboardPagePadding;

    return Container(
      color: t.background,
      padding: EdgeInsets.fromLTRB(pad.left, 12, pad.right, 22),
      child: _dashboardWidthLimiter(
        Container(
          padding: EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 54,
                color: t.textMuted,
              ),
              SizedBox(height: 12),
              Text(
                'Nenhum resultado encontrado',
                style: TextStyle(
                  color: _onCard(),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 6),
              Text(
                'Ajuste a busca ou escolha outro filtro de aniversário.',
                style: TextStyle(
                  color: _onCardMuted(),
                  fontSize: 13,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBirthdayCard(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      DateTime birthDate, {
        bool isMonthView = false,
        bool isHoje = false,
        bool compactMargin = false,
      }) {
    final t = context.uai;
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

    final Color accent = isHoje
        ? t.primary
        : dias <= 7
        ? t.warning
        : t.info;

    final Color visibleAccent = _ensureVisible(accent, t.card);
    final Color cardBg = isHoje
        ? Color.alphaBlend(visibleAccent.withOpacity(0.15), t.card)
        : t.card;
    final Color borderColor = isHoje
        ? visibleAccent.withOpacity(0.72)
        : t.border;

    return Container(
      margin: compactMargin
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: borderColor, width: isHoje ? 1.45 : 1),
        boxShadow: isHoje ? t.cardShadow : t.softShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(t.cardRadius),
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
                      size: _isDesktopDashboard ? 66 : 62,
                      borderColor: isHoje ? visibleAccent : t.border,
                    ),
                    if (isHoje)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: visibleAccent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _readableOn(visibleAccent).withOpacity(0.95),
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.cake_rounded,
                            color: _readableOn(visibleAccent),
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
                          fontWeight: FontWeight.w900,
                          fontSize: 15.5,
                          color: _readableOn(cardBg),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (apelido != null && apelido.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            '"$apelido"',
                            style: TextStyle(
                              color: _readableOn(cardBg).withOpacity(0.68),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: [
                          _buildSmallChip(
                            icon: Icons.calendar_today_rounded,
                            text: _formatarDiaMes(birthDate),
                            color: t.info,
                          ),
                          _buildSmallChip(
                            icon: Icons.cake_rounded,
                            text: isHoje
                                ? '$idadeAtual anos'
                                : 'fará $idadeQueVaiFazer',
                            color: t.associacao,
                          ),
                          if (turma != null && turma.trim().isNotEmpty)
                            _buildSmallChip(
                              icon: Icons.groups_rounded,
                              text: turma,
                              color: t.success,
                            ),
                          if (!isHoje)
                            _buildSmallChip(
                              icon: Icons.hourglass_bottom_rounded,
                              text: dias == 0
                                  ? 'Hoje'
                                  : 'faltam $dias dia${dias == 1 ? '' : 's'}',
                              color: t.warning,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isHoje)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Criar arte',
                        onPressed: () =>
                            _abrirArteAniversario(context, aluno, alunoId),
                        icon: Icon(
                          Icons.auto_awesome_rounded,
                          color: visibleAccent,
                        ),
                      ),
                      Text(
                        'Arte',
                        style: TextStyle(
                          fontSize: 10,
                          color: visibleAccent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: t.textMuted),
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
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: accent),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              color: _readableOn(t.cardAlt),
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: fotoUrl != null && fotoUrl.isNotEmpty
            ? CachedNetworkImage(
          imageUrl: fotoUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: context.uai.cardAlt,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.uai.primary,
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
      color: context.uai.cardAlt,
      child: Center(
        child: Text(
          inicial,
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold,
            color: _readableOn(context.uai.cardAlt).withOpacity(0.72),
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
    final t = context.uai;
    final onPrimary = _onPrimary();
    final pad = _dashboardPagePadding;

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: t.background,
          padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 10),
          child: SafeArea(
            bottom: false,
            child: _dashboardWidthLimiter(
              Container(
                padding: EdgeInsets.all(_isDesktopDashboard ? 18 : 14),
                decoration: BoxDecoration(
                  gradient: t.primaryGradient,
                  borderRadius: BorderRadius.circular(t.cardRadius + 6),
                  border: Border.all(color: onPrimary.withOpacity(0.14)),
                  boxShadow: t.cardShadow,
                ),
                child: Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() => _selectedMonth = null),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: onPrimary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: onPrimary.withOpacity(0.14),
                            ),
                          ),
                          child: Icon(
                            Icons.arrow_back_rounded,
                            color: onPrimary,
                            size: 25,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nomeMes,
                            style: TextStyle(
                              color: onPrimary,
                              fontSize: _isDesktopDashboard ? 24 : 22,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${monthlyBirthdays.length} aniversariante${monthlyBirthdays.length == 1 ? '' : 's'} encontrado${monthlyBirthdays.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: onPrimary.withOpacity(0.82),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: onPrimary.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: onPrimary.withOpacity(0.16)),
                      ),
                      child: Text(
                        '${monthlyBirthdays.length}',
                        style: TextStyle(
                          color: onPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: monthlyBirthdays.isEmpty
              ? _buildEmptyMonthState(month)
              : RefreshIndicator(
            color: t.primary,
            onRefresh: () async => setState(() {}),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 720) {
                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                      pad.left,
                      12,
                      pad.right,
                      24,
                    ),
                    gridDelegate:
                    SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: _isDesktopDashboard ? 430 : 390,
                      mainAxisExtent: 118,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: monthlyBirthdays.length,
                    itemBuilder: (context, index) {
                      final doc = monthlyBirthdays[index];
                      final birthDate = _parseDataNascimento(
                        doc.data()['data_nascimento'],
                      );
                      if (birthDate == null) return SizedBox.shrink();

                      return _buildBirthdayCard(
                        doc,
                        birthDate,
                        isMonthView: true,
                        isHoje: _isAniversarioHoje(birthDate),
                        compactMargin: true,
                      );
                    },
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(0, 12, 0, 24),
                  itemCount: monthlyBirthdays.length,
                  itemBuilder: (context, index) {
                    final doc = monthlyBirthdays[index];
                    final birthDate = _parseDataNascimento(
                      doc.data()['data_nascimento'],
                    );
                    if (birthDate == null) return SizedBox.shrink();

                    return _buildBirthdayCard(
                      doc,
                      birthDate,
                      isMonthView: true,
                      isHoje: _isAniversarioHoje(birthDate),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthGridSection(Map<int, int> monthCounts) {
    final t = context.uai;
    final pad = _dashboardPagePadding;

    return Container(
      color: t.background,
      padding: EdgeInsets.fromLTRB(pad.left, 24, pad.right, 24),
      child: _dashboardWidthLimiter(
        Container(
          padding: EdgeInsets.all(_isDesktopDashboard ? 16 : 14),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: t.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.primary.withOpacity(0.14)),
                    ),
                    child: Icon(
                      Icons.calendar_view_month_rounded,
                      color: _ensureVisible(t.primary, t.card),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Buscar por mês',
                      style: TextStyle(
                        color: _onCard(),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '12 meses',
                    style: TextStyle(
                      color: _onCardMuted(),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;

                  final columns = width >= 1120
                      ? 6
                      : width >= 780
                      ? 4
                      : width >= 420
                      ? 3
                      : 2;

                  final itemHeight = width >= 1120
                      ? 106.0
                      : width >= 780
                      ? 98.0
                      : width >= 420
                      ? 88.0
                      : 82.0;

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      mainAxisExtent: itemHeight,
                    ),
                    itemCount: 12,
                    itemBuilder: (context, index) {
                      final month = index + 1;
                      return _buildMonthCard(month, monthCounts[month] ?? 0);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthCard(int month, int count) {
    final t = context.uai;
    final isCurrentMonth = month == DateTime.now().month;
    final hasBirthdays = count > 0;
    final compact = MediaQuery.sizeOf(context).width < 620;
    final radius = compact ? 14.0 : 15.0;

    final accent = _ensureVisible(
      isCurrentMonth
          ? t.primary
          : hasBirthdays
          ? t.warning
          : t.textMuted,
      t.cardAlt,
    );

    final bg = isCurrentMonth || hasBirthdays
        ? Color.alphaBlend(accent.withOpacity(0.12), t.cardAlt)
        : t.cardAlt;
    final onBg = _readableOn(bg);

    return Material(
      borderRadius: BorderRadius.circular(radius),
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedMonth = month),
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isCurrentMonth || hasBirthdays
                  ? accent.withOpacity(0.28)
                  : t.border,
            ),
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getMonthAbbreviation(month).replaceAll('.', '').toUpperCase(),
                      style: TextStyle(
                        color: hasBirthdays || isCurrentMonth
                            ? accent
                            : onBg.withOpacity(0.70),
                        fontWeight: FontWeight.w900,
                        fontSize: compact ? 13 : 15,
                        height: 1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: compact ? 4 : 5),
                    Text(
                      month.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: onBg.withOpacity(0.62),
                        fontSize: compact ? 11 : 12,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: compact ? 0 : 1,
                top: compact ? 0 : 1,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 6 : 7,
                    vertical: compact ? 2.5 : 3,
                  ),
                  decoration: BoxDecoration(
                    color: hasBirthdays || isCurrentMonth
                        ? accent.withOpacity(0.16)
                        : t.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasBirthdays || isCurrentMonth
                          ? accent.withOpacity(0.22)
                          : t.border,
                    ),
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 10 : 11,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: hasBirthdays || isCurrentMonth
                          ? accent
                          : t.textSecondary,
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

  Widget _buildStateCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    Widget? action,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      color: t.background,
      padding: _dashboardPagePadding,
      child: Center(
        child: _dashboardWidthLimiter(
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(_isDesktopDashboard ? 30 : 24),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(t.cardRadius + 4),
              border: Border.all(color: t.border),
              boxShadow: t.softShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withOpacity(0.18)),
                  ),
                  child: Icon(icon, size: 38, color: accent),
                ),
                SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _onCard(),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: _onCardMuted(),
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (action != null) ...[
                  SizedBox(height: 18),
                  action,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    final t = context.uai;

    return Container(
      color: t.background,
      padding: _dashboardPagePadding,
      child: Center(
        child: _dashboardWidthLimiter(
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(_isDesktopDashboard ? 30 : 24),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(t.cardRadius + 4),
              border: Border.all(color: t.border),
              boxShadow: t.softShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(
                    color: t.primary,
                    strokeWidth: 3,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Carregando aniversariantes...',
                  style: TextStyle(
                    color: _onCardMuted(),
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return _buildStateCard(
      icon: Icons.error_outline_rounded,
      title: 'Erro ao carregar aniversariantes',
      subtitle: error,
      color: context.uai.error,
    );
  }

  Widget _buildEmptyState() {
    final t = context.uai;
    final onPrimary = _onPrimary();

    return Column(
      children: [
        Container(
          color: t.background,
          padding: _dashboardPagePadding,
          child: _dashboardWidthLimiter(
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(_isDesktopDashboard ? 20 : 16),
              decoration: BoxDecoration(
                gradient: t.primaryGradient,
                borderRadius: BorderRadius.circular(t.cardRadius + 6),
                boxShadow: t.cardShadow,
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cake_rounded, color: onPrimary, size: 30),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Aniversariantes',
                        style: TextStyle(
                          color: onPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _buildStateCard(
            icon: Icons.celebration_outlined,
            title: 'Nenhum aniversariante encontrado',
            subtitle:
            'Não há alunos ativos com data de nascimento cadastrada.',
            color: t.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyMonthState(int month) {
    return _buildStateCard(
      icon: Icons.cake_outlined,
      title: 'Nenhum aniversariante em ${_getMonthName(month)}',
      subtitle: 'Tente buscar outro mês ou conferir os cadastros dos alunos.',
      color: context.uai.textMuted,
      action: TextButton.icon(
        onPressed: () => setState(() => _selectedMonth = null),
        icon: Icon(Icons.arrow_back, color: context.uai.primary),
        label: Text(
          'Voltar',
          style: TextStyle(
            color: context.uai.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Tela refatorada visualmente em 03/07/2026 às 13:44
// Refatoração focada em tema dinâmico, responsividade e layout adaptativo.
// Lógica original preservada.
// ============================================================
